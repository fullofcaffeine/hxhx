/**
	Names the legacy parser shapes that remain intentionally unsupported by the
	typed-body spine.

	Opaque nodes are allowed only when `TypedBodyInvariant` can prove that their
	raw payload contains no operator or mutation syntax. This keeps unsupported
	bootstrap syntax explicit without creating a hiding place for semantic
	operator decisions.
**/
enum TypedOpaqueExprKind {
	TryCatch;
	Switch;
	Unsupported;
}
