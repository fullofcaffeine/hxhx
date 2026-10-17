# Shared constructor allocation assembly

This fixture checks the allocation wrapper used by the standalone OCaml class emitter.
The shared target function receives the already selected initializer, constructor body and parameter patterns.
It allocates the receiver, runs the body once, and returns that same receiver.
The shared record builder adds the runtime class marker as the first slot and checks the remaining member order against the declaration.
The class owner still selects inherited fields, dispatch methods, field carriers and storage defaults.
A shared marker operation consumes the existing checked runtime permission for each constructor or empty allocation.

Run the full source-to-runtime check from the repository root:

```sh
bash scripts/ci/reflaxe-ocaml-shared-construction-test.sh
```

The independent OCaml observer checks order, object identity, distinct storage and constructor exceptions.
The Haxe program checks field initialization, two instances, and retained mutations after an exception.
It also checks inherited fields, virtual calls, zero-argument constructors and separate array storage.
Runtime reflection must recover the correct class after ordinary and empty allocation, including an upcast from a child to its parent.
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

## Constructor input phase

The lifecycle command also checks Haxe's constructor input before and after generation.
Haxe inserts instance field initializers after `onGenerate`, before Reflaxe consumes the program.
The test checks that each initializer precedes the authored body and the child's `super()` call.
Three-field cases distinguish Haxe 4.3.7's observed reverse declaration order
from alphabetical order. The inherited case omits its constructor in source;
Haxe supplies a constructor that initializes local fields, then forwards the
inherited argument to `super`. The test checks that argument's binding identity.
Independent eval, JavaScript, and Neko observations establish the expected order.
The native lifecycle program also checks these cases and their empty allocations.
This guards the shared-target migration against omitted or duplicated initialization effects.
It does not claim that the native program adapter already supports complete construction.

Run this focused check from this fixture directory:

```sh
haxe -cp source -cp src -main Main --no-output --macro 'ConstructorInputPhaseFixture.install()'
```
