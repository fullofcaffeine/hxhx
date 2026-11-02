# Stage3 `Math.pow` and `Math.log`

```haxe
final b = 2.0;
final p = Math.pow(b, 3);   // upstream eval: 8; Stage3 emitted `let p = (Obj.magic 0)`
```

Stage3 matched `Math.pow` and `Math.log` by name, in
`tryExprToOcamlStage3MathCallIntrinsic`, and emitted the `(Obj.magic 0)`
placeholder for both. The program then crashed with signal 139. The runtime
`Math` module (`packages/reflaxe.ocaml/std/runtime/Math.ml`) already
implements them as OCaml `**` and `log`, which are the C library's `pow` and
`log`, the same functions upstream eval uses. The placeholders are deleted,
so Stage3 calls the runtime functions, as it already did for `Math.exp` and
`Math.ceil`.

`Main.hx` covers:
- exact results, such as `pow(2, 3)` and `pow(2.5, 2)`;
- Int arguments;
- the IEEE special values:
  - `pow(0, 0)`, `pow(NaN, 0)`, and `pow(1, NaN)` are 1;
  - `pow(-8, 1/3)` is NaN;
  - `pow(-0.0, -1)` is -Infinity, and `pow(-0.0, 3)` is -0.0;
  - `pow(10, 309)` overflows to +Infinity;
  - `log(0)` and `log(-0.0)` are -Infinity, and `log(-1)` is NaN.

Results are classified (`nan`, `+inf`, `-inf`, `-0`, `0`) or compared with
an exactly representable expected value. Two reasons:
- native printing of whole-number Floats differs (Bead `haxe_ocaml-iffj5`);
- inexact results such as `pow(2, 0.5)` can differ in the last bit between C
  math libraries, so they are only checked against a tolerance.

`npm run test:m14:stage3-math-pow-log` checks that upstream Haxe 4.3.7
prints `expected.stdout`, then requires the Stage3 native executable to
print the same text.

This change was reviewed under the gate in
`docs/00-project/FLOAT_NUMERIC_REVIEW_GATE.md`. The answers and the eval and
neko oracle output are recorded on Bead `haxe_ocaml-hbch2`. Eval and neko
agree on every special value.
