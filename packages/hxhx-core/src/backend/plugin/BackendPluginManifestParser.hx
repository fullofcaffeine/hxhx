package backend.plugin;

import backend.BackendAbi;
import hxhx.CompilerJsonArray;
import hxhx.CompilerJsonParser;

private typedef JsonObject = haxe.DynamicAccess<Dynamic>;

/**
	Parses and validates backend plugin manifests from JSON text.

	Why
	- Stage3 loader paths need deterministic, human-readable validation failures for
	  missing/invalid plugin metadata.
	- JSON parsing is a runtime boundary; we constrain untyped values here and return
	  fully-typed manifest structures to the rest of the compiler.

	How
	- Parse JSON once at this boundary.
	- Convert all required fields to typed values with explicit checks.
	- Run compatibility validation (`BackendAbi`) before returning.

	Gotchas
	- `CompilerJsonParser` returns untyped values by design.
	- This parser is the only place where `Dynamic` JSON values are accepted for plugin
	  manifests; callers should use typed `BackendPluginManifest` values only.
**/
class BackendPluginManifestParser {
	public static inline var SCHEMA_VERSION:Int = 1;

	static inline function normalizeSourceLabel(sourceLabel:String):String {
		final s = sourceLabel == null ? "" : StringTools.trim(sourceLabel);
		return s.length == 0 ? "<unknown-source>" : s;
	}

	static inline function fail(sourceLabel:String, message:String):Dynamic {
		throw "invalid backend plugin manifest (" + normalizeSourceLabel(sourceLabel) + "): " + message;
	}

	static function requireObject(value:Dynamic, fieldPath:String, sourceLabel:String):JsonObject {
		if (value == null)
			fail(sourceLabel, "missing required object `" + fieldPath + "`");
		if (Std.isOfType(value, String) || Std.isOfType(value, Bool) || Std.isOfType(value, Int) || Std.isOfType(value, Float)
			|| Std.isOfType(value, Array) || Std.isOfType(value, CompilerJsonArray)) {
			fail(sourceLabel, "field `" + fieldPath + "` must be an object");
		}
		return cast value;
	}

	static function requireField(object:JsonObject, fieldName:String, fieldPath:String, sourceLabel:String):Dynamic {
		if (!object.exists(fieldName))
			fail(sourceLabel, "missing required field `" + fieldPath + "`");
		return object.get(fieldName);
	}

	static function requireString(value:Dynamic, fieldPath:String, sourceLabel:String):String {
		if (!Std.isOfType(value, String))
			fail(sourceLabel, "field `" + fieldPath + "` must be a string");
		final s:String = cast value;
		final normalized = StringTools.trim(s);
		if (normalized.length == 0)
			fail(sourceLabel, "field `" + fieldPath + "` must be a non-empty string");
		return normalized;
	}

	static function requireInt(value:Dynamic, fieldPath:String, sourceLabel:String):Int {
		if (Std.isOfType(value, Int))
			return cast value;
		if (Std.isOfType(value, Float)) {
			final f = Std.parseFloat(Std.string(value));
			final i = Std.int(f);
			final iAsFloat:Float = i;
			if (iAsFloat == f)
				return i;
		}
		fail(sourceLabel, "field `" + fieldPath + "` must be an integer");
		return -1;
	}

	static function requireStringArray(value:Dynamic, fieldPath:String, sourceLabel:String):Array<String> {
		var raw:Array<Dynamic>;
		if (Std.isOfType(value, CompilerJsonArray)) {
			raw = (cast value : CompilerJsonArray).values;
		} else if (Std.isOfType(value, Array)) {
			raw = cast value;
		} else {
			fail(sourceLabel, "field `" + fieldPath + "` must be an array of strings");
			raw = [];
		}
		final out = new Array<String>();
		var index = 0;
		for (entry in raw) {
			final itemPath = fieldPath + "[" + index + "]";
			if (!Std.isOfType(entry, String))
				fail(sourceLabel, "field `" + itemPath + "` must be a string");
			final normalized = StringTools.trim(cast entry);
			if (normalized.length == 0)
				fail(sourceLabel, "field `" + itemPath + "` must be a non-empty string");
			out.push(normalized);
			index++;
		}
		return out;
	}

	static function parseKind(value:String, sourceLabel:String):BackendPluginManifestKind {
		return switch (value) {
			case BackendPluginManifestKind.LinkedProvider: BackendPluginManifestKind.LinkedProvider;
			case BackendPluginManifestKind.OcamlDynlink: BackendPluginManifestKind.OcamlDynlink;
			case _:
				fail(sourceLabel, "unsupported backend kind `" + value + "` (supported: linked-provider, ocaml-dynlink)");
		}
	}

