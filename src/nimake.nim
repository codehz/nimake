import tables, os, osproc, sequtils, times, strformat, strutils, segfaults, sets, colorize

export `/`, walkDirRec, walkDir, walkFiles, walkDirs, walkPattern
export parentDir, splitPath
export `&`
export sequtils, strutils, colorize, osproc, sets

type
  BuildDef = object
    isfake: bool
    islazy: bool
    taskname: string
    mainfile: string
    depfiles: OrderedSet[string]
    cleandeps: OrderedSet[string]
    action: proc(): BuildResult
    cleans: proc()
  BuildResult* = enum
    Success, Failed

const tmpdir* = ".nimakefiles"
var alltargets = newTable[string, BuildDef] 16
var verb = 0
var defaultTarget = ""

proc getProjectDir*(): string = getAppDir() / ".."

template walkTargets*(x) = toSeq(alltargets.keys).filterIt x

template exec*(cmd: string) =
  if verb >= 1:
    echo "exec ".fgGreen, cmd
  let code = execShellCmd(cmd)
  if code != 0:
    stderr.writeLine "Executing '$1' failed with code $2.".format(cmd.bold, ($code).fgRed.bold)
    return Failed

template mkdir*(dir) =
  if not dirExists dir:
    try:
      if verb >= 1:
        echo "mkdir ".fgBlue, dir
      createDir dir
    except:
      stderr.writeLine "Cannot create directory: $1.".format(dir.bold)

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
      echo "entering ".fgBlue, dir.bold
    setCurrentDir dir
    template relative(target: untyped): untyped {.inject,used.} =
      let target {.inject.} = target.relativePath dir
    xbody
  except:
    stderr.writeLine "Failed to change working directory to $1.".format(dir.fgRed.bold)
    return Failed
  finally:
    if verb >= 2:
      echo "leaving ".fgBlue, dir.bold
    setCurrentDir curDir

template cp*(source, dest: string) =
  try:
    if verb >= 1:
      echo "copy ".fgGreen, source, " ", dest
    copyFile source, dest
  except:
    stderr.writeLine "Failed to copy file from $1 to $2.".format(source.fgYellow.bold, dest.fgRed.bold)
    return Failed

template target*(file: string, getDef: untyped) =
  block:
    let target {.inject,used.} = file
    var name {.inject,used.}: string = ""
    var fake {.inject,used.}: bool = false
    var lazy {.inject,used.}: bool = false
    var deps {.inject,used.}: OrderedSet[string] = initOrderedSet[string] 256
    var cleandeps {.inject,used.}: OrderedSet[string] = initOrderedSet[string] 256
    var main {.inject,used.}: string
    var cleans: proc() = nil

    template dep(it) {.used.} =
      deps.incl(it)
    template depIt(it) {.used.} =
      for i in it:
        deps.incl(i)
    template cleanDep(it) {.used.} =
      cleandeps.incl(it)
    template cleanDepIt(it) {.used.} =
      for i in it:
        cleandeps.incl(i)
    template clean(body) {.used.} =
      cleans = proc() =
        setCurrentDir getProjectDir()
        body
    template receipt(body): BuildDef {.used.} =
      BuildDef(
        isfake: fake,
        islazy: lazy,
        taskname: name,
        mainfile: main,
        depfiles: deps,
        cleandeps: cleandeps,
        cleans: if cleans != nil or fake: cleans else: (proc() = rm getProjectDir() / file),
        action: proc(): BuildResult =
          setCurrentDir getProjectDir()
          template absolute(path: untyped): untyped =
            let path {.inject.} = path.absolutePath()
          body
          return Success
      )
    alltargets[target] = getDef

proc checkfake(name: string): bool =
  if alltargets.contains name:
    return alltargets[name].isfake

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
      if def.islazy:
        if verb >= 3:
          echo "skipped modification time check due to lazy = true".fgMagenta
        break demand
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
  result = getAppFilename().getLastModificationTime
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
    var tmp = def.depfiles.toSeq.filterIt(it in tgts).toHashSet
    if def.mainfile != "" and def.mainfile in tgts:
      tmp.incl def.mainfile
    tab[target] = (def, tmp)
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
    tab[target] = (def, def.cleandeps.toSeq.filterIt(it in tgts).toHashSet)
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

