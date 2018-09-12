Fs = null
Path = null

regexEscape = /[|\\{}()[\]^$+*?.]/g

module.exports =
  invalidFileSize: 2097152

  getProjectPath: (editor) ->
    return null unless atom.workspace.isTextEditor(editor)
    for dir in atom.project.getDirectories()
      if dir.contains editor.getPath()
        projectPath = dir.getPath()
        break
    return null unless projectPath
    return projectPath

  getProjectDir: (editor) ->
    return null unless atom.workspace.isTextEditor(editor)
    for dir in atom.project.getDirectories()
      if dir.contains editor.getPath()
        projectDir = dir
        break
    return null unless projectDir
    return projectDir

  isAimlEditor: (editor) ->
    return false unless atom.workspace.isTextEditor(editor)
    return @isAimlGrammar(editor.getGrammar())

  isAimlGrammar: (grammar) ->
    return grammar?.name is "AIML"

  escapeRegExp: (value) ->
    value = value?.replace(regexEscape, "\\$&")

  isFileExist: (path) ->
    try
      Fs ?= require "fs-plus"
      stats = Fs.statSync path
    catch error
      return false
    return false unless stats?.isFile()
    return true

  isDirExist: (path) ->
    try
      Fs ?= require "fs-plus"
      stats = Fs.statSync path
    catch error
      return false
    return false unless stats?.isDirectory()
    return true

  getFileSize: (path) ->
    return 0 unless path
    try
      Fs ?= require "fs-plus"
      stats = Fs.statSync path
    catch error
      console.error error
      return -1
    return -1 unless stats?.isFile()
    return stats.size

  # 無効なファイルサイズチェック
  # 2MB以上のファイルは構文解析が機能しないため無効とする（Atom 1.8.0 現在 ）
  isInvalidFileSize: (bytes) ->
    if atom.workspace.isTextEditor(bytes)
      bytes = @getFileSize(bytes.getPath())
    bytes < 0 or @invalidFileSize <= bytes

  toStringBytes: (bytes) ->
    return "#{bytes} B" if bytes < 100
    kb = bytes / 1024
    return "#{kb.toFixed(1)} KB" if kb < 1000
    mb = kb / 1024
    return "#{mb.toFixed(1)} MB" if mb < 1000
    gb = mb / 1024
    return "#{gb.toFixed(1)} GB"

  # ディレクトリ作成
  createDir: (path) ->
    return false if @isDirExist path
    try
      Fs ?= require "fs-plus"
      Fs.mkdirSync path
    catch error
      console.error error
      throw error
    return true

  # ファイルコピー (上書き)
  copyFile: (srcFile, destFile) ->
    try
      Fs ?= require "fs-plus"
      text = Fs.readFileSync srcFile
      Fs.writeFileSync destFile, text
    catch error
      console.error error
      throw error

  # ファイルコピー 非同期
  copyFileAsync: (src, dest) ->
    return new Promise (resolve, reject) ->
      Fs ?= require "fs-plus"
      rs = Fs.createReadStream src
        .on "error", (error) ->
          console.error error
          reject error
      ws = Fs.createWriteStream dest
        .on "error", (error) ->
          console.error error
          reject error
        .on "close", ->
          resolve()
      rs.pipe ws

  # functionチェック
  isFunction: (obj) ->
    typeof obj is 'function'

  # package version
  getPackageVersion: ->
    Path ?= require "path"
    package_json = Path.resolve(__dirname, "..", "package.json")
    return require(package_json).version
