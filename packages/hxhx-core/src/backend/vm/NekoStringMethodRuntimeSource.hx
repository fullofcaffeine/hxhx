package backend.vm;

/**
	Provides instance methods for values stored as native Neko strings.

	The VM string-splitting primitive returns a linked sequence of native arrays.
	Build contiguous backing storage in two passes, then give that fresh storage
	to the retained Haxe Array factory. The provider owns the public Array object
	and its mutations; the native helper never returns raw storage as an Array.
	Each returned method closes over the selected string. Ordinary object fields
	continue through the separate object-field dispatcher.
**/
class NekoStringMethodRuntimeSource {
	/** Read the factory through the shared table when called, after all program chunks load. */
	public static function render(out:Array<String>, arrayFactory:Null<String>):Void {
		if (arrayFactory == null) {
			out.push("var __hxhx_string_method = function(receiver, field) { return null; }");
			return;
		}
		out.push("var __hxhx_native_string_split = $loader.loadprim(\"std@string_split\", 2);");
		out.push("var __hxhx_string_method = function(receiver, field) {");
		out.push("  if (field != \"split\") return null;");
		out.push("  return function(separator) {");
		out.push("    var pieces = __hxhx_native_string_split(receiver, separator);");
		out.push("    if (pieces == null) return " + arrayFactory + "($array(\"\"), 1);");
		out.push("    var count = 0;");
		out.push("    var cursor = pieces;");
		out.push("    while (cursor != null) { count = count + 1; cursor = cursor[1]; }");
		out.push("    var result = $amake(count);");
		out.push("    var index = 0;");
		out.push("    cursor = pieces;");
		out.push("    while (cursor != null) { result[index] = cursor[0]; index = index + 1; cursor = cursor[1]; }");
		out.push("    return " + arrayFactory + "(result, count);");
		out.push("  };");
		out.push("}");
	}
}
