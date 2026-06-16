package backend.vm;

typedef NekoRuntimeClassMeta = {
	var fullName:String;
	var instanceFields:Array<String>;
	var staticFields:Array<String>;
}

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
	public static function render(out:Array<String>, classes:Array<NekoRuntimeClassMeta>):Void {
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
		out.push("var __hxhx_instance_fields = $new(null);");
		out.push("var __hxhx_static_fields = $new(null);");
		for (meta in classes) {
			out.push("$objset(__hxhx_instance_fields, $hash(" + quote(meta.fullName) + "), " + renderStringArray(meta.instanceFields) + ");");
			out.push("$objset(__hxhx_static_fields, $hash(" + quote(meta.fullName) + "), " + renderStringArray(meta.staticFields) + ");");
		}
		out.push("var __hxhx_type_class_name = function(c) {");
		out.push("  if (c == null) return null;");
		out.push("  return \"\" + c;");
		out.push("}");
		out.push("");
		out.push("var __hxhx_type_get_class = function(o) {");
		out.push("  if (o == null) return null;");
		out.push("  if ($typeof(o) == $tarray) return \"Array\";");
		out.push("  if ($typeof(o) == $tobject && o.__hx_ctor != null) return o.__hx_ctor;");
		out.push("  return null;");
		out.push("}");
		out.push("");
		out.push("var __hxhx_type_fields = function(map, c) {");
		out.push("  var name = __hxhx_type_class_name(c);");
		out.push("  if (name == null) return $array();");
		out.push("  var fields = $objget(map, $hash(name));");
		out.push("  return if (fields == null) $array() else fields;");
		out.push("}");
		out.push("");
		out.push("var __hxhx_reflect_fields = function(o) {");
		out.push("  var names = $array();");
		out.push("  if (o == null || $typeof(o) != $tobject) return names;");
		out.push("  var raw = $objfields(o);");
		out.push("  var i = 0;");
		out.push("  while (i < $asize(raw)) { names[$asize(names)] = $field(raw[i]); i = i + 1; }");
		out.push("  return names;");
		out.push("}");
		out.push("");
		out.push("var __hxhx_reflect_has_field = function(o, field) {");
		out.push("  return o != null && $typeof(o) == $tobject && $objget(o, $hash(field)) != null;");
		out.push("}");
		out.push("");
		out.push("var __hxhx_string_starts_with = function(s, start) {");
		out.push("  if (s == null || start == null) return false;");
		out.push("  if ($typeof(s) != $tstring) s = __hxhx_string(s);");
		out.push("  if ($typeof(start) != $tstring) start = __hxhx_string(start);");
		out.push("  if ($ssize(s) < $ssize(start)) return false;");
		out.push("  var pos = try $sfind(s, 0, start) catch e null;");
		out.push("  return pos == 0;");
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

	static function renderStringArray(values:Array<String>):String {
		return "$array(" + [for (value in values) quote(value)].join(", ") + ")";
	}

	static function quote(value:String):String {
		return '"' + StringTools.replace(StringTools.replace(StringTools.replace(value, "\\", "\\\\"), "\n", "\\n"), '"', '\\"') + '"';
	}
}
