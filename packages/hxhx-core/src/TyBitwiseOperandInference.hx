/**
	Retain Int constraints from builtin bitwise operations in omitted inputs.
	The caller first checks declared abstract operators. This helper only constrains
	unresolved operands beside Int, Dynamic or another unresolved operand; written
	types and other operator families keep their existing owners. Aliases share the
	function's inference variables, so publication observes the same solved input.
 */
function constrain(input:{
	sources:Array<HxExpr>,
	types:Array<TyType>,
	scope:TyFunctionEnv,
	index:TyperIndex,
	filePath:String,
	position:HxPos
}):Void {
	if (input.sources.length != 2 || input.types.length != 2)
		throw "bitwise operand inference requires two checked operands";
	for (type in input.types)
		if (!type.isUnknown() && !type.isDynamic() && type.unwrapNull().getSemanticKey() != "primitive:Int")
			return;
	final inference = input.scope.getInference();
	final sources = [
		for (index in 0...2)
			if (input.types[index].isUnknown() && inference.canReceiveContext(input.sources[index], input.scope)) input.sources[index]
	];
	if (sources.length != 0 && !inference.constrain(sources, sources.map(_ -> TyType.fromHintText("Int")), input.scope, input.index))
		throw new TyperError(input.filePath, input.position, "bitwise operands conflict with their inferred Int inputs");
}
