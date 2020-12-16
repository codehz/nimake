import nimake

target "a":
  fake = true
  dep "b"
  dep "c"
  receipt do:
    echo "here"

target "b":
  fake = true
  dep "d"
  receipt do:
    echo "it's B"

target "c":
  fake = true
  dep "d"
  receipt do:
    echo "it's C"

target "d":
  fake = true
  receipt do:
    echo "it's D"

handleCLI()