	public static function validate(manifest:BackendPluginManifest):Null<String> {
		if (manifest == null)
			return "manifest is required";

		if (manifest.schemaVersion != SCHEMA_VERSION)
			return "schemaVersion mismatch: expected " + SCHEMA_VERSION + ", got " + manifest.schemaVersion;

		final pluginId = manifest.pluginId == null ? "" : StringTools.trim(manifest.pluginId);
		if (pluginId.length == 0)
			return "pluginId must be a non-empty string";

		final pluginVersion = manifest.pluginVersion == null ? "" : StringTools.trim(manifest.pluginVersion);
		if (pluginVersion.length == 0)
			return "pluginVersion must be a non-empty string";

		if (manifest.backend == null)
			return "backend section is required";

		final entry = manifest.backend.entry == null ? "" : StringTools.trim(manifest.backend.entry);
		if (entry.length == 0)
			return "backend.entry must be a non-empty string";

		if (manifest.backend.targetIds == null || manifest.backend.targetIds.length == 0)
			return "backend.targetIds must contain at least one target id";

		final seenTargetIds = new haxe.ds.StringMap<Bool>();
		var targetIndex = 0;
		for (targetId in manifest.backend.targetIds) {
			final normalized = targetId == null ? "" : StringTools.trim(targetId);
			if (normalized.length == 0)
				return "backend.targetIds[" + targetIndex + "] must be a non-empty string";
			if (seenTargetIds.exists(normalized))
				return "backend.targetIds contains duplicate value `" + normalized + "`";
			seenTargetIds.set(normalized, true);
			targetIndex++;
		}

		if (manifest.requires == null)
			return "requires section is required";

		final requiresError = BackendAbi.validateManifestRequires(pluginId, manifest.requires.abiVersion, manifest.requires.genIrVersion,
			manifest.requires.macroApiVersion);
		if (requiresError != null)
			return requiresError;

		switch (manifest.backend.kind) {
			case BackendPluginManifestKind.LinkedProvider:
				return null;
			case BackendPluginManifestKind.OcamlDynlink:
				if (!StringTools.endsWith(entry, ".cmxs") && !StringTools.endsWith(entry, ".cma"))
					return "backend.entry must end with `.cmxs` or `.cma` for kind `ocaml-dynlink`";
				return null;
			case _:
				return "unsupported backend kind `" + manifest.backend.kind + "`";
		}
	}

	public static function parse(content:String, sourceLabel:String):BackendPluginManifest {
		final source = normalizeSourceLabel(sourceLabel);
		if (content == null || StringTools.trim(content).length == 0)
			fail(source, "content is empty");

		final raw:Dynamic = try {
			CompilerJsonParser.parse(content);
		} catch (error:Dynamic) {
			fail(source, "invalid JSON: " + Std.string(error));
		}

		final root = requireObject(raw, "$", source);
		final backendObj = requireObject(requireField(root, "backend", "backend", source), "backend", source);
		final requiresObj = requireObject(requireField(root, "requires", "requires", source), "requires", source);
		final kind = parseKind(requireString(requireField(backendObj, "kind", "backend.kind", source), "backend.kind", source), source);

		final manifest:BackendPluginManifest = {
			schemaVersion: requireInt(requireField(root, "schemaVersion", "schemaVersion", source), "schemaVersion", source),
			pluginId: requireString(requireField(root, "pluginId", "pluginId", source), "pluginId", source),
			pluginVersion: requireString(requireField(root, "pluginVersion", "pluginVersion", source), "pluginVersion", source),
			backend: {
				kind: kind,
				entry: requireString(requireField(backendObj, "entry", "backend.entry", source), "backend.entry", source),
				targetIds: requireStringArray(requireField(backendObj, "targetIds", "backend.targetIds", source), "backend.targetIds", source)
			},
			requires: {
				abiVersion: requireInt(requireField(requiresObj, "abiVersion", "requires.abiVersion", source), "requires.abiVersion", source),
				genIrVersion: requireInt(requireField(requiresObj, "genIrVersion", "requires.genIrVersion", source), "requires.genIrVersion", source),
				macroApiVersion: requireInt(requireField(requiresObj, "macroApiVersion", "requires.macroApiVersion", source), "requires.macroApiVersion",
					source)
			}
		};

		final validationError = validate(manifest);
		if (validationError != null)
			fail(source, validationError);

		return manifest;
	}
}
