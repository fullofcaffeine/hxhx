package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.macro.Expr;
import haxe.macro.Expr.MetadataEntry;
import haxe.macro.Expr.Position;
#if macro
import haxe.macro.Context;
#end

/** Stable source information carried from target input into lowered nodes. */
typedef OcamlLoweredSourceSpan = {
	final file:String;
	final min:Int;
	final max:Int;
}

/**
	Creates and reads stable target-lowering origins.

	The metadata is internal to the target adapter. Besides giving a lowered node
	a deterministic identity, its wrapper prevents Reflaxe's generic
	Everything-Is-An-Expression pass from splitting an admitted assignment into a
	write followed by a second read of its place.
**/
class OcamlLoweredOrigin {
	public static inline final PLACE_META = ":reflaxeOcamlPlaceOrigin";
	public static inline final PLACE_PROTECTION_META = ":reflaxeOcamlPlaceProtection";

	static function normalizePath(path:String):String {
		if (path == null)
			return "";
		var normalized = StringTools.replace(path, "\\", "/");
		#if macro
		final cwd = StringTools.replace(Sys.getCwd(), "\\", "/");
		if (StringTools.startsWith(normalized, cwd)) {
			normalized = normalized.substr(cwd.length);
			if (StringTools.startsWith(normalized, "/"))
				normalized = normalized.substr(1);
		}
		final repositoryMarkers = ["/packages/reflaxe.ocaml/", "/test/", "/examples/"];
		for (marker in repositoryMarkers) {
			final markerIndex = normalized.indexOf(marker);
			if (markerIndex >= 0)
				return normalized.substr(markerIndex + 1);
		}
		#end
		return normalized;
	}

	/** Returns a path-stable source span when the host exposes one. */
	public static function sourceSpan(position:Position):OcamlLoweredSourceSpan {
		#if macro
		final info = Context.getPosInfos(position);
		return {
			file: normalizePath(info.file),
			min: info.min,
			max: info.max
		};
		#else
		return {file: "", min: 0, max: 0};
		#end
	}

	/** Whether a source belongs to the target compatibility library, not user code. */
	public static function isTargetLibrarySource(span:OcamlLoweredSourceSpan):Bool {
		return StringTools.startsWith(span.file, "packages/reflaxe.ocaml/std/")
			|| span.file.indexOf("/packages/reflaxe.ocaml/std/") >= 0
			|| span.file.indexOf("/std/ocaml/_std/") >= 0;
	}

	/**
		Builds a deterministic structural identity within one normalized function.

		Source offsets are intentionally excluded: they remain diagnostic origin
		data and must not change semantic identity after an unrelated earlier edit.
	**/
	public static function placeId(functionId:String, ordinal:Int):String {
		final seed = functionId + "|" + ordinal;
		return "place:" + Sha256.encode(seed).substr(0, 24);
	}

	/** Wraps a typed expression with the stable place identity metadata. */
	public static function metadata(id:String, position:Position):MetadataEntry {
		final value:Expr = {expr: EConst(CString(id)), pos: position};
		return {name: PLACE_META, params: [value], pos: position};
	}

	/** Wraps an admitted operation while generic Reflaxe value rewrites run. */
	public static function protection(id:String, position:Position):MetadataEntry {
		final value:Expr = {expr: EConst(CString(id)), pos: position};
		return {name: PLACE_PROTECTION_META, params: [value], pos: position};
	}

	/** Whether this metadata is the transient OCaml place-protection envelope. */
	public static function isPlaceProtection(entry:MetadataEntry):Bool {
		return entry.name == PLACE_PROTECTION_META;
	}

	/** Reads the stable identity carried by an early protection envelope. */
	public static function readProtectionId(entry:MetadataEntry):Null<String> {
		if (!isPlaceProtection(entry))
			return null;
		return switch (entry.params) {
			case [{expr: EConst(CString(value, _))}]: value;
			case _: null;
		}
	}

	/** Reads the stable identity from target-owned place metadata. */
	public static function readPlaceId(entry:MetadataEntry):Null<String> {
		if (entry.name != PLACE_META)
			return null;
		return switch (entry.params) {
			case [{expr: EConst(CString(value, _))}]: value;
			case _: null;
		}
	}
}
#end
