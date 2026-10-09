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
	if (call.method != "typeof")
		return null;
	if (call.arguments.length != 1 || call.resultType != "String")
		throw "JavaScript typeof requires its selected one-argument String contract";
	return "(typeof (" + operand(call.arguments[0]) + "))";
}
