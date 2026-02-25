package reflaxe.ocaml;

/**
	Stage0 OCaml profile contract parser for `reflaxe.ocaml`.

	Why:
	- Stage0 and Stage3 must accept the same profile contract values/defaults.
	- Runtime/report generation should fail fast on invalid profile values.

	What:
	- Accepted values: `portable` (default), `metal`.
	- Missing/empty values normalize to `portable`.
	- Invalid values throw an actionable error message.
**/
enum abstract OcamlProfileContract(String) from String to String {
	var Portable = "portable";
	var Metal = "metal";

	public static function fromDefineValue(raw:Null<String>):OcamlProfileContract {
		if (raw == null)
			return Portable;
		final trimmed = StringTools.trim(raw);
		if (trimmed.length == 0)
			return Portable;
		final normalized = trimmed.toLowerCase();
		return switch (normalized) {
			case "portable": Portable;
			case "metal": Metal;
			case _:
				throw "invalid -D ocaml_profile=" + raw + " (expected portable|metal)";
		}
	}

	public static inline function toDefineValue(profile:OcamlProfileContract):String {
		return cast profile;
	}
}
