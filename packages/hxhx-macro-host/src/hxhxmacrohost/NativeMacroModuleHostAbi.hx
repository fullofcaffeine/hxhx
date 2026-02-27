package hxhxmacrohost;

/**
	Typed ABI decoder/validator for native macro-module registrations.

	Why
	- Native module loading is a runtime boundary.
	- We keep that boundary deterministic by decoding a tiny line-based snapshot and
	  validating it before activation.

	Snapshot contract
	- First non-empty line: `v1` (`NativeMacroModuleAbi.SNAPSHOT_VERSION`).
	- Remaining lines: `<pluginId>\t<expr>`.
	- Tokens must be non-empty and must not contain tabs/newlines.

	Failure policy
	- Any malformed row or identity mismatch is a hard error.
	- Validation happens before macro expressions are accepted as runnable.
**/
class NativeMacroModuleHostAbi {
	static inline final FIELD_SEPARATOR = "\t";

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
		expr:String
	} {
		final idx = line.indexOf(FIELD_SEPARATOR);
		if (idx <= 0 || idx + FIELD_SEPARATOR.length >= line.length)
			fail(sourceLabel, "invalid registration row at line " + lineNumber + " (expected pluginId<TAB>expr)");
		if (line.indexOf(FIELD_SEPARATOR, idx + FIELD_SEPARATOR.length) >= 0)
			fail(sourceLabel, "invalid registration row at line " + lineNumber + " (too many separators)");
		final pluginId = requireToken(line.substr(0, idx), "pluginId", sourceLabel);
		final expr = requireToken(line.substr(idx + FIELD_SEPARATOR.length), "expr", sourceLabel);
		return {
			pluginId: pluginId,
			expr: expr
		};
	}

	public static function decodeSnapshot(snapshot:String, sourceLabel:String):Array<{
		pluginId:String,
		expr:String
	}> {
		final raw = snapshot == null ? "" : snapshot;
		final lines = raw.split("\n");
		final rows = new Array<{
			pluginId:String,
			expr:String
		}>();
		var sawVersion = false;
		var lineNumber = 0;
		for (line in lines) {
			lineNumber++;
			final normalized = trim(trimTrailingCr(line));
			if (normalized.length == 0)
				continue;
			if (!sawVersion) {
				if (normalized != NativeMacroModuleAbi.SNAPSHOT_VERSION) {
					fail(sourceLabel, "invalid snapshot version `" + normalized + "` (expected `" + NativeMacroModuleAbi.SNAPSHOT_VERSION + "`)");
				}
				sawVersion = true;
				continue;
			}
			rows.push(decodeRow(normalized, lineNumber, sourceLabel));
		}

		if (!sawVersion)
			fail(sourceLabel, "snapshot is missing version header `" + NativeMacroModuleAbi.SNAPSHOT_VERSION + "`");
		return rows;
	}

	static function exprsForPluginInternal(snapshot:String, pluginId:String, sourceLabel:String, allowEmpty:Bool):Array<String> {
		final expectedPluginId = requireToken(pluginId, "pluginId", sourceLabel);
		final rows = decodeSnapshot(snapshot, sourceLabel);
		final out = new Array<String>();
		final seenExprs = new haxe.ds.StringMap<Bool>();
		for (row in rows) {
			if (row.pluginId != expectedPluginId) {
				fail(sourceLabel, "registration pluginId mismatch: expected `"
					+ expectedPluginId
					+ "`, got `"
					+ row.pluginId
					+ "` (expr `"
					+ row.expr
					+ "`)");
			}
			if (seenExprs.exists(row.expr))
				fail(sourceLabel, "duplicate expr registration `" + row.expr + "` for plugin `" + expectedPluginId + "`");
			seenExprs.set(row.expr, true);
			out.push(row.expr);
		}
		if (!allowEmpty && out.length == 0)
			fail(sourceLabel, "plugin `" + expectedPluginId + "` did not register any macro expressions");
		return out;
	}

	public static function exprsForPlugin(snapshot:String, pluginId:String, sourceLabel:String):Array<String> {
		return exprsForPluginInternal(snapshot, pluginId, sourceLabel, false);
	}

	public static function exprsForPluginAllowEmpty(snapshot:String, pluginId:String, sourceLabel:String):Array<String> {
		return exprsForPluginInternal(snapshot, pluginId, sourceLabel, true);
	}
}
