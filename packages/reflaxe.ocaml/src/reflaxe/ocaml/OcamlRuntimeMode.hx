package reflaxe.ocaml;

/**
	Stage0 runtime planning mode contract for `reflaxe.ocaml`.
**/
enum abstract OcamlRuntimeMode(String) from String to String {
	var Full = "full";
	var Selective = "selective";

	public static function fromDefineValue(raw:Null<String>, fallback:OcamlRuntimeMode):OcamlRuntimeMode {
		if (raw == null)
			return fallback;
		final trimmed = StringTools.trim(raw);
		if (trimmed.length == 0)
			return fallback;
		final normalized = trimmed.toLowerCase();
		return switch (normalized) {
			case "full": Full;
			case "selective": Selective;
			case "none":
				throw "invalid -D ocaml_runtime_mode=none (none is not supported; use selective + -D ocaml_runtime_no_infer"
					+ " and optional -D ocaml_runtime_modules=... for minimal runtime planning)";
			case _:
				throw "invalid -D ocaml_runtime_mode=" + raw + " (expected full|selective)";
		}
	}

	public static inline function toDefineValue(mode:OcamlRuntimeMode):String {
		return cast mode;
	}
}
