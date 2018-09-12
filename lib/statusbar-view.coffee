DictionaryLoader = null
Dictionary = null
Util = null

module.exports =
class VersionStatusBarView
  enable: false
  statusBar: null
  versionLabel: null
  statusBarTile: null
  activeTextEditor: null
  dictionarySubscription: null
  activeItemSubscription: null
  grammarSubscription: null
  configurationSubscription: null

  constructor: (serializedState) ->

    @element = document.createElement('div')
    @element.classList.add("aiml-version-statusbar", "inline-block")
    @versionLabel = document.createElement("label")
    @element.appendChild @versionLabel

  initialize: (statusBar) ->
    @statusBar = statusBar
    @handleEvents()
    return @

  destroy: ->
    @disposeDictionarySubscription()

    @activeItemSubscription?.dispose()
    @activeItemSubscription = null

    @configurationSubscription?.dispose()
    @configurationSubscription = null

    @grammarSubscription?.dispose()
    @grammarSubscription = null

    @removeStatusBarTile()

    @element.remove()

  disposeDictionarySubscription: ->
    @dictionarySubscription?.dispose()
    @dictionarySubscription = null

  handleEvents: ->
    @activeItemSubscription = atom.workspace.onDidChangeActivePaneItem(
      (item) => @changeActivePaneItem(item))
    @configurationSubscription = atom.config.observe(
      'xaiml-editor.showVersionInStatusBar', (value) =>
        @changeConfig(value))

    @changeActivePaneItem(atom.workspace.getActiveTextEditor())

  changeConfig: (value) ->
    @enable = value
    if value?
      @changeView @activeTextEditor?getGrammar()
    else
      @disableStatusBar()

  changeActivePaneItem: (item) ->

    @disposeDictionarySubscription()

    unless atom.workspace.isTextEditor(item)
      @activeTextEditor = null
      @removeStatusBarTile()
      return
    else
      @activeTextEditor = item
    editor = item

    @grammarSubscription?.dispose()
    @grammarSubscription = editor.onDidChangeGrammar (grammar) =>
      @changeView grammar

    @changeView editor.getGrammar()

  changeView: (grammar) ->
    Util ?= require './util'
    if @enable and Util.isAimlGrammar(grammar)
      @enableStatusBar()
      @updateVersion(grammar)
    else
      @disableStatusBar()

  enableStatusBar: ->
    @addStatusBarTile()
    @disposeDictionarySubscription()

    DictionaryLoader ?= require "./dictionary-loader"
    @dictionarySubscription = DictionaryLoader.onDidLoadDictionary (version) =>
      @updateVersion @activeTextEditor?.getGrammar()

  disableStatusBar: ->
    @removeStatusBarTile()
    @disposeDictionarySubscription()

  addStatusBarTile: () ->
    return if @statusBarTile?
    @statusBarTile = @statusBar.addRightTile(item: @, priority: 5)

  removeStatusBarTile: ->
    @statusBarTile?.destroy()
    @statusBarTile = null

  updateVersion: (grammar)->
    Util ?= require './util'
    if Util.isAimlGrammar grammar
      Dictionary ?= require "./dictionary"
      @versionLabel.textContent = "Ver.#{Dictionary.getDictionaryVersion()}"
    else
      @versionLabel.textContent = ""
