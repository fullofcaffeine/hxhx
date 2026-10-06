package backend.cpp;

/**
	Compare allocation identity after the caller selects a reference representation.
	Both operands are rooted and evaluated in source order. Null has no allocation;
	values with another runtime representation fail the checked managed accessor.
 */
function compute(op:String, left:String, right:String, destination:String, indent:String):Array<String> {
	if (op != "==" && op != "!=")
		throw "managed reference comparison requires equality or inequality";
	final a = "(" + left + ".kind() == hxhx::managed::ValueKind::Null ? hxhx::managed::ErasedRef{} : " + left + ".asManaged())";
	final b = "(" + right + ".kind() == hxhx::managed::ValueKind::Null ? hxhx::managed::ErasedRef{} : " + right + ".asManaged())";
	final equal = "(" + a + " == " + b + ")";
	return [
		indent + destination + ".set(hxhx::managed::Value::boolean(" + (op == "!=" ? "!" : "") + equal + "));"
	];
}

/**
	One operand has a checked class-reference type; the other retains an opaque value.
	Primitives and declaration handles cannot equal that instance. Test tags before
	reading allocations, preserve two nulls, and compare references by identity.
	This is not general equality between two opaque values or scalar coercion.
 */
function computeOpaqueInstance(op:String, left:String, right:String, destination:String, indent:String):Array<String> {
	if (op != "==" && op != "!=")
		throw "managed opaque instance comparison requires equality or inequality";
	final equal = "(" + left + ".kind() == " + right + ".kind() && (" + left + ".kind() == hxhx::managed::ValueKind::Null || (" + left
		+ ".kind() == hxhx::managed::ValueKind::Managed && " + left + ".asManaged() == " + right + ".asManaged())))";
	return [
		indent + destination + ".set(hxhx::managed::Value::boolean(" + (op == "!=" ? "!" : "") + equal + "));"
	];
}
