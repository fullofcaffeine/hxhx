package backend.cpp;

/** A literal null selects a tag test, never object equality or numeric coercion. */
function selects(op:String, left:TyType, right:TyType):Bool
	return (op == '==' || op == '!=') && (left.isNullLiteral() || right.isNullLiteral());

/** Both values must have a representation that preserves null as its own tag. */
function requireTypes(op:String, left:TyType, right:TyType, ?casts:CppManagedCastPlan):Void {
	if (!selects(op, left, right)
		|| !CppManagedValueTransfer.retainsNull(left, casts)
		|| !CppManagedValueTransfer.retainsNull(right, casts))
		throw 'managed null comparison requires null-preserving value storage';
}

/** Operands have completed in source order; reading their tags never allocates or compares payloads. */
function compute(op:String, left:String, right:String, destination:String, indent:String):Array<String> {
	if (op != '==' && op != '!=')
		throw 'managed null comparison requires equality or inequality';
	return [indent
		+ destination
		+ '.set(hxhx::managed::Value::boolean(('
		+ left
		+ '.kind() == hxhx::managed::ValueKind::Null) '
		+ op
		+ ' ('
		+ right
		+ '.kind() == hxhx::managed::ValueKind::Null)));'];
}
