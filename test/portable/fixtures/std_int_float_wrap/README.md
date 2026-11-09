# reflaxe.ocaml `Std.int` of out-of-range Floats

```haxe
Std.int(4294967295.0);          // upstream eval: -1; reflaxe.ocaml was 4294967295
final zero = 0;
Std.int(zero / zero);           // upstream eval: 0; reflaxe.ocaml died with Division_by_zero
Std.int((-2147483647 - 1) / -1) // upstream eval: -2147483648; reflaxe.ocaml was 2147483648
```

The reflaxe.ocaml backend inlined `Std.int` instead of calling the runtime:

- a Float argument became a bare `int_of_float`, which returns a 63-bit
  OCaml int without the 32-bit wrap;
- `Std.int(a / b)` with Int operands became OCaml integer division. That
  overflowed at `-2^31 / -1` and raised `Division_by_zero` for a zero
  divisor. In Haxe, `a / b` is a Float division.

Both now use the same truncate-then-wrap expression as the runtime `Std.int`
(PR #164, Bead `haxe_ocaml-3lpr4`):
`Stdlib.Int32.to_int (Stdlib.Int32.of_int (int_of_float x))`, built by
`OcamlBuilder.stdIntOfFloat`.

`src/Main.hx` reuses the Stage3 oracle cases from
`test/fixtures/stage3_std_int_wrap` and adds the Int-division cases.
`expected.stdout` is the output of upstream Haxe 4.3.7 `--interp` (eval),
the reference target. `npm run test:portable` compiles the fixture with
reflaxe.ocaml and requires the native executable to print the same text.

The cases are chosen under the Float numeric review gate
(`docs/00-project/FLOAT_NUMERIC_REVIEW_GATE.md`; answers on Beads
`haxe_ocaml-3lpr4` and `haxe_ocaml-kmdfe`). For `±Infinity`,
`|x| >= 2^63`, and `x / 0` with a non-zero Int `x`, eval's result comes from
the CPU's float-to-int conversion. The generated code uses the same
conversion, so it matches eval on the same host, but those values are not
pinned here.
