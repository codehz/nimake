import os

import global, colorset

const tmpdir* = ".nimakefiles"

template exec*(cmd: string) =
  echo_NormalOp("exec", cmd)
  let code = execShellCmd(cmd)
  if code != 0:
    stderr.writeLine "Executing '$1' failed with code $2.".format(cmd.bold, ($code).fgRed.bold)
    return Failed

template mkdir*(dir) =
  if not dirExists dir:
    try:
      echo_NormalOp("mkdir", dir)
      createDir dir
    except:
      stderr.writeLine "Cannot create directory: $1.".format(dir.bold)

template rm*(path) =
  if dirExists path:
    echo_DangerOp("rmdir", path)
    removeDir path
  elif fileExists path:
    echo_DangerOp("rm", path)
    removeFile path

template withDir*(dir, xbody) =
  let curDir = getCurrentDir()
  if not dirExists(dir):
    mkdir dir
  try:
    echo_SwitchDirectory("entering", dir)
    setCurrentDir dir
    template relative(target: untyped): untyped {.inject,used.} =
      let target {.inject.} = target.relativePath dir
    xbody
  except:
    stderr.writeLine "Failed to change working directory to $1.".format(dir.fgRed.bold)
    return Failed
  finally:
    echo_SwitchDirectory("leaving", dir)
    setCurrentDir curDir

template cp*(source, dest: string) =
  try:
    echo_NormalOp("copy", source, dest)
    copyFile source, dest
  except:
    stderr.writeLine "Failed to copy file from $1 to $2.".format(source.fgYellow.bold, dest.fgRed.bold)
    return Failed

proc toExe*(filename: string): string =
  (when defined(windows): filename & ".exe" else: filename)

proc toDll*(filename: string): string =
  (when defined(windows): filename & ".dll" else: "lib" & filename & ".so")

template propagate*(body: untyped): untyped =
  if body == Failed:
    return Failed

proc getProjectDir*(): string = getAppDir() / ".."