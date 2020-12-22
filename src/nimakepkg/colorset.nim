import colorize, times, strutils, tables, os
import global

proc colorfmt*(format: string, mapping: openarray[(string, typeof(bold))]): string =
  var mapped = newSeqOfCap[string] mapping.len
  for (k, v) in mapping:
    mapped.add if usecolor:
      v(k)
    else:
      k
  return format % mapped

proc identity*(s: string): string = s

template `|`*(a, b: typeof(bold)): typeof(bold) =
  proc tmp(s: string): string {.gensym.} = a(b(s))
  tmp

template checkVerbose*(verbose: int) =
  if verb < verbose:
    return

proc echo_NormalOp*(opname, target: string) =
  checkVerbose 1
  echo "$1 $2".colorfmt { opname: fgGreen, target: identity }

proc echo_NormalOp*(opname, source, target: string) =
  checkVerbose 1
  echo "$1 $2 $3".colorfmt { opname: fgGreen, source: bold, target: identity }

proc echo_DangerOp*(opname, target: string) =
  checkVerbose 1
  echo "$1 $2".colorfmt { opname: fgRed, target: identity }

proc echo_SwitchDirectory*(opname, target: string) =
  checkVerbose 2
  echo "$1 $2".colorfmt { opname: fgBlue, target: identity }

proc echo_Checking*(target: string) =
  checkVerbose 2
  echo "$1 $2".colorfmt { "checking": fgBlue, target: identity }

proc echo_Checked*(opname, target: string) =
  checkVerbose 2
  echo "$1 $2".colorfmt { opname: fgGreen, target: identity }

proc echo_SkippedLazy*(message: string) =
  checkVerbose 3
  echo "$1".colorfmt { message: fgMagenta }

proc echo_TimeReport*(target, latest: Time) =
  checkVerbose 3
  echo "$1 target: $2 dep: $3".colorfmt { "time": fgCyan, ($target): fgCyan, ($latest): fgCyan }

proc echo_TimeOfMainFile*(file: string, time: Time) =
  checkVerbose 4
  echo "$1 $2 $3 $4".colorfmt { "time": fgCyan, "main": bold, file: bold, ($time): fgCyan }

proc echo_TimeSkipped*(file: string) =
  checkVerbose 4
  echo "$1 $2 $3".colorfmt { "time": fgCyan, file: bold, "skipped": fgRed }

proc echo_TimeOfFile*(file: string, time: Time) =
  checkVerbose 4
  echo "$1 $2 $3".colorfmt { "time": fgCyan, file: bold, ($time): fgCyan }

proc echo_SkippedTarget*(target: string) =
  checkVerbose 1
  echo "$1 $2".colorfmt { "skipped": fgYellow, target: identity }

proc echo_OutdatedTarget*(target: string) =
  checkVerbose 1
  echo "$1 $2".colorfmt { "outdated": fgRed, target: identity }

proc echo_Found*(ismain: bool, target: string) =
  checkVerbose 2
  if ismain:
    echo "$1 $2 $3".colorfmt { "found": fgGreen, "main": bold, target: identity }
  else:
    echo "$1 $2".colorfmt { "found": fgGreen, target: identity }

proc echo_Building*(target: string) =
  checkVerbose 1
  echo "$1 $2".colorfmt { "building": fgLightGreen | bold, target: identity }

proc echo_Cleaning*(target: string) =
  checkVerbose 1
  echo "$1 $2".colorfmt { "cleaning": fgRed | bold, target: identity }

proc echo_AllDone*() =
  checkVerbose 1
  echo "$1".colorfmt { "all done": fgLightGreen | bold }

proc echo_DumpTitle*(target: string) =
  echo "[$1]".colorfmt { target: fgGreen | bold }

proc echo_DumpName*(name: string) =
  echo "  name: $1".colorfmt { name: fgMagenta | bold }

proc echo_DumpMain*(name: string) =
  echo "  name: ", name

proc echo_DumpDeps*() =
  echo "  deps:"

proc echo_DumpDepFile*(name: string) =
  echo "    - ", name

proc echo_NoRecipt*(target: string) =
  stderr.writeLine "No receipt for $1".colorfmt { target: fgRed | bold }

proc echo_CannotResolve*(action, target: string) =
  stderr.writeLine "Cannot resolve dependences for %1: %2".colorfmt { action: bold, target: fgRed | bold }

proc echo_NotExists*(target, file: string) =
  stderr.writeLine "Recipe for %1 failed, the file '$2' is not exists".colorfmt { target: identity, file: fgRed }

proc getFriendlyName*(target: string, def: BuildDef): string =
  if def.taskname != "":
    "$1($2)".colorfmt { (def.taskname): bold, target: fgYellow }
  else:
    "$1".colorfmt { target: fgYellow }

proc colorizeTarget*(name: string): string =
  if name in alltargets: "$1".colorfmt { name: fgYellow }
  elif name in alttargets: "$1 <- $2".colorfmt { name: fgCyan | bold, (alttargets[name]): fgYellow }
  elif fileExists name: "$1".colorfmt { name: fgBlue }
  else: "$1".colorfmt { name: fgRed }