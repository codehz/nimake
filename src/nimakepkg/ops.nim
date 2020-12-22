import os, strformat

import global

const tmpdir* = ".nimakefiles"

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

proc toExe*(filename: string): string =
  (when defined(windows): &"{filename}.exe" else: filename)

proc toDll*(filename: string): string =
  (when defined(windows): &"{filename}.dll" else: &"lib{filename}.so")

template propagate*(body: untyped): untyped =
  if body == Failed:
    return Failed

proc getProjectDir*(): string = getAppDir() / ".."