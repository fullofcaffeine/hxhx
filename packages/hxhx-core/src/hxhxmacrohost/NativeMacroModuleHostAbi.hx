package hxhxmacrohost;

/**
	Typed ABI decoder/validator for native macro-module registrations.

	Why
	- Native module loading is a runtime boundary.
	- We keep that boundary deterministic by decoding a tiny line-based snapshot and
	  validating it before activation.

	Snapshot contract
	- First non-empty line: snapshot version token (`NativeMacroModuleAbi.SNAPSHOT_VERSION`).
	- Second non-empty line: `abiVersion=<int>`.
	- Third non-empty line: `macroApiVersion=<int>`.
	- Remaining lines: `<pluginId>\t<declaration>`, where a declaration is `pack.Type.method`.
	- Tokens must be non-empty and must not contain tabs/newlines.

	Failure policy
	- Any malformed row or identity mismatch is a hard error.
	- Validation happens before macro declarations are accepted as runnable.
**/
class NativeMacroModuleHostAbi {
	static inline final FIELD_SEPARATOR = "\t";
	static inline final ABI_HEADER_PREFIX = "abiVersion=";
	static inline final MACRO_API_HEADER_PREFIX = "macroApiVersion=";

	static inline function trim(value:String):String {
		return value == null ? "" : StringTools.trim(value);
	}

	static inline function normalizeSourceLabel(sourceLabel:String):String {
		final normalized = trim(sourceLabel);
		return normalized.length == 0 ? "<unknown-native-macro-source>" : normalized;
	}

	static function fail(sourceLabel:String, message:String):Void {
		throw "native macro module registration (" + normalizeSourceLabel(sourceLabel) + "): " + message;
	}

	static inline function trimTrailingCr(line:String):String {
		if (line == null)
			return "";
		final len = line.length;
		if (len == 0)
			return "";
		return line.charCodeAt(len - 1) == 13 ? line.substr(0, len - 1) : line;
	}

	static function requireToken(value:String, field:String, sourceLabel:String):String {
		final token = trim(value);
		if (token.length == 0)
			fail(sourceLabel, field + " is required");
		if (token.indexOf("\n") >= 0 || token.indexOf("\r") >= 0 || token.indexOf(FIELD_SEPARATOR) >= 0)
			fail(sourceLabel, field + " must not contain tab/newline characters");
		return token;
	}

	static function decodeRow(line:String, lineNumber:Int, sourceLabel:String):{
		pluginId:String,
		declaration:String
	} {
		final idx = line.indexOf(FIELD_SEPARATOR);
		if (idx <= 0 || idx + FIELD_SEPARATOR.length >= line.length)
			fail(sourceLabel, "invalid registration row at line " + lineNumber + " (expected pluginId<TAB>declaration)");
		if (line.indexOf(FIELD_SEPARATOR, idx + FIELD_SEPARATOR.length) >= 0)
			fail(sourceLabel, "invalid registration row at line " + lineNumber + " (too many separators)");
		final pluginId = requireToken(line.substr(0, idx), "pluginId", sourceLabel);
		final declaration = requireToken(line.substr(idx + FIELD_SEPARATOR.length), "declaration", sourceLabel);
		return {
			pluginId: pluginId,
			declaration: declaration
		};
	}

	static function requireHeaderInt(line:String, prefix:String, field:String, expected:Int, lineNumber:Int, sourceLabel:String):Void {
		if (!StringTools.startsWith(line, prefix))
			fail(sourceLabel, "missing " + field + " header at line " + lineNumber + " (expected `" + prefix + expected + "`)");
		final rawValue = trim(line.substr(prefix.length));
		final parsed = Std.parseInt(rawValue);
		if (parsed == null)
			fail(sourceLabel, "invalid " + field + " value `" + rawValue + "` at line " + lineNumber);
		if (parsed != expected)
			fail(sourceLabel, field + " mismatch: expected " + field + "=" + expected + ", got " + parsed);
	}

	public static function decodeSnapshot(snapshot:String, sourceLabel:String):Array<{
		pluginId:String,
		declaration:String
	}> {
		final raw = snapshot == null ? "" : snapshot;
		final lines = raw.split("\n");
		final rows = new Array<{
			pluginId:String,
			declaration:String
		}>();
		var headerState = 0;
		var lineNumber = 0;
		for (line in lines) {
			lineNumber++;
			final normalized = trim(trimTrailingCr(line));
			if (normalized.length == 0)
				continue;
			if (headerState == 0) {
				if (normalized != NativeMacroModuleAbi.SNAPSHOT_VERSION)
					fail(sourceLabel, "invalid snapshot version `" + normalized + "` (expected `" + NativeMacroModuleAbi.SNAPSHOT_VERSION + "`)");
				headerState = 1;
				continue;
			}
			if (headerState == 1) {
				requireHeaderInt(normalized, ABI_HEADER_PREFIX, "abiVersion", NativeMacroModuleAbi.ABI_VERSION, lineNumber, sourceLabel);
				headerState = 2;
				continue;
			}
			if (headerState == 2) {
				requireHeaderInt(normalized, MACRO_API_HEADER_PREFIX, "macroApiVersion", NativeMacroModuleAbi.MACRO_API_VERSION, lineNumber, sourceLabel);
				headerState = 3;
				continue;
			}
			rows.push(decodeRow(normalized, lineNumber, sourceLabel));
		}

		if (headerState == 0)
			fail(sourceLabel, "snapshot is missing version header `" + NativeMacroModuleAbi.SNAPSHOT_VERSION + "`");
		if (headerState == 1)
			fail(sourceLabel, "snapshot is missing abiVersion header `abiVersion=" + NativeMacroModuleAbi.ABI_VERSION + "`");
		if (headerState == 2)
			fail(sourceLabel, "snapshot is missing macroApiVersion header `macroApiVersion=" + NativeMacroModuleAbi.MACRO_API_VERSION + "`");
		return rows;
	}

	static function declarationsForPluginInternal(snapshot:String, pluginId:String, sourceLabel:String, allowEmpty:Bool):Array<String> {
		final expectedPluginId = requireToken(pluginId, "pluginId", sourceLabel);
		final rows = decodeSnapshot(snapshot, sourceLabel);
		final out = new Array<String>();
		final seen = new haxe.ds.StringMap<Bool>();
		for (row in rows) {
			if (row.pluginId != expectedPluginId) {
				fail(sourceLabel,
					"registration pluginId mismatch: expected `"
					+ expectedPluginId
					+ "`, got `"
					+ row.pluginId
					+ "` (declaration `"
					+ row.declaration
					+ "`)");
			}
			if (seen.exists(row.declaration))
				fail(sourceLabel, "duplicate declaration registration `" + row.declaration + "` for plugin `" + expectedPluginId + "`");
			seen.set(row.declaration, true);
			out.push(row.declaration);
		}
		if (!allowEmpty && out.length == 0)
			fail(sourceLabel, "plugin `" + expectedPluginId + "` did not register any macro declarations");
		return out;
	}

	public static function declarationsForPlugin(snapshot:String, pluginId:String, sourceLabel:String):Array<String> {
		return declarationsForPluginInternal(snapshot, pluginId, sourceLabel, false);
	}

	public static function declarationsForPluginAllowEmpty(snapshot:String, pluginId:String, sourceLabel:String):Array<String> {
		return declarationsForPluginInternal(snapshot, pluginId, sourceLabel, true);
	}
}
