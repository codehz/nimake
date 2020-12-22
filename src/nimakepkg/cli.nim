import parseopt, strutils, tables
import private, defines

proc printHelp*() {.noreturn.} =
  echo "nimake - Build script written in Nim."
  echo ""
  echo "usage:"
  echo "nimake [--help,-h]            Print help"
  echo "nimake build [target list]    Build multiple targets"
  echo "nimake clean [target list]    Clean up targets"
  echo "nimake dump                   Dump target list"
  echo ""
  echo "options:"
  echo "--define:opt[=value],-d:opt[=value]    Pass arguments to build system"
  echo "--color[:on|off]                       Enable/disable colorful output (alias to -d:color=on|off)"
  echo "--verbosity:number,-v:number           Set verbosity level (alias to -d:verbosity=number)"
  quit 0

type SubCommandMode = enum
  scm_none,
  scm_build,
  scm_clean,
  scm_dump,

proc parseDefine(input: string) =
  if input == "":
    quit "Invalid syntax for defines"
  var kv = input.split('=', 2)
  if kv.len == 2:
    let key = move kv[0]
    let value = move kv[1]
    if defineList.contains key:
      defineList[key](value)
    else:
      quit "Unknown define: " & key
  else:
    if defineList.contains input:
      defineList[input]("on")
    else:
      quit "Unknown define: " & input

proc handleCLI*() =
  var p = initOptParser()
  var scm: SubCommandMode = scm_none
  var targets = newSeq[string]()
  while true:
    p.next()
    case p.kind:
    of cmdEnd: break
    of cmdShortOption, cmdLongOption:
      case p.key:
      of "help", "h":
        printHelp()
      of "define", "d":
        parseDefine p.val
      of "verbosity", "v":
        parseDefine "verbosity=" & p.val
      of "colors":
        parseDefine "colors=" & p.val
      else:
        quit "Unknown option: " & p.key
    of cmdArgument:
      if scm == scm_none:
        scm = case p.key:
        of "build": scm_build
        of "clean": scm_clean
        of "dump": scm_dump
        else: quit "Invalid sub command"
      else:
        targets.add p.key
  case scm:
  of scm_none: printHelp()
  of scm_build: build(targets)
  of scm_clean: clean(targets)
  of scm_dump: dump()