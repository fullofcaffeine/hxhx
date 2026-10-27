/**
	Integer arithmetic consumes nullable operands but produces an Int result.
	Call this only for addition, subtraction, multiplication, and remainder after
	checking abstract operators. Operand types remain unchanged so each target can
	apply its own null conversion. Division and Float policy are separate contracts.
 */
function result(left:TyType, right:TyType):Null<TyType> {
	if (!left.isNullable() && !right.isNullable())
		return null;
	return isInteger(left) && isInteger(right) ? TyType.fromHintText("Int") : null;
}

/** Inspect real nullable wrappers without changing the source type or accepting an abstract carrier. */
function isInteger(type:TyType):Bool {
	if (type == null)
		return false;
	while (type.isNullable())
		type = type.getNullableInner();
	return type.getSemanticKey() == "primitive:Int";
}

/** An Int result can fit a nullable integer place without an executable Haxe conversion. */
function admits(expected:TyType, actual:TyType):Bool {
	return expected.getSemanticKey() == actual.getSemanticKey() || (actual.getSemanticKey() == "primitive:Int" && isInteger(expected));
}
