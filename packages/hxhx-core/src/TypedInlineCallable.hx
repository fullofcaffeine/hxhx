import haxe.ds.StringMap;

/**
	Copy a callable boundary into an inline expansion. Its parameters receive fresh
	identities, while captured reads retain the surrounding expansion's bindings.
	Named functions also publish their fresh recursive binding in the enclosing scope.
	The caller owns type substitution and the new function control target.
 */
function copy(input:{
	source:TypedExpr,
	locals:StringMap<TyLocalBinding>,
	fresh:TyLocalBinding->TyLocalBinding,
	substitute:(TypedExpr, StringMap<TyLocalBinding>) -> TypedExpr,
	applyType:TyType->TyType,
	target:TyControlTarget
}):TypedExpr {
	final source = input.source;
	final facts = source.getSourceFunction();
	if (facts == null || source.getCatchUses().length != 0)
		throw "inline callable requires authored function facts without lowered catch bindings";
	final named = facts.getDeclaredName() != null;
	final locals = input.locals.copy();
	final bindings = [for (binding in source.getLocalBindings()) input.fresh(binding)];
	if (bindings.length != facts.getBindingNames().length)
		throw "inline callable lost its exact parameter bindings";
	for (index in 0...bindings.length)
		locals.set(source.getLocalBindings()[index].getIdentity().getCanonicalKey(), bindings[index]);
	if (named)
		input.locals.set(source.getLocalBindings()[0].getIdentity().getCanonicalKey(), bindings[0]);
	final parameters = named ? bindings.slice(1) : bindings;
	final original = facts.getSignature().getParameters();
	final callableType = input.applyType(source.getType());
	final signature = new HxLambdaSignature([
		for (index in 0...original.length)
			{
				typeHint: original[index].typeHint == null ? null : parameters[index].getType().getCanonicalDisplay(),
				isOptional: original[index].isOptional,
				isRest: original[index].isRest,
				hasDefault: original[index].hasDefault
			}
	],
		facts.getSignature().getReturnTypeHint() == null ? null : callableType.getFunctionReturn().getCanonicalDisplay());
	final copiedFacts = new HxSourceFunction({
		kind: switch facts.getKind() {
			case Named(_, inlineFlag): Named(bindings[0].getSourceName(), inlineFlag);
			case other: other;
		},
		placement: facts.getPlacement(),
		arguments: parameters.map(binding -> binding.getSourceName()),
		signature: signature,
		generics: facts.getGenerics()
	});
	final children = source.getExpressions();
	final defaults = [for (value in children.slice(1)) input.substitute(value, locals)];
	final body = input.substitute(children[0], locals);
	return TypedExpr.sourceFunctionExpr(copiedFacts, body, defaults, callableType, source.getPosition(), bindings).withControlTarget(input.target);
}
