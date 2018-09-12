Fs = null
Path = null

module.exports =
  schemaPath: ""
  lastPath: ""
  isLoading: false

  initialize: ->
    {CompositeDisposable} = require 'atom'
    @subscriptions = new CompositeDisposable()
    @subscriptions.add atom.config.observe 'xaiml-editor.schemaPath',
      (schemaPath) =>
        @downloadSchema(true)

  dispose: ->
    @subscriptions.dispose()

  downloadSchema: (reload = false) ->
    uri = atom.config.get("xaiml-editor.schemaPath").trim()
    return if uri is ""
    return if not reload and @lastPath is uri
    return if @isLoading
    @isLoading = true
    @lastPath = ""

    @loadFile uri, (ret) =>
      unless /^<\?xml /.test ret
        atom.notifications.addError "SchemaFile Download Error.",
          detail: """
            #{uri}
            #{ret}
            """
          dismissable: true
        @isLoading = false
        return
      @setFile ret,(result) =>
        unless result
          @isLoading = false
          return
        @lastPath = uri if result
        @isLoading = false

  loadFile: (uri, complete) ->

    Fs ?= require "fs-plus"
    Fs.readFile uri, (error, content) ->
      if error?
        atom.notifications.addError "SchemaFile Read Error.",
          detail: """
            #{uri}
            #{error}
            """
          dismissable: true
      else
        complete(content) unless error?

  setFile: (data,callback) ->
    Path ?= require "path"
    @schemaPath = Path.resolve(atom.config.get("xaiml-editor.schemaPath").trim())
    path = @schemaPath
    Fs ?= require "fs-plus"
    Fs.readFile path, data, (error) ->
      if error
        dismissable: true
        callback(false)
      else
        callback(true)

  isDownload: ->
    return false unless @lastPath
    return true
