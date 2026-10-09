package backend.cpp;

/**
	Select equality only when both operands use erased storage after abstract lowering.
	A statically known operand can select a different native comparison contract.
	Those existing operations keep their owners; this module does not widen them.
 */
function selects(op:String, left:TyType, right:TyType, casts:Null<CppManagedCastPlan>):Bool {
	if (op != "==" && op != "!=")
		return false;
	function erased(type:TyType):Bool {
		var represented = casts == null ? type : casts.representationType(type);
		while (represented.getNullableInner() != null)
			represented = represented.getNullableInner();
		return represented.isDynamic();
	}
	return erased(left) && erased(right);
}

/** Both operands already occupy roots after once-only, left-to-right evaluation. */
function compute(op:String, left:String, right:String, destination:String, indent:String):Array<String> {
	if (op != "==" && op != "!=")
		throw "managed Dynamic comparison requires equality or inequality";
	return [indent
		+ destination
		+ ".set(hxhx::managed::Value::boolean(hxhx::managed::dynamicEquality("
		+ left
		+ ", "
		+ right
		+ ", "
		+ (op == "!=" ? "true" : "false")
		+ ")));"];
}
