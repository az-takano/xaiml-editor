CompositeDisposable = null
Directory = null

Path = null
Fs = null
CSON = null
Util = null
DictionaryLoader = null
rp = null

module.exports =

  initialize: ->
    {CompositeDisposable, Directory} = require 'atom'
    @subscriptions = new CompositeDisposable()
    @subscriptions.add atom.commands.add 'atom-workspace',
      'xaiml-editor:reloadProjectSettings': => @loadProjectSettings(true)
    @loadPaths = []

  dispose: ->
    @subscriptions.dispose()

  loadProjectSettings: (isManual = false) ->
    new Promise (resolve) =>
      @loadProjects atom.project.getPaths(), isManual
        .then ->
          if isManual
            atom.notifications.addSuccess "Project Settings Loaded."
          resolve()
        .catch ->
          resolve()

  isCurrentProject: (projectPath) ->
    return false unless projectPath
    editor = atom.workspace.getActiveTextEditor()
    unless atom.workspace.isTextEditor(editor)
      return false
    dir = new Directory projectPath
    unless dir.contains editor.getPath()
      return false
    return true

  loadProjects: (projectPaths, isManual = false) ->
    return new Promise (resolve, reject) =>
      Path ?= require "path"
      Util ?= require "./util"
      ps = []
      for projectPath in projectPaths
        filePath = Path.resolve projectPath
        continue unless Util.isFileExist filePath
        p = new Promise (resolve) =>
          @loadProject projectPath
          .then (projectPath) ->
            resolve()
          .catch (error) ->
            atom.notifications.addError "Load Project Settings Error.",
              detail: """
                #{error.projectPath}
                #{error}
                """
              dismissable: true
            resolve()
        p.catch (error) ->
          console.error error
        ps.push p

      Promise.all ps
        .then =>
          if isManual
            for projectPath in projectPaths
              if @isCurrentProject projectPath
                DictionaryLoader ?= require "./dictionary-loader"
                DictionaryLoader.load(true)
                break
          resolve()
        .catch -> reject()

  loadProject: (projectPath) ->
    return new Promise (resolve, reject) =>
      if projectPath not in atom.project.getPaths()
        atom.notifications.addError "Project Path Error.",
          detail: "#{projectPath}"
          dismissable: true
        return reject(projectPath)
      return resolve(projectPath)
