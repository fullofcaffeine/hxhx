# JavaScript comprehensions after shared lowering

Run `haxe test/m14_js_lowered_comprehension_test.hxml` from the repository root.
The same authored source compiles with upstream Haxe 4.3.7 and the candidate.
Node must produce the independent `expected.stdout` for both outputs.

The fixture covers ranges, array iteration, guards, nested loops, conditional
selection, ordered bound and yield effects, and early method returns.
A comprehension inside a callback reads the current captured value.
Shared typing uses the real Class and Array declarations.
The test also rejects copied, foreign, ownerless, and mutated append operations.
Targets without an append consumer retain their existing rejection.

The complete provider graph remains a separate integration requirement.
This focused test emits every declaration in its authored module.
It does not establish complete standard-library or native compiler readiness.

The existing `test:m14:js-expr-array-comprehension` command runs this test first.
Its following legacy expression-only checks still require migration to the
current shared lowering contract. Those checks remain unchanged and fail at
the explicit source-control guard. Task `haxe_ocaml-20jan` retains that work.

The observer uses qualified static calls. The valid bare-call form currently
fails capture analysis when its argument needs statement lowering.
Task `haxe_ocaml-9pfzw` retains that separate failure and its original fixture.
