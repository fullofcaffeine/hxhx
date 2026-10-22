package backend.cpp;

/**
	Select one real function in the exact executable projection. Ordinary methods
	use their projection object; nested functions use their cataloged expression.
	A root is never represented by a fabricated lambda or a source-name match.
 */
enum CppManagedFunctionOwner {
	Root(projection:TypedBackendFunctionProjection);
	Closure(expression:HxExpr);
}
