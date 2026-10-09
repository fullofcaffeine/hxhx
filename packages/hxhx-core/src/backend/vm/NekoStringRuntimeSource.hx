package backend.vm;

/**
	Emits value-to-string conversion and array joining for the native Neko runtime.

	Array elements are converted once in order. Nested arrays use the same
	conversion, and object values retain the existing toString call contract.
	Joining first measures the converted pieces, then fills one native string
	buffer instead of repeatedly copying the growing prefix. A shared function
	table supports mutual calls: Neko closures capture local binding values, so a
	forward local initialized to null would stay null inside an earlier closure.

	Static class discovery keeps these helpers available to the bootstrap compiler.
**/
class NekoStringRuntimeSource {
	public static function render(out:Array<String>):Void {
		out.push("var __hxhx_string_runtime = $new(null);");
		out.push("__hxhx_string_runtime.string = function(value) {");
		out.push("  if (value == null) return \"null\";");
		out.push("  if ($typeof(value) == $tarray) return \"[\" + __hxhx_string_runtime.join(value, \",\") + \"]\";");
		out.push("  if ($typeof(value) == $tobject && value.toString != null) return value.toString();");
		out.push("  return \"\" + value;");
		out.push("}");
		out.push("");
		out.push("__hxhx_string_runtime.join = function(values, separator) {");
		out.push("  var count = $asize(values);");
		out.push("  if (count == 0) return \"\";");
		out.push("  var sep = __hxhx_string_runtime.string(separator);");
		out.push("  var sepLength = $ssize(sep);");
		out.push("  var parts = $amake(count);");
		out.push("  var total = 0;");
		out.push("  var i = 0;");
		out.push("  while (i < count) {");
		out.push("    var part = __hxhx_string_runtime.string(values[i]);");
		out.push("    parts[i] = part;");
		out.push("    total = total + $ssize(part);");
		out.push("    if (i > 0) total = total + sepLength;");
		out.push("    i = i + 1;");
		out.push("  }");
		out.push("  var result = $smake(total);");
		out.push("  var offset = 0;");
		out.push("  i = 0;");
		out.push("  while (i < count) {");
		out.push("    if (i > 0) { $sblit(result, offset, sep, 0, sepLength); offset = offset + sepLength; }");
		out.push("    var part = parts[i];");
		out.push("    var length = $ssize(part);");
		out.push("    $sblit(result, offset, part, 0, length);");
		out.push("    offset = offset + length;");
		out.push("    i = i + 1;");
		out.push("  }");
		out.push("  return result;");
		out.push("}");
		out.push("var __hxhx_string = __hxhx_string_runtime.string;");
		out.push("var __hxhx_array_join = __hxhx_string_runtime.join;");
		out.push("");
	}
}
