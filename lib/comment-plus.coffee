CompositeDisposable = null
Range = null

Util = null

module.exports =
  subscriptions: null

  initialize: ->
    {CompositeDisposable, Range} = require "atom"

    @subscriptions = new CompositeDisposable()
    @subscriptions.add atom.commands.add "atom-workspace",
      "xaiml-editor:toggleComment", => @toggleComment()

  dispose: ->
    @subscriptions.dispose()

  toggleComment: ->
    Util ?= require './util'
    editor = atom.workspace.getActiveTextEditor()
    if Util.isAimlEditor(editor)
      result = @analyzeSelection editor
    else
      return

    if result.add
      @addComment editor, result
    else
      @removeComment editor, result

    if result.isSelected
      @restoreSelection editor, result
    else
      @restorCursorPosition editor, result
      editor.moveDown(1)

  analyzeSelection: (editor) ->
    isSingleLine = false
    add = false

    cursor = editor.getLastCursor()
    savePos = cursor.getBufferPosition()
    selectRange = editor.getSelectedBufferRange()
    isSelected = not selectRange.isEmpty()

    reverse = false
    if selectRange.isSingleLine()
      if selectRange.end.column > savePos.column
        reverse = true
    else if selectRange.end.row > savePos.row
      reverse = true

    cursor.setBufferPosition([selectRange.start.row, 0])
    startRowText = editor.lineTextForBufferRow selectRange.start.row
    if /^\s*$/.test startRowText
      editor.moveToEndOfLine()
    else
      editor.moveToFirstCharacterOfLine()
    cursor = editor.getLastCursor()
    startRowPos = cursor.getBufferPosition()
    startTag = /^\s*<!--/.test startRowText

    endRow = selectRange.end.row
    endRow -= 1 if isSelected and selectRange.end.column is 0
    cursor.setBufferPosition([endRow, 0])
    editor.moveToEndOfLine()
    cursor = editor.getLastCursor()
    endRowPos = cursor.getBufferPosition()
    endRowText = editor.lineTextForBufferRow endRow
    endTag = /-->\s*$/.test endRowText

    targetRange = new Range(startRowPos, endRowPos)
    text = editor.getTextInBufferRange targetRange

    if targetRange.isSingleLine()
      isSingleLine = true

    result = /^[\s]*(<!--\s?)([\s\S]*?)(\s?-->)[\s]*$/.exec text
    innerText = result?[2]
    multiCommentBlock = false
    hasContents = false
    if /-->[\s\S]*?<!--/.test innerText
      multiCommentBlock = true
      contentsArr = innerText.match /-->([\s\S]*?)<!--/g
      for content in contentsArr
        unless /^-->\s*<!--$/.test content
          hasContents = true
          break

    startLength = 5
    endLength = 4
    if result?
      if hasContents
        add = true
      else
        add = false
        startLength = result[1]?.length
        endLength = result[3]?.length
    else
      add = true

    isSelected: isSelected
    isSingleLine: isSingleLine
    savePos: savePos
    selectRange: selectRange
    targetRange: targetRange
    add: add
    reverse: reverse
    startTag: startTag
    startLength: startLength
    endLength: endLength

  addComment: (editor, result) ->
    targetText = editor.getTextInBufferRange(result.targetRange)
    targetText = targetText.replace /<!(\++)-/g, "<!+$1-"
    targetText = targetText.replace /-(\++)>/g, "-$1+>"
    targetText = targetText.replace /<!--/g, "<!+-"
    targetText = targetText.replace /-->/g, "-+>"

    editor.setTextInBufferRange result.targetRange, "<!-- #{targetText} -->"

  removeComment: (editor, result) ->
    targetText = editor.getTextInBufferRange(result.targetRange)
    targetText = targetText.replace /<!--\s?|\s?-->/g, ""
    targetText = targetText.replace /<!\+-/g, "<!--"
    targetText = targetText.replace /-\+>/g, "-->"
    targetText = targetText.replace /<!\+(\++)-/g, "<!$1-"
    targetText = targetText.replace /-\+(\++)>/g, "-$1>"

    editor.setTextInBufferRange result.targetRange, targetText

  restoreSelection: (editor, {targetRange, selectRange, add, startTag, reverse, startLength, endLength}) ->
    startAdjust = 0
    endAdjust = 0
    if targetRange.start.row is selectRange.start.row
      if add
        if targetRange.start.column < selectRange.start.column
          startAdjust += startLength
      else
        if startTag
          if targetRange.start.column < selectRange.start.column
            startAdjust -= startLength
    if targetRange.end.row is selectRange.end.row
      if targetRange.end.column <= selectRange.end.column
        if add
          endAdjust += endLength
        else
          endAdjust -= endLength
    if selectRange.start.row is selectRange.end.row and
        targetRange.start.column < selectRange.end.column
      if add
        endAdjust += startLength
      else
        endAdjust -= startLength

    selectRange.start.column += startAdjust
    selectRange.end.column += endAdjust

    if reverse
      editor.setCursorBufferPosition(selectRange.end)
      editor.selectToBufferPosition(selectRange.start)
    else
      editor.setCursorBufferPosition(selectRange.start)
      editor.selectToBufferPosition(selectRange.end)

  restorCursorPosition: (editor, {targetRange, savePos, add, startLength, endLength}) ->
    columnAdjust = 0
    if targetRange.start.row is savePos.row and
        targetRange.start.column <= savePos.column
      if add
        columnAdjust += startLength
      else
        columnAdjust -= startLength
    if targetRange.end.row is savePos.row and
        targetRange.end.column <= savePos.column
      if add
        columnAdjust += endLength
      else
        columnAdjust -= endLength
    savePos.column += columnAdjust

    editor.setCursorBufferPosition(savePos)
