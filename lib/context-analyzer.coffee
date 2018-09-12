Range = null

Dictionary = null

REGX_INPUT_TAG = /<[^!?%<>\s]*$/
REGX_CURRENT_ELEMENT = /<([^\/!?%<>\s][^\/<>\s]*)[\s\/][^<>]*/
REGX_PARENT_ELEMENT_G = /<([^\/!?%<>\s][^\/<>\s]*)\s*[^<>]*>|<\/([^<>\s]+)[^\/<>]*>/g
REGX_END_CLOSE = /\/>$/
REGX_START_CLOSE = /^<\//
REGX_TAG_G = /<|>/g

module.exports =
class ContextAnalyzer

  constructor: ({@activatedManually, @bufferPosition, @editor, @prefix, @scopeDescriptor}) ->
    Range ?= require("atom").Range
    Dictionary ?= require "./dictionary"

    @isInnerElmentTag = false
    @firstTagEnd = null
    @lastTag = null
    @currentPaths = []
    @currentTagBody = ""
    @scanRange = new Range([0, 0], @bufferPosition)
    @cursorWord = @editor.getWordUnderCursor()

  analyze: ->
    unless @getCurrentElement()
      for i in [1..100]
        if @getParentElement()
          break

    if @isInnerElmentTag
      @getCurrentTagBody()
    else
      @input = @editor.getTextInBufferRange([@firstTagEnd, @bufferPosition])
      @inputTag = REGX_INPUT_TAG.exec(@input)?[0] ? ""

    currentPath: @currentPaths
    input: @input
    prefix: @inputTag
    currentBody: @currentTagBody
    lastBody: @lastTag

  getCurrentElement: ->
    result = false
    @editor.backwardsScanInBufferRange REGX_CURRENT_ELEMENT, @scanRange, ({match, matchText, range, stop}) =>
      if range.end.compare(@bufferPosition) isnt 0
        return
      scopes = @editor.scopeDescriptorForBufferPosition(range.start.translate([0, 1])).getScopesArray()
      if "meta.tag.aiml" not in scopes and "meta.tag.no-content.aiml" not in scopes
        return
      if elm = match[1]
        @isInnerElmentTag = true
        @firstTagEnd = range.start
        @inputTag = @input = matchText
        @currentPaths.push elm
        result = !Dictionary.isDuplicate(elm)

    return result

  getParentElement: ->
    result = false
    closeElement = null
    @editor.backwardsScanInBufferRange REGX_PARENT_ELEMENT_G, @scanRange, ({match, matchText, range, stop}) =>
      scopes = @editor.scopeDescriptorForBufferPosition(range.start).getScopesArray()
      if ContextAnalyzer.isIgnoreScopes(scopes)
        return
      else if elm = match[1]
        if Dictionary.isElement(elm) and not REGX_END_CLOSE.test(matchText)
          @currentPaths.push elm
          result = !Dictionary.isDuplicate(elm)
          @scanRange.end = range.start
          stop()
      else if elm = match[2]
        if Dictionary.isElement(elm)
          closeElement = elm
          @scanRange.end = range.start
          stop()

      @firstTagEnd ?= range.end
      @lastTag ?= matchText

    if closeElement?
      result = @getParentElementByCloseElement(closeElement)

    return result

  getParentElementByCloseElement: (closeElement) ->
    result = false
    parents = Dictionary.getParents(closeElement)
    if not parents?
      return true
    else if parents.length is 1 and @currentPaths.length is 0 and
    !Dictionary.isDuplicate(parents[0])
      @currentPaths.push parents[0]
      return true

    skipOpenOnce = null
    if closeElement in parents
      skipOpenOnce = closeElement

    buf = "</?(#{parents.join('|')})\\s*[^<>]*>"
    regex = new RegExp(buf, "g")
    closeCount = 0

    @editor.backwardsScanInBufferRange regex, @scanRange, ({match, matchText, range, stop}) =>
      scopes = @editor.scopeDescriptorForBufferPosition(range.start).getScopesArray()
      if ContextAnalyzer.isIgnoreScopes(scopes)
        return
      else if REGX_END_CLOSE.test matchText
      else if REGX_START_CLOSE.test matchText
        closeCount++
      else if elm = match[1]
        if closeCount is 0
          if skipOpenOnce is elm
            skipOpenOnce = null
          else
            @currentPaths.push elm
            result = !Dictionary.isDuplicate(elm)
            @scanRange.end = range.start
            stop()
        else
          closeCount--


    return result

  getCurrentTagBody: ->
    scanRange = new Range(@firstTagEnd, [Infinity, Infinity])
    currentBodyEnd = null

    @editor.scanInBufferRange REGX_TAG_G, scanRange, ({matchText, range, stop}) =>
      if range.end.compare(@bufferPosition) > 0
        if matchText is "<"
          currentBodyEnd = range.start
        else if matchText is ">"
          currentBodyEnd = range.end
        stop()

    if currentBodyEnd?
      scanRange.end = currentBodyEnd

    @currentTagBody = @editor.getTextInBufferRange(scanRange)

  @isIgnoreScopes = (scopes) ->
    "string.unquoted.cdata.aiml" in scopes or "comment.block.aiml" in scopes or
    "meta.tag.preprocessor.aiml" in scopes or "meta.tag.sgml.doctype.aiml" in scopes or
    "source.java-props.embedded.aiml" in scopes or "source.java.embedded.aiml" in scopes
