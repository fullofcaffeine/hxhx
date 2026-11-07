# Indexed array assignment

A statement such as `values[1] = 7` must change the real array, not a copy,
and must not be dropped. An older native OCaml build compiled that statement
to `()`, so the program ran without error and printed `null` where upstream
Haxe printed `7`.

This fixture writes through an alias passed to another function, repeats
writes to one slot, uses a write as a value, grows an array by writing past
its end, and writes `String`, `Float`, nullable `Int`, and loop-indexed
elements. It also records that the receiver, the index, and the value are each
evaluated once, in that order.

The test runs this source with upstream Haxe and with the native OCaml target
and compares both with `expected.stdout`:

```sh
npm run test:m14:stage3-indexed-array-assignment
```

Arithmetic between two element reads, such as `values[0] + values[1]`, is not
covered here. That gap is tracked separately (`haxe_ocaml-zc8om`).
