# Neko numeric catch selection

Run `haxe test/m14_neko_typed_catch_integration_test.hxml` from the repository root.
The harness compares Haxe 4.3.7 with both generated Neko layouts.

Neko 2.4.0 classifies the Float value `-1073741824.0` differently on the
observed runtimes. macOS ARM selects the Float catch; Linux x86-64 selects Int.
The two complete snapshots preserve those upstream observations. Running either
host's bytecode on the other runtime follows the runtime's result.
The harness accepts only these recorded upstream outputs, then requires both
generated layouts to match the current runtime's upstream output exactly.

Each row reports the Int predicate, Float predicate, and selected catch.
The expectations cover integer and floating representations, Neko conversion
limits, fractions, negative zero, NaN, infinities, and nonnumeric values.
NaN and infinities are constructed through arithmetic. Reading the Math static
fields remains separate work in haxe_ocaml-1wi5b and is not proved here.

Dynamic is confined to the heterogeneous throw boundary. Each input is tested
immediately, then reported through concrete booleans and a selected-handler name.
