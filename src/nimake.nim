import tables, os, osproc, sequtils, times, strformat, strutils, segfaults, sets, colorize

export `/`, walkDirRec, walkDir, walkFiles, walkDirs, walkPattern
export parentDir, splitPath
export `&`
export sequtils, strutils, colorize, osproc

type
  BuildDef = object
    isfake: bool
    taskname: string
    mainfile: string
    depfiles: seq[string]
    action: proc(): BuildResult
    cleans: proc()
  BuildResult* = enum
    Success, Failed

const tmpdir* = ".nimakefiles"
var targets = newTable[string, BuildDef] 16
var verb = 0
var defaultTarget = ""

proc getProjectDir*(): string = getAppDir() / ".."

template walkTargets*(x) = toSeq(targets.keys).filterIt x

template exec*(cmd: string) =
  if verb >= 1:
    echo "exec ".fgGreen, cmd
  let code = execShellCmd(cmd)
  if code != 0:
    stderr.writeLine "Executing '$1' failed with code $2.".format(cmd, code)
    return Failed

template mkdir*(dir) =
  if not dirExists dir:
    try:
      if verb >= 1:
        echo "mkdir ".fgBlue, dir
      createDir dir
    except:
      stderr.writeLine "Cannot create directory: $1.".format(dir)

template rm*(path) =
  if verb >= 2:
    echo "removing ".fgLightRed, path
  if dirExists path:
    if verb >= 1:
      echo "rm -r ".fgLightRed, path
    removeDir path
  elif fileExists path:
    if verb >= 1:
      echo "rm ".fgLightRed, path
    removeFile path

template withDir*(dir, xbody) =
  let curDir = getCurrentDir()
  if not dirExists(dir):
    mkdir dir
  try:
    if verb >= 2:
      echo "entering ".fgBlue, dir
    setCurrentDir dir
    xbody
  except:
    stderr.writeLine "Failed to change working directory to $1.".format(dir)
    return Failed
  finally:
    if verb >= 2:
      echo "leaving ".fgBlue, dir
    setCurrentDir curDir

template cp*(source, dest: string) =
  try:
    if verb >= 1:
      echo "copy ".fgGreen, source, " ", dest
    copyFile source, dest
  except:
    stderr.writeLine "Failed to copy file from $1 to $2.".format(source, dest)
    return Failed

template target*(file: string, getDef: untyped) =
  block:
    let target {.inject,used.} = file
    var name {.inject,used.}: string = ""
    var fake {.inject,used.}: bool = false
    var deps {.inject,used.}: seq[string] = newSeqOfCap[string] 256
    var main {.inject,used.}: string
    var cleans: proc() = proc() =
      if not fake:
        rm getProjectDir() / file

    template dep(it) {.used.} =
      deps.add(it)
    template depIt(it) {.used.} =
      deps.add(toSeq it)
    template clean(body) {.used.} =
      cleans = proc() =
        setCurrentDir getProjectDir()
        body
    template receipt(body): BuildDef {.used.} =
      BuildDef(
        isfake: fake,
        taskname: name,
        mainfile: main,
        depfiles: deps,
        cleans: cleans,
        action: proc(): BuildResult =
          setCurrentDir getProjectDir()
          body
          return Success
      )
    targets[target] = getDef

proc checkfake(name: string): bool =
  if targets.contains name:
    return targets[name].isfake

template onDemand(target: string, def: BuildDef, build) =
  block demand:
    let friendlyname = if def.taskname != "":
      def.taskname & "('" & target & "')"
    else:
      "'" & target & "'"
    if verb >= 2:
      echo "checking ".fgMagenta, friendlyname
    for f in def.depfiles:
      if (not fileExists f) and (not checkfake(f)):
        stderr.writeline "Recipe for " & friendlyname & " failed, file '" & f & "' is not exists"
        return Failed
    if not def.isfake and target.fileExists:
      if verb >= 2:
        echo "exist ".fgYellow, friendlyname
      let targetTime = target.getLastModificationTime
      let depsTime = def.genLatest
      if targetTime >= depsTime:
        if verb >= 1:
          echo "skipped ".fgYellow, friendlyname
        break demand
      if verb >= 2:
        echo "outdated ".fgRed, friendlyname
    build

