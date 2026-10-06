/** Copy parameter types from a checked call alignment without emitting omission placeholders. */
function resolve(call:TypedExpr):Array<Null<TyType>> {
	final children = call.getExpressions();
	final result:Array<Null<TyType>> = [for (_ in 1...children.length) null];
	final named = call.getNamedArguments();
	if (call.getTag() != Call || children.length == 0 || (call.getExtensionProvider() != null && named == null))
		return result;
	final callable = named == null ? children[0].getType() : named.getArguments().getFunctionType();
	if (!callable.isFunction())
		return result;
	final signature = TyCallableSignature.fromFunctionValue(callable);
	final binding = named == null ? call.getArgumentBinding() : named.getArguments();
	final arguments = children.slice(1);
	final kinds = TypedExpr.operandKinds(arguments);
	final types = TypedExpr.operandTypes(arguments, kinds);
	call.assertArgumentBinding();
	final alignment = binding == null ? TyCallValidation.validate(signature, types, kinds,
		Unchecked) : TyCallAlignment.TyCallAlignmentResult.Aligned(binding.getSlots());
	switch alignment {
		case Rejected(_):
		case Aligned(slots):
			final parameters = signature.getParameters();
			for (index in 0...slots.length)
				switch slots[index] {
					case Supplied(source): result[source] = parameters[index].type;
					case RestElements(sources): for (source in sources)
							result[source] = parameters[index].type;
					case Omitted | RestSpread(_):
				}
	}
	return result;
}
