package backend.js;

/** Consume the original projected occurrence before rendering its operand exactly once. */
function emit(expression:HxExpr, scope:JsEmitScope):String {
	if (scope == null || scope.runtimeTypes == null)
		throw "JavaScript runtime type operand requires its exact executable scope";
	final occurrence = scope.runtimeTypes.requireOccurrence(expression);
	final reference = scope.runtimeTypes.reference(occurrence.getTarget());
	final value = occurrence.getValue();
	if (value == null)
		return reference;
	final operand = JsExprEmitter.emit(value, scope);
	return switch occurrence.getTarget().getKind() {
		// Haxe's JavaScript Array check uses prototype identity, including its
		// cross-realm behavior. Interface metadata cannot confer core membership.
		case ArrayCore: "((" + operand + ") instanceof " + reference + ")";
		// A String instance test checks the primitive representation. Boxed
		// strings and replacement constructors do not change this contract.
		case StringCore: "(typeof (" + operand + ") === \"string\")";
		case _: "__hx_is_nominal(" + operand + ", " + reference + ")";
	};
}

/**
	Read the native constructor at the occurrence, after any left-operand effects.
	The accessor's dollar sign cannot occur in a mangled source local. Its outer
	scope keeps an Array-named parameter from replacing the type operand.
 */
function arrayReference():String {
	return "$hx_array_type()";
}

/** String class values observe the host constructor; instance checks use primitive representation instead. */
function stringReference():String {
	return "$hx_string_type()";
}

/**
	Nominal objects use native prototype identity and the typed interface closure.
	Class objects and enum values do not gain membership from names or string tags.
	The evaluated operand is a function argument, so effects occur exactly once.
 */
function emitDefinition(writer:JsWriter):Void {
	writer.writeln("function $hx_array_type() { return Array; }");
	writer.writeln("function $hx_string_type() { return String; }");
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
