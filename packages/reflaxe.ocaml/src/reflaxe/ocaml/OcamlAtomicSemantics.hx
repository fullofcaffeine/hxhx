package reflaxe.ocaml;

/**
	Portable-contract atomic semantics for `haxe.atomic.*` in `reflaxe.ocaml`.

	Current contract:
	- `emulated` (default): API-compatible single-thread semantics implemented by
	  mutable wrappers in `_std/haxe/atomic/*`.
	- True hardware/thread-level atomics are not available yet in the portable lane.

	Policy:
	- Missing/empty define values normalize to `emulated`.
	- Any non-`emulated` value is rejected with an actionable error.
**/
enum abstract OcamlAtomicSemantics(String) from String to String {
	var Emulated = "emulated";

	public static function fromDefineValue(raw:Null<String>):OcamlAtomicSemantics {
		if (raw == null)
			return Emulated;
		final trimmed = StringTools.trim(raw);
		if (trimmed.length == 0)
			return Emulated;
		final normalized = trimmed.toLowerCase();
		return switch (normalized) {
			case "emulated": Emulated;
			case _:
				throw "invalid -D ocaml_atomic_semantics="
					+ raw
					+ " (only emulated is currently supported; true thread-level atomic mode is not available yet)";
		};
	}

	public static inline function toDefineValue(value:OcamlAtomicSemantics):String {
		return cast value;
	}
}
