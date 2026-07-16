package backend.cpp;

typedef CppExactCallEmitterServices = {
	var lookupForScope:CppRenderScope->CppClassLookup;
	var ownerForType:String->CppRenderScope->CppClassLookup->Null<HxClassDecl>;
	var cppTypeHint:String->CppRenderScope->CppClassLookup->String;
	var representation:HxClassDecl->CppClassLookup->Null<CppAbstractRepresentation>;
	var ordinaryCall:HxExpr->String->Array<HxExpr>->CppRenderScope->String;
	var method:HxClassDecl->String->Null<HxFunctionDecl>;
	var isInline:HxFunctionDecl->Bool;
	var inlineBody:HxExpr->HxFunctionDecl->CppRenderScope->Null<String>;
	var valueForExpectedType:HxExpr->String->CppRenderScope->String;
	var renderExpression:HxExpr->CppRenderScope->String;
	var sanitizeIdentifier:String->String;
};

/**
	Emits an exact typed instance call without choosing its source declaration.

	Shared typing has already selected the canonical declaration and lowered every
	abstract operator decision before this module runs. This target seam only maps
	the selected receiver call onto the current C++ carrier ABI. Ordinary classes
	keep instance dispatch; direct-carrier abstracts call their generated helper.
	The inline-body branch is retained solely for ordinary abstract methods during
	the carrier-cleanup migration and must not receive a lowered operator call.
**/
class CppExactCallEmitter {
	/** Return the C++ result representation carried by the exact typed call. **/
	public static function cppType(expression:HxExpr, scope:CppRenderScope, services:CppExactCallEmitterServices):String {
		if (scope == null)
			return "";
		final exact = TypedExactCallSource.decodeInstance(expression);
		return exact == null ? "" : services.cppTypeHint(exact.resultType, scope, services.lookupForScope(scope));
	}

	/** Emit one already-selected call, or return null when the expression is not an exact-call payload. **/
	public static function render(expression:HxExpr, scope:CppRenderScope, services:CppExactCallEmitterServices):Null<String> {
		if (scope == null)
			return null;
		final exact = TypedExactCallSource.decodeInstance(expression);
		if (exact == null)
			return null;
		if (exact.declaration.length == 0)
			throw "exact typed instance call is missing its canonical declaration identity";

		final lookup = services.lookupForScope(scope);
		final owner = services.ownerForType(exact.owner, scope, lookup);
		final representation = services.representation(owner, lookup);
		if (representation == null)
			return services.ordinaryCall(exact.receiver, exact.method, exact.arguments, scope);

		final helper = services.method(owner, exact.method);
		if (helper != null && services.isInline(helper)) {
			final inlineBody = exact.arguments.length == 0 ? services.inlineBody(exact.receiver, helper, scope) : null;
			if (inlineBody != null)
				return inlineBody;
		}
		final receiver = services.valueForExpectedType(exact.receiver, representation.getCarrierCppType(), scope);
		final arguments = [for (argument in exact.arguments) services.renderExpression(argument, scope)];
		return representation.instanceHelperCall(services.sanitizeIdentifier(exact.method), receiver, arguments);
	}
}
