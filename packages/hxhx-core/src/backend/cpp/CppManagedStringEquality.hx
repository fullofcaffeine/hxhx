package backend.cpp;

/** String equality preserves null separately from empty text and compares exact UTF-8 bytes. */
function supports(op:String, left:TyType, right:TyType):Bool
	return (op == "==" || op == "!=") && left.getSemanticKey() == "primitive:String" && right.getSemanticKey() == "primitive:String";

/** Operands have already completed in source order and remain rooted through this non-collecting comparison. */
function compute(op:String, left:String, right:String, destination:String, indent:String):Array<String> {
	if (op != "==" && op != "!=")
		throw "managed String comparison requires equality or inequality";
	final nullLeft = left + ".kind() == hxhx::managed::ValueKind::Null";
	final nullRight = right + ".kind() == hxhx::managed::ValueKind::Null";
	final equal = "((" + nullLeft + ") || (" + nullRight + ") ? (" + nullLeft + ") == (" + nullRight + ") : " + left + ".asString() == " + right
		+ ".asString())";
	return [
		indent + destination + ".set(hxhx::managed::Value::boolean(" + (op == "!=" ? "!" : "") + equal + "));"
	];
}
