/** One method-level type parameter constraint recovered from Haxe source. **/
typedef HxFunctionTypeParamConstraint = {
	var name:String;
	var typeHint:String;
}

/**
	Canonical metadata bridge for method-level generic parameters.

	The bootstrap AST currently stores generic declarations in metadata instead
	of a full typed constraint graph. This helper keeps every parser path on one
	encoding and preserves constraint text such as `B:Array<A>` for target type
	flow without asking emitters to rescan Haxe source.
**/
class HxFunctionTypeParamMetadata {
	public static inline final TYPE_PARAMS_PREFIX = "__hxhx_fn_type_params=";
	public static inline final CONSTRAINT_PREFIX = "__hxhx_fn_type_constraint=";

	/** Parse one raw `<...>` declaration into stable AST metadata entries. **/
	public static function fromGenericText(text:String):Array<String> {
		final out = new Array<String>();
		final names = new Array<String>();
		final constraints = new Array<HxFunctionTypeParamConstraint>();
		final trimmed = StringTools.trim(text == null ? "" : text);
		if (!StringTools.startsWith(trimmed, "<") || !StringTools.endsWith(trimmed, ">"))
			return out;
		final inner = trimmed.substr(1, trimmed.length - 2);
		for (segment in splitTopLevelComma(inner)) {
			final colon = topLevelColon(segment);
			final name = typeParamName(colon < 0 ? segment : segment.substr(0, colon));
			if (name.length == 0)
				continue;
			names.push(name);
			if (colon >= 0) {
				final typeHint = compactTypeHint(segment.substr(colon + 1));
				if (typeHint.length > 0)
					constraints.push({name: name, typeHint: typeHint});
			}
		}
		if (names.length > 0)
			out.push(TYPE_PARAMS_PREFIX + names.join(","));
		for (constraint in constraints)
			out.push(CONSTRAINT_PREFIX + constraint.name + ":" + constraint.typeHint);
		return out;
	}

	/** Read declared parameter names from either new or existing AST metadata. **/
	public static function typeParamNames(metadata:Array<String>):Array<String> {
		final out = new Array<String>();
		if (metadata == null)
			return out;
		for (entry in metadata) {
			if (!StringTools.startsWith(entry, TYPE_PARAMS_PREFIX))
				continue;
			for (name in entry.substr(TYPE_PARAMS_PREFIX.length).split(",")) {
				final clean = StringTools.trim(name);
				if (clean.length > 0 && out.indexOf(clean) < 0)
					out.push(clean);
			}
		}
		return out;
	}

	/** Read the source constraint hint associated with each declared parameter. **/
	public static function constraints(metadata:Array<String>):haxe.ds.StringMap<String> {
		final out = new haxe.ds.StringMap<String>();
		if (metadata == null)
			return out;
		for (entry in metadata) {
			if (!StringTools.startsWith(entry, CONSTRAINT_PREFIX))
				continue;
			final payload = entry.substr(CONSTRAINT_PREFIX.length);
			final colon = payload.indexOf(":");
			if (colon <= 0)
				continue;
			final name = StringTools.trim(payload.substr(0, colon));
			final typeHint = StringTools.trim(payload.substr(colon + 1));
			if (name.length > 0 && typeHint.length > 0)
				out.set(name, typeHint);
		}
		return out;
	}

	static function typeParamName(text:String):String {
		final matcher = ~/^[ \t\r\n]*([A-Za-z_][A-Za-z0-9_]*)/;
		return matcher.match(text == null ? "" : text) ? matcher.matched(1) : "";
	}

	static function compactTypeHint(text:String):String {
		var out = StringTools.trim(text == null ? "" : text);
		for (whitespace in [" ", "\t", "\r", "\n"])
			out = StringTools.replace(out, whitespace, "");
		return out;
	}

	static function splitTopLevelComma(text:String):Array<String> {
		final out = new Array<String>();
		var start = 0;
		var angle = 0;
		var paren = 0;
		var brace = 0;
		var bracket = 0;
		for (i in 0...text.length) {
			final ch = text.charAt(i);
			switch (ch) {
				case "<":
					angle++;
				case ">" if (i == 0 || text.charAt(i - 1) != "-"):
					if (angle > 0)
						angle--;
				case "(":
					paren++;
				case ")":
					if (paren > 0)
						paren--;
				case "{":
					brace++;
				case "}":
					if (brace > 0)
						brace--;
				case "[":
					bracket++;
				case "]":
					if (bracket > 0)
						bracket--;
				case "," if (angle == 0 && paren == 0 && brace == 0 && bracket == 0):
					out.push(text.substring(start, i));
					start = i + 1;
				case _:
			}
		}
		out.push(text.substr(start));
		return out;
	}

	static function topLevelColon(text:String):Int {
		var angle = 0;
		var paren = 0;
		var brace = 0;
		var bracket = 0;
		for (i in 0...text.length) {
			final ch = text.charAt(i);
			switch (ch) {
				case "<":
					angle++;
				case ">" if (i == 0 || text.charAt(i - 1) != "-"):
					if (angle > 0)
						angle--;
				case "(":
					paren++;
				case ")":
					if (paren > 0)
						paren--;
				case "{":
					brace++;
				case "}":
					if (brace > 0)
						brace--;
				case "[":
					bracket++;
				case "]":
					if (bracket > 0)
						bracket--;
				case ":" if (angle == 0 && paren == 0 && brace == 0 && bracket == 0):
					return i;
				case _:
			}
		}
		return -1;
	}
}
