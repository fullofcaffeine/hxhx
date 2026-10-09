package backend.js;

/**
	Read the single JavaScript enum layout for target-owned formatting and matching.
	The real Type provider consumes the same registry directly. These small helpers
	also serve fixtures that intentionally emit no standard-library provider bodies.
	They never interpret the retired parser-produced object layout.
 */
function emit(writer:JsWriter):Void {
	writer.writeln("function $hx_enum_constructor(value) {");
	writer.pushIndent();
	writer.writeln("var owner = value == null ? null : $hxEnums[value.__enum__];");
	writer.writeln("return owner == null ? null : owner.__constructs__[value._hx_index];");
	writer.popIndent();
	writer.writeln("}");
	writer.writeln("function $hx_enum_name(value) {");
	writer.pushIndent();
	writer.writeln("var constructor = $hx_enum_constructor(value);");
	writer.writeln("return constructor == null ? null : constructor._hx_name;");
	writer.popIndent();
	writer.writeln("}");
	writer.writeln("function $hx_enum_parameters(value) {");
	writer.pushIndent();
	writer.writeln("var constructor = $hx_enum_constructor(value);");
	writer.writeln("var names = constructor == null ? null : constructor.__params__;");
	writer.writeln("return names == null ? [] : names.map(function(name) { return value[name]; });");
	writer.popIndent();
	writer.writeln("}");
}
