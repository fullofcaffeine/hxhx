# Saved interval values

A saved `2...6` value is a mutable `IntIterator`. An alias shares its cursor: after one `next()`, looping the original consumes only the remaining values, and a second loop is empty. Two freshly constructed intervals consume independently.

`expected.stdout` is an independent behavior specification. The test compiles the ordinary Haxe fixtures with pinned upstream Haxe 4.3.7, checks Node output against that specification, then runs the same source through the authored `Stage3Compiler` driver and compares Node output again. Imported and same-package classes named `IntIterator` keep their own constructor and initialized state; interval syntax selects the core provider.

Run from the repository root:

```sh
node_modules/.bin/haxe test/m14_stage3_range_value_test.hxml
```

The test also checks typed constructor ownership and replay, retained direct-loop range nodes, quoted interval syntax, invalid floating-point bounds, and rejected key/value range loops. It writes isolated outputs under `.tmp/stage3-range-values-*`. This authored-host test supports the compiler change; a freshly regenerated native compiler must still pass the unchanged five-fixture JS oracle workflow before native acceptance.