template propagate*(body: untyped): untyped =
  if body == Failed:
    return Failed

proc grabDependencies(tab: var TableRef[string, BuildDef], name: string, forClean: static bool): BuildResult =
  if not (name in alltargets):
    stderr.writeLine "No receipt for " & name.fgRed.bold
    return Failed
  let base = alltargets[name]
  tab[name] = base
  if base.mainfile in alltargets and not (base.mainfile in tab):
    let target = base.mainfile
    let def = alltargets[target]
    if verb >= 2:
      let friendlyname = getFriendlyName(target, def)
      echo "found ".fgGreen, "main ".bold, friendlyname
    propagate grabDependencies(tab, target, forClean)
  for target in (when forClean: base.cleandeps else: base.depfiles):
    if target in alltargets and not (target in tab):
      let def = alltargets[target]
      if verb >= 2:
        let friendlyname = getFriendlyName(target, def)
        echo "found ".fgGreen, friendlyname
      propagate grabDependencies(tab, target, forClean)

proc buildList(selected: openarray[string]): BuildResult =
  var tmpTargets = newTable[string, BuildDef] 16
  for tgt in selected:
    propagate grabDependencies(tmpTargets, tgt, false)
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

proc buildAll(): BuildResult =
  for target, def in reorder(alltargets):
    let friendlyname = getFriendlyName(target, def)
    onDemand(target, def):
      if verb >= 1:
        echo "building ".fgLightGreen.bold, friendlyname
      if def.action() != Success:
        return Failed
  if verb >= 1:
    echo "all done".fgLightGreen.bold
  Success

proc cleanList(selected: seq[string]): BuildResult =
  var tmpTargets = newTable[string, BuildDef] 16
  for tgt in selected:
    propagate grabDependencies(tmpTargets, tgt, true)
  for target, def in cleanReorder(tmpTargets):
    let friendlyname = getFriendlyName(target, def)
    if verb >= 1:
      echo "clean ".fgRed.bold, friendlyname
    if def.cleans != nil:
      def.cleans()
  return Success

proc cleanAll(): BuildResult =
  for target, def in cleanReorder(alltargets):
    let friendlyname = getFriendlyName(target, def)
    if verb >= 1:
      echo "clean ".fgRed.bold, friendlyname
    if def.cleans != nil:
      def.cleans()
  return Success

proc fail2fatal(res: BuildResult) =
  if res == Failed:
    quit 1

proc build(verbosity: int = 0, targets: seq[string]) =
  verb = verbosity
  fail2fatal if targets.len == 0:
    if defaultTarget == "":
      buildAll()
    else:
      buildList([defaultTarget])
  else:
    buildList(targets)

proc clean(verbosity: int = 0, targets: seq[string]) =
  verb = verbosity
  fail2fatal if targets.len == 0:
    cleanAll()
  else:
    cleanList(targets)

proc colorizeTarget(name: string): string =
  if name in alltargets: name.fgYellow
  elif fileExists name: name.fgBlue
  else: name.fgRed

proc dump() =
  for key, tgt in reorder(alltargets):
    echo key.fgYellow
    if tgt.taskname != "":
      echo "  name: ", tgt.taskname.fgYellow.bold
    if tgt.mainfile != "":
      echo "  main: ", tgt.mainfile.colorizeTarget
    if tgt.depfiles.len > 0:
      echo "  deps:"
      for dep in tgt.depfiles:
        echo "    - ", dep.colorizeTarget

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

  alltargets[exe] = BuildDef(
    taskname: "build",
    mainfile: nimakefile,
    depfiles: initOrderedSet[string](),
    cleandeps: initOrderedSet[string](),
    cleans: proc () = removeDir(tmpdir),
    action: proc(): BuildResult =
      echo "Rebuilding " & nimakefile.fgYellow.bold & "..."
      mkdir tmpdir
      exec &"nim c --verbosity:0 --hints:off --out:{exe} --nimcache:{tmpdir} --skipProjCfg:on --skipParentCfg:on {nimakefile}"
      return Success
  )
  build(0, @[])

  quit(execCmd(exe & " " & args.join(" ")))