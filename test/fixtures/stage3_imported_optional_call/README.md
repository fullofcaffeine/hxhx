# Imported optional call

This fixture checks that a wildcard-imported function executes when its caller skips optional String arguments before a Bool.
The function prints `imported-call:executed`. Compiler success alone is insufficient: an affected native compiler silently drops the call.

Run from the repository root with a prebuilt native compiler:

```sh
HXHX_BIN=/path/to/hxhx bash scripts/hxhx/test-imported-optional-call.sh
```

Compare with upstream Haxe 4.3.7:

```sh
haxe -cp test/fixtures/stage3_imported_optional_call/src --run consumer.Main
```

The test-only `Sys` extern declares the existing console primitive. It excludes unrelated standard-library dependencies from this focused check.
The target integration runner executes this check before the original `runci.System` fixture, which retains full standard-library coverage.
This fixture does not prove complete standard-library compatibility or every optional-argument rule.