template default*(target: string) =
  defaultTarget = target

proc genLatest(build: BuildDef): Time =
  result = fromUnix(0)
  if build.mainfile != "":
    result = build.mainfile.getLastModificationTime
  for f in build.depfiles:
    let temp = f.getLastModificationTime
    if temp > result:
      result = temp

iterator reorder(subtargets: TableRef[string, BuildDef]): tuple[tgt: string, def: BuildDef] =
  var tab = initTable[string, tuple[def: BuildDef, deps: HashSet[string]]] 256
  var tgts = toSeq subtargets.keys()
  for target, def in subtargets:
    tab[target] = (def, def.depfiles.filterIt(it in tgts).toHashSet)
  while tab.len > 0:
    var queue = newSeqOfCap[string] 256
    for target, tp in tab:
      if tp.deps.len == 0:
        yield (target, tp.def)
        queue.add target
    if queue.len == 0:
      stderr.writeLine "Cannot resolve dependences: " & toSeq(tab.keys()).join(", ")
      break
    for item in queue:
      tab.del item
    for item in queue:
      for _,tp in tab.mpairs:
        tp.deps.excl item

proc buildOne*(tgt: string): BuildResult =
  if tgt in targets:
    let def = targets[tgt]
    var tmpTargets = def.depfiles.filterIt(it in targets).mapIt((it, targets[it])).newTable
    tmpTargets[tgt] = def
    for target, def in reorder(tmpTargets):
      onDemand(target, def):
        if verb >= 1:
          echo "building ".fgLightGreen.bold, target
        if def.action() != Success:
          return Failed
    if verb >= 1:
      echo "all done".fgLightGreen.bold
    return Success
  stderr.writeLine "No receipt for " & tgt
  Failed

proc buildAll*(): BuildResult =
  for target, def in reorder(targets):
    onDemand(target, def):
      if verb >= 1:
        echo "building ".fgLightGreen.bold, target
      if def.action() != Success:
        return Failed
  if verb >= 1:
    echo "all done".fgLightGreen.bold
  Success

proc clean*(verbosity: int = 0) =
  verb = verbosity
  for t, def in targets:
    if verb >= 1:
      echo "clean ".fgRed.bold, t
    def.cleans()

proc fail2fatal(res: BuildResult) =
  if res == Failed:
    quit 1

proc build(target: string = "", verbosity: int = 0) =
  verb = verbosity
  if target == "":
    if defaultTarget == "":
      fail2fatal buildAll()
    else:
      fail2fatal buildOne(defaultTarget)
  else:
    fail2fatal buildOne(target)

template handleCLI*() =
  import cligen
  dispatchMulti([build], [clean])

proc toExe*(filename: string): string =
  (when defined(windows): &"{filename}.exe" else: filename)

proc toDll*(filename: string): string =
  (when defined(windows): &"{filename}.lib" else: &"lib{filename}.so")

when isMainModule:
  var args = commandLineParams()
  var nimakefile = "build.nim"

  if args.len >= 1 and args[0].endsWith(".nim"):
    nimakefile = args[0]
    args.delete 0

  let striped = nimakefile[0..^5].multiReplace {"/": "@", "\\": "@"}
  let exe = tmpdir / striped.toExe

  targets[exe] = BuildDef(
    taskname: "build",
    mainfile: nimakefile,
    depfiles: @[],
    cleans: proc () = removeDir(tmpdir),
    action: proc(): BuildResult =
      echo &"Rebuilding {nimakefile}..."
      mkdir tmpdir
      exec &"nim c --verbosity:0 --hints:off --out:{exe} --nimcache:{tmpdir} --skipProjCfg:on --skipParentCfg:on --opt:speed {nimakefile}"
      return Success
  )
  build()

  quit(execCmd(exe & " " & args.join(" ")))