package backend.js;

/**
	Adapt the native JavaScript integer parser to Haxe's nullable result.
	The primitive receives an already evaluated String, preserves decimal/hex
	prefix handling, and maps only the native invalid-result sentinel to null.
	It does not truncate large JavaScript results or change Float operations.
 */
function emitDefinition(writer:JsWriter):Void {
	writer.writeln("function $hx_parse_int(value) {");
	writer.pushIndent();
	writer.writeln("var parsed = parseInt(value);");
	writer.writeln("return parsed !== parsed ? null : parsed;");
	writer.popIndent();
	writer.writeln("}");
}

/** Both ordinary Std calls and the existing supported extractor use one conversion. */
function call(value:String):String {
	return "$hx_parse_int(" + value + ")";
}
