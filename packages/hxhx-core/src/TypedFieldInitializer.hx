/**
	One declared field paired with its target-neutral typed initializer.

	Field initializers execute outside ordinary function bodies, but they can still
	read constants, call functions, and use types from other modules. Keeping the
	typed expression on `TypedClass` lets compiler analyses inspect those real
	resolved relationships instead of searching initializer source text.
**/
class TypedFieldInitializer {
	final field:TyFieldInfo;
	final expression:TypedExpr;

	public function new(field:TyFieldInfo, expression:TypedExpr) {
		if (field == null || expression == null)
			throw "typed field initializer requires field information and an expression";
		this.field = field;
		this.expression = expression;
	}

	public function getField():TyFieldInfo
		return field;

	public function getExpression():TypedExpr
		return expression;
}
