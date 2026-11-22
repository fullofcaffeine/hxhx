/**
	Retain Int constraints from `-`, `*`, `/`, and `%` in omitted inputs.

	As in Haxe 4.3.7, an unresolved operand becomes Int when its peer is Int, Float, Dynamic,
	or another unresolved operand. A Float peer does not make it Float: `value - 1.5` gives
	`value : Int` and a Float result. The caller first checks declared abstract operators and
	abstract `to` views; written types and other peers keep their own rules. Aliases share the
	function's inference variables, so publication observes the same solved input.
**/
function constrain(input:{
	left:HxExpr,
	right:HxExpr,
	leftType:TyType,
	rightType:TyType,
	scope:TyFunctionEnv,
	index:TyperIndex,
	filePath:String,
	position:HxPos
}):{left:TyType, right:TyType} {
	final inference = input.scope.getInference();
	final leftUnknown = input.leftType.isOpenValue() && inference.canReceiveContext(input.left, input.scope);
	final rightUnknown = input.rightType.isOpenValue() && inference.canReceiveContext(input.right, input.scope);
	function acceptsIntPeer(type:TyType):Bool {
		final concrete = type.unwrapNull();
		return type.isOpenValue() || concrete.isDynamic() || concrete.isNumeric();
	}
	final sources = new Array<HxExpr>();
	if (leftUnknown && acceptsIntPeer(input.rightType))
		sources.push(input.left);
	if (rightUnknown && acceptsIntPeer(input.leftType))
		sources.push(input.right);
	if (sources.length != 0 && !inference.constrain(sources, sources.map(_ -> TyType.fromHintText("Int")), input.scope, input.index))
		throw new TyperError(input.filePath, input.position, "arithmetic operands conflict with their inferred Int inputs");
	return {
		left: inference.expressionType(input.left, input.leftType, input.scope),
		right: inference.expressionType(input.right, input.rightType, input.scope)
	};
}
