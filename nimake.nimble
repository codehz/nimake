# Package

version       = "0.2.0"
author        = "CodeHz"
description   = "A simple build system"
license       = "MIT"
srcDir        = "src"
bin           = @["nimake"]
binDir        = "build"

# Dependencies

requires "nim >= 0.18.0"
requires "cligen >= 0.9.0"
requires "colorize >= 0.2.0"
