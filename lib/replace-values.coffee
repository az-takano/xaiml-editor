# {CompositeDisposable, Range, TextBuffer} = require 'atom'
CompositeDisposable = null
Range = null

Util = null
Replacer = null

module.exports =
  enable: true
  targetEditor: null
  marker: null
  otherMarkers: null
  subscription: null
  subscriptions: null
  oldText: null
  replacing: false

  initialize: ->

    {CompositeDisposable, Range} = require 'atom'
    @subscriptions = new CompositeDisposable()

    @subscriptions.add atom.commands.add 'atom-workspace',
      'xaiml-editor:toggleReplaceValues': => @toggleReplace()
    @subscriptions.add atom.commands.add 'atom-workspace',
      'xaiml-editor:beginReplaceValues': => @begin()
    @subscriptions.add atom.commands.add 'atom-workspace',
      'xaiml-editor:execReplaceValues': => @execute()

  dispose: ->
    @subscriptions.dispose()

  isAttributeValueScope: (editor) ->
    scopeDescriptor = editor.getLastCursor().getScopeDescriptor()
    scopes = scopeDescriptor.getScopesArray()
    result =
      "comment.block.aiml" not in scopes and
      "text.aiml" in scopes and
      ("meta.tag.aiml" in scopes or "meta.tag.no-content.aiml" in scopes) and
      ("string.quoted.double.aiml" in scopes or "string.quoted.single.aiml" in scopes) and
      "punctuation.definition.string.begin.aiml" not in scopes

  isContentsValueScope: (editor) ->
    scopeDescriptor = editor.getLastCursor().getScopeDescriptor()
    scopes = scopeDescriptor.getScopesArray()
    for scope in scopes
      console.debug scope
    result =
      "comment.block.aiml" not in scopes and
      "text.aiml" in scopes and
      "meta.tag.preprocessor.aiml" not in scopes and
      "meta.tag.sgml.doctype.aiml" not in scopes and
      "source.java-props.embedded.aiml" not in scopes and
      "source.java.embedded.aiml" not in scopes and
      "string.unquoted.cdata.aiml" not in scopes

  getAttributeTargetRange: (editor) ->
    result = null
    regex = /(["'])([^"'<>\n]*?)\1/g
    pos = editor.getLastCursor().getBufferPosition()
    scanRange = new Range([pos.row, 0], [pos.row, Infinity])
    it = ({match, matchText, range, stop, replace}) ->
      console.debug matchText
      range = range.translate([0, 1], [0, -1])
      if range.containsPoint(pos)
        console.debug match
        result = range
        stop()
    editor.backwardsScanInBufferRange(regex, scanRange, it)
    return result

  getContentsTargetRange: (editor) ->
    result = null
    regex = /<([^\s\/>]+)([^>]*>)([^<>"'\n]*)(<\/\1\s*>)/g
    pos = editor.getLastCursor().getBufferPosition()
    scanRange = new Range([pos.row - 10, 0], [pos.row, Infinity])
    value = null
    editor.backwardsScanInBufferRange regex, scanRange,
      ({match, matchText, range, stop, replace}) ->
        if range.containsPoint(pos)
          console.debug matchText
          console.debug match
          value = match[3]
          stop()
    return null unless value?
    console.debug value

    Util ?= require "./util"
    value = Util.escapeRegExp(value)
    regex = new RegExp(">#{value}<", "g")
    scanRange = new Range([pos.row, 0], [pos.row, Infinity])
    editor.backwardsScanInBufferRange regex, scanRange,
      ({match, matchText, range, stop, replace}) ->
        range = range.translate([0, 1], [0, -1])
        if range.containsPoint(pos)
          console.debug matchText
          console.debug match
          result = range
          stop()

    return result

  markEditTarget: (editor, range) ->
    @removeMark()
    console.debug "markEditTarget"
    @oldText = editor.getTextInBufferRange(range)
    @marker = editor.markBufferRange(range)
    decoration = editor.decorateMarker(@marker,
      {type: "highlight", class: "replace-values"})
    @subscription = editor.onDidChangeCursorPosition ({newBufferPosition}) =>
      return if not @marker? or not @marker.isValid()
      return if @marker.getBufferRange().containsPoint(newBufferPosition)
      console.debug "out of range"
      @removeMark()
    @targetEditor = editor

  markReplaceTarget: (editor, range) ->
    marker = editor.markBufferRange(range)
    decoration = editor.decorateMarker(marker,
      {type: "highlight", class: "replace-values target"})
    return marker

  removeMark: ->
    console.debug "removeMark"
    @oldText = null
    if @marker?
      @marker.destroy()
      @marker = null
    if @subscription?
      @subscription.dispose()
      @subscription = null
    @targetEditor = null
    if @otherMarkers?
      for marker in @otherMarkers
        marker.destroy()
      @otherMarkers = null

  begin: ->
    return unless @enable
    console.debug "begin replace"

    editor = atom.workspace.getActiveTextEditor()
    Util ?= require "./util"
    return unless Util.isAimlEditor(editor)

    if @isAttributeValueScope(editor)
      targetRange = @getAttributeTargetRange(editor)
    else if @isContentsValueScope(editor)
      targetRange = @getContentsTargetRange(editor)
    else
      return

    return unless targetRange?

    @markEditTarget(editor, targetRange)

    @otherMarkers = []
    Replacer ?= require "./replacer"
    Replacer.scanEditor editor, @oldText, (range) =>
      return if targetRange.intersectsWith(range)
      @otherMarkers.push @markReplaceTarget(editor, range)

    return

  execute: ->
    return true unless @enable

    return false unless @oldText?
    oldText = @oldText

    editor = atom.workspace.getActiveTextEditor()
    Util ?= require "./util"
    return true unless Util.isAimlEditor(editor)

    if @targetEditor isnt editor
      console.debug "editor object not same"
      console.debug @targetEditor
      console.debug editor
      return false

    return false if not @marker? or not @marker.isValid()
    pos = editor.getLastCursor().getBufferPosition()
    return false unless @marker.getBufferRange().containsPoint(pos)

    if @isAttributeValueScope(editor)
      targetRange = @getAttributeTargetRange(editor)
    else if @isContentsValueScope(editor)
      targetRange = @getContentsTargetRange(editor)
    else
      return true

    console.debug targetRange
    return true unless targetRange?

    newText = editor.getTextInBufferRange(targetRange)
    console.debug newText

    if oldText is newText
      console.debug "same value"
      @removeMark()
      return true

    if @replacing
      atom.notifications.addWarning "Now busy ..."
      return true
    @replacing = true
    @removeMark()

    console.debug "execute replace"
    Replacer ?= require "./replacer"
    new Replacer(editor).replace(oldText, newText)
      .then => @replacing = false
      .catch => @replacing = false

    return true

  toggleReplace: ->
    return unless @enable
    editor = atom.workspace.getActiveTextEditor()
    Util ?= require "./util"
    return unless Util.isAimlEditor(editor)
    unless @execute()
      @begin()
