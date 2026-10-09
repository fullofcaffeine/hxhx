package backend.cpp;

/** Select String addition by exact operand types, without treating unsupported conversions as integer addition. */
function selects(op:String, left:TyType, right:TyType):Bool
	return op == "+" && (left.getSemanticKey() == "primitive:String" || right.getSemanticKey() == "primitive:String");

/** Require conversion contracts for both operands before emitting any operation. */
function resultType(left:TyType, right:TyType):TyType {
	if (!selects("+", left, right))
		throw "managed concatenation requires an exact String operand";
	// Dynamic retains its runtime tag until the shared formatter selects an
	// existing conversion. This does not make unsupported object/Float tags printable.
	if (!left.isDynamic())
		CppManagedStringConversion.requireType(left);
	if (!right.isDynamic())
		CppManagedStringConversion.requireType(right);
	return TyType.fromHintText("String");
}

/** Both rooted operands have completed in source order. Native C++ converts null Strings to text, including two nulls. */
function compute(leftType:TyType, rightType:TyType, left:String, right:String, destination:String, indent:String):Array<String> {
	resultType(leftType, rightType);
	final lines = [indent + "{"];
	for (line in CppManagedStringConversion.render(leftType, left, "hxhx_concat_left_bytes"))
		lines.push(indent + "  " + line);
	for (line in CppManagedStringConversion.render(rightType, right, "hxhx_concat_right_bytes"))
		lines.push(indent + "  " + line);
	lines.push(indent + "  " + destination + ".set(hxhx::managed::Value::string(hxhx_concat_left_bytes + hxhx_concat_right_bytes));");
	lines.push(indent + "}");
	return lines;
}
