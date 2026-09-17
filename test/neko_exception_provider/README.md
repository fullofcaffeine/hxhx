# Exception provider type facts

This fixture follows class values through the real Neko `haxe.Exception`
provider. The shared typing check verifies the selected `Std.isOfType` call and
the `Class<haxe.Exception>` argument in the provider methods.

Run `haxe test/m14_runtime_type_provider_facts_integration_test.hxml` from the
repository root. The runtime expectation in `expected.stdout` is a separate
upstream reference. Passing the typing check does not prove native exception
conversion or catch dispatch. Those remain owned by `haxe_ocaml-j4pby` and
`haxe_ocaml-41m6r`.
