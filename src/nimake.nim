import tables, os, osproc, sequtils, strutils, segfaults, sets, colorize

export `/`, walkDirRec, walkDir, walkFiles, walkDirs, walkPattern
export parentDir, splitPath
export sequtils, strutils, colorize, osproc, sets

import nimakepkg/[ops, global, cli, defines, colorset]
export ops, cli, define, colorfmt, identity, `|`, checkVerbose

proc colorMode*(): bool = usecolor

template walkTargets*(x) = toSeq(alltargets.keys).filterIt x

template target*(file: string, getDef: untyped) =
  block:
    let target {.inject,used.} = file
    var name {.inject,used.}: string = ""
    var fake {.inject,used.}: bool = false
    var lazy {.inject,used.}: bool = false
    var deps {.inject,used.}: OrderedSet[string] = initOrderedSet[string] 256
    var cleandeps {.inject,used.}: OrderedSet[string] = initOrderedSet[string] 256
    var altoutputs {.inject,used.}: OrderedSet[string] = initOrderedSet[string] 256
    var main {.inject,used.}: string
    var cleans: proc() = nil

    template output(it) {.used.} =
      altoutputs.incl(it)
    template outputIt(it) {.used.} =
      for i in it:
        altoutputs.incl(i)
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
      for alt in altoutputs:
        alttargets[alt] = file
      BuildDef(
        isfake: fake,
        islazy: lazy,
        taskname: name,
        mainfile: main,
        depfiles: deps,
        cleandeps: cleandeps,
        cleans: if cleans != nil or fake: cleans else: (proc() =
          setCurrentDir getProjectDir()
          rm file
          for alt in altoutputs:
            rm alt
        ),
        action: proc(): BuildResult =
          setCurrentDir getProjectDir()
          template absolute(path: untyped): untyped =
            let path {.inject.} = path.absolutePath()
          body
          return Success
      )
    alltargets[target] = getDef

template default*(target: string) =
  defaultTarget = target

when isMainModule:
  import nimakepkg/private

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
      if not fileExists nimakefile:
        echo nimakefile & " not found!"
        printHelp()
      echo "Rebuilding " & nimakefile & "..."
      mkdir tmpdir
      exec "nim c --verbosity:0 --hints:off --out:$1 --nimcache:$2 --skipProjCfg:on --skipParentCfg:on $3" % [exe, tmpdir, nimakefile]
      return Success
  )
  build(@[])

  quit(execCmd(exe & " " & args.join(" ")))