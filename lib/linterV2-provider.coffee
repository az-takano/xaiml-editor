CompositeDisposable = null

Util = null
Helpers = null
Path = null
SchemaLoader = null
XRegExp = null

module.exports =
  provider:
    name: "AIML Linter"
    grammarScopes: ['text.aiml']
    scope: 'file'
    lintsOnChange: false

  subscriptions: null
  executablePath: ''
  internalPath: "resources/xaiml1.0.0.xsd"
  builtinSchemaPath: null

  initialize: ->
    require('atom-package-deps').install('xaiml-editor')

    Helpers ?= require 'atom-linter'

    Path ?= require "path"
    @builtinSchemaPath = Path.resolve(__dirname, '..', @internalPath)

    {CompositeDisposable} = require 'atom'
    @subscriptions ?= new CompositeDisposable()


    @subscriptions.add atom.commands.add 'atom-workspace',
      'xaiml-editor:executeLinter': => @executeLinter()

    @subscriptions.add atom.config.observe 'xaiml-editor.executablePath',
      (executablePath) => @executablePath = executablePath
    @subscriptions.add atom.config.observe 'xaiml-editor.lintOnFly',
      (lintOnFly) => @provider.lintsOnChange = lintOnFly
    @subscriptions.add atom.config.observe 'xaiml-editor.suggestOption.builtinSchemaVersion',
      (version) =>
        @internalPath = "resources/#{version}.xsd"
        @builtinSchemaPath = Path.resolve(__dirname, '..', @internalPath)

    return @

  dispose: ->
    @subscriptions?.dispose()

  getProvider: ->
    @provider.lint = (textEditor) =>
      return @lintEditor textEditor
    return @provider

  executeLinter: (textEditor = null) ->
    Util ?= require './util'
    textEditor ?= atom.workspace.getActiveTextEditor()
    return unless Util.isAimlEditor(textEditor)
    view = atom.views.getView(textEditor)
    atom.commands.dispatch(view, "linter:lint")

  lintEditor: (textEditor) ->
    SchemaLoader ?= require "./schema-loader"
    if SchemaLoader.isDownload()
      schemaPath = SchemaLoader.schemaPath
    else
      schemaPath = @builtinSchemaPath
    return @checkWellFormed textEditor
    .then (messages) =>
      if messages.length
        return messages
      return @checkValid(textEditor, schemaPath)
      .then (messages) ->
        return messages

  checkWellFormed: (textEditor) ->
    params = ['--noout', '-']
    options = {
      stdin: textEditor.getText()
      stream: 'stderr'
      allowEmptyStderr: true
    }
    return Helpers.exec(@executablePath, params, options, {uniqueKey: "aiml-linter:#{textEditor.getPath()}"})
    .then (output) =>
      messages = @parseMessages(textEditor, output)
      for message in messages
        message.location.file = textEditor.getPath()
      return messages

  checkValid: (textEditor, schemaPath) ->
    return @validateSchema(textEditor, '--schema', schemaPath)

  validateSchema: (textEditor, argSchemaType, schemaPath) ->
    params = []
    params.push('--noout')
    params = params.concat([argSchemaType, schemaPath, '-'])
    options = {
      cwd: Path.dirname(textEditor.getPath())
      stdin: textEditor.getText()
      stream: 'stderr'
    }

    if @builtinSchemaPath is schemaPath
      msgSchemaUrl = "Builtin Schema"
    else
      msgSchemaUrl = schemaPath

    return Helpers.exec(@executablePath, params, options, {uniqueKey: "aiml-linter:#{textEditor.getPath()}"})
      .then (output) =>
        messages = @parseSchemaMessages(textEditor, output)
        if messages.length
          for message in messages
            message.severity = 'error'
            message.excerpt = message.excerpt + ' (' + msgSchemaUrl + ')'
            message.location.file = textEditor.getPath()
        else if output.indexOf('- validates') is -1
          messages.push({
            severity: 'error'
            excerpt: output
            location: {
              file: textEditor.getPath()
              position: Helpers.generateRange(textEditor, 0, 0)
            }
          })
        return messages

  parseMessages: (textEditor, output) ->
    XRegExp ?= require('xregexp')
    messages = []
    regex = XRegExp(
      '^(?<file>.+):' +
      '(?<line>\\d+): ' +
      '(?<severity>.+) : ' +
      '(?<message>.+)' +
      '(' +
      '\\r?\\n' +
      '(?<source_line>.*)\\r?\\n' +
      '(?<marker>.*)\\^' +
      ')?' +
      '$', 'm')
    XRegExp.forEach output, regex, (match, i) ->
      line = parseInt(match.line) - 1
      column = if match.marker then match.marker.length else 0
      messages.push({
        severity: 'error'
        excerpt: match.message
        location: {
          file: match.file
          position: Helpers.generateRange(textEditor, line, column)
        }
      })
    return messages

  parseSchemaMessages: (textEditor, output) ->
    regex = '(?<file>.+):(?<line>\\d+): .*: .* : (?<message>.+)'
    messages = Helpers.parse(output, regex)
    for message in messages
      message.severity = message.type
      delete message.type

      message.excerpt = message.text
      delete message.text

      message.location = {
        file: message.filePath
      }
      delete message.filePath

      message.location.position = Helpers.generateRange(textEditor, message.range[0][0])
      delete message.range
    return messages
