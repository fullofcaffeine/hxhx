/** Statements inserted before a loop and at the start of each iteration. */
typedef TypedRepeatedConditionPlan = {
	final prefix:Array<TypedExpr>;
	final head:Array<TypedExpr>;
}

/**
	Keep statement-valued loop conditions on every condition edge, including continue.
	A body-first loop skips only its first check. The caller allocates its flag per
	loop activation and keeps the authored loop destination; no closure or jump
	retargeting is needed. Each condition executes inside its original lexical scope.
 */
class TypedRepeatedCondition {
	public static function build(input:{
		steps:Array<TypedExpr>,
		value:Null<TypedExpr>,
		completes:Bool,
		kind:HxWhileKind,
		target:TyControlTarget,
		first:Null<TyLocalBinding>,
		position:Null<HxPos>
	}):TypedRepeatedConditionPlan {
		final position = input.position;
		final voidType = TyType.fromHintText("Void");
		final checks = input.steps.copy();
		if (input.completes) {
			if (input.value == null)
				throw "repeated condition requires its final value";
			checks.push(TypedExpr.controlBranch(input.value, TypedExpr.controlRegion([], voidType, position),
				TypedExpr.controlRegion([TypedExpr.breakExpr(position).withControlTarget(input.target)], TyType.noNormalCompletion(), position), voidType,
				position));
		}
		final checkRegion = TypedExpr.controlRegion(checks, input.completes ? voidType : TyType.noNormalCompletion(), position);
		if (input.kind == Normal)
			return {prefix: [], head: [checkRegion]};
		final first = input.first;
		if (first == null)
			throw "body-first repeated condition requires a fresh first-iteration binding";
		final boolType = TyType.fromHintText("Bool");
		final read = TypedExpr.localRead(first.getSourceName(), boolType, position, first);
		final declaration = TypedExpr.variableDeclarations([
			TypedExpr.variableDeclaration(first.getSourceName(), "Bool", TypedExpr.boolLiteral(true, boolType, position), false, false, boolType, position,
				first)
		], voidType, position);
		final skip = TypedExpr.controlRegion([
			TypedExpr.assign(read, TypedExpr.boolLiteral(false, boolType, position), boolType, position)
		], voidType, position);
		return {prefix: [declaration], head: [TypedExpr.controlBranch(read, skip, checkRegion, voidType, position)]};
	}
}
