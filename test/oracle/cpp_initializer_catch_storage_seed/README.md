# Catch variables in field initializers

A field initializer can catch a value and return a closure that retains it.
Each object must receive a separate mutable catch variable. A function stored
in a field can also create these closures, with separate variables on each call.
An uncaptured catch retains the selected value without an extra heap cell.

The Haxe program checks both forms and uncaptured catches. Its independent
success expectation is exit status zero and empty stdout/stderr. Build it with
upstream Haxe 4.3.7 and hxcpp, using the repository's background scheduling policy:

```sh
haxe -cp test/oracle/cpp_initializer_catch_storage_seed -main Main -cpp .tmp/cpp-initializer-catch-reference
.tmp/cpp-initializer-catch-reference/Main
```

Run `haxe test/m14_cpp_initializer_catch_storage_test.hxml` for candidate storage
coverage, or `npm run test:m14:cpp-catch-uses` for the related tests together.
The candidate test uses the actual field and closure binding projections.
Production emitters allocate catch storage and generate the retained closure.
The independent native observer supplies the selected value after unwinding.
It checks separate cells, payload identity, null, collection, failed publication,
and complete cleanup at O0/O2 with address and undefined-behavior sanitizers.
Ownership negatives reject foreign bindings, wrong lexical owners, wrong
creation events, and mutated projections.

This test proves storage after handler selection. Native Haxe handler selection,
wrapping, and complete field execution still require the full exception and
initializer tests. Tasks `haxe_ocaml-qrk0u` and `haxe_ocaml-9jezt` remain open.
