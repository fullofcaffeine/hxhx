/**
	Integer arithmetic consumes nullable operands but produces an Int result.
	Call this only for addition, subtraction, multiplication, and remainder after
	checking abstract operators. Operand types remain unchanged so each target can
	apply its own null conversion. Division and Float policy are separate contracts.
 */
function result(left:TyType, right:TyType):Null<TyType> {
	if (!left.isNullable() && !right.isNullable())
		return null;
	final integer = TyType.fromHintText("Int");
	return left.unwrapNull().getSemanticKey() == integer.getSemanticKey()
		&& right.unwrapNull().getSemanticKey() == integer.getSemanticKey() ? integer : null;
}
