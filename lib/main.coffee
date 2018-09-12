CompositeDisposable = null

Util = null
LanguageAimlView = null
Autocomplete = null
CommentPlus = null
LinterV2 = null
ReplaceValues = null
SchemaLoader = null
Project = null
HackHighlightSelected = null
StatusBarView = null
Dictionary = null
DictionaryLoader = null
PredicateCollector = null

module.exports =
  # pacage configuration
  config:
    dictionaryPath:
      order: 1
      title: 'Dictionary File Path'
      # description: 'Path Of The Dictionary File.'
      description: '辞書ファイルのパスを指定します。'
      type: 'string'
      default: ''
    showVersionInStatusBar:
      order: 2
      title: 'Show Dictionary Version In Status Bar'
      # description: 'Show in the status bar the Dictionary AIML Version.'
      description: 'ステータスバーに辞書ファイルのバージョンを表示します。'
      type: 'boolean'
      default: false
    schemaPath:
      order: 3
      title: 'Schema File Path'
      # description: 'Path Of The Dictionary File.'
      description: 'AIMLスキーマファイル(xsd)のパスを指定します。'
      type: 'string'
      default: ''
    executablePath:
      order: 4
      title: 'Xmllint Executable Path'
      # title: 'xmllint 実行パス'
      description: 'xmllintの実行パスを指定します。(※パスが通っていない場合)'
      type: 'string'
      default: 'xmllint'
    lintOnFly:
      order: 5
      title: 'Lint On Fly'
      description: '構文チェックを即時実行します。（※linter > Lint on Change 有効時）'
      type: 'boolean'
      default: false
    suggestOption:
      order: 6
      title: 'Suggest Options'
      description: 'Suggest オプション'
      collapsed: true
      type: 'object'
      properties:
        builtinSchemaVersion:
          order: 1
          title: 'Built-in Dictionary and Schema Version'
          description: '内蔵辞書とスキーマのバージョンを指定します。'
          type: 'string'
          default: "xaiml1.0.0"
          enum: ['xaiml1.0.0']
        suggestSystemPredicateName:
          order: 2
          title: 'Suggest System PredicateNames'
          description: 'システムPredicate名を候補に表示します。'
          type: 'boolean'
          default: false
        autoCollectPredicateName:
          order: 3
          title: 'Suggest Auto Collect PredicateNames'
          description: '開いているAIMLファイルからPredicate名を収集し候補に表示します。'
          type: 'boolean'
          default: false
    highlightSelectedExtension:
      order: 7
      title: 'highlight-selected Extension'
      description: 'highlight-selected 機能拡張'
      collapsed: true
      type: 'object'
      properties:
        enable:
          order: 1
          title: 'Wide Characters Support'
          description: 'highlight-selectedをワイド文字で動作するよう機能拡張します。'
          type: 'boolean'
          default: true
        targetGrammar:
          order: 2
          title: 'Target Grammar'
          description: 'highlight-selected機能拡張の動作対象となるGrammarを指定します。'
          type: 'string'
          default: 'AIML'
          enum: ['AIML', 'ALL']

  versionView: null
  subscriptions: null
  changeGrammarSubscription: null


  activate: (state) ->


    Project ?= require "./project"
    CommentPlus ?= require "./comment-plus"
    ReplaceValues ?= require "./replace-values"
    SchemaLoader ?= require "./schema-loader"
    Dictionary ?= require "./dictionary"
    DictionaryLoader ?= require "./dictionary-loader"
    PredicateCollector ?= require "./predicate-collector"
    {CompositeDisposable} = require "atom"
    @subscriptions = new CompositeDisposable()

    Project.initialize()
    @subscriptions.add Project
    CommentPlus.initialize()
    @subscriptions.add CommentPlus
    ReplaceValues.initialize()
    @subscriptions.add ReplaceValues
    SchemaLoader.initialize()
    @subscriptions.add SchemaLoader
    Dictionary.initialize()
    @subscriptions.add Dictionary
    DictionaryLoader.initialize()
    @subscriptions.add DictionaryLoader
    PredicateCollector.initialize()
    @subscriptions.add PredicateCollector

    @subscriptions.add atom.workspace.onDidStopChangingActivePaneItem (item) =>
      @changingActivePaneItem(item)
    @subscriptions.add atom.project.onDidChangePaths (projectPaths) ->
      Project.loadProjectSettings()

    @subscriptions.add atom.packages.onDidActivateInitialPackages =>
      Project.loadProjectSettings()
      .then =>
        @updateSettings atom.workspace.getActiveTextEditor()

  deactivate: ->
    @changeGrammarSubscription?.dispose()
    @changeGrammarSubscription = null

    @versionView?.destroy()
    @versionView = null

    @subscriptions?.dispose()
    @subscriptions = null

  provideAutocomplete: ->
    Autocomplete ?= require "./autocomplete-provider"
    Autocomplete

  provideLinterV2: ->
    LinterV2 ?= require "./linterV2-provider"
    @subscriptions.add LinterV2.initialize()
    LinterV2.getProvider()

  consumeStatusBar: (statusBar) ->
    StatusBarView ?= require './statusbar-view'
    @versionView = new StatusBarView().initialize(statusBar)

  consumeHighlightSelectedV1: (areaView) ->
    HackHighlightSelected ?= require "./hack-highlight-selected"
    HackHighlightSelected.initialize(areaView)
    @subscriptions.add HackHighlightSelected

  consumeHighlightSelectedV2: (areaView) ->
    HackHighlightSelected ?= require "./hack-highlight-selected"
    HackHighlightSelected.initialize(areaView)
    @subscriptions.add HackHighlightSelected

  changingActivePaneItem: (item) ->
    return unless atom.workspace.isTextEditor(item)
    editor = item

    Util ?= require './util'

    @changeGrammarSubscription?.dispose()
    @changeGrammarSubscription = editor.onDidChangeGrammar (grammar) =>
      return unless Util.isAimlGrammar(grammar)
      @updateSettings editor

    bytes = Util.getFileSize(editor.getPath())
    if Util.isInvalidFileSize(bytes)
      Autocomplete?.enable = false
      ReplaceValues.enable = false
    else
      Autocomplete?.enable = true
      ReplaceValues.enable = true

    @updateSettings editor

  updateSettings: (editor) ->
    new Promise (resolve, reject) ->
      Util ?= require './util'
      return resolve() unless Util.isAimlEditor(editor)
      DictionaryLoader.load()
      PredicateCollector.collect(editor)
      resolve()
