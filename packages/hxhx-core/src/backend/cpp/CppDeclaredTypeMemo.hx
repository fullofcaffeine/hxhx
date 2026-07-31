package backend.cpp;

/**
	Request-owned memoization for C++ declared-type rendering.

	One `CppClassLookup` creates this memo for one program render and shares it
	with every `CppRenderScope` derived from that lookup. Keys still include the
	active scope shape, so generic mappings and resolved class representations
	cannot alias. The memo must never outlive its lookup or become a cross-request
	semantic cache.
**/
class CppDeclaredTypeMemo {
	/** Rendered function-argument types keyed by declaration and scope shape. **/
	public final functionArgTypesByShape:haxe.ds.StringMap<String>;

	/** Rendered field types keyed by declaration and scope shape. **/
	public final fieldTypesByShape:haxe.ds.StringMap<String>;

	public function new() {
		functionArgTypesByShape = new haxe.ds.StringMap<String>();
		fieldTypesByShape = new haxe.ds.StringMap<String>();
	}
}
