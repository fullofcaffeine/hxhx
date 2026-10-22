# Public runtime names

Haxe reflection uses a public name that can differ from the compiler declaration identity.
For example, the public class `model.Types.PublicLeaf` reflects as `model.PublicLeaf`.
Its private sibling reflects as `model._Types.Hidden`.

The retained Haxe 4.3.7 interpreter and JavaScript observations agree on `expected.stdout`.
They cover class and enum names, imported aliases, explicit native names, ordinary generic classes,
specialized generic classes, and lookup by public versus module-qualified names.
`Selection.hx` also distinguishes equal short names in two packages and a local that shadows an import.

`ExternNames.hx` binds existing JavaScript host constructors. Haxe reports `Array` for one
and `undefined` for the other. A native binding name alone cannot prove host reflection metadata.
The shared compiler therefore rejects extern reflection names until a target supplies the runtime identity.
It also rejects specialized generic names until it owns their generated declarations.
These restrictions apply when a consumer requests reflection, not to type-only uses.

Run the regression with:

```sh
haxe test/m14_public_reflection_name_test.hxml
```

The test compares both upstream executions with the retained output. It also checks shared facts,
import selection, local shadowing, immutable metadata, changed fingerprints, and C++ projection ownership.
The required `test:m14:runtime-type-shared` command includes it.
C++ runtime reflection execution remains a separate requirement of `haxe_ocaml-sp2zl`.
