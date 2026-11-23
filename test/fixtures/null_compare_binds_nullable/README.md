# Null comparison binds nullable

`value == null` on an untyped input makes it `Null<T>`, and later evidence chooses `T`, as in Haxe 4.3.7. The fixture covers `setResolver`, the four operator kinds that read the input as open, and `merge`. The native run leaves out `flagged`, because frozen Stage3 emits a placeholder for `|` on `Null<Int>` (`haxe_ocaml-ayqj8`).

The fixture also covers recursive results. In `return if (c) a else b`, a recursive call passed to `wrap(n:Node)` binds the result to `Node` before the one return (`BalancedTree.removeLoop`). A return written before the recursive call binds the result first, so it stays `Null<Node>`.

`UpstreamSignatures.hx` prints the full upstream signatures, because the shared input observer reads through `Null`. Run `node_modules/.bin/haxe test/m14_null_compare_binds_nullable_test.hxml`. The test compares input types and signatures with upstream, and runs the native output.
