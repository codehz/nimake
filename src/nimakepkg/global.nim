import sets, tables

type
  BuildDef* = object
    isfake*: bool
    islazy*: bool
    taskname*: string
    mainfile*: string
    depfiles*: OrderedSet[string]
    cleandeps*: OrderedSet[string]
    action*: proc(): BuildResult
    cleans*: proc()
  BuildResult* = enum
    Success, Failed

var alltargets* = newTable[string, BuildDef] 16
var alttargets* = newTable[string, string] 16
var verb* = 0
var defaultTarget* = ""