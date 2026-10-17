/**
	Addition constrains omitted input types before a method's checked signature is published.
	An unresolved operand follows its primitive peer; two unresolved operands select Int,
	as in Haxe 4.3.7. Written types, Dynamic values, and abstract operators keep their own rules.
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
	final leftUnknown = input.leftType.isUnknown() && inference.canReceiveContext(input.left, input.scope);
	final rightUnknown = input.rightType.isUnknown() && inference.canReceiveContext(input.right, input.scope);
	function primitivePeer(type:TyType):Null<TyType> {
		final concrete = type.unwrapNull();
		return switch concrete.getSemanticKey() {
			case "primitive:Int" | "primitive:Float" | "primitive:String": concrete;
			case _: null;
		};
	}
	final expected = leftUnknown
		&& rightUnknown ? TyType.fromHintText("Int") : leftUnknown ? primitivePeer(input.rightType) : rightUnknown ? primitivePeer(input.leftType) : null;
	if (expected != null) {
		final sources = new Array<HxExpr>();
		if (leftUnknown)
			sources.push(input.left);
		if (rightUnknown)
			sources.push(input.right);
		if (!inference.constrain(sources, sources.map(_ -> expected), input.scope, input.index))
			throw new TyperError(input.filePath, input.position, "addition operands conflict with their inferred types");
	}
	return {
		left: inference.expressionType(input.left, input.leftType, input.scope),
		right: inference.expressionType(input.right, input.rightType, input.scope)
	};
}
