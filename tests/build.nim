import nimake

target "a":
  fake = true
  dep "b"
  receipt do:
    echo "here"

target "b":
  fake = true
  receipt do:
    echo "it's B"

handleCLI()