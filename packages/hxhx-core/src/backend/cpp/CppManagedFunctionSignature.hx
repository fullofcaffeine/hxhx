package backend.cpp;

/**
	Derive the same named-function transport for both callers and entry emission.
	Body types supply resolved values; the exact declaration supplies omission,
	rest, name, and metadata facts. Dropping omission would turn boxed optional
	scalars into direct native operands and disagree with the callee's parameters.
 */
function resolve(projection:TypedBackendFunctionProjection, substitute:TyType->TyType):TyType {
	final declaration = projection.requireSemanticDeclaration();
	final signature = declaration.getSignature();
	return TyCallableSignature.fromDeclaration(declaration, new TyFunSig(signature.getName(), signature.getIsStatic(), signature.getArgNames(), [
		for (parameter in projection.getParameters())
			substitute(parameter.getBinding().getType())
	], signature.getArgOptional(),
		signature.getArgRest(), substitute(projection.getReturnType()), signature.getPos())).getFunctionType();
}
