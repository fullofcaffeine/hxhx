# Sort arrays with three comparator shapes

The program sorts three arrays and prints each result:

1. Anonymous records `{key:String, tick:Int}` sorted by an expression-bodied
   comparator that reads `tick`.
2. Strings sorted by a block-bodied comparator. It reads captured arrays, binds
   locals, returns early, and only then reaches its final comparison.
3. Strings sorted by a comparator that passes each parameter to a typed
   `String` lookup method and also to `Reflect.compare`. This is the shape that
   upstream utest uses to order test method names.

Earlier native builds failed on these shapes. Reflaxe OCaml once read record
fields as tuple projections such as `fst left` and once kept an unused result
binding that the OCaml warnings-as-errors build rejected. The hxhx Stage3
emitter rejected the third shape because its `Reflect.compare` shim accepted
only `Obj.t`, and it sent a typed `Array.sort` call to OCaml's
`Stdlib.Array.sort`.

Run `PORTABLE_FIXTURE_ALLOWLIST=sort_callback_shapes bash scripts/test-portable.sh`
for the Reflaxe OCaml build. The runner compares native output with
`expected.stdout`, and `test.sh` compares the same program with upstream Haxe
eval. `npm run test:m14:stage3-sort-callbacks` builds the same program with the
Stage3 emitter and compares it with upstream Haxe.
