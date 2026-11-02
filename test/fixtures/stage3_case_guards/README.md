# Case guards and fallthrough

Run `npm run test:m14:stage3-nested-patterns` from the repository root.

A guard (`case Circle(r) if (r > 10):`) refines a pattern. Haxe checks the
guard only after the pattern matches. When the guard is false, matching
continues with the next case, which may have the same pattern.

`Main.hx` covers guards on enum constructors (including a nested array inside
an enum payload), constants and OR patterns, arrays, and anonymous structures.
It also covers guards that read a local captured by a closure after the local
changes, guard side effects and their order, and a statement switch where no
guard succeeds.

The test compares upstream Haxe (`--interp`), native Stage3 OCaml, and the
native JavaScript backend with the same independently recorded
`expected.stdout`. `test/fixtures/stage3_switch_guard` holds the broader guard
contract (bindings across OR alternatives, `break`/`continue`, Dynamic and
abstract conditions).
