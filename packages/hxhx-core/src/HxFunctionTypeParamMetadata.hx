import HxTypeSyntax.HxTypeSyntaxParameter;

/**
	Canonical metadata bridge for method-level generic parameters.

	The bootstrap AST currently stores generic declarations in metadata instead
	of a full typed constraint graph. This helper keeps every parser path on one
	encoding and preserves constraint text such as `B:Array<A>` for current
	consumers. The shared structured grammar selects binders and constraints;
	this projection never discovers declarations by splitting source strings.
	It is not the complete generic syntax record used by the function migration.
**/
class HxFunctionTypeParamMetadata {
	public static inline final TYPE_PARAMS_PREFIX = "__hxhx_fn_type_params=";
	public static inline final CONSTRAINT_PREFIX = "__hxhx_fn_type_constraint=";

	/** Parse one raw `<...>` declaration into stable AST metadata entries. **/
	public static function fromGenericText(text:String):Array<String> {
		if (text == null || StringTools.trim(text).length == 0)
			return [];
		return fromParameters(HxTypedefParser.parseParameters(text), text);
	}

	/** Project already parsed binders; source ranges retain constraint spelling for the existing hint consumers. */
	public static function fromParameters(parameters:Array<HxTypeSyntaxParameter>, source:String):Array<String> {
		final out = new Array<String>();
		final names = [for (parameter in parameters) parameter.name];
		if (names.length > 0)
			out.push(TYPE_PARAMS_PREFIX + names.join(","));
		for (parameter in parameters) {
			final hints = [
				for (constraint in parameter.constraints)
					compactTypeHint(source.substring(constraint.getPos().getIndex(), constraint.getEndPos().getIndex()))
			];
			if (hints.length > 0)
				out.push(CONSTRAINT_PREFIX + parameter.name + ":" + hints.join("&"));
		}
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

	static function compactTypeHint(text:String):String {
		var out = StringTools.trim(text == null ? "" : text);
		for (whitespace in [" ", "\t", "\r", "\n"])
			out = StringTools.replace(out, whitespace, "");
		return out;
	}

	/** Split compound bounds without splitting type arguments, function groups, or anonymous fields. */
	public static function constraintHints(text:String):Array<String> {
		return [for (part in splitTopLevel(text, "&")) StringTools.trim(part)];
	}

	static function splitTopLevelComma(text:String):Array<String> {
		return splitTopLevel(text, ",");
	}

	static function splitTopLevel(text:String, separator:String):Array<String> {
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
				case ch if (ch == separator && angle == 0 && paren == 0 && brace == 0 && bracket == 0):
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
