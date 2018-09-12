TextBuffer = null

Fs = null
Path = null
Util = null

module.exports =
class Replacer
  totalRep: 0

  constructor: (@currentEditor) ->
    Util ?= require "./util"
    @projectDir = Util.getProjectDir(@currentEditor)
    @openedPaths = []
    @replaced = []
    @errors = []

  replace: (@oldText, @newText) ->
    new Promise (resolve) =>
      if @oldText is @newText
        console.debug "Skip Same Value: #{@oldText} -> #{@newText}"
        return resolve()

      console.debug "Project: #{@projectDir?.getPath()}"
      console.debug "Replace: #{@oldText} -> #{@newText}"

      @replaceCurrentEditor()
        .then =>
          @replaceOpenedEditors()
        .then =>
          @replaceOtherFiles()
        .then =>
          console.debug "Replace Completed."
          atom.notifications.addSuccess "Replace Completed.",
            detail: """
              From: "#{@oldText}"  To: "#{@newText}"
              #{@replaced.join("\n")}
              Files: #{@replaced.length}  Total: #{@totalRep}
              """
            dismissable: true
          if @errors.length > 0
            atom.notifications.addError "Replace Error.",
              detail: """
                From: "#{@oldText}"  To: "#{@newText}"
                #{@errors.join("\n")}
                Total: #{@errors.length}
                """
              dismissable: true
          resolve()

  replaceCurrentEditor: ->
    new Promise (resolve) =>
      vae = new VirtualAimlEditor()
      p = vae.duplicate(@currentEditor)
      p.then (veditor) =>
        count = Replacer.replaceEditor(veditor.editor, @oldText, @newText)
        console.debug "CurrentEditor: #{veditor.path} (#{count})"
        return resolve() if count is 0
        veditor.writeBack()
        @replaced.push "#{veditor.path} (#{count})"
        @totalRep += count
        resolve()

  replaceOpenedEditors: ->
    new Promise (resolve) =>
      return resolve() unless @projectDir?

      Util ?= require "./util"
      ps = []
      for openedEditor in atom.workspace.getTextEditors()
        @openedPaths.push path = openedEditor.getPath()
        continue if openedEditor is @currentEditor
        continue unless Util.isAimlEditor(openedEditor)
        continue unless @projectDir.contains(path)
        console.debug "AIML: #{path}"

        p = new VirtualAimlEditor().duplicate(openedEditor)
        .then (veditor) =>
          count = Replacer.replaceEditor(veditor.editor, @oldText, @newText)
          console.debug "OpenedEditor: #{veditor.path} (#{count})"
          return if count is 0
          veditor.writeBack()
          @replaced.push "#{veditor.path} (#{count})"
          @totalRep += count
        .catch (error) ->
          console.error error
        ps.push p

      Promise.all ps
        .then -> resolve()

  replaceOtherFiles: ->
    new Promise (resolve) =>
      return resolve() unless @projectDir?

      Fs ?= require "fs-plus"
      Path ?= require "path"
      paths = []
      console.debug "=== traverseTreeSync ==="
      console.time("traverseTreeSync")
      onFile = (path) =>
        if Path.extname(path) is ".aiml"
          console.debug "AIML: #{path}"
          if path not in @openedPaths and path not in paths
            paths.push path
      onDir = (path) ->
        Fs.traverseTreeSync(path, onFile, onDir)
      Fs.traverseTreeSync(@projectDir.getPath(), onFile, onDir)
      console.timeEnd("traverseTreeSync")

      console.debug paths.join('\n')

      ps = []
      for path in paths
        p = new VirtualAimlEditor().open(path)
        .then (veditor) =>
          if veditor.error
            @errors.push "#{veditor.path} (#{veditor.error})"
            return
          count = Replacer.replaceEditor(veditor.editor, @oldText, @newText)
          console.debug "OtherFile: #{veditor.path} (#{count})"
          return if count is 0
          veditor.save()
          if veditor.error
            @errors.push "#{veditor.path} (#{veditor.error})"
            return
          @replaced.push "#{veditor.path} (#{count})"
          @totalRep += count
        .catch (error) ->
          console.error error
        ps.push p

      Promise.all ps
        .then -> resolve()

  @replaceEditorOld: (editor, oldText, newText, callback = null) ->
    result = 0

    unless atom.workspace.isTextEditor(editor)
      console.error "Not TextEditor"
      return result
    unless oldText?
      console.error "oldText Error"
      return result

    Util ?= require "./util"
    before = Util.escapeRegExp(oldText)

    attributeValue = "([\"'])#{before}\\1"
    contentsValue = "<([^\\s/>]+)([^>]*>)#{before}(</\\2\\s*>)"
    regex = new RegExp("#{attributeValue}|#{contentsValue}", "g")

    editor.scan regex, ({match, matchText, range, stop, replace}) ->
      if /^[\"']/.test(matchText)
        scopePos = range.start
        scopeDes = editor.scopeDescriptorForBufferPosition(scopePos)
        return unless scopeDes
        scopes = scopeDes.getScopesArray()
        if scopes.indexOf("text.aiml") isnt -1 and
            scopes.indexOf("comment.block.aiml") is -1 and
            (scopes.indexOf("meta.tag.aiml") isnt -1 or
            scopes.indexOf("meta.tag.no-content.aiml") isnt -1) and
            (scopes.indexOf("string.quoted.double.aiml") isnt -1 or
            scopes.indexOf("string.quoted.single.aiml") isnt -1) and
            scopes.indexOf("punctuation.definition.string.begin.aiml") isnt -1
          if callback?
            callback(range.translate([0, 1], [0, -1]))
          else if newText?
            replace("#{match[1]}#{newText}#{match[1]}")
          result++
        else
          console.debug scopes
      else if /^</.test(matchText)
        scopePos = range.start.translate([0, 1])
        scopeDes = editor.scopeDescriptorForBufferPosition(scopePos)
        return unless scopeDes
        scopes = scopeDes.getScopesArray()
        if scopes.indexOf("text.aiml") isnt -1 and
            scopes.indexOf("comment.block.aiml") is -1 and
            (scopes.indexOf("meta.tag.aiml") isnt -1 or
            scopes.indexOf("meta.tag.no-content.aiml") isnt -1) and
            scopes.indexOf("entity.name.tag.localname.aiml") isnt -1 and
            scopes.indexOf("meta.tag.preprocessor.aiml") is -1 and
            scopes.indexOf("meta.tag.sgml.doctype.aiml") is -1 and
            scopes.indexOf("source.java-props.embedded.aiml") is -1 and
            scopes.indexOf("source.java.embedded.aiml") is -1 and
            scopes.indexOf("string.unquoted.cdata.aiml") is -1
          if callback?
            startTrim = 1 + match[2].length + match[3].length
            endTrim = match[4].length * -1
            callback(range.translate([0, startTrim], [0, endTrim]))
          else if newText?
            replace("<#{match[2]}#{match[3]}#{newText}#{match[4]}")
          result++
        else
          console.debug scopes
      else
        console.error matchText

    return result

  @replaceEditor: (editor, oldText, newText, callback = null) ->
    result = 0

    unless atom.workspace.isTextEditor(editor)
      console.error "Not TextEditor"
      return result
    unless oldText?
      console.error "oldText Error"
      return result

    Util ?= require "./util"
    before = Util.escapeRegExp(oldText)

    regex = new RegExp("([\"'])#{before}\\1", "g")
    editor.scan regex, ({match, matchText, range, stop, replace}) ->
      scopePos = range.start
      scopeDes = editor.scopeDescriptorForBufferPosition(scopePos)
      return unless scopeDes
      scopes = scopeDes.getScopesArray()
      if "text.aiml" in scopes and "comment.block.aiml" not in scopes and
          ("meta.tag.aiml" in scopes or "meta.tag.no-content.aiml" in scopes) and
          ("string.quoted.double.aiml" in scopes or "string.quoted.single.aiml" in scopes) and
          "punctuation.definition.string.begin.aiml" in scopes
        if callback?
          callback(range.translate([0, 1], [0, -1]))
        else if newText?
          replace("#{match[1]}#{newText}#{match[1]}")
        result++
      else
        console.debug scopes

    regex = new RegExp("<([^\\s/>]+)([^>]*>)#{before}(</\\1\\s*>)", "g")
    editor.scan regex, ({match, matchText, range, stop, replace}) ->
      scopePos = range.start.translate([0, 1])
      scopeDes = editor.scopeDescriptorForBufferPosition(scopePos)
      return unless scopeDes
      scopes = scopeDes.getScopesArray()
      if "text.aiml" in scopes and "comment.block.aiml" not in scopes and
          ("meta.tag.aiml" in scopes or "meta.tag.no-content.aiml" in scopes) and
          "entity.name.tag.localname.aiml" in scopes and
          "meta.tag.preprocessor.aiml" not in scopes and
          "meta.tag.sgml.doctype.aiml" not in scopes and
          "source.java-props.embedded.aiml" not in scopes and
          "source.java.embedded.aiml" not in scopes and
          "string.unquoted.cdata.aiml" not in scopes
        if callback?
          startTrim = 1 + match[1].length + match[2].length
          endTrim = match[3].length * -1
          callback(range.translate([0, startTrim], [0, endTrim]))
        else if newText?
          replace("<#{match[1]}#{match[2]}#{newText}#{match[3]}")
        result++
      else
        console.debug scopes

    return result

  @scanEditor: (editor, searchText, callback) ->
    Replacer.replaceEditor(editor, searchText, null, callback)

class VirtualAimlEditor
  grammar: null
  editor: null
  event: null
  path: null
  error: null
  lineCount: null
  chunkSize: null
  chunked: false
  srcEditor: null

  constructor: ->

    @grammar = atom.grammars.grammarForScopeName('text.aiml')
    @editor = atom.workspace.buildTextEditor()
    @editor.setGrammar @grammar
    @editor.setVisible(true) # このフラグを立てないと構文解析が途中までしか行われない
    @chunkSize = @editor.displayBuffer?.tokenizedBuffer?.chunkSize ? 50

  open: (@path) ->
    new Promise (resolve, reject) =>
      Util ?= require "./util"
      bytes = Util.getFileSize(@path)
      if Util.isInvalidFileSize(bytes)
        @error = "Invalid Size: #{Util.toStringBytes(bytes)}"
        return resolve(@)

      Fs ?= require "fs-plus"
      try
        text = Fs.readFileSync(@path, "utf-8")
      catch error
        console.error error
        @error = error
        return resolve(@)

      unless text
        return resolve(@)

      TextBuffer ?= require('atom').TextBuffer
      buffer = new TextBuffer(text)
      @lineCount = buffer.getLineCount()

      if @chunkSize < @lineCount
        @chunked = true

      if @editor.onDidTokenize?
        @event = @editor.onDidTokenize () =>
          @event.dispose()
          console.debug "onDidTokenize #{@path}"
          resolve(@)
      else
        @event = @editor.onDidChange (event) =>
          if @lineCount is event.end + 1 or
              (!@chunked and @lineCount is event.bufferDelta + 1)
            @event.dispose()
            console.debug "onDidChange: #{@path}"
            console.debug event
            resolve(@)

      @editor.setText text

  save: ->
    Fs ?= require "fs-plus"
    try
      Fs.writeFileSync @path, @editor.getText()
    catch error
      console.error error
      @error = error
      return
    console.debug "File Saved. #{@path}"

  duplicate: (@srcEditor) ->
    new Promise (resolve, reject) =>
      console.debug @srcEditor.getBuffer().getMaxCharacterIndex()
      @path = @srcEditor.getPath()
      text = @srcEditor.getText()
      unless text
        return resolve(@)

      TextBuffer ?= require('atom').TextBuffer
      buffer = new TextBuffer(text)
      @lineCount = buffer.getLineCount()

      console.debug @chunkSize
      console.debug @lineCount
      if @chunkSize < @lineCount
        @chunked = true

      if @editor.onDidTokenize?
        @event = @editor.onDidTokenize () =>
          @event.dispose()
          console.debug "onDidTokenize #{@path}"
          resolve(@)
      else
        @event = @editor.onDidChange (event) =>
          if @lineCount is event.end + 1 or
              (!@chunked and @lineCount is event.bufferDelta + 1)
            @event.dispose()
            console.debug "onDidChange: #{@path}"
            console.debug event
            resolve(@)

      @editor.setText text

  writeBack: ->
    return unless @srcEditor?
    lastPos = @srcEditor.getLastCursor().getBufferPosition()
    @srcEditor.setText(@editor.getText())
    @srcEditor.setCursorBufferPosition(lastPos)
