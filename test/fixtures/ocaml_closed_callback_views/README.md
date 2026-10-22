# Callback locals with fully known uses

This source program checks callback representation through the actual standalone
compiler and native executable. It adapts static methods and a lambda between
concrete and Dynamic signatures. Aliases and separately adapted views must keep
the originating function's identity. Boolean arguments and results must remain
distinct from integer values.

The callback values in this fixture stay in one function. They are initialized,
called, aliased, and compared; they do not escape through fields, arrays, other
functions, or mutable captured storage. The planner checks all uses before it
changes a local from a raw arrow into an invocation-and-identity pair.

Run the upstream observation with:

```sh
node_modules/.bin/haxe -cp test/fixtures/ocaml_closed_callback_views --run Main
```

`test/m14_dynamic_callable_conversion_test.hxml` reaches this fixture through
`M14StoredCallbackViewsTest`. The harness compares upstream output, generates
OCaml, requires a successful Dune build, and compares native stdout with
`expected.stdout`. It then runs the larger stored-callback fixture, which also
requires higher-order arguments, returned functions, and the diagnostic compiler
path. Passing this program does not replace that acceptance.

The same harness generates a lowering report and runs `verify-report.js` through
the public inspector. It requires seven callback locals and initializer decisions,
eight raw representation operations, and two Boolean runtime-helper uses. Copied
reports must fail inspection when a conversion, selected local, identity proof,
source revision, raw operation, or runtime-helper record is missing or altered.
The test compiles the inspector once and reuses it for all corrupted copies.

Callback reports describe immutable locals whose uses stay within one function.
They do not claim support for returned functions, mutable callback storage, or
foreign calling conventions. The larger fixture keeps those limits visible.
