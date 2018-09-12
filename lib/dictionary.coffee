CompositeDisposable = null

REGX_ELEMENT_NAME = /^<([^\s]*)/
REGX_ATTRIBUTE = /\s([^\s]+)$/
REGX_ATTRIBUTE_VALUE = /\s([^\s]*)\s*=\s*(?:"([^"]*)|'([^']*))$/
REGX_CHK_SNIPPET = /\$\{\d+\:[^}]+\}/
REGX_CHK_TAG_OPEN = /^</
REGX_CHK_TAG_CLOSE = /^<\/|\/>$/

module.exports =
  rootAlias: "_ROOT_"
  subscriptions: null
  dictionary: null
  isSuggestSystemPredicateNames: false
  systemPredicateNames: []
  autoPredicateNames: []

  initialize: ->
    CompositeDisposable ?= require('atom').CompositeDisposable
    @subscriptions = new CompositeDisposable()
    @subscriptions.add atom.config.observe 'xaiml-editor.suggestOption.suggestSystemPredicateName',
      (enabled) =>
        @isSuggestSystemPredicateNames = enabled

  dispose: ->
    @subscriptions.dispose()

  setDictionary: (dictionary) ->
    @dictionary = dictionary

  getDictionaryVersion: ->
    return "#{@dictionary?.version}"

  isDuplicate: (name) ->
    return false unless @dictionary.dedup[name]?
    return true

  isElement: (name) ->
    return true if @dictionary.elements[name]?
    return true if @dictionary.dedup[name]?
    return false

  getParents: (name) ->
    return null unless @isElement name
    parents = []

    dup = @dictionary.dedup[name]
    if dup?
      for key, value of dup
        for pa in value.parents
          pn = @dictionary.elements[pa]?.name
          if pn? and pn not in parents
            parents = parents.concat pn
    else
      element = @dictionary.elements[name]
      parents = parents.concat element.parents

    return parents

  getVarName: (parent, name) ->
    return @rootAlias unless name

    dup = @dictionary.dedup[name]
    unless dup?
      return name

    for key, value of dup
      if parent in value.parents
        return key

    return name

  getAlias: (currentPaths) ->
    alias = null
    depth = currentPaths.length
    if depth < 2
      return @getVarName(alias, currentPaths[0])

    for i in [depth - 2..0]
      alias ?= currentPaths[i + 1]
      alias = @getVarName(alias, currentPaths[i])

    return alias

  getSnippetSuggestions: ({bufferPosition}, {currentPath, prefix, input}) ->
    result = []

    prefix = input.trim() if prefix.length is 0
    currentRow = bufferPosition.row + 1
    currentElement = @getAlias(currentPath) ? ""

    for key, snippet of @dictionary.snippets when prefix.length is 0 or
    snippet.snippet.startsWith prefix
      continue if snippet.rowonly? and snippet.rowonly isnt currentRow
      continue if snippet.rowlater? and snippet.rowlater > currentRow
      if not snippet.parents?
        result.push @makeSnippetCompletion snippet, prefix
      else if currentElement in snippet.parents
        result.push @makeSnippetCompletion snippet, prefix

    return result

  makeSnippetCompletion: (snippet, prefix) ->
    text: snippet.name
    snippet: snippet.snippet
    displayText: snippet.displayText ? snippet.name
    description: snippet.description ? ""
    type: snippet.type ? "snippet"
    leftLabel: snippet.leftLabel
    rightLabel: snippet.rightLabel
    replacementPrefix: prefix
    interlock: snippet.interlock

  getElementSuggestions: (request, {prefix, currentPath}) ->
    result = []

    if not request.activatedManually and not prefix
      return result

    prefixName = REGX_ELEMENT_NAME.exec(prefix)?[1] ? ""

    alias = @getAlias currentPath
    element = @dictionary.elements[alias]
    if not element? or not element.children?
      return result

    for childName in element.children
      child = @dictionary.elements[childName]
      unless child?
        continue
      if prefixName is "" or
      child.name.toLowerCase().startsWith(prefixName.toLowerCase())
        result.push @makeElementCompletion(child, prefix)

    if result.length isnt 0
      request.prefix = prefix

    return result

  makeElementCompletion: (element, prefix) ->
    if prefix[0] is "<"
      snippetBuf = element.snippet?.substr 1
      replacementPrefixBuf = prefix.substr 1
    else
      snippetBuf = element.snippet
      replacementPrefixBuf = prefix

    text: element.text ? element.name
    snippet: snippetBuf ? undefined
    displayText: element.displayText ? element.name
    description: element.description ? ""
    type: element.type ? "tag"
    leftLabel: element.leftLabel
    rightLabel: element.rightLabel
    replacementPrefix: replacementPrefixBuf
    interlock: element.interlock
    autoindent: element.autoindent ? true

  getAttributeSuggestions: ({prefix, currentPath, currentBody}) ->
    result = []

    alias = @getAlias(currentPath)
    element = @dictionary.elements[alias]
    if not element? or not element.attributes?
      return result

    attributePrefix = REGX_ATTRIBUTE.exec(prefix)?[1] ? ""

    for key, attribute of element.attributes
      unless attribute?
        attribute = {}
      unless attribute.name?
        attribute.name = key
      if (new RegExp("\\s#{attribute.name}\\s*=")).test(currentBody)
        continue
      if attributePrefix is "" or
      attribute.name.toLowerCase().startsWith(attributePrefix.toLowerCase())
        if attribute.values? and attribute.values.length > 0
          attribute.interlock = true
        result.push @makeAttributeCompletion(attribute, attributePrefix)

    return result

  makeAttributeCompletion: (attribute, prefix) ->
    if attribute.dollars
      snippet = "#{attribute.name}=\"$1\""
    else
      snippet = "#{attribute.name}=\"$1\"$2"

    text: attribute.name
    snippet: snippet
    displayText: attribute.displayText ? attribute.name
    description: attribute.description
    type: attribute.type ? "attribute"
    rightLabel: attribute.rightLabel
    leftLabel: attribute.leftLabel
    replacementPrefix: attribute.prefix
    interlock: attribute.interlock

  getAttributeValueSuggestions: ({prefix, currentPath, currentBody}) ->
    result = []

    alias = @getAlias(currentPath)
    element = @dictionary.elements[alias]
    if not element? or not element.attributes?
      return result

    attributes = REGX_ATTRIBUTE_VALUE.exec(prefix)
    currentAttribute = attributes?[1] ? ""
    valuePrefix = attributes?[2] ? ""

    attribute = element.attributes[currentAttribute]
    if not attribute? or not attribute.values?
      return result

    regex = new RegExp(
      "\\s#{currentAttribute}\\s*=\\s*([\"'])([^<>\\n]*?)\\1", "g")

    enteredValue = regex.exec(currentBody)?[2] ? ""
    enteredDelimiters = []
    for delimiter in attribute.delimiters
      if enteredValue.includes delimiter
        enteredDelimiters.push delimiter

    valueList = attribute.valueList
    delimiterList = attribute.delimiterList

    if attribute.isPredicateName?
      if @isSuggestSystemPredicateNames and @systemPredicateNames?.length > 0
        addValueList = @systemPredicateNames.filter (element, index, array) ->
          element not in valueList
        valueList = valueList.concat addValueList
      if @autoPredicateNames?.length > 0
        addValueList = @autoPredicateNames.filter (element, index, array) ->
          element not in valueList
        valueList = valueList.concat addValueList

    isDelmimitType = false
    if enteredDelimiters.length is 0
      if enteredValue.length isnt 0
        for value, index in valueList
          delimiter = delimiterList[index]
          if enteredValue is value and delimiter and delimiter?
            enteredDelimiters.push delimiter
            isDelmimitType = true
            break
      prefix = valuePrefix
      if enteredValue?
        values = [enteredValue]
      else
        values = [valuePrefix]
    else
      wk = valuePrefix.split(delimiter)
      prefix = wk[wk.length - 1] ? ""
      if enteredDelimiters.length > 1
        buf = enteredValue
        for enterDelimiter, i in enteredDelimiters when i > 1
          buf = buf.replace(enterDelimiter, enteredDelimiters[0])
      values = enteredValue.split(enteredDelimiters[0])
      for value in values when value isnt "" and value isnt prefix
        if value in attribute.delimitValues
          isDelmimitType = true
        else
          isDelmimitType = false
          break

    if not isDelmimitType and enteredDelimiters.length isnt 0
      return result

    for value, index in valueList
      delimiter = delimiterList[index]
      if isDelmimitType
        if not delimiter and not delimiter?
          continue
      else
        if values[0] isnt prefix
          continue

      continue if value in values
      if prefix isnt "" and prefix is value
        continue
      unless value.toLowerCase().startsWith(prefix.toLowerCase())
        continue
      result.push @makeAttributeValueCompletion(value, prefix)

    return result

  makeAttributeValueCompletion: (value, prefix) ->
    text: value
    snippet: value if REGX_CHK_SNIPPET.test value
    type: "value"
    replacementPrefix: prefix if prefix.length isnt 0

  getContentsSuggestions: (request, {prefix, currentPath, input, lastBody}) ->
    result = []

    if prefix isnt "" and REGX_CHK_TAG_OPEN.test(prefix)
      return result

    if REGX_CHK_TAG_CLOSE.test(lastBody)
      return result

    prefixName = prefix

    alias = @getAlias(currentPath)
    element = @dictionary.elements[alias]
    if not element? or not element.contents?
      return result

    valueList = element.contents

    if element.contents.isPredicateName?
      if @isSuggestSystemPredicateNames and @systemPredicateNames?.length > 0
        addValueList = @systemPredicateNames.filter (element, index, array) ->
          element not in valueList
        valueList = valueList.concat addValueList
      if @autoPredicateNames?.length > 0
        addValueList = @autoPredicateNames.filter (element, index, array) ->
          element not in valueList
        valueList = valueList.concat addValueList

    for content in valueList
      unless content?
        continue
      if input is "" or (input isnt content and
      content.toLowerCase().startsWith(input.toLowerCase()))
        result.push @makeContentsCompletion(content, input)

    if result.length isnt 0
      request.prefix = input

    return result

  makeContentsCompletion: (content, prefix) ->
    text: content
    snippet: content if REGX_CHK_SNIPPET.test content
    type: "value"
    replacementPrefix: prefix if prefix.length isnt 0

  setSystemPredicateNames: (predicateNames) ->
    @systemPredicateNames = predicateNames

  setAutoPredicateNames: (predicateNames) ->
    @autoPredicateNames = predicateNames
