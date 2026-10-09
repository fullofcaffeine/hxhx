# Native object allocation and typed field storage

The program observes static and local object literals, nested fields, Boolean
reads and writes through typed and Dynamic aliases, and object identity.
It also checks initializer order, left-to-right comparison effects, and a
throwing initializer that must prevent later field evaluation.

Run `npm run test:m14:stage3-object-storage` from the repository root.
The test compares upstream Haxe 4.3.7 and native OCaml with `expected.stdout`.
It also rejects conversion facts borrowed from another projection or a removed
field access. Generated target files remain artifacts, never edited inputs.

This fixture does not establish all object semantics. Optional-field presence,
nullable Boolean conversions, compound field operations, and broader bootstrap
integration remain acceptance work under `haxe_ocaml-05q72` and its related tasks.
