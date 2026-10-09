# Shared constructor allocation assembly

This fixture checks the allocation wrapper used by the standalone OCaml class emitter.
The shared target function receives the already selected initializer, constructor body and parameter patterns.
It allocates the receiver, runs the body once, and returns that same receiver.
Class layout, field defaults, dispatch and runtime authorization remain with their existing owners.

Run the full source-to-runtime check from the repository root:

```sh
bash scripts/ci/reflaxe-ocaml-shared-construction-test.sh
```

The independent OCaml observer checks order, object identity, distinct storage and constructor exceptions.
The Haxe program checks field initialization, two instances, and retained mutations after an exception.
It also checks inherited fields, virtual calls, zero-argument constructors and separate array storage.
Upstream Haxe initializes the child's field before entering the parent constructor in this fixture.
Both ordinary and inherited empty allocation must skip authored initializers and constructor effects.
Both upstream Haxe and the generated native executable must produce `expected.stdout`.
No generated file is edited to obtain a passing result.

The focused assembly check is:

```sh
node_modules/.bin/haxe test/reflaxe_ocaml_shared_construction/test.hxml
```

This extraction does not admit class construction in the complete native program wrapper.
The original instance-call acceptance remains open under `haxe_ocaml-i1c2c`.
