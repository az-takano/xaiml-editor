CompositeDisposable = null

Util = null

REGEX_NOT_BASICLATIN = /[^\u0000-\u007F]/

module.exports =
  areaView: null
  allGrammar: false

  initialize: (areaView) ->
    return @ unless areaView?
    return @ unless typeof areaView.handleSelection is "function"

    @areaView = areaView
    @areaView.handleSelection_original = areaView.handleSelection
    @areaView.handleSelection_extension = handleSelectionEx

    ## イベント登録
    # 設定変更イベント 有効無効
    {CompositeDisposable} = require 'atom'
    @subscriptions ?= new CompositeDisposable()
    @subscriptions.add atom.config.observe 'xaiml-editor.highlightSelectedExtension.enable',
      (enabled) =>
        # console.debug "highlightSelectedExtension #{enabled}"
        if enabled
          @areaView.handleSelection = @areaView.handleSelection_extension
        else
          @areaView.handleSelection = @areaView.handleSelection_original

    return @

  dispose: ->
    return unless @areaView?
    @areaView.handleSelection = @areaView.handleSelection_original
    @subscriptions?.dispose()

handleSelectionEx = ->
  try
    @removeMarkers()

    editor = @getActiveEditor()
    return unless editor
    return if editor.getLastSelection().isEmpty()

    targetGrammar = atom.config.get("xaiml-editor.highlightSelectedExtension.targetGrammar")
    # console.debug "TargetGrammar: #{targetGrammar}"
    Util ?= require './util'
    if targetGrammar is 'AIML' and not Util.isAimlEditor(@getActiveEditor())
      return @handleSelection_original()

    @selections = editor.getSelections()
    text = @selections[0].getText()

    inNotBasicLatin = REGEX_NOT_BASICLATIN.test(text)
    text = Util.escapeRegExp text

    unless inNotBasicLatin
      # console.debug "basic latin. #{text}"
      return @handleSelection_original()

    result = /\S*\w*/gi.exec text
    # console.debug result

    return unless result?
    return if result[0].length < atom.config.get(
      'highlight-selected.minimumLength') or
              result.index isnt 0 or
              result[0] isnt result.input

    regexFlags = 'g'
    if atom.config.get('highlight-selected.ignoreCase')
      regexFlags = 'gi'

    range =  [[0, 0], editor.getEofBufferPosition()]

    @ranges = []
    regexSearch = result[0]

    if not inNotBasicLatin and
    atom.config.get('highlight-selected.onlyHighlightWholeWords')
      if regexSearch.indexOf("\$") isnt -1 \
      and editor.getGrammar()?.name in ['PHP', 'HACK']
        regexSearch = regexSearch.replace("\$", "\$\\b")
      else
        regexSearch =  "\\b" + regexSearch
      regexSearch = regexSearch + "\\b"

    @resultCount = 0
    # for highlight-selected@0.11.2 or later (Atom v1.13.0 or later)
    if typeof @highlightSelectionInEditor is "function"
      if atom.config.get('highlight-selected.highlightInPanes')
        @getActiveEditors().forEach (editor) =>
          @highlightSelectionInEditor(editor, regexSearch, regexFlags)
      else
        @highlightSelectionInEditor(editor, regexSearch, regexFlags)
    else
      editor.scanInBufferRange new RegExp(regexSearch, regexFlags), range,
        (result) =>
          @resultCount += 1
          unless @showHighlightOnSelectedWord(result.range, @selections)
            marker = editor.markBufferRange(result.range)
            decoration = editor.decorateMarker(marker,
              {type: 'highlight', class: @makeClasses()})
            @views?.push marker
            @emitter?.emit 'did-add-marker', marker

    @statusBarElement?.updateCount(@resultCount)

  catch error
    console.error error
