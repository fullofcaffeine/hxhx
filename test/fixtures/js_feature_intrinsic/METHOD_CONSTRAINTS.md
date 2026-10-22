# Direct generic method constraints

Run `haxe test/m14_direct_method_constraint_test.hxml` from the repository root.
The test checks source acceptance with upstream Haxe, exact shared-typer results,
and generated JavaScript behavior with Node.

For `echo<T:Base>(value:T):T`, passing a child of `Base` keeps the child's exact type.
Passing an `Int` must produce a source diagnostic before target emission.
The fixtures also cover these cases:

- A caller declares an unrelated type with the same short name as the bound.
- A value must satisfy both a base-class bound and an interface bound.
- An inherited interface has the required type argument.
- A method bound refers to its receiver's class parameter, including through an inherited receiver.
- An empty-object bound retains the original object and concrete result type.

`FeatureBoundConstraintCapture` checks a separate upstream behavior.
Storing this constrained identity method as a callback permits a later call with `Int`.
The direct-call check must not reject that stored-callback fixture.
This case does not establish that every constraint disappears from every captured method.

Upstream and local diagnostic wording can differ.
The test retains separate expectations for the incompatible interface argument.
Neither an arbitrary compiler failure nor successful source acceptance alone counts as passing.

The empty-object acceptance matrix is documented in
[`empty_object_constraint_seed`](../../oracle/empty_object_constraint_seed/README.md).
These tests support `haxe_ocaml-wnqhz`; they do not establish full generic inference
or change README Goals status.
