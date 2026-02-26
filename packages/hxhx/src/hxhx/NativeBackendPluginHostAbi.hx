package hxhx;

import backend.BackendRegistrationSpec;

/**
	Typed Stage3 host registration ABI for native backend plugins.

	Why
	- Native plugin loading is an unavoidable runtime boundary.
	- We keep that boundary narrow by exchanging only encoded registration rows:
	  `pluginId<TAB>providerType`.
	- Everything after decoding (identity checks, duplicate checks, descriptor
	  conflict checks) is typed and deterministic in Haxe.

	Contract
	- Snapshot format:
	  - first non-empty line: `v1`
	  - each remaining line: `<pluginId>\t<providerType>`
	- Rows are plugin-local:
	  - Stage3 expects all rows to match the plugin currently being loaded.
	- Registration conflicts:
	  - duplicate provider type in one plugin is a hard error
	  - duplicate descriptor implId is a hard error
	  - duplicate descriptor target id across different implIds is a hard error

	Gotchas
	- Plugin IDs and provider types cannot contain tabs/newlines in this ABI.
	- This class intentionally does not use `Dynamic`.
**/
class NativeBackendPluginHostAbi {
	public static inline var SNAPSHOT_VERSION = "v1";
	static inline var FIELD_SEPARATOR = "\t";

	static inline function trim(value:String):String {
		return value == null ? "" : StringTools.trim(value);
	}

	static inline function normalizeSourceLabel(sourceLabel:String):String {
		final normalized = trim(sourceLabel);
		return normalized.length == 0 ? "<unknown-native-plugin-source>" : normalized;
	}

	static function fail(sourceLabel:String, message:String):Void {
		throw "native backend plugin registration (" + normalizeSourceLabel(sourceLabel) + "): " + message;
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
		if (token.indexOf("\n") >= 0 || token.indexOf("\r") >= 0 || token.indexOf(FIELD_SEPARATOR) >= 0) {
			fail(sourceLabel, field + " must not contain tab/newline characters");
		}
		return token;
	}

	static function decodeRow(line:String, lineNumber:Int, sourceLabel:String):{
		pluginId:String,
		providerType:String
	} {
		final idx = line.indexOf(FIELD_SEPARATOR);
		if (idx <= 0 || idx + FIELD_SEPARATOR.length >= line.length) {
			fail(sourceLabel, "invalid registration row at line " + lineNumber + " (expected pluginId<TAB>providerType)");
		}
		if (line.indexOf(FIELD_SEPARATOR, idx + FIELD_SEPARATOR.length) >= 0) {
			fail(sourceLabel, "invalid registration row at line " + lineNumber + " (too many separators)");
		}
		final pluginId = requireToken(line.substr(0, idx), "pluginId", sourceLabel);
		final providerType = requireToken(line.substr(idx + FIELD_SEPARATOR.length), "providerType", sourceLabel);
		return {
			pluginId: pluginId,
			providerType: providerType
		};
	}

	public static function decodeSnapshot(snapshot:String, sourceLabel:String):Array<{
		pluginId:String,
		providerType:String
	}> {
		final raw = snapshot == null ? "" : snapshot;
		final lines = raw.split("\n");
		final rows = new Array<{
			pluginId:String,
			providerType:String
		}>();
		var sawVersion = false;
		var lineNumber = 0;
		for (line in lines) {
			lineNumber++;
			final normalized = trim(trimTrailingCr(line));
			if (normalized.length == 0)
				continue;
			if (!sawVersion) {
				if (normalized != SNAPSHOT_VERSION)
					fail(sourceLabel, "invalid snapshot version `" + normalized + "` (expected `" + SNAPSHOT_VERSION + "`)");
				sawVersion = true;
				continue;
			}
			rows.push(decodeRow(normalized, lineNumber, sourceLabel));
		}

		if (!sawVersion)
			fail(sourceLabel, "snapshot is missing version header `" + SNAPSHOT_VERSION + "`");
		return rows;
	}

	public static function providerTypesForPlugin(snapshot:String, pluginId:String, sourceLabel:String, ?allowEmpty:Bool = false):Array<String> {
		final expectedPluginId = requireToken(pluginId, "pluginId", sourceLabel);
		final rows = decodeSnapshot(snapshot, sourceLabel);
		final out = new Array<String>();
		final seenProviderTypes = new haxe.ds.StringMap<Bool>();
		for (row in rows) {
			if (row.pluginId != expectedPluginId) {
				fail(sourceLabel,
					"registration pluginId mismatch: expected `"
					+ expectedPluginId
					+ "`, got `"
					+ row.pluginId
					+ "` (providerType `"
					+ row.providerType
					+ "`)");
			}
			if (seenProviderTypes.exists(row.providerType))
				fail(sourceLabel, "duplicate providerType registration `" + row.providerType + "` for plugin `" + expectedPluginId + "`");
			seenProviderTypes.set(row.providerType, true);
			out.push(row.providerType);
		}
		if (!allowEmpty && out.length == 0)
			fail(sourceLabel, "plugin `" + expectedPluginId + "` did not register any provider types");
		return out;
	}

	public static function captureProviderTypesForPlugin(pluginId:String, sourceLabel:String):Array<String> {
		final snapshot = NativeBackendPluginHost.snapshot();
		return providerTypesForPlugin(snapshot, pluginId, sourceLabel);
	}

	public static function beginCapture():Void {
		NativeBackendPluginHost.clear();
	}

	public static function assertNoDescriptorConflicts(pluginId:String, specs:Array<BackendRegistrationSpec>, sourceLabel:String):Void {
		final normalizedPluginId = requireToken(pluginId, "pluginId", sourceLabel);
		if (specs == null || specs.length == 0)
			fail(sourceLabel, "plugin `" + normalizedPluginId + "` did not provide backend registration specs");

		final seenImplIds = new haxe.ds.StringMap<Bool>();
		final targetToImpl = new haxe.ds.StringMap<String>();

		for (spec in specs) {
			if (spec == null || spec.descriptor == null || spec.create == null)
				fail(sourceLabel, "plugin `" + normalizedPluginId + "` produced invalid backend registration spec (descriptor/create required)");

			final descriptor = spec.descriptor;
			final implId = requireToken(descriptor.implId, "descriptor.implId", sourceLabel);
			final targetId = requireToken(descriptor.id, "descriptor.id", sourceLabel);
			if (seenImplIds.exists(implId))
				fail(sourceLabel, "plugin `" + normalizedPluginId + "` has duplicate implId `" + implId + "`");
			seenImplIds.set(implId, true);

			final existingTargetImpl = targetToImpl.get(targetId);
			if (existingTargetImpl == null) {
				targetToImpl.set(targetId, implId);
			} else if (existingTargetImpl != implId) {
				fail(sourceLabel,
					"plugin `"
					+ normalizedPluginId
					+ "` has duplicate target id `"
					+ targetId
					+ "` mapped to implIds `"
					+ existingTargetImpl
					+ "` and `"
					+ implId
					+ "`");
			}
		}
	}
}
