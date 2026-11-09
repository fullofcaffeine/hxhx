# Float to String

Run `npm run test:m14:stage3-float-string` from the repository root. The test
runs `Main.hx` with pinned upstream Haxe 4.3.7, builds it with the Stage3 native
emitter, and requires both programs to print `expected.stdout` exactly.

Native output used OCaml's `string_of_float`. It keeps 12 significant digits and
adds a trailing `.` to whole numbers:

| Haxe expression | Upstream Haxe | Old native output |
| --- | --- | --- |
| `Std.string(2.0)` | `2` | `2.` |
| `Std.string(7.0 / 3)` | `2.33333333333333348` | `2.33333333333` |
| `Std.string(0.1 + 0.2)` | `0.300000000000000044` | `0.3` |
| `Std.string(-0.0)` | `-0` | `-0.` |

Both native routes (Stage3 and `reflaxe.ocaml`) now call one runtime helper,
`HxRuntime.float_toStdString`. A finite value prints in C `%g` form with the
fewest of 12, 15 or 18 significant digits whose text reads back as the same
value. This rule matched upstream `haxe --interp` on 20000 random doubles.

The fixture covers whole numbers on both sides of 1e12 (the bound of the
helper's integer path), signed zero, values that need more than 12
digits, short values, exponent forms, the smallest subnormal value, a parsed
value, Float literals in concatenation, and Floats stored in Dynamic,
`Null<Float>`, arrays, anonymous objects, and `StringBuf`.

Not covered: `NaN` prints `nan` and the infinities print OCaml's `inf` and
`-inf`. Upstream targets disagree on this text (eval prints `nan`, `infinity`
and `neg_infinity`), so it needs its own decision. Bead: haxe_ocaml-iffj5.
