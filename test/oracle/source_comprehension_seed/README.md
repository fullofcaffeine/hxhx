# Authored comprehension contract

These fixtures describe syntax that macros must receive before execution is lowered.
They cover ordinary and guarded comprehensions, written parentheses, key/value bindings,
nested loops, and strings or comments that contain an arrow token.

Run the public syntax observer with pinned upstream Haxe 4.3.7:

```sh
./node_modules/.bin/haxe -cp test/oracle/source_comprehension_seed/src --run Main
./node_modules/.bin/haxe -cp test/oracle/source_comprehension_seed/src --run RuntimeMain
./node_modules/.bin/haxe -cp test/oracle/source_comprehension_seed/src --run ForMain
```

`ComprehensionContract.expected()` contains explicit constructor-shape expectations.
The upstream macro compares those expectations with `Context.parse` output.
`RuntimeMain` separately checks ordinary array and map behavior.
Syntax observations alone do not establish runtime equivalence.

Run the corresponding hxhx contract:

```sh
./node_modules/.bin/haxe test/m14_source_comprehension_syntax_test.hxml
```

This regression belongs to `haxe_ocaml-20jan`.
It is not yet part of the passing CI command set.
The parser and shared typing must preserve authored structure before this task can close.
Do not replace the grouped inputs, discard guards, or accept synthetic helper calls as source syntax.
The task also requires binding, source-position, target-runtime, and combined regression evidence.

Check inferred element types and exact backend occurrence ownership:

```sh
./node_modules/.bin/haxe test/m14_source_comprehension_typing_test.hxml
```

The `array/Collection.hx` function provides a small native execution contract.
Its observer uses real standard-library type declarations and the managed C++ function emitter.
It checks yielded values, iteration count, guard evaluation order, and per-iteration closure capture.
Array key/value cases check zero-based indices and closures that retain both iteration variables.
Chained guards skip later tests and yields when an earlier guard rejects an element.
Captured functions retain distinct values after the result array is released.
Nested loops append to one flat array in source order.
A return in a yielded block exits the authored function; loop exits skip the appropriate appends.
The observer forces garbage collection and checks that released storage is reclaimed.
It compiles at `-O0` and `-O2` with address and undefined-behavior sanitizers.

```sh
./node_modules/.bin/haxe -cp test/oracle/source_comprehension_seed/array -main CollectionOracle --interp
./node_modules/.bin/haxe test/m14_source_comprehension_managed_test.hxml
```

The separate full-program test retains module loading and ordinary library calls:

```sh
./node_modules/.bin/haxe test/m14_source_comprehension_native_test.hxml
```

That test currently fails while resolving a generic Array typedef before native emission.
The direct observer does not establish full-program success.
Maps, conversions, other target routes, and further nested/control combinations still need execution evidence.
Array key/value coverage here is limited to this direct native observer.

The `maps/` fixture retains plain, grouped, guarded, branched, and nested map yields.
It also distinguishes a map comprehension from an array whose elements are maps.
Run the independent upstream expectation and shared typing contract:

```sh
./node_modules/.bin/haxe -cp test/oracle/source_comprehension_seed/maps -main MapOracle --interp
./node_modules/.bin/haxe test/m14_source_map_comprehension_typing_test.hxml
```

Upstream passes all cases. Shared typing now accepts map yields using the real Map provider.
The expanded typing contract still fails for the short alias in `Array<Map<Int, Int>>`.
The corresponding fully qualified `Array<haxe.ds.Map<Int, Int>>` case passes its type assertions.
The original alias case remains in the test; typedef resolution belongs to `haxe_ocaml-pmsr1.1`.
The focused map-capture fixture now runs through shared control lowering and managed C++ storage:

```sh
./node_modules/.bin/haxe -cp test/oracle/source_comprehension_seed/map_capture -main MapCaptureOracle --interp
./node_modules/.bin/haxe test/m14_source_map_capture_managed_test.hxml
```

Integer and string keys replace earlier entries while retaining distinct iteration closures.
The native observer releases the map, collects garbage, invokes the retained closures, and checks that all storage is reclaimed.
Both optimization modes use address and undefined-behavior sanitizers.
This proves selected construction operations; ordinary Map methods, other key kinds, nullable keys, and full-program target integration remain unproved.

The broader map execution contract remains separate and unchanged:

```sh
./node_modules/.bin/haxe -cp test/oracle/source_comprehension_seed/map_execution -main MapExecutionOracle --interp
./node_modules/.bin/haxe test/m14_source_map_comprehension_managed_test.hxml
```

Upstream passes that contract. Native generation stops at the remainder operator in its duplicate-key case.
`haxe_ocaml-6gjt1` owns that arithmetic prerequisite. The modulo expression remains in the test.
The focused map-capture pass does not replace this broader failing gate.
