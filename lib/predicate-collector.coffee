CompositeDisposable = null

Util = null
Dictionary = null

REGX_SET_NAME = /<set(\s+|\s+[^<>]*\s+)name\s*=\s*?(['"])([^<>\n]*?)\2/g
MATCH_INDEX = 3

module.exports =
  subscriptions: null
  eventTokenize: null
  eventSave: null

  initialize: ->
    {CompositeDisposable} = require 'atom'
    @subscriptions = new CompositeDisposable()

    @subscriptions.add atom.config.observe 'xaiml-editor.suggestOption.autoCollectPredicateName',
      (enabled) =>
        @enabled = enabled
        Dictionary ?= require "./dictionary"
        Dictionary.setAutoPredicateNames [] unless @enabled

    @subscriptions.add atom.commands.add 'atom-workspace',
      'xaiml-editor:collectPredicateName': => @collect()

  dispose: ->
    @subscriptions.dispose()
    @eventTokenize?.dispose()
    @eventSave?.dispose()

  collect: (editor) ->
    @eventTokenize?.dispose()
    @eventSave?.dispose()
    return unless @enabled

    editor ?= atom.workspace.getActiveTextEditor()

    if not editor.tokenizedBuffer?.fullyTokenized and editor.onDidTokenize?
      @eventTokenize = editor.onDidTokenize () =>
        @collectAll(editor)
    else
      @collectAll(editor)

    @eventSave = editor.onDidSave () =>
      @collectAll(editor)

  collectAll: (currentEditor) ->
    Util ?= require "./util"
    activeEditor = atom.workspace.getActiveTextEditor()
    currentEditor ?= activeEditor

    return unless currentEditor is activeEditor
    return unless Util.isAimlEditor currentEditor
    return if Util.isInvalidFileSize currentEditor

    Dictionary ?= require "./dictionary"
    predicateList = []
    Dictionary.setAutoPredicateNames predicateList

    new Promise (resolve, reject) =>
      @collectPredicateName currentEditor, predicateList
      @collectOpenedEditors currentEditor, predicateList
      predicateList.sort()
      resolve()

  collectOpenedEditors: (currentEditor, predicateList) ->
    Util ?= require "./util"
    count = 0
    projectDir = Util.getProjectDir(currentEditor)
    return count unless projectDir?

    for openedEditor in atom.workspace.getTextEditors()
      path = openedEditor.getPath()
      continue if openedEditor is currentEditor
      continue unless Util.isAimlEditor(openedEditor)
      continue unless projectDir.contains(path)
      continue unless openedEditor.tokenizedBuffer?.fullyTokenized
      count += @collectPredicateName openedEditor, predicateList

    return count

  collectPredicateName: (editor, predicateList) ->
    Util ?= require "./util"
    count = 0
    return count if Util.isInvalidFileSize(editor)

    it = ({match, matchText, range, stop, replace}) =>
      pos = range.end.translate [0, -1]
      if @isAttributeValueScope(editor, pos)
        predicateName = match[MATCH_INDEX]
        if predicateName? and predicateName not in predicateList
          predicateList.push predicateName
          count++

    editor.scan(REGX_SET_NAME, it)

    return count

  isAttributeValueScope: (editor, pos) ->
    scopeDescriptor = editor.scopeDescriptorForBufferPosition(pos)
    scopes = scopeDescriptor.getScopesArray()
    result =
      "comment.block.aiml" not in scopes and
      "text.aiml" in scopes and
      ("meta.tag.aiml" in scopes or "meta.tag.no-content.aiml" in scopes) and
      ("string.quoted.double.aiml" in scopes or "string.quoted.single.aiml" in scopes) and
      "punctuation.definition.string.begin.aiml" not in scopes
