Emitter = null

Fs = null
Path = null
CSON = null
Dictionary = null
Project = null

REGEX_VARIABLE = /^#([^\s]+)/

module.exports =
  internalDictionaryPath: 'resources/dictionary_xaiml1.0.0.cson'
  isLoading: false
  emitter: null
  eventName: "did-load-dictionary"

  initialize: ->
    Emitter ?= require("atom").Emitter
    @emitter ?= new Emitter()

    Dictionary ?= require "./dictionary"

    {CompositeDisposable} = require 'atom'
    @subscriptions ?= new CompositeDisposable()

    @subscriptions.add atom.config.observe 'xaiml-editor.suggestOption.builtinSchemaVersion',
    (version) =>
      @internalDictionaryPath = "resources/dictionary_#{version}.cson"

  dispose: ->
    @emitter?.dispose()
    @subscriptions?.dispose()

  onDidLoadDictionary: (callback) ->
    @emitter?.on @eventName, callback

  load: (reload = false) ->
    return new Promise (resolve, reject) =>
      if @isLoading
        return
      @isLoading = true

      @loadExternalDictionary(reload)
        .catch (error) =>
          @loadInternalDictionary()
        .catch (error) =>
          console.error "loadInternalDictionary Error. #{error}"
          @isLoading = false
          reject(error)
        .then () =>
          @isLoading = false
          resolve()

  loadExternalDictionary: (reload = false) ->
    return new Promise (resolve, reject) =>
      path = atom.config.get("xaiml-editor.dictionaryPath").trim()
      return reject("Path Empty") unless path
      if not reload and @lastPath is path
        return resolve()

      @loadDictionary path, (ret) =>
        if not ret or not ret.version?
          atom.notifications.addError "External Dictionary Load Error.",
            detail: """
              #{path}
              #{ret}
              """
            dismissable: true
          return reject(ret)
        try
          Dictionary.setDictionary @parseDictionaly(ret)
        catch error
          atom.notifications.addError "Dictionary Parse Error.",
            detail: """
              #{path}
              #{error}
              #{ret}
              """
            dismissable: true
        @lastPath = path
        @emitter?.emit @eventName, Dictionary.getDictionaryVersion()
        resolve()

  loadInternalDictionary: ->
    return new Promise (resolve, reject) =>
      Path ?= require "path"
      path = Path.resolve(__dirname, "..", @internalDictionaryPath)
      if @lastPath is path
        return resolve()

      @loadDictionary path, (ret) =>
        unless ret.version?
          atom.notifications.addFatalError "Dfault Dictionary Load Error.",
            detail: """
              #{path}
              #{ret}
              """
            dismissable: true
          return reject(ret)
        try
          Dictionary.setDictionary @parseDictionaly(ret)
        catch error
          atom.notifications.addError "Dictionary Parse Error.",
            detail: """
              #{path}
              #{error}
              #{ret}
              """
            dismissable: true
        @lastPath = path
        @emitter?.emit @eventName, Dictionary.getDictionaryVersion()
        resolve()

  loadDictionary: (uri, complete) ->
    Path ?= require "path"
    if Path.extname(uri) is ".cson"
      CSON ?= require "season"
      PARSER = CSON
    else if Path.extname(uri) is ".json"
      PARSER = JSON
    else
      CSON ?= require "season"
      PARSER = CSON

    Fs ?= require "fs-plus"
    Fs.readFile uri, (error, content) ->
      if error?
        atom.notifications.addError "Dictionary Read Error.",
          detail: """
            #{uri}
            #{error}
            """
          dismissable: true
      else
        ret = PARSER.parse(content) unless error?
        complete(ret)

  parseDictionaly: (dictionary) ->
    for key, dup of dictionary.dedup
      for key, alias of dup
        parents = []
        for parent in alias.parents
          groupName = REGEX_VARIABLE.exec(parent)?[1]
          unless groupName?
            parents.push parent
            continue
          group = dictionary.parents_groups[groupName]
          continue unless group?
          parents = parents.concat(group.parents)
        alias.parents = parents

    for key, snippet of dictionary.snippets
      if snippet.parents?
        parents = []
        for parent in snippet.parents
          if parent is ""
            parents.push Dictionary.rootAlias
            continue
          groupName = REGEX_VARIABLE.exec(parent)?[1]
          unless groupName?
            parents.push parent
            continue
          group = dictionary.parents_groups?[groupName]
          continue unless group?
          parents = parents.concat(group.parents)
        snippet.parents = parents


    for key, element of dictionary.elements
      if element.children?
        children = []
        for child in element.children
          groupName = REGEX_VARIABLE.exec(child)?[1]
          unless groupName?
            children.push child
            continue
          group = dictionary.children_groups?[groupName]
          continue unless group?
          children = children.concat(group.children)
        element.children = children
      if element.parents?
        parents = []
        for parent in element.parents
          groupName = REGEX_VARIABLE.exec(parent)?[1]
          unless groupName?
            parents.push parent
            continue
          group = dictionary.parents_groups?[groupName]
          continue unless group?
          parents = parents.concat(group.parents)
        element.parents = parents
      if element.attributes?
        attributes = {}
        for key, attribute of element.attributes
          name = attribute?.name ? key
          groupName = REGEX_VARIABLE.exec(name)?[1]
          unless groupName?
            attributes[name] = attribute
            continue
          group = dictionary.attributes_types?[groupName]
          continue unless group?
          for key, attr of group.attributes
            attributes[attr?.name ? key] = attr
        element.attributes = attributes
        for key, attribute of element.attributes
          if attribute?.values?
            dollars = false
            valueList = []
            delimiterList = []
            convertValues = []
            delimiters = []
            delimitValues = []
            for value in attribute.values
              dollars = value.split("$").length > 2
              typeName = REGEX_VARIABLE.exec(value)?[1]
              unless typeName?
                valueList.push value
                delimiterList.push attribute.delimiter
                convertValues.push
                  value: value
                  delimiter: attribute.delimiter
                if attribute.delimiter
                  delimitValues.push value
                  if attribute.delimiter not in delimiters
                    delimiters.push attribute.delimiter
                continue
              if typeName is "PredicateName"
                attribute.isPredicateName = true
              type = dictionary.values_types?[typeName]
              continue unless type?
              for value in type.values
                valueList.push value
                delimiterList.push type.delimiter
                convertValues.push
                  value: value
                  delimiter: type.delimiter
                if type.delimiter
                  delimitValues.push value
                  if type.delimiter not in delimiters
                    delimiters.push type.delimiter
            attribute.dollars = dollars
            attribute.valueList = valueList
            attribute.delimiterList = delimiterList
            attribute.convertValues = convertValues
            attribute.delimiters = delimiters
            attribute.delimitValues = delimitValues
      if element.contents?
        contents = []
        for content in element.contents
          groupName = REGEX_VARIABLE.exec(content)?[1]
          unless groupName?
            contents.push content
            continue
          if groupName is "PredicateName"
            contents.isPredicateName = true
          group = dictionary.values_types?[groupName]
          continue unless group?
          contents = contents.concat(group.values)
        element.contents = contents

    for key, element of dictionary.elements
      if key is "_ROOT_"
        element.name = ""
        continue
      unless element.name?
        element.name = key
      unless element.parents?
        element.parents = []
        for k, v of dictionary.elements
          continue unless v.children?
          if key in v.children
            if (v.name ? k) not in element.parents
              element.parents.push v.name ? k

    systemPredicateNames = dictionary.values_types?["SystemPredicate"]?.values
    if systemPredicateNames?.length > 0
      Dictionary.setSystemPredicateNames systemPredicateNames

    return dictionary
