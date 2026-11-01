# Stage3 abstract constructors that assign control flow to `this`

An abstract constructor picks the abstract's run-time value with
`this = value`. That value can come from control flow:

```haxe
abstract Pick(Int) {
	public function new(n:Int) this = if (n > 0) n else -n;
}
abstract Squares(Array<Int>) {
	public function new(n:Int) this = [for (i in 0...n) i * i];
}
```

`Main.hx` assigns `this` from `if`/`else`, a ternary, a `switch` with a guard,
an array comprehension, an `if` that contains a `switch`, `try`/`catch`, and a
closure created in the constructor. It also uses a compound assignment whose
right side is control flow (`this *= switch ...`, `this += if ...`), a right
side that reads `this` (`this = if (c) this + 1 else this`), a compound right
side that writes `this` before the update (`this` was 10, the right side sets
it to 100 and yields 1, and the result is 11), and control-valued writes used
as values (`final stored = (this = if (c) 3 else 4)`). Int,
String, Array, and Float backing types are covered; the Float cases check that
the value stays an OCaml float.

Before the fix, the native build stopped with
`control-valued assignment requires a supported exact destination`. Control
lowering moves the statements of an `if` or `switch` value in front of the
assignment and then writes the final value to the saved destination, but it
did not accept `this` as a destination. It now treats `this` like a local: there
is no receiver or index to save, so the lowered code runs the branch statements
and then performs one ordinary `this = value`, which Stage3 stores in the
constructor's `this` slot.

The fixture avoids two open gaps that are not specific to `this`: an Int
branch value inside a Float-valued `if` (Bead haxe_ocaml-hnqdn) and integral
Float literals such as `1.0` (Bead haxe_ocaml-l26hl).

Outside a constructor, Stage3 rejects a control-valued `this` write with a
named error. An inline abstract method such as
`inline function bump(c:Bool) this = if (c) this + 1 else this - 1` runs in
upstream Haxe, but the native method body cannot yet write the caller's value
back (Bead haxe_ocaml-rs48f), and the lowered write would otherwise be dropped
without a message. The test checks that rejection, and also the class case
that upstream itself rejects.

`npm run test:m14:stage3-abstract-this-constructor` checks that upstream
Haxe 4.3.7 prints `expected.stdout`, builds the program with Stage3, and
requires the native executable to print the same text.
