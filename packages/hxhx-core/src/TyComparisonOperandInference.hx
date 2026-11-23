/**
	Retain constraints from `==`, `!=`, `<`, `<=`, `>`, and `>=` in omitted inputs.

	As in Haxe 4.3.7, an unresolved operand takes the type of a known peer (`value == 1` gives
	`value : Int`, `value < 1.5` gives Float, `value != "x"` gives String), and two unresolved
	operands of an ordering become Int. An equality with `null` binds the operand to `Null<fresh>`.
	Two unresolved operands of an equality, a Dynamic peer, and a peer with unresolved parts leave
	the operand unresolved. The caller first
	checks declared abstract operators. Aliases share the function's inference variables, so
	publication observes the same solved input.
**/
function constrain(input:{
	left:HxExpr,
	right:HxExpr,
	leftType:TyType,
	rightType:TyType,
	ordering:Bool,
	scope:TyFunctionEnv,
	index:TyperIndex,
	filePath:String,
	position:HxPos
}):Void {
	// `value == null` binds an unsolved `value` to `Null<fresh>`, as upstream does; the inner type
	// comes from later evidence.
	if (input.left.match(ENull) || input.right.match(ENull)) {
		final leftNull = input.left.match(ENull);
		if (!input.ordering && (leftNull ? input.rightType : input.leftType).isUnknown())
			input.scope.getInference().bindNullComparison(leftNull ? input.right : input.left, input.scope);
		return;
	}
	final inference = input.scope.getInference();
	final leftUnknown = input.leftType.isOpenValue() && inference.canReceiveContext(input.left, input.scope);
	final rightUnknown = input.rightType.isOpenValue() && inference.canReceiveContext(input.right, input.scope);
	function knownPeer(type:TyType):Null<TyType> {
		return type.isOpenValue() || type.hasUnknownComponent() || type.unwrapNull().isDynamic() ? null : type;
	}
	final sources = new Array<HxExpr>();
	final expected = new Array<TyType>();
	if (leftUnknown && rightUnknown) {
		if (input.ordering) {
			sources.push(input.left);
			sources.push(input.right);
			expected.push(TyType.fromHintText("Int"));
			expected.push(TyType.fromHintText("Int"));
		}
	} else if (leftUnknown) {
		final peer = knownPeer(input.rightType);
		if (peer != null) {
			sources.push(input.left);
			expected.push(peer);
		}
	} else if (rightUnknown) {
		final peer = knownPeer(input.leftType);
		if (peer != null) {
			sources.push(input.right);
			expected.push(peer);
		}
	}
	if (sources.length != 0 && !inference.constrain(sources, expected, input.scope, input.index))
		throw new TyperError(input.filePath, input.position, "comparison operands conflict with their inferred types");
}
