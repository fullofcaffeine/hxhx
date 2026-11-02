# Typer: the type of an assignment expression

`Main.hx` uses `$type(...)` on assignment expressions: to Float, `Null<Int>`,
Int and String locals, to Float and `Null<Int>` class fields, to
`Array<Float>` and `Array<Null<Int>>` elements, to an abstract local whose
`@:from` converts the Int value, and one compound assignment (`total += 2`).
Upstream Haxe 4.3.7 prints each type as a compile-time warning.
`expected.types` lists those types in order.

Haxe types `place = value` as the type of `place`, after the value is
converted to it. Before the fix, the hxhx typer gave an assignment to a
local or an array element the type of the value instead: `(ratio = 5)` with
`ratio:Float` was typed Int, and `(maybe = 3)` with `maybe:Null<Int>` was
typed Int.

`npm run test:m14:typer-assignment-type` checks that upstream still prints
`expected.types`. It then types the same program with hxhx (each `$type(`
replaced by `(`) and requires the type of every assignment expression, in
source order, to match that list.
