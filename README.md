Another Build System Written By NIM
===

Examples:

```nim
import nimake

target "bin/execute"
  depIt: walkPattern "src/*.c"
  depIt: walkPattern "src/*.h"
  main: "src/main.c"
  receipt:
    let depline = deps.join " "
    exec &"gcc -o {target} {depline}"

handleCLI()
```