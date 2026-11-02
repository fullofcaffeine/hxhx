# Stage3 Math with Int arguments and Null<Int> indices

`Main.hx` calls `Math` functions with Int literals, Int-returning calls and
Int locals, and uses a `Null<Int>` local as an array index.

Before the fix:

- `Math.abs(-2)` failed to compile. Stage3 emitted
  `abs_float ((HxInt.neg (2)))`, passing an OCaml int where a float is
  needed, and `Math.isNaN(3)` passed an int to `classify_float`. Haxe declares
  every `Math` function with Float parameters, so an Int argument must be
  widened first.
- `a[i] = 5` with `i:Null<Int>` was dropped (the program printed `1,2,7`
  instead of `1,5,7`). Indexed reads and writes were lowered only for an
  exact `Int` index. A `Null<Int>` index is now unwrapped first; a null index
  raises the runtime's Null Access error.

Whole-number Float results are printed after adding `0.5` (for example
`Math.abs(-2) + 0.5`), because native Float printing of `2.0` still differs
from upstream (haxe_ocaml-vzr17). `a[i]++` is not covered: `++` on any array
element is still dropped (haxe_ocaml-p19r8). `Null<Int>` Map keys are
covered by PR #151 (`stage3_nullable_call_arguments`).

`npm run test:m14:stage3-math-int-nullable-index` checks that upstream Haxe
4.3.7 prints `expected.stdout`. It then builds the program with Stage3 and
requires the native executable to print the same text.
