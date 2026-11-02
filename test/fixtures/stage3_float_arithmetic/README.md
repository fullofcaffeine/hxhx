# Stage3 Float arithmetic

`Main.hx` does arithmetic, comparisons, and compound updates on Float values
and checks that the native Stage3 program prints what upstream Haxe 4.3.7
prints. It covers:

- Float method results, Float and Int fields, a field and a method result of
  type `T` instantiated with Float, and `Array<Float>` elements, each with
  `+ - * / %`;
- mixed Int and Float operands, and `Int / Int` (which is a Float in Haxe);
- `< <= > >= == !=` on those values;
- `+=` and `-=` on a Float local, `f = f + count()`, `this.v += n` and
  `c.v += count()` on a Float field, and `a[0] += count()` on an
  `Array<Float>` element;
- `this` arithmetic in a Float-backed abstract;
- Float-valued `if` and `switch` expressions with an Int branch, stored in a
  local and in a field;
- `Array<Float>` and `Array<Int>` element sums stored in a local and passed
  straight to `Sys.println` (`Sys.println(floats[0] + floats[1])` printed
  `1.52.25` before);
- Int and Float instance fields added with and without `this.` (`x + y`
  printed 0 natively before, haxe_ocaml-evi2o);
- `Null<Float>` and `Null<Int>` operands, and a null `Null<Float>` operand,
  which must raise a catchable error;
- String + Float and String + Int, also when the String comes from a
  function-typed local, which must still concatenate.

The test also requires the typer to reject `count += 1.5` and `count /= 2` on
an Int local with Haxe's `Float should be Int`.

Before the fix, the emitter guessed each operand type from its source shape.
`c.get() + 0.5` printed `1.250.5` (String concatenation), `g.value / 8` and
`a[0] + a[1]` printed 0 (the placeholder `(Obj.magic 0)`) or crashed when used
again, `this / 2` printed 0, `side * side / 2` failed in `ocamlopt`, and
`c.v += count()` was dropped without an error. The typer also typed `7 / 2`
as Int and `maybe * 3` (with `maybe:Null<Float>`) as unknown.

PR #127 made Stage3 read the typer's recorded type for each operand (a call,
a field, an index, `this`). This fixture adds the remaining pieces: the typed
body now records the result type of every arithmetic and ordering expression,
so a nested operand such as `side * side` or `count() * a[2]` is classified
too; the typer types `Int / Int` as Float and `Null<Float> * Int` as Float;
Float field compound updates use the field update lowering; and
`Array<Float>` compound updates use Float arithmetic.

The abstract is built with `from Float` instead of a constructor, because an
abstract constructor that assigns `this` has its own open task
(haxe_ocaml-bc4pm). Every printed Float has a fractional part, so the output
does not depend on how whole-number Floats are formatted (haxe_ocaml-vzr17).

`npm run test:m14:stage3-float-arithmetic` checks that upstream Haxe prints
`expected.stdout`, builds the program with Stage3, and requires the native
executable to print the same text. It also checks that the generated OCaml uses
Float addition for `a[0] + a[1]` and for the `Array<Float>` compound update.
