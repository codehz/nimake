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
    cleandeps: seq[string]
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
    echo "removing ".fgLightRed, path.fgYellow
  if dirExists path:
    if verb >= 1:
      echo "rm -r ".fgLightRed, path.fgYellow
    removeDir path
  elif fileExists path:
    if verb >= 1:
      echo "rm ".fgLightRed, path.fgYellow
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
    var cleandeps {.inject,used.}: seq[string] = newSeqOfCap[string] 256
    var main {.inject,used.}: string
    var cleans: proc() = nil

    template dep(it) {.used.} =
      deps.add(it)
    template depIt(it) {.used.} =
      deps.add(toSeq it)
    template cleanDep(it) {.used.} =
      cleandeps.add(it)
    template cleanDepIt(it) {.used.} =
      cleandeps.add(toSeq it)
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
        cleandeps: cleandeps,
        cleans: if cleans != nil or fake: cleans else: (proc() = rm getProjectDir() / file),
        action: proc(): BuildResult =
          setCurrentDir getProjectDir()
          body
          return Success
      )
    targets[target] = getDef

proc checkfake(name: string): bool =
  if targets.contains name:
    return targets[name].isfake

proc getFriendlyName(target: string, def: BuildDef): string =
  if def.taskname != "":
    def.taskname.bold & "(" & target.fgYellow & ")"
  else:
    target.fgYellow

template onDemand(target: string, def: BuildDef, build) =
  block demand:
    let friendlyname = getFriendlyName(target, def)
    if verb >= 2:
      echo "checking ".fgMagenta, friendlyname
    for f in def.depfiles:
      if (not fileExists f) and (not checkfake(f)):
        stderr.writeline "error".fgRed & " Recipe for " & friendlyname & " failed, file '" & f & "' is not exists"
        return Failed
    if not def.isfake and target.fileExists:
      if verb >= 2:
        echo "exist ".fgGreen, friendlyname
      let targetTime = target.getLastModificationTime
      let depsTime = def.genLatest
      if verb >= 3:
        echo "time ".fgCyan, "target: ", ($targetTime).fgCyan, " depsTime: ", ($depsTime).fgCyan
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
  if build.isfake: return
  if build.mainfile != "":
    result = build.mainfile.getLastModificationTime
    if verb >= 4:
      echo "time ".fgBlue, "main ".bold, build.mainfile.fgYellow, " ", ($result).fgCyan
  for f in build.depfiles:
    if checkfake f:
      if verb >= 4:
        echo "time ".fgBlue, f.fgYellow, " ", "skipped".fgRed
      continue
    let temp = f.getLastModificationTime
    if verb >= 4:
      echo "time ".fgBlue, f.fgYellow, " ", ($temp).fgCyan
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

iterator cleanReorder(subtargets: TableRef[string, BuildDef]): tuple[tgt: string, def: BuildDef] =
  var tab = initTable[string, tuple[def: BuildDef, deps: HashSet[string]]] 256
  var tgts = toSeq subtargets.keys()
  for target, def in subtargets:
    tab[target] = (def, def.cleandeps.filterIt(it in tgts).toHashSet)
  while tab.len > 0:
    var queue = newSeqOfCap[string] 256
    for target, tp in tab:
      if tp.deps.len == 0:
        yield (target, tp.def)
        queue.add target
    if queue.len == 0:
      stderr.writeLine "Cannot resolve dependences for clean: " & toSeq(tab.keys()).join(", ")
      break
    for item in queue:
      tab.del item
    for item in queue:
      for _,tp in tab.mpairs:
        tp.deps.excl item

proc grabDependencies(tab: var TableRef[string, BuildDef], base: BuildDef) =
  for target in base.depfiles:
    if target in targets and not (target in tab):
      let def = targets[target]
      if verb >= 2:
        let friendlyname = getFriendlyName(target, def)
        echo "found ".fgGreen, friendlyname
      tab[target] = def
      grabDependencies(tab, def)

proc buildOne*(tgt: string): BuildResult =
  if tgt in targets:
    let def = targets[tgt]
    var tmpTargets = newTable[string, BuildDef] 16
    grabDependencies(tmpTargets, def)
    for target, def in reorder(tmpTargets):
      let friendlyname = getFriendlyName(target, def)
      onDemand(target, def):
        if verb >= 1:
          echo "building ".fgLightGreen.bold, friendlyname
        if def.action() != Success:
          return Failed
    if verb >= 1:
      echo "all done".fgLightGreen.bold
    return Success
  stderr.writeLine "No receipt for " & tgt
  Failed

proc buildAll*(): BuildResult =
  for target, def in reorder(targets):
    let friendlyname = getFriendlyName(target, def)
    onDemand(target, def):
      if verb >= 1:
        echo "building ".fgLightGreen.bold, friendlyname
      if def.action() != Success:
        return Failed
  if verb >= 1:
    echo "all done".fgLightGreen.bold
  Success

proc clean*(verbosity: int = 0) =
  verb = verbosity
  for target, def in cleanReorder(targets):
    if def.cleans != nil:
      let friendlyname = getFriendlyName(target, def)
      if verb >= 1:
        echo "clean ".fgRed.bold, friendlyname
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

proc dump() =
  for key, tgt in reorder(targets):
    echo key.fgYellow
    if tgt.taskname != "":
      echo "  name: ", tgt.taskname
    if tgt.mainfile != "":
      echo "  main: ", tgt.mainfile
    if tgt.depfiles.len > 0:
      echo "  deps:"
      for dep in tgt.depfiles:
        if dep in targets:
          echo "    - ", dep.fgYellow
        elif fileExists dep:
          echo "    - ", dep.fgBlue
        else:
          echo "    - ", dep.fgRed

template handleCLI*() =
  import cligen
  dispatchMulti([build], [clean], [dump])

proc toExe*(filename: string): string =
  (when defined(windows): &"{filename}.exe" else: filename)

proc toDll*(filename: string): string =
  (when defined(windows): &"{filename}.dll" else: &"lib{filename}.so")

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
      echo "Rebuilding " & nimakefile.fgYellow & "..."
      mkdir tmpdir
      exec &"nim c --verbosity:0 --hints:off --out:{exe} --nimcache:{tmpdir} --skipProjCfg:on --skipParentCfg:on --opt:speed {nimakefile}"
      return Success
  )
  build()

  quit(execCmd(exe & " " & args.join(" ")))