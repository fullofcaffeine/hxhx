package backend.js;

import TypedExactStaticCallSource.TypedExactStaticCall;

/**
	Emit JavaScript syntax from its selected target API declaration. Aliased calls
	keep that owner; unrelated methods with the same short name stay ordinary.
	The operand appears once, directly beneath typeof, so an undeclared JavaScript
	identifier retains the operator's special behavior instead of becoming a call argument.
 */
function emit(call:TypedExactStaticCall, operand:HxExpr->String, inlineCode:Array<HxExpr>->String):Null<String> {
	if (call.owner != "js.Syntax")
		return null;
	if (call.method == "code")
		return inlineCode(call.arguments);
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
