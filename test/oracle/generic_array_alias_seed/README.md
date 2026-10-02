# Alias constructor and generic call

Constructing `Buffer` must produce the target type `Array<Int>`.
Passing that value to a generic method must select the same declaration as direct array construction.
This fixture reduces the full-program failure in `haxe.io.Bytes.alloc` when it calls `cpp.NativeArray.setSize`.

Run the independent Haxe 4.3.7 observer:

```sh
./node_modules/.bin/haxe -cp test/oracle/generic_array_alias_seed -main Main --interp
```

Expected stdout is `0` followed by a newline.

Run the retained hxhx regression:

```sh
./node_modules/.bin/haxe test/m14_typedef_array_constructor_test.hxml
```

The published compiler fails the explicit `Array<Int>` type assertion because shared declarations discard the typedef target.
The integration compiler instead reports a missing sealed method capture during replay of the direct call.
Existing task `haxe_ocaml-pmsr1.1` owns alias retention and resolution.
Do not replace the alias constructor, widen its type, or allow new inference state during replay.
This failing regression is not part of the passing CI command set.
