package reflaxe.ocaml.target;

/** Builds target-owned structural paths without host allocation identities. **/
class OcamlTargetExpressionPath {
	public static inline final ROOT = "root";

	public static function child(parent:String, role:String):String
		return require(parent) + "/" + requireRole(role);

	public static function indexed(parent:String, role:String, index:Int):String {
		if (index < 0)
			throw "OCaml target expression path requires a non-negative child index";
		return child(parent, role) + "/" + index;
	}

	public static function require(value:String):String {
		final normalized = value == null ? "" : StringTools.trim(value);
		if (normalized != ROOT && !StringTools.startsWith(normalized, ROOT + "/"))
			throw "OCaml target expression path must begin at root";
		for (segment in normalized.split("/"))
			if (!validSegment(segment))
				throw 'OCaml target expression path contains invalid segment "${segment}"';
		return normalized;
	}

	static function requireRole(value:String):String {
		final normalized = value == null ? "" : StringTools.trim(value);
		if (!validRole(normalized))
			throw 'OCaml target expression path contains invalid role "${normalized}"';
		return normalized;
	}

	static function validSegment(value:String):Bool {
		if (value == null || value.length == 0)
			return false;
		for (index in 0...value.length) {
			final code = value.charCodeAt(index);
			if (code == null)
				return false;
			final lower = code >= 97 && code <= 122;
			final digit = code >= 48 && code <= 57;
			if (!lower && !digit && code != 45)
				return false;
		}
		return true;
	}

	static function validRole(value:String):Bool {
		if (!validSegment(value))
			return false;
		final first = value.charCodeAt(0);
		return first != null && first >= 97 && first <= 122;
	}
}
