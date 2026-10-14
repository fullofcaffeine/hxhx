# JavaScript indexed compound assignments

Run `npm run test:m14:js-array-compound` from the repository root.

The test first compares this authored Haxe program with upstream Haxe eval.
It then types the same source, generates fresh JavaScript, runs Node, and
compares both results with the independently specified `expected.stdout`.

The program checks receiver/index/RHS order, reading the old element before
the RHS changes it, returned assignment values, and no write after a throw.
It also checks lazy null-coalescing assignment, instance receiver access,
and a local name that resembles an internal emitter variable.

The same command runs the unchanged 14-line abstract-operator fixture from
`../cpp_abstract_binary_operator_seed` through its real JavaScript providers.
That fixture covers an inline abstract update whose destination is an array
element. A reduced test alone must not replace this original regression.
