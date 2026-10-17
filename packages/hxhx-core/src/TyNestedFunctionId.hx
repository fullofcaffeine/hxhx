import HxParsedFunction.HxParsedFunctionForm;
import HxParsedFunction.HxParsedFunctionOrigin;

/** A named local declaration and a function value occupy different source roles. */
enum TyNestedFunctionKind {
	LocalDeclaration;
	FunctionExpression;
}

/** Source occurrence facts supplied by the enclosing function's deterministic traversal. */
typedef TyNestedFunctionIdentityInput = {
	final ownerIdentity:String;
	final sourceOrdinal:Int;
	final form:HxParsedFunctionForm;
	final origin:HxParsedFunctionOrigin;
	final kind:TyNestedFunctionKind;
};

/**
	Identify a nested function independently of its source name or position.

	The enclosing function owns the occurrence ordinal. A nested function uses
	this key as the owner of its parameters, locals, and generic binders. Replay
	must supply the same source occurrence, while siblings and nested scopes
	remain distinct even when they reuse every source name.

	This value does not allocate ordinals or infer captures. Those operations
	belong to the shared typer's traversal when it adopts the complete function AST.
 */
class TyNestedFunctionId {
	final canonicalKey:String;
	final ownerIdentity:String;

	public function new(input:TyNestedFunctionIdentityInput) {
		if (input.ownerIdentity == null || StringTools.trim(input.ownerIdentity).length == 0 || input.sourceOrdinal < 0)
			throw "nested function identity requires an owner and non-negative source ordinal";
		ownerIdentity = input.ownerIdentity;
		final form = switch (input.form) {
			case Ordinary: "ordinary";
			case Arrow: "arrow";
		};
		final origin = switch (input.origin) {
			case Authored: "authored";
			case Generated: "generated";
		};
		final kind = switch (input.kind) {
			case LocalDeclaration: "local-declaration";
			case FunctionExpression: "function-expression";
		};
		canonicalKey = CompilerCacheIdentity.encode([
			"nested-function-identity-v1",
			ownerIdentity,
			Std.string(input.sourceOrdinal),
			form,
			origin,
			kind
		]);
	}

	public function getCanonicalKey():String
		return canonicalKey;

	public function getOwnerIdentity():String
		return ownerIdentity;

	public function equals(other:TyNestedFunctionId):Bool
		return other != null && canonicalKey == other.getCanonicalKey();
}
