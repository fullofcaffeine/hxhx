The shared representation decision explains why a nullable primitive field uses
an `Obj.t` carrier, but it can serve more than one emitted field/default. It must
not become a reusable permission to print `HxRuntime.hx_null` anywhere.

Introduce one small Haxe-authored default plan whose identity includes the
concrete field or static-storage owner, owner revision, source span, exact
`Null<Int>` or `Null<Bool>` representation, profile, runtime requirement, and
one expression occurrence. The field materializer validates that plan and can
construct the private identifier only through `OcamlRuntimeUseAuthority`.

The compiler already supplies stable field/storage owner IDs to
`materializeRepresentedFieldDefault`. Extend that existing boundary rather than
recovering ownership in syntax code. Keep type/carrier materialization as a
separate path that validates the representation but never constructs a runtime
value. Reconcile the completed default locally and through the final output
authority, including deliberate constructor copies.

Start from an independently authored focused expectation that fails because the
plan type and checked occurrence do not exist. Preserve the regression, then
prove one native build/run tracer. Stop and redesign if the implementation needs
a type-wide runtime permission, target-text scanning, generated-output repair,
or a handwritten OCaml semantic helper.
