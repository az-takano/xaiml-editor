Dictionary = null
ContextAnalyzer = null

REGX_END_SPACE = /\s$/
REGX_ATTRIBUTE_NAME = /^<[^\/\s]+\s/
REGX_CLOSE_SHORT_TAG = /^<[^\/\s>]+[^>]+\/$/
REGX_ELEMENT = /^<$|^<[^\/\s]+$/
REGX_CLOSE_LONG_TAG = /^<\/[^\s\/]*$/

module.exports =
  enable: true
  selector: '.text.aiml'
  disableForSelector: '.text.aiml .comment'
  inclusionPriority: 1
  excludeLowerPriority: true
  suggestionPriority: 2
  filterSuggestions: false

  onDidInsertSuggestion: ({editor, triggerPosition, suggestion}) ->
    if suggestion.interlock
      setTimeout(@triggerAutocomplete.bind(this, editor), 1)

    if suggestion.autoindent
      @autoIndentSnippet(editor, triggerPosition, suggestion)

  triggerAutocomplete: (editor) ->
    atom.commands.dispatch(atom.views.getView(editor),
      'autocomplete-plus:activate', activatedManually: true)

  autoIndentSnippet: (editor, triggerPosition, {snippet}) ->
    rows = 1
    rows = snippet?.split("\n").length

    if rows is 1
      editor.autoIndentSelectedRows()
      return

    cursor = editor.getLastCursor()
    savedPosition = cursor.getBufferPosition()
    pos = triggerPosition.copy()

    startRow = 0
    if savedPosition.row is pos.row
      startRow = 1
      editor.autoIndentSelectedRows()
      aiPos = editor.getLastCursor().getBufferPosition()
      if savedPosition.column is aiPos.column
        return
      savedPosition.column = aiPos.column

    for i in [startRow...rows]
      pos.row = triggerPosition.row + i
      pos.column = savedPosition.column
      cursor.setBufferPosition(pos)
      editor.autoIndentSelectedRows()
      if pos.row is savedPosition.row
        savedPosition = editor.getLastCursor().getBufferPosition()

    editor.getLastCursor().setBufferPosition(savedPosition)

  getSuggestions: (request) ->
    return new Promise (resolve) =>
      result = []
      return resolve(result) unless @enable

      ContextAnalyzer ?= require "./context-analyzer"
      context = new ContextAnalyzer(request).analyze()
      return resolve(result) unless context?

      Dictionary ?= require "./dictionary"

      if @isAttributeValue request, context
        result = result.concat Dictionary.getAttributeValueSuggestions context
      else if @isShortTagClosing request, context
        result = result.concat @getClosingShortTagSuggestion()
      else if @isAttributeName request, context
        result = result.concat Dictionary.getAttributeSuggestions context
      else if @isElement request, context
        if request.activatedManually or not REGX_END_SPACE.test(context.input)
          result = result.concat Dictionary.getSnippetSuggestions(request, context)
          result = result.concat Dictionary.getContentsSuggestions(request, context)
          result = result.concat Dictionary.getElementSuggestions(request, context)
      else if @isTagClosing request, context
        result = result.concat @getClosingTagSuggestions context
      else
        result = result.concat Dictionary.getSnippetSuggestions request, context

      resolve result

  isAttributeValue: ({scopeDescriptor}, {prefix}) ->
    scopes = scopeDescriptor.getScopesArray()
    result =
      ("meta.tag.aiml" in scopes or "meta.tag.no-content.aiml" in scopes) and
      ("string.quoted.double.aiml" in scopes or "string.quoted.single.aiml" in scopes) and
      "punctuation.definition.string.begin.aiml" not in scopes

  isShortTagClosing: ({scopeDescriptor}, {prefix}) ->
    scopes = scopeDescriptor.getScopesArray()
    result =
      "meta.tag.aiml" in scopes and
      "meta.tag.no-content.aiml" not in scopes and
      "string.quoted.double.aiml" not in scopes and
      "string.quoted.single.aiml" not in scopes and
      REGX_CLOSE_SHORT_TAG.test prefix

  isAttributeName: ({scopeDescriptor}, {prefix}) ->
    scopes = scopeDescriptor.getScopesArray()
    result =
      ("meta.tag.aiml" in scopes or "meta.tag.no-content.aiml" in scopes) and
      "string.quoted.double.aiml" not in scopes and
      "string.quoted.single.aiml" not in scopes and
      REGX_ATTRIBUTE_NAME.test prefix

  isElement: ({scopeDescriptor}, {prefix}) ->
    scopes = scopeDescriptor.getScopesArray()
    result =
      "text.aiml" in scopes and
      "comment.block.aiml" not in scopes and
      "string.unquoted.cdata.aiml" not in scopes and
      "meta.tag.preprocessor.aiml" not in scopes and
      "meta.tag.sgml.doctype.aiml" not in scopes and
      "source.java-props.embedded.aiml" not in scopes and
      "source.java.embedded.aiml" not in scopes and
      (prefix is "" or REGX_ELEMENT.test(prefix))

  isTagClosing: ({scopeDescriptor}, {prefix}) ->
    scopes = scopeDescriptor.getScopesArray()
    result =
      "text.aiml" in scopes and
      "comment.block.aiml" not in scopes and
      "string.unquoted.cdata.aiml" not in scopes and
      "meta.tag.preprocessor.aiml" not in scopes and
      "meta.tag.sgml.doctype.aiml" not in scopes and
      "source.java-props.embedded.aiml" not in scopes and
      "source.java.embedded.aiml" not in scopes and
      REGX_CLOSE_LONG_TAG.test prefix

  getClosingTagSuggestions: ({currentPath, prefix}) ->
    element = currentPath[0]
    return [] if not element?

    text: "</#{element}>"
    description: "close tag."
    type: "tag"
    replacementPrefix: prefix
    autoindent: true

  getClosingShortTagSuggestion: ->
    text: "/>"
    displayText: "/>"
    description: "close tag."
    type: "tag"
    replacementPrefix: "/"
    autoindent: true
