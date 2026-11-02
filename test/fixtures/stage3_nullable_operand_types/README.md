# Stage3 nullable and Dynamic operand types

`Main.hx` uses nullable and Dynamic values as operands of `+ - * /`. The
results go into locals, call arguments, and `Sys.println`. The native Stage3
program must print what upstream Haxe 4.3.7 prints. It covers:

- `Null<Float>` and `Null<Int>` compound assignment values as operands:
  `(ratio *= 2.5) + 0.5` and `(count += 2) / 4`;
- `Map<String, Float>` and `Map<String, Int>` lookups (`Null<...>`) as
  operands, also passed to a Float parameter;
- `Null<Int> / Int` passed to `Std.int` and to a Float parameter
  (`Std.int(s.charCodeAt(0) / 2)`);
- `Dynamic + Int`, `Dynamic * Float`, `Dynamic - Float`, and `Dynamic / Int`,
  passed straight to `Sys.println`, stored in a Float local, and passed to a
  Float parameter.

On main, each of these stopped in the typer with "selected call conversion
does not satisfy its retained parameter: unknown -> dynamic" (or
`-> primitive:Float`). The arithmetic had no type, because the typer did not
unwrap a nullable operand and did not give `- * / %` with a Dynamic operand
the Float type Haxe gives it. The nullable cases are fixed by the typer change
in #135. This fixture adds the Dynamic rule, reads a Dynamic result typed
Float as a Float, and prints a Dynamic sum through the runtime value instead of
concatenating its operands as text.

Every printed Float has a fractional part, so the output does not depend on
how whole-number Floats are formatted (haxe_ocaml-vzr17).

`npm run test:m14:stage3-nullable-operand-types` checks that upstream Haxe
prints `expected.stdout`, builds the program with Stage3, and requires the
native executable to print the same text.
