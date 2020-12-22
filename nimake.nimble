# Package

version       = "0.5.0"
author        = "CodeHz"
description   = "A simple build system"
license       = "MIT"
srcDir        = "src"
bin           = @["nimake"]
binDir        = "build"
installExt    = @["nim"]

# Dependencies

requires "nim >= 1.4.0"
requires "colorize >= 0.2.0"
