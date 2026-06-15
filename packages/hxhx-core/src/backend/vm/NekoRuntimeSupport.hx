package backend.vm;

/**
	Emits the small native Neko runtime prelude used by the Stage3 Neko backend.

	Why
	- `NekoTargetCore` should describe Haxe-to-Neko lowering decisions, not keep
	  growing with target runtime string blocks.
	- The Neko Full1 gate currently needs a compact Map/array support surface to
	  compile and execute upstream unit-runner code without leaking Haxe syntax
	  such as map-literal arrows into Neko source.

	What
	- Adds target-owned helpers for string conversion, array push/indexOf, and a
	  minimal Map-like object with set/get/exists/remove/keys/iterator/toString.

	How
	- Keeps the support prelude in one module so future extraction to a template
	  or standalone runtime file is a mechanical move instead of more emitter
	  growth.
**/
class NekoRuntimeSupport {
	public static function render(out:Array<String>):Void {
		out.push("var __hxhx_string = function(value) {");
		out.push("  if (value == null) return \"null\";");
		out.push("  if ($typeof(value) == $tobject && value.toString != null) return value.toString();");
		out.push("  return \"\" + value;");
		out.push("}");
		out.push("");
		out.push("var __hxhx_array_indexOf = function(a, value) {");
		out.push("  var i = 0;");
		out.push("  var len = $asize(a);");
		out.push("  while (i < len) {");
		out.push("    if (a[i] == value) return i;");
		out.push("    i = i + 1;");
		out.push("  }");
		out.push("  return -1;");
		out.push("}");
		out.push("");
		out.push("var __hxhx_array_push = function(a, value) {");
		out.push("  a[$asize(a)] = value;");
		out.push("  return a;");
		out.push("}");
		out.push("");
		out.push("var __hxhx_map_new = function(kind) {");
		out.push("  var map = $new(null);");
		out.push("  map.__hx_ctor = kind;");
		out.push("  map.__hx_params = $array();");
		out.push("  map.__hxhx_pairs = $array();");
		out.push("  map.__hxhx_find = function(key) {");
		out.push("    var i = 0;");
		out.push("    while (i < $asize(map.__hxhx_pairs)) {");
		out.push("      if (map.__hxhx_pairs[i][0] == key) return i;");
		out.push("      i = i + 1;");
		out.push("    }");
		out.push("    return -1;");
		out.push("  };");
		out.push("  map.set = function(key, value) {");
		out.push("    var i = map.__hxhx_find(key);");
		out.push("    if (i < 0) map.__hxhx_pairs[$asize(map.__hxhx_pairs)] = $array(key, value);");
		out.push("    else map.__hxhx_pairs[i][1] = value;");
		out.push("  };");
		out.push("  map.get = function(key) {");
		out.push("    var i = map.__hxhx_find(key);");
		out.push("    return if (i < 0) null else map.__hxhx_pairs[i][1];");
		out.push("  };");
		out.push("  map.exists = function(key) { return map.__hxhx_find(key) >= 0; };");
		out.push("  map.remove = function(key) {");
		out.push("    var i = map.__hxhx_find(key);");
		out.push("    if (i < 0) return false;");
		out.push("    var last = $asize(map.__hxhx_pairs) - 1;");
		out.push("    map.__hxhx_pairs[i] = map.__hxhx_pairs[last];");
		out.push("    $asize(map.__hxhx_pairs, last);");
		out.push("    return true;");
		out.push("  };");
		out.push("  map.keys = function() {");
		out.push("    var keys = $array();");
		out.push("    var i = 0;");
		out.push("    while (i < $asize(map.__hxhx_pairs)) { keys[$asize(keys)] = map.__hxhx_pairs[i][0]; i = i + 1; }");
		out.push("    return keys.iterator();");
		out.push("  };");
		out.push("  map.iterator = function() {");
		out.push("    var values = $array();");
		out.push("    var i = 0;");
		out.push("    while (i < $asize(map.__hxhx_pairs)) { values[$asize(values)] = map.__hxhx_pairs[i][1]; i = i + 1; }");
		out.push("    return values.iterator();");
		out.push("  };");
		out.push("  map.toString = function() {");
		out.push("    var parts = $array();");
		out.push("    var i = 0;");
		out.push("    while (i < $asize(map.__hxhx_pairs)) {");
		out.push("      var pair = map.__hxhx_pairs[i];");
		out.push("      parts[$asize(parts)] = __hxhx_string(pair[0]) + \" => \" + __hxhx_string(pair[1]);");
		out.push("      i = i + 1;");
		out.push("    }");
		out.push("    return \"[\" + parts.join(\", \") + \"]\";");
		out.push("  };");
		out.push("  return map;");
		out.push("}");
		out.push("");
	}
}
