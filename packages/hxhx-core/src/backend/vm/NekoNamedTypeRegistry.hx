package backend.vm;

import haxe.ds.StringMap;

/** One already-selected runtime descriptor and its public qualified name. */
typedef NekoNamedType = {
	final identity:String;
	final name:String;
}

/**
	Build Neko's bootstrap name tree before authored standard-library startup.

	Leaves reference the original descriptor objects. Replacing a source type
	binding later does not rewrite this tree. Std.__init__ can populate its core
	entries normally. Namespace nodes are allocated in parent-first order; exact
	type descriptors take precedence when a node is also a namespace prefix.
 */
function render(out:Array<String>, entries:Array<NekoNamedType>, symbols:String, rootField:String):Void {
	final descriptors = new StringMap<String>();
	final paths = new StringMap<Array<String>>();
	var bootIdentity:Null<String> = null;
	for (entry in entries) {
		if (entry.identity.length == 0 || entry.name.length == 0)
			throw "Neko named type registry requires nonempty identities and names";
		if (descriptors.exists(entry.name) && descriptors.get(entry.name) != entry.identity)
			throw "Neko named type registry has conflicting public names: " + entry.name;
		descriptors.set(entry.name, entry.identity);
		final parts = entry.name.split(".");
		for (index in 0...parts.length) {
			if (parts[index].length == 0)
				throw "Neko named type registry has an empty namespace component";
			final prefix = parts.slice(0, index + 1);
			paths.set(prefix.join("."), prefix);
		}
		if (entry.identity == "nominal:neko.Boot")
			bootIdentity = entry.identity;
	}
	final root = symbols + "." + rootField;
	function descriptor(identity:String):String
		return "$objget(" + symbols + ".__hxhx_types, $hash(" + haxe.Json.stringify(identity) + "))";
	function namespace(parts:Array<String>):String {
		var value = root;
		for (part in parts)
			value = "$objget(" + value + ", $hash(" + haxe.Json.stringify(part) + "))";
		return value;
	}
	final ordered = [for (path in paths) path];
	ordered.sort(function(left, right) {
		if (left.length != right.length)
			return left.length - right.length;
		final leftName = left.join(".");
		final rightName = right.join(".");
		return leftName < rightName ? -1 : leftName == rightName ? 0 : 1;
	});
	out.push(root + " = $new(null);");
	for (parts in ordered) {
		final identity = descriptors.get(parts.join("."));
		out.push("$objset(" + namespace(parts.slice(0, parts.length - 1)) + ", $hash(" + haxe.Json.stringify(parts[parts.length - 1]) + "), "
			+ (identity == null ? "$new(null)" : descriptor(identity)) + ");");
	}
	if (bootIdentity != null)
		out.push(descriptor(bootIdentity) + ".__classes = " + root + ";");
}
