package backend.vm;

/**
	Small Neko source lowering for macro `ComplexType` quotes.

	Why
	- Upstream-derived Neko gates exercise `macro :Type` values through macro
	  printer-style runtime helpers.
	- `NekoTargetCore` should not grow a second parser-shaped subsystem while
	  Full1 burn-down progresses.

	What
	- Emits the minimal enum-like object shape used by this repo's macro quote
	  tests: `__hx_ctor`, `__hx_index`, and `__hx_params`.
	- Currently supports simple type paths and top-level function arrows such
	  as `X -> Y`, which is the observed Neko Gate3 blocker.
**/
class NekoMacroTypeLowering {
	public static function render(raw:String):String {
		final text = trimLeadingTypeColon(raw);
		final arrow = findTopLevelArrow(text);
		if (arrow >= 0) {
			final left = text.substring(0, arrow);
			final right = text.substr(arrow + 2);
			return macroEnum("TFunction", ["$array(" + render(left) + ")", render(right)]);
		}
		return macroTypePath(text);
	}

	static function macroTypePath(raw:String):String {
		final path = StringTools.trim(stripGenericTypeParams(raw));
		final parts = path.length == 0 ? [""] : path.split(".");
		final name = parts[parts.length - 1];
		final pack = new Array<String>();
		if (parts.length > 1) {
			for (i in 0...parts.length - 1)
				pack.push(quote(parts[i]));
		}
		return macroEnum("TPath", [
			anonObject(["pack", "name", "params", "sub"], ["$array(" + pack.join(", ") + ")", quote(name), "$array()", "null"])
		]);
	}

	static function macroEnum(name:String, params:Array<String>):String {
		return anonObject(["__hx_ctor", "__hx_index", "__hx_params"], [quote(name), "0", "$array(" + (params == null ? "" : params.join(", ")) + ")"]);
	}

	static function anonObject(fieldNames:Array<String>, fieldValues:Array<String>):String {
		final tmp = "__hxhx_o";
		final parts = ["(function() { var " + tmp + " = $new(null);"];
		final count = fieldNames.length < fieldValues.length ? fieldNames.length : fieldValues.length;
		for (i in 0...count)
			parts.push(tmp + "." + safeIdent(fieldNames[i]) + " = " + fieldValues[i] + ";");
		parts.push("return " + tmp + "; })()");
		return parts.join(" ");
	}

	static function trimLeadingTypeColon(raw:String):String {
		var text = StringTools.trim(raw == null ? "" : raw);
		if (StringTools.startsWith(text, ":"))
			text = StringTools.trim(text.substr(1));
		return text;
	}

	static function stripGenericTypeParams(raw:String):String {
		final lt = findTopLevelChar(raw, "<".code);
		return lt < 0 ? raw : raw.substr(0, lt);
	}

	static function findTopLevelArrow(raw:String):Int {
		var paren = 0;
		var bracket = 0;
		var angle = 0;
		var brace = 0;
		var i = 0;
		while (i + 1 < raw.length) {
			final c = raw.charCodeAt(i);
			switch (c) {
				case "(".code:
					paren++;
				case ")".code:
					if (paren > 0)
						paren--;
				case "[".code:
					bracket++;
				case "]".code:
					if (bracket > 0)
						bracket--;
				case "<".code:
					angle++;
				case ">".code:
					if (angle > 0)
						angle--;
				case "{".code:
					brace++;
				case "}".code:
					if (brace > 0)
						brace--;
				case "-".code if (paren == 0 && bracket == 0 && angle == 0 && brace == 0 && raw.charCodeAt(i + 1) == ">".code):
					return i;
				case _:
			}
			i++;
		}
		return -1;
	}

	static function findTopLevelChar(raw:String, target:Int):Int {
		var paren = 0;
		var bracket = 0;
		var angle = 0;
		var brace = 0;
		for (i in 0...raw.length) {
			final c = raw.charCodeAt(i);
			switch (c) {
				case "(".code:
					paren++;
				case ")".code:
					if (paren > 0)
						paren--;
				case "[".code:
					bracket++;
				case "]".code:
					if (bracket > 0)
						bracket--;
				case "<".code:
					angle++;
				case ">".code:
					if (angle > 0)
						angle--;
				case "{".code:
					brace++;
				case "}".code:
					if (brace > 0)
						brace--;
				case _ if (c == target && paren == 0 && bracket == 0 && angle == 0 && brace == 0):
					return i;
				case _:
			}
		}
		return -1;
	}

	static function safeIdent(name:String):String {
		if (name == null || name.length == 0)
			return "_";
		final out = new StringBuf();
		for (i in 0...name.length) {
			final c = name.charCodeAt(i);
			final ok = (c >= "a".code && c <= "z".code)
				|| (c >= "A".code && c <= "Z".code)
				|| c == "_".code
				|| (i > 0 && c >= "0".code && c <= "9".code);
			out.addChar(ok ? c : "_".code);
		}
		return out.toString();
	}

	static function quote(value:String):String {
		return '"' + StringTools.replace(StringTools.replace(StringTools.replace(value, "\\", "\\\\"), "\n", "\\n"), '"', '\\"') + '"';
	}
}
