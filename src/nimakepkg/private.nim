import tables, os, strutils, sets, times, sequtils
import global, ops, colorset

proc checkfake(name: string): bool =
  if alltargets.contains name:
    return alltargets[name].isfake

template onDemand(target: string, def: BuildDef, build) =
  block demand:
    let friendlyname = getFriendlyName(target, def)
    echo_Checking(friendlyname)
    for f in def.depfiles:
      if (not fileExists f) and (not checkfake(f)):
        echo_NotExists(friendlyname, f)
        return Failed
    if not def.isfake and target.fileExists:
      echo_Checked("exist", friendlyname)
      if def.islazy:
        echo_SkippedLazy("skipped modification time check due to lazy = true")
        break demand
      let targetTime = target.getLastModificationTime
      let depsTime = def.genLatest
      echo_TimeReport(targetTime, depsTime)
      if targetTime >= depsTime:
        echo_SkippedTarget(friendlyname)
        break demand
      echo_OutdatedTarget(friendlyname)
    build

proc genLatest(build: BuildDef): Time =
  result = getAppFilename().getLastModificationTime
  if build.isfake: return
  if build.mainfile != "":
    result = build.mainfile.getLastModificationTime
    echo_TimeOfMainFile(build.mainfile, result)
  for f in build.depfiles:
    if checkfake f:
      echo_TimeSkipped(f)
      continue
    let temp = f.getLastModificationTime
    echo_TimeOfFile(f, temp)
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
      echo_CannotResolve("build", toSeq(tab.keys()).join(", "))
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
      echo_CannotResolve("clean", toSeq(tab.keys()).join(", "))
      break
    for item in queue:
      tab.del item
    for item in queue:
      for _,tp in tab.mpairs:
        tp.deps.excl item

proc findDependencies(tab: var TableRef[string, BuildDef], target: string, ismain, forClean: static bool, rec: bool = false): BuildResult

proc grabDependencies(tab: var TableRef[string, BuildDef], name: string, forClean: static bool): BuildResult =
  if not (name in alltargets):
    echo_NoRecipt(name)
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
    let friendlyname = getFriendlyName(target, def)
    echo_Found(ismain, friendlyname)
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
        echo_Building(friendlyname)
      if def.action() != Success:
        return Failed
  echo_AllDone()
  return Success

proc buildAll(): BuildResult =
  for target, def in reorder(alltargets):
    let friendlyname = getFriendlyName(target, def)
    onDemand(target, def):
      echo_Building(friendlyname)
      if def.action() != Success:
        return Failed
  echo_AllDone()
  Success

proc cleanList(selected: seq[string]): BuildResult =
  var tmpTargets = newTable[string, BuildDef] 16
  for tgt in selected:
    propagate grabDependencies(tmpTargets, tgt, true)
  for target, def in cleanReorder(tmpTargets):
    let friendlyname = getFriendlyName(target, def)
    echo_Cleaning(friendlyname)
    if def.cleans != nil:
      def.cleans()
  return Success

proc cleanAll(): BuildResult =
  for target, def in cleanReorder(alltargets):
    let friendlyname = getFriendlyName(target, def)
    echo_Cleaning(friendlyname)
    if def.cleans != nil:
      def.cleans()
  return Success

proc fail2fatal(res: BuildResult) =
  if res == Failed:
    quit 1

proc build*(targets: seq[string]) =
  fail2fatal if targets.len == 0:
    if defaultTarget == "":
      buildAll()
    else:
      buildList([defaultTarget])
  else:
    buildList(targets)

proc clean*(targets: seq[string]) =
  fail2fatal if targets.len == 0:
    cleanAll()
  else:
    cleanList(targets)

proc dump*() =
  for key, tgt in reorder(alltargets):
    echo_DumpTitle(key)
    if tgt.taskname != "":
      echo_DumpName(tgt.taskname)
    if tgt.mainfile != "":
      echo_DumpMain(tgt.mainfile.colorizeTarget)
    if tgt.depfiles.len > 0:
      echo_DumpDeps()
      for dep in tgt.depfiles:
        echo_DumpDepFile(dep.colorizeTarget)