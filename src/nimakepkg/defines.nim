import tables

var defineList* = initTable[string, proc (x: string)]()

template define*(name: static string, variable: untyped, body: untyped) =
  when not declared(variable):
    var variable*: typeof(body(""))
  proc temp(x: string) {.gensym.} =
    variable = body(x)
  defineList[name] = temp