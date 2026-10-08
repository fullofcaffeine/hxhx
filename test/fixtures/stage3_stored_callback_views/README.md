# Stored callback views

A declared callback view must preserve both invocation and function identity.
The source stores one `Dynamic -> Dynamic` function in two `Int -> Dynamic`
locals. Both views and the original function must compare equal. An alias must
also keep that identity. Calling a view with `7` must return `7`.

A second case passes an `Int -> Int` callback through a function that accepts
and returns `Dynamic -> Dynamic` callbacks. The returned view must produce `8`
for input `7` and compare equal to the original callback. This checks opposite
conversion directions at the argument and result boundaries.

The native acceptance contract follows upstream Haxe 4.3.7 eval. In eval,
repeated evaluation of the same lambda creates distinct function identities,
including lambdas with no captures. Repeated reads of a static method remain
equal. The fixture checks both observations and invokes both returned lambdas.
OCaml can share a capture-free invocation closure. To preserve this eval
behavior, a lambda view needs a fresh identity token that later views retain.

This is not an identity-allocation rule shared by every Haxe target. Upstream
Haxe 4.3.7 with Neko 2.4.1 reuses the capture-free function in this fixture.
`expected.neko.stdout` records that observation separately. Lines 9 and 19
differ from eval: separate factory results compare equal, including through a
forwarding function. All other observations agree. The regression checks both
upstream outputs and still requires the native target to match eval.
The [Reflect API](https://api.haxe.org/v/4.3.7/Reflect.html#compareMethods)
describes identity comparison, but does not establish fresh allocation for
every lambda evaluation.

The final case stores the static method directly in an `Int -> Dynamic` local.
Its initializer must create the declaration's view and adapt the argument in
one write. Calling it returns `7`, and it still compares equal to the original
stored function. This tests producer construction and conversion together.

The last six observations exercise function return boundaries. Returning an
existing parameter must preserve its identity and invocation. Returning a
static method must preserve that declaration's identity. Forwarding a factory
result must preserve the identity created by the factory. Wrapping each result
as a new function at the caller would break the existing-value cases.

Run the independent upstream observation from the repository root:

```sh
node_modules/.bin/haxe -cp test/fixtures/stage3_stored_callback_views --run Main
```

The expected output is in `expected.stdout`. The native regression runs through
`test/m14_dynamic_callable_conversion_test.hxml`. It first compiles the same
source with standalone `reflaxe.ocaml`, requires a successful Dune build, and
compares native output. It then parses and types that source with the Stage3
diagnostic compiler, generates OCaml, and compares its native output too.
Both complete source paths must pass.

The same command first checks conversion selection against upstream typed
assignments. A separate native syntax test consumes those selected conversions
and checks identity, evaluation order, and captured-value lifetime. Passing
that component test does not replace the complete source compilation test.

Current limitation: the Stage3 diagnostic emitter stores the original function
without adapting its input representation. Native compilation rejects the raw
integer where the stored function requires `Obj.t`. A wrapper-only repair is
insufficient because separate wrappers change function identity.

The local standalone integration now compiles and executes this program, but
still shares capture-free factory identity instead of matching eval. The
complete source test remains failing. Reproduce that separate route from the
repository root:

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
