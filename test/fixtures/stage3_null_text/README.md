# Null values and enum values as text

Run `npm run test:m14:stage3-null-text` from the repository root. The test runs
`Main.hx` with pinned upstream Haxe 4.3.7, builds it with the Stage3 native
emitter, and requires both programs to print `expected.stdout` exactly.

A null String at run time is the runtime null sentinel, not the text `null`.
Stage3 passed some String values to OCaml's `^` and `print_endline` unchanged,
so they printed the sentinel's raw bytes:

| Haxe expression | Upstream | Old native output |
| --- | --- | --- |
| `"x=" + nothing` (String local, null) | `x=null` | `x=` and raw bytes |
| `"static " + staticText` | `static null` | raw bytes |
| `Sys.println(nothing)` | `null` | raw bytes |
| `'interpolated ${nothing}'` | `interpolated null` | raw bytes |
| `s += "x"` on a null local | `nullx` | raw bytes, then `x` |
| `"concat " + (hello.charCodeAt(9) + "a")` | `concat nulla` | raw bytes |
| `"e=" + Red`, `"e=" + Rgb(1, 2, 3)` | `e=Red`, `e=Rgb(1,2,3)` | `e=<object>` |

Now:
- A String operand of a concatenation, a String argument of `Sys.println` or
  `Sys.print`, and both operands of a String `+=` on a local print through
  `HxString.toStdString`, which turns the sentinel into `null`. The operand
  type comes from the typed concatenation and call-argument records, so only
  String-typed operands get the check. A string literal or another
  concatenation can never be null and is left unchanged
  (`Stage3OcamlStringConversion.nonNullText`).
- A static field without an initializer holds null when it is stored as a
  reference (String, nullable types, Dynamic, functions, anonymous
  structures, classes, enums). It holds `0`, `0.0` or `false` when its
  carrier is an unboxed number or Bool: a non-null Int, Float or Bool, or an
  abstract over one such as `enum abstract Kind(Int)` (`Stage3OcamlStaticDefault`).
  That is the static-target default; upstream eval prints `null` for these too
  (haxe_ocaml-a8wbz), so the fixture only compares them with themselves and
  the test checks the emitted defaults. Stage3 used to emit the immediate
  `(Obj.magic 0)` for every type, which the String null check did not
  recognize: printing such a String crashed the program.
- A parenthesized concatenation inside another one keeps its typed operands,
  so a null `Null<Int>` operand prints `null`.
- `HxDynamic.toStdString` prints a boxed enum value as its constructor name,
  followed by its arguments in parentheses when it has any.

Not covered:
- `trace(nothing)` still prints raw bytes, because `trace` does not go
  through the call-argument record; and a String `+=` on a field or a static
  is not converted. Both are handled with haxe_ocaml-00tpu.
- Enum abstract values print their index (haxe_ocaml-cu68l).
- A Bool argument of an enum constructor is stored as a raw OCaml bool, so
  `Flagged(true)` prints `Flagged(1)` (haxe_ocaml-k3jwd).

Beads: haxe_ocaml-txs4e, haxe_ocaml-npbsu, haxe_ocaml-aib5d.
