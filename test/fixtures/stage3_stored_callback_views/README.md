# Stored callback views

A declared callback view must preserve both invocation and function identity.
The source stores one `Dynamic -> Dynamic` function in two `Int -> Dynamic`
locals. Both views and the original function must compare equal. An alias must
also keep that identity. Calling a view with `7` must return `7`.

A second case passes an `Int -> Int` callback through a function that accepts
and returns `Dynamic -> Dynamic` callbacks. The returned view must produce `8`
for input `7` and compare equal to the original callback. This checks opposite
conversion directions at the argument and result boundaries.

Run the independent upstream observation from the repository root:

```sh
node_modules/.bin/haxe -cp test/fixtures/stage3_stored_callback_views --run Main
```

The expected output is in `expected.stdout`. The native regression runs through
`test/m14_dynamic_callable_conversion_test.hxml`. It parses and types the same
source, generates OCaml, compiles it, and observes the executable output.

The same command first checks conversion selection against upstream typed
assignments. A separate native syntax test consumes those selected conversions
and checks identity, evaluation order, and captured-value lifetime. Passing
that component test does not replace the complete source compilation test.

Current limitation: the Stage3 diagnostic emitter stores the original function
without adapting its input representation. Native compilation rejects the raw
integer where the stored function requires `Obj.t`. A wrapper-only repair is
insufficient because separate wrappers change function identity.

The standalone target currently emits the same invalid native call. Reproduce
that separate route from the repository root:

```sh
node_modules/.bin/haxe -cp test/fixtures/stage3_stored_callback_views -main Main --no-output -lib reflaxe.ocaml -D ocaml_no_build -D ocaml_output=.tmp/stored_callback_views/standalone
dune build --root .tmp/stored_callback_views/standalone ./standalone.exe
```

Require the Dune command to pass before executing its output. The compiler can
report a failed automatic Dune build as a warning while returning success.
After a successful native build, run `_build/default/standalone.exe` inside
the output directory and compare its output with `expected.stdout`.

This fixture belongs to `haxe_ocaml-v0zbr`. Repair the standalone target's
callable storage/conversion contract and preserve the native host acceptance;
this failing regression does not prove shared-target readiness.
