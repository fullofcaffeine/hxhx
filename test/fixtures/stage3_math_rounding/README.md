# Native `Math` rounding: floor, ceil, round, ffloor, fceil, fround

```haxe
Math.floor(2147483648.0);  // upstream eval: 0          native was 2147483648
Math.floor(1e10);          // upstream eval: 1410065408 native was 10000000000
Math.fround(1.5);          // upstream eval: 2          native was 1.5 (identity)
Math.ffloor(Math.NaN);     // upstream eval: NaN        native was 0
```

Upstream Haxe 4.3.7 eval (the reference target) computes the Int results as
`Int32.of_float (mod_float r 2147483648.0)`, where `r` is the Float floor,
ceil, or round. `mod_float` keeps the sign of `r`, so the result lies in
(-2^31, 2^31). This is a different rule from `Std.int`, which wraps modulo
2^32. The Float variants return the unbounded Float result.

Before the fix:

- The runtime (`packages/reflaxe.ocaml/std/runtime/Math.ml`) used a bare
  `int_of_float` for `floor`, `ceil`, and `round`. `fround` was the
  identity function. `ffloor` and `fceil` went through an Int, which lost
  NaN, the infinities, large values, and `-0.0`.
- Stage3 emitted `Math.floor` and `Math.fround` as the `(Obj.magic 0)`
  placeholder. It inlined `Math.round` as `int_of_float (floor ...)`, and an
  unqualified `floor` resolved to a local variable named `floor`, so this
  program crashed with SIGSEGV.

Now the runtime implements eval's rule (`Math.int_of_rounded`), and Stage3
calls the runtime `Math` functions, as it already did for `Math.ceil`.

`Main.hx` covers ties, signed zero, NaN, the infinities, and values around
`±2^31`, `2^32`, `3e9`, `1e10`, `2^53`, and `1e20`. The Float variants are
compared with the expected value in the table, including NaN and the sign of
zero. They are not printed, because native printing of whole-number Floats
differs (Bead `haxe_ocaml-iffj5`).

- `npm run test:m14:stage3-math-rounding` runs `Main.hx` through Stage3.
- The portable fixture `test/portable/fixtures/math_rounding_wrap` runs the
  same program through the reflaxe.ocaml backend.

Both require the native output to equal upstream eval's `expected.stdout`.

## Target differences (known_divergence)

This change was reviewed under the gate in
`docs/00-project/FLOAT_NUMERIC_REVIEW_GATE.md`. The answers are recorded on
Bead `haxe_ocaml-32vsc`. Out-of-range Int results are not stable across
upstream targets: neko saturates to the Int32 range (`Math.floor(2^31)` is
2147483647, and `±Infinity` gives `±2^31`), while eval gives 0. The fixture
matches eval.

For NaN and the infinities, eval computes `Int32.of_float` of NaN, which is
the CPU's conversion (0 on arm64 and x86-64). The native code uses the same
OCaml primitive. The python target cannot run this program, because its
`Math.floor(NaN)` raises.
