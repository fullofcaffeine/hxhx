package backend.js;

import TypedExactStaticCallSource.TypedExactStaticCall;

/**
	Emit JavaScript syntax from its selected target API declaration. Aliased calls
	keep that owner; unrelated methods with the same short name stay ordinary.
	Operands appear once in their native operator positions. This preserves typeof's
	undefined-name behavior and delete's ordered receiver/key evaluation and Boolean result.
 */
function emit(call:TypedExactStaticCall, operand:HxExpr->String, inlineCode:Array<HxExpr>->String):Null<String> {
	if (call.owner != "js.Syntax")
		return null;
	if (call.method == "code")
		return inlineCode(call.arguments);
	if (call.method == "delete") {
		if (call.arguments.length != 2 || call.resultType != "Bool")
			throw "JavaScript delete requires its selected two-argument Bool contract";
		return "(delete (" + operand(call.arguments[0]) + ")[" + operand(call.arguments[1]) + "])";
	}
	if (call.method == "construct") {
		if (call.arguments.length == 0)
			throw "JavaScript construct requires its selected constructor operand";
		// The API's literal-string overload names native syntax. Every other
		// operand is a runtime constructor expression, evaluated once before
		// its arguments. Parentheses keep calls and member accesses grouped.
		final constructor = switch call.arguments[0] {
			case EString(name): name;
			case value: operand(value);
		};
		return "new (" + constructor + ")(" + call.arguments.slice(1).map(operand).join(", ") + ")";
	}
	if (call.method != "typeof")
		return null;
	if (call.arguments.length != 1 || call.resultType != "String")
		throw "JavaScript typeof requires its selected one-argument String contract";
	return "(typeof (" + operand(call.arguments[0]) + "))";
}
