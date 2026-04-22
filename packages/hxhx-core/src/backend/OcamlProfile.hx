package backend;

/**
	OCaml compilation profile contract for Stage3 backends.

	Why
	- We need one explicit switch for future runtime/lowering policy (`portable` vs `metal`)
	  without introducing ad-hoc feature defines.
	- The contract must be deterministic so stage policy docs, CI gates, and backends
	  all agree on the same profile value.

	What
	- Accepted values:
	  - `portable` (default; backward compatible behavior)
	  - `metal` (future stricter native-oriented behavior)
	- Parsing is centralized here so every caller gets identical validation and errors.

	How
	- Normalize raw `-D ocaml_profile=...` values to lowercase.
	- Empty/missing value maps to `portable`.
	- Unknown values fail fast with an actionable message.
**/
enum abstract OcamlProfile(String) from String to String {
	var Portable = "portable";
	var Metal = "metal";

	static function isTrimCode(code:Int):Bool {
		return code == " ".code || code == "\t".code || code == "\r".code || code == "\n".code;
	}

	static function trimAscii(value:String):String {
		var start = 0;
		var end = value.length;
		while (start < end && isTrimCode(value.charCodeAt(start)))
			start++;
		while (end > start && isTrimCode(value.charCodeAt(end - 1)))
			end--;
		return value.substr(start, end - start);
	}

	public static function fromDefineValue(raw:Null<String>):OcamlProfile {
		if (raw == null)
			return Portable;
		final trimmed = trimAscii(raw);
		if (trimmed.length == 0)
			return Portable;
		final normalized = trimmed.toLowerCase();
		return switch (normalized) {
			case "portable": Portable;
			case "metal": Metal;
			case _: throw "invalid -D ocaml_profile=" + raw + " (expected portable|metal)";
		}
	}

	public static inline function toDefineValue(profile:OcamlProfile):String {
		return cast profile;
	}
}
