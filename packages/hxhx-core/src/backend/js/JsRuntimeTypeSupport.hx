package backend.js;

/** Consume the original projected occurrence before rendering its operand exactly once. */
function emit(expression:HxExpr, scope:JsEmitScope):String {
	if (scope == null || scope.runtimeTypes == null)
		throw "JavaScript runtime type operand requires its exact executable scope";
	final occurrence = scope.runtimeTypes.requireOccurrence(expression);
	final reference = scope.runtimeTypes.reference(occurrence.getTarget());
	final value = occurrence.getValue();
	return value == null ? reference : "__hx_is_nominal(" + JsExprEmitter.emit(value, scope) + ", " + reference + ")";
}

/**
	Nominal objects use native prototype identity and the typed interface closure.
	Class objects and enum values do not gain membership from names or string tags.
	The evaluated operand is a function argument, so effects occur exactly once.
 */
function emitDefinition(writer:JsWriter):Void {
	writer.writeln("function __hx_is_nominal(value, type) {");
	writer.pushIndent();
	writer.writeln("if (value == null || typeof type !== \"function\") return false;");
	writer.writeln("if (value instanceof type) return true;");
	writer.writeln("var owner = value.__class__;");
	writer.writeln("var interfaces = owner == null ? null : owner.__hx_interfaces;");
	writer.writeln("return interfaces != null && interfaces.indexOf(type) >= 0;");
	writer.popIndent();
	writer.writeln("}");
}
