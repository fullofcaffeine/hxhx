Use a local compound assignment, such as `x -= 2`, as a value in the native
OCaml program.

In Haxe a compound assignment is an expression. It stores the updated value in
the local and produces that same value, so `var r = (x -= 2)` with `x = 4`
leaves both `r` and `x` at 2, and `while ((i += 1) < 3)` steps `i` on every
test. Upstream Haxe 4.3.7 behaves this way for every local type checked here.

What the fixture checks:

- `-=`, `+=`, `*=`, and `%=` on an `Int` local, used as an initializer, inside
  arithmetic, as a call argument, and as a `while` condition.
- `+=`, `/=`, `*=`, and `%=` on a `Float` local, with `Int` and `Float` right
  operands.
- `+=` and `-=` on a `Null<Int>` local and `*=` on a `Null<Float>` local. The
  result is typed `Null<Int>` or `Null<Float>`, like the local, so the
  produced value is the same nullable carrier that was stored.
- `+=` on a null `Null<Int>` local. The right operand still runs, then the
  update throws before anything is stored, so the local is still null.
- `+=` on a `String` local, with `String`, `Int`, and `Bool` right operands.
  A numeric right operand is computed before it is appended, so
  `text += 1 + 2` appends "3", in both the value and the statement form.
- `+=` on a `Dynamic` local.
- Operators that consume the value: `(x += 1) + (x += 1)`,
  `0.25 * (x += 2)`, `(f += 1) * 2`, `(n += 2) * 3` and `while ((n += 1) < 9)`
  on a `Null<Int>`, `(r *= 3) > 4` on a `Null<Float>`, and `(s += "t") + "!"`.
  The value has the local's type, so the operator must treat it like the local.
- Evaluation order. The old value is read before the right operand runs, so
  `y += (y += 5)` with `y = 10` produces 25 (10 + 15), not 30. The same holds
  for `Float` and `String` locals, and for statements such as
  `y += (y += 5);` and `calls += bump();` where `bump` changes `calls`.
  Statement-position updates use the same lowering with the value ignored.

The test also checks one unsupported shape: `+=` on a `Null<String>` local must
stop emission with an "unsupported OCaml local compound assignment value"
error instead of producing a placeholder.

Before this fixture, the native emitter produced the placeholder
`Obj.magic 0` for every local compound assignment used as a value. The program
printed `0 4` for `var r = (x -= 2)`, skipped the store, and looped forever on
`while ((i += 1) < 3)`. Statement-position updates stored a value, but they
ran the right operand before reading the old value (`y += (y += 5);` gave 30),
and `text += 1 + 2;` appended "12".

Values are chosen so no whole-number Float is printed: `Std.string` of such a
Float still prints `6.` natively (haxe_ocaml-iffj5). Each value is bound to a
local before it is printed, because native String concatenation runs its
operands right to left (haxe_ocaml-5of2v).

Not covered here, and tracked separately:

- the bitwise compound operators `<<=`, `>>=`, `>>>=`, `&=`, `|=`, and `^=`
  (haxe_ocaml-sq6ii);
- a plain assignment used as a value, such as `var r = (x = 7)`
  (haxe_ocaml-afosm);
- a `Dynamic` right operand of an `Int` or `Float` update (haxe_ocaml-jru2s);
- a null value in a `String` local, which natively appends as "" rather than
  "null" (haxe_ocaml-txs4e);
- arithmetic on a `Null<Float>` compound value, such as `(r *= 2) + 0.5`,
  which the typer does not yet type as Float (haxe_ocaml-8rmeb);
- local functions that return `Float` (haxe_ocaml-f0nx0);
- field and array-element compound assignments, which already have their own
  native lowering.

Run `haxe test/m14_stage3_local_compound_value_test.hxml` (or
`npm run test:m14:stage3-local-compound-value`) to compare upstream Haxe with
the generated native OCaml executable.
