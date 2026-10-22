# Native generic values

This fixture checks that generic methods preserve the distinction between Boolean values and integers.
The same authored program runs with upstream Haxe and the native OCaml emitter.
Its expected output is written independently in `expected.stdout`.

The program checks direct generic returns, static and instance method captures,
Float identity, delayed invocation, and writes to the captured receiver.
The native test also checks that emission does not change the authored typed module.

Run `haxe test/m14_ocaml_generic_values_integration_test.hxml` from the repository root.
The existing Int-field integration command includes this test and the String-field test.
These focused tests load real provider declarations but emit their root module.
They do not establish support for the complete standard-library dependency closure.
