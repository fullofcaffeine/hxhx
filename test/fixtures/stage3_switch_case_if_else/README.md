# Conditionals inside switch cases

Run `npm run test:m14:stage3-switch-case-if-else` from the repository root.

A switch case body can end with a conditional that produces the case value:

```haxe
case "u":
	var t = date.getDay();
	if (t == 0) "7" else Std.string(t);
```

Both branches must stay reachable. `Main.hx` covers an expression `if`/`else`
after a local declaration, `else if` chains, a ternary, a nested `if` whose
inner `else` belongs to the inner condition, a statement `if` with a semicolon
before `else`, and the same conditional in a block outside any switch.

The test compares upstream Haxe (`--interp`), native Stage3 OCaml, and the
native JavaScript backend with the same independently recorded
`expected.stdout`. It also checks the parsed case body shape directly.
