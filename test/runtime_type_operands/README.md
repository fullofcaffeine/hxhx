# Runtime type operands

This fixture checks how a class name acts as a type or a value. Two unrelated
classes have the short name `Parent`. Imports and an alias select their exact
declarations.

The right operand of `value is Parent` selects the imported type even when a
local value has the same name. The second argument of `Std.isOfType` selects
that local value. Class-valued fields and enum constructors keep their own
meaning.

Run the behavior reference with upstream Haxe 4.3.7:

```sh
haxe -cp test/runtime_type_operands -main Main --interp
```

Compare stdout with `expected.stdout`. Run the shared typing checks with:

```sh
npm run test:m14:runtime-type-operands
```

The typing test inspects compiler facts before backend projection. The
projection test checks that each operand belongs to its exact function or field
initializer. It rejects copied markers, foreign bodies, stale revisions, and
mutated marker arguments. Ordinary static fields and calls use their selected
declarations without requiring runtime class objects.

The backend test checks rejection before output for targets that do not yet
support these operands. Existing files must retain their contents. These tests
do not prove generated type-check behavior. Native Neko predicates and typed
catches remain separate requirements.

The occurrence identity test observes the catalog's exact raw String diagnostic.
It validates the caught value before comparing the message. This keeps exception
provider conversion separate from the syntax-node identity contract. Native
validation also requires the OCaml enum identity repair tracked by
`haxe_ocaml-3z9p4`. Typed exception-provider retention is tracked by
`haxe_ocaml-ztk6r`.
