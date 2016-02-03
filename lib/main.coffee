{BufferedProcess, CompositeDisposable} = require 'atom'
_ = require 'underscore'

module.exports =
  config:
    executablePath:
      type: 'string'
      title: 'Path to aspell command'
      default: '/usr/local/bin/aspell'
    ignoredWords:
      type: 'string',
      title: 'Comma separated list of words to ignore'
      default: ''
    dictionary:
      type: 'string',
      title: 'This dictionary will be used if possible'
      default: 'en_GB'

  activate: ->
    @subscriptions = new CompositeDisposable
    @subscriptions.add atom.config.observe 'linter-aspell.executablePath',
      (executablePath) =>
        @executablePath = executablePath
    @subscriptions.add atom.config.observe 'linter-aspell.ignoredWords',
      (ignoredWords) =>
        @ignoredWords = _.map (ignoredWords || '').split(','), (word) ->
          word.toLowerCase()
    @subscriptions.add atom.config.observe 'linter-aspell.dictionary',
      (dictionary) =>
        @dictionary = dictionary

    # atom.commands.add "atom-text-editor",
    #   "linter-aspell-ignore -current-word": => @ignoreCurrentWord()

  # @ignoreCurrentWord: () ->


  deactivate: ->
    @subscriptions.dispose()

  provideLinter: ->
    provider =
      grammarScopes: ['text.*', 'source.gfm']
      scope: 'file'
      lintOnFly: true

      lint: (textEditor) =>
        filePath = textEditor.getPath()
        shell = atom.config.get('run-command.shellCommand') || '/bin/bash'
        aspell = @executablePath
        ignore = @ignoredWords
        dictionary = @dictionary
        # fixword = (word) -> "echo #{word} | aspell pipe -d en_gb | grep '^&' | cut -d':' -f2 | cut -c2- | cut -d',' -f1"
        checkCmd = "cat \"#{filePath}\" | #{aspell} -d #{dictionary} -a | grep -v '*' | cut -d' ' -f2 -f5- | grep -v '^$' | sort | uniq | sed 's/, /,/g' | sed 's/ /|/'"

        parse = (word, corrections, errors) ->
          regex = new RegExp("\\b#{word}\\b", 'igm')
          message = corrections.slice(0,6).join(', ')
          textEditor.scan regex, (result) ->
            error =
              type: 'spelling',
              text: message,
              filePath: filePath,
              range: result.range
            errors.push error

        return new Promise (resolve, reject) =>
          badWords = []
          process = new BufferedProcess
            command: shell
            args: ["-c", checkCmd]

            stdout: (data) ->
              badWords = badWords.concat(data.split '\n')

            exit: (code) =>
              return resolve [] unless code is 0

              errors = []
              for badWord in badWords
                bits = badWord.split('|')
                continue unless bits.length > 0
                word = bits[0]
                corrections = bits[1]
                continue unless word? && word != '' && corrections?
                if @ignoredWords? && @ignoredWords.length > 0
                  if word.toLowerCase() in @ignoredWords
                    continue
                corrections = corrections.split(',')

                info = parse word, corrections, errors

              errors = _.uniq errors, (error) ->
                "#{error.range.start.row} #{error.range.start.column}"
              errors = _.sortBy errors, (error) ->
                error.range.start.row * 1000 + error.range.start.column

              return resolve errors

          process.onWillThrowError ({error,handle}) ->
            atom.notifications.addError "Failed to run #{@executablePath}",
              detail: "#{error.message}"
              dismissable: true
            handle()
            resolve []
