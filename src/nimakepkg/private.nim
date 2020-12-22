import tables, os, strutils, colorize, sets, times, sequtils
import global, ops

proc checkfake*(name: string): bool =
  if alltargets.contains name:
    return alltargets[name].isfake

proc getFriendlyName*(target: string, def: BuildDef): string =
  if def.taskname != "":
    def.taskname.bold & "(" & target.fgYellow & ")"
  else:
    target.fgYellow

template onDemand*(target: string, def: BuildDef, build) =
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

proc colorizeTarget*(name: string): string =
  if name in alltargets: name.fgYellow
  elif name in alttargets: "$1 <- $2".format(name.fgCyan.bold, alttargets[name].fgYellow)
  elif fileExists name: name.fgBlue
  else: name.fgRed

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

proc addDependency(res: var HashSet[string], name: string) =
  if name in alltargets:
    res.incl name
  elif name in alttargets:
    res.incl alttargets[name]

iterator reorder(subtargets: TableRef[string, BuildDef]): tuple[tgt: string, def: BuildDef] =
  var tab = initTable[string, tuple[def: BuildDef, deps: HashSet[string]]] 256
  for target, def in subtargets:
    var tmp = initHashSet[string]()
    for name in def.depfiles:
      addDependency(tmp, name)
    if def.mainfile != "":
      addDependency(tmp, def.mainfile)
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

proc findDependencies(tab: var TableRef[string, BuildDef], target: string, ismain, forClean: static bool, rec: bool = false): BuildResult

proc grabDependencies(tab: var TableRef[string, BuildDef], name: string, forClean: static bool): BuildResult =
  if not (name in alltargets):
    stderr.writeLine "No receipt for " & name.fgRed.bold
    return Failed
  let base = alltargets[name]
  tab[name] = base
  if base.mainfile in alltargets and not (base.mainfile in tab):
    propagate findDependencies(tab, base.mainfile, true, forClean)
  for target in (when forClean: base.cleandeps else: base.depfiles):
    propagate findDependencies(tab, target, false, forClean)

proc findDependencies(tab: var TableRef[string, BuildDef], target: string, ismain, forClean: static bool, rec: bool = false): BuildResult =
  if target in tab: return Success
  elif target in alltargets:
    let def = alltargets[target]
    if verb >= 2:
      let friendlyname = getFriendlyName(target, def)
      if ismain:
        echo "found ".fgGreen, "main ".bold, friendlyname
      else:
        echo "found ".fgGreen, friendlyname
    return grabDependencies(tab, target, forClean)
  elif not rec and target in alttargets:
    return findDependencies(tab, alttargets[target], ismain, forClean, true)
  else:
    return Success

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

proc build*(verbosity: int = 0, targets: seq[string]) =
  verb = verbosity
  fail2fatal if targets.len == 0:
    if defaultTarget == "":
      buildAll()
    else:
      buildList([defaultTarget])
  else:
    buildList(targets)

proc clean*(verbosity: int = 0, targets: seq[string]) =
  verb = verbosity
  fail2fatal if targets.len == 0:
    cleanAll()
  else:
    cleanList(targets)

proc dump*() =
  for key, tgt in reorder(alltargets):
    echo "[", key.fgGreen.bold, "]"
    if tgt.taskname != "":
      echo "  name: ", tgt.taskname.fgMagenta.bold
    if tgt.mainfile != "":
      echo "  main: ", tgt.mainfile.colorizeTarget
    if tgt.depfiles.len > 0:
      echo "  deps:"
      for dep in tgt.depfiles:
        echo "    - ", dep.colorizeTarget