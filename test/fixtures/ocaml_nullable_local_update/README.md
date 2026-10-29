Update nullable `Int` and `Float` locals in the native OCaml program.

A `Null<Int>` or `Null<Float>` local is stored in the nullable carrier described
in `test/fixtures/ocaml_nullable_int_carrier/README.md`: `HxRuntime.hx_null`
for null, otherwise the boxed number. An increment, decrement, or compound
assignment must read the number out of that carrier, compute the next number,
and box it again before storing it.

What the fixture checks:

- `n++`, `++n`, `n--`, and `--n` on a populated `Null<Int>`, used both as a
  value and as a statement. Postfix produces the old number and prefix the new
  one. In Haxe 4.3.7 both results are typed `Int`, not `Null<Int>`.
- `+=`, `-=`, and `*=` statements on the same local.
- The same updates on a `Null<Float>` local and on a plain `Float` local, which
  step by `1.0` with float arithmetic.
- A nested `Null<Null<Int>>` local. Haxe 4.3.7 keeps the written type but
  updates it like one nullable layer; the native program uses the same carrier.
- Updating a null `Null<Int>` with `n++`, `++n`, and `n += 1`, and a null
  `Null<Float>` with `f++` and `f += 1`. Each one throws "Null Access" before
  anything is stored, so the local is still null after the caught exception.
- Decrementing a null `Null<Null<Int>>`, and `n += side()` / `n + side()` /
  `f += side()` on null locals. The right operand still runs before the throw,
  as in Haxe, and the next number is never stored.
- Upstream Haxe's interpreter reports "Null Access" only when a null is stepped
  by the literal 1 (`n++`, `++n`, `n += 1`). Other shapes report a different
  message, such as "Invalid operation: null - 1" for a decrement or
  "Invalid operation: null + 2" for `n += 2`. The native program raises Null
  Access for every null update, so those cases print only that they threw.

Before this fixture, the native emitter applied integer arithmetic directly to
the carrier, so the generated OCaml either failed to compile or (when OCaml
inference let it through) printed an unrelated integer for a null update. A
null `Null<Float>` unwrap also raised an uncatchable OCaml `Failure` instead of
the Haxe Null Access exception, and a nullable Int operand was unwrapped before
the right operand ran.

Values are chosen so no whole-number Float is printed: `Std.string` of such a
Float still prints `6.` natively (haxe_ocaml-l26hl). The helper calls are
counted through an array because native static variable increments are a
separate gap (haxe_ocaml-nq65n).

Not covered here: a compound assignment used as a value, such as
`var r = (n -= 2)`. `test/fixtures/ocaml_local_compound_value` covers that
form for nullable and ordinary locals.

Run `haxe test/m14_stage3_nullable_local_update_test.hxml` (or
`npm run test:m14:stage3-nullable-local-update`) to compare upstream Haxe with
the generated native OCaml executable.
