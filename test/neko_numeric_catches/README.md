# Neko numeric catch selection

Run `haxe test/m14_neko_typed_catch_integration_test.hxml` from the repository root.
The harness compares Haxe 4.3.7 with both generated Neko layouts.

Each row reports the Int predicate, Float predicate, and selected catch.
The expectations cover integer and floating representations, Neko conversion
limits, fractions, negative zero, NaN, infinities, and nonnumeric values.
NaN and infinities are constructed through arithmetic. Reading the Math static
fields remains separate work in haxe_ocaml-1wi5b and is not proved here.

Dynamic is confined to the heterogeneous throw boundary. Each input is tested
immediately, then reported through concrete booleans and a selected-handler name.
