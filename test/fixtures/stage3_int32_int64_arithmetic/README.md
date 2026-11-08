# Stage3 `haxe.Int32` and `haxe.Int64` arithmetic

`Main.hx` prints the results of `haxe.Int32` and `haxe.Int64` operations:

- Int32 `+ - * / %`, negation, `<< >> >>>`, `& | ^ ~`, and comparisons,
  with operands that overflow and wrap around at 32 bits.
- Int32 operations that mix `Int32` and plain `Int` operands, an `Int32`
  assigned to an `Int`, `Int32.ucompare`, and `++`/`--` in prefix and postfix
  form.
- Int64 `make`, `ofInt`, `toInt`, `toStr`, `+ - * / %` with Int64 and Int
  operands, `compare`, `ucompare`, `<`, `==`, the `high`/`low` words,
  `Std.string`, and postfix `++`/`--`, including a carry from the low word
  into the high word and an alias that keeps its old value.
- `text += (i32 + 1)`, a user class whose own fields are named `high` and
  `low`, an Int64 word write whose receiver and value both print, and local
  assignments used as values, including an Int stored in a `Float` local.

Before the fix, the native program crashed with SIGSEGV on the first line:
an Int32 value inside a string concatenation reached OCaml's `^` without
conversion to a string. `++` on Int32 and Int64 locals also left the value
unchanged, and `Int64.compare` returned only the sign of the difference.
Storing an Int in a `Float` local (`ratio = 3`) failed to compile.

`npm run test:m14:stage3-int32-int64-arithmetic` checks that upstream Haxe
4.3.7 prints `expected.stdout`. It then builds the program with Stage3 and
requires the native executable to print the same text.

Prefix `++value`/`--value` on an Int64 is not supported yet. The test checks
that it stops with a named error before any program is produced.

Float division results are exact binary fractions (`3.5`, `1.75`), because
native and `--interp` Float printing differ for values such as `7 / 3`.
