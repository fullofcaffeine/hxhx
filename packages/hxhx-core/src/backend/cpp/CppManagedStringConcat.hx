package backend.cpp;

/** Select String addition by exact operand types, without treating unsupported conversions as integer addition. */
function selects(op:String, left:TyType, right:TyType):Bool
	return op == "+" && (left.getSemanticKey() == "primitive:String" || right.getSemanticKey() == "primitive:String");

/** Require conversion contracts for both operands before emitting any operation. */
function resultType(left:TyType, right:TyType):TyType {
	if (!selects("+", left, right))
		throw "managed concatenation requires an exact String operand";
	CppManagedStringConversion.requireType(left);
	CppManagedStringConversion.requireType(right);
	return TyType.fromHintText("String");
}

/** Both rooted operands have completed in source order. Native C++ converts null Strings to text, including two nulls. */
function compute(leftType:TyType, rightType:TyType, left:String, right:String, destination:String, indent:String):Array<String> {
	resultType(leftType, rightType);
	final lines = [];

	lines.push(indent + destination + ".set(hxhx::managed::Value::string(" + CppManagedStringConversion.format(leftType, left) + " + "
		+ CppManagedStringConversion.format(rightType, right) + "));");
	return lines;
}
