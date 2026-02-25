package reflaxe.ocaml;

/**
	Portable-profile policy for target-native `ocaml.*` surface usage.

	Why:
	- Portable profile aims to preserve cross-target semantics.
	- `ocaml.*` APIs are intentionally target-native and non-portable.
	- We need a deterministic policy knob for migration and CI enforcement.

	Values:
	- `warn` (default): allow compile, emit warning/report signal.
	- `allow`: no diagnostics.
	- `error`: fail fast when `ocaml.*` appears in portable profile sources.
**/
enum abstract OcamlPortableNativeSurfacePolicy(String) from String to String {
	var Warn = "warn";
	var Allow = "allow";
	var Error = "error";

	public static function fromDefineValue(raw:Null<String>):OcamlPortableNativeSurfacePolicy {
		if (raw == null)
			return Warn;
		final trimmed = StringTools.trim(raw);
		if (trimmed.length == 0)
			return Warn;
		final normalized = trimmed.toLowerCase();
		return switch (normalized) {
			case "warn": Warn;
			case "allow": Allow;
			case "error": Error;
			case _:
				throw "invalid -D ocaml_portable_native_surface=" + raw + " (expected warn|allow|error)";
		}
	}

	public static inline function toDefineValue(policy:OcamlPortableNativeSurfacePolicy):String {
		return cast policy;
	}
}
