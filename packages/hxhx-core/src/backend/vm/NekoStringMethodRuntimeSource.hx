package backend.vm;

/**
	Provides instance methods for values stored as native Neko strings.

	The VM string-splitting primitive returns a linked sequence of native arrays.
	Convert that sequence to the target's contiguous array representation in two
	passes, so building the result does not repeatedly copy its growing prefix.
	Each returned method closes over the selected string. Ordinary object fields
	continue through the separate object-field dispatcher.
**/
class NekoStringMethodRuntimeSource {
	public static function render(out:Array<String>):Void {
		out.push("var __hxhx_native_string_split = $loader.loadprim(\"std@string_split\", 2);");
		out.push("var __hxhx_string_method = function(receiver, field) {");
		out.push("  if (field != \"split\") return null;");
		out.push("  return function(separator) {");
		out.push("    var pieces = __hxhx_native_string_split(receiver, separator);");
		out.push("    if (pieces == null) return $array(\"\");");
		out.push("    var count = 0;");
		out.push("    var cursor = pieces;");
		out.push("    while (cursor != null) { count = count + 1; cursor = cursor[1]; }");
		out.push("    var result = $amake(count);");
		out.push("    var index = 0;");
		out.push("    cursor = pieces;");
		out.push("    while (cursor != null) { result[index] = cursor[0]; index = index + 1; cursor = cursor[1]; }");
		out.push("    return result;");
		out.push("  };");
		out.push("}");
	}
}
