# Stage3 maps: StringMap, IntMap, ObjectMap, and Map

`Main.hx` uses every instance method of `haxe.ds.StringMap`, `IntMap`, and
`ObjectMap` (`set`, `get`, `exists`, `remove`, `keys`, `iterator`,
`keyValueIterator`, `copy`, `toString`, `clear`). It also uses the `Map<K, V>`
abstract with String and Int keys: `new Map()`, map literals such as
`["one" => 1]`, `map[key]` reads and `map[key] = value` writes, and the three
loop forms `for (k in m.keys())`, `for (v in m)`, and `for (k => v in m)`. It
covers missing keys (`get` returns `null`), removing a key twice, copies that
change independently, clearing, object keys compared by identity, and maps
held in a local, a static field, an instance field, and a parameter. A
map literal in a static initializer and `Array` values read back through
`get` and `map[key]` (then used with `push` and `length`) are covered too.

Upstream Haxe does not define a Map iteration order, so every listing with
more than one entry is sorted before printing, and `toString` is only printed
for maps with zero or one entry.

Before the fix, the native program printed `string get=0,0 missing=0` and
`string exists=false,false`, then crashed with SIGBUS (exit 138). The map
classes are `extern`, so their methods have no Haxe body, and Stage3 bound
each call to an empty generated stub. `new StringMap()` produced the
placeholder `0`. The `Map` abstract forwards to the `IMap` interface, whose
calls also reached stubs, and map literals produced the placeholder `0`.

`npm run test:m14:stage3-map-methods` checks that upstream Haxe 4.3.7 prints
`expected.stdout`. It then builds the program with Stage3 and requires the
native executable to print the same text. It also checks that every instance
method of the emitted map classes has a native adapter, that every `Map`
instance method stays a call for that adapter, and that a `Map` with an enum
key fails at emit time with a named error.
