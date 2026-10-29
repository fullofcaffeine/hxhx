package backend.plugin;

import backend.BackendAbi;
import hxhx.CompilerJsonParser;
import hxhx.CompilerJsonValue;

private typedef JsonObject = haxe.ds.StringMap<CompilerJsonValue>;

/**
	Parses and validates backend plugin manifests from JSON text.

	Each schema field must match its decoded JSON variant before it reaches the
	plugin loader. Missing fields and wrong kinds produce source-labelled errors.
	Compatibility validation through `BackendAbi` runs before a manifest is returned.
**/
class BackendPluginManifestParser {
	public static inline var SCHEMA_VERSION:Int = 1;

	static inline function normalizeSourceLabel(sourceLabel:String):String {
		final s = sourceLabel == null ? "" : StringTools.trim(sourceLabel);
		return s.length == 0 ? "<unknown-source>" : s;
	}

	static inline function failureMessage(sourceLabel:String, message:String):String {
		return "invalid backend plugin manifest (" + normalizeSourceLabel(sourceLabel) + "): " + message;
	}

	static function requireObject(value:CompilerJsonValue, fieldPath:String, sourceLabel:String):JsonObject {
		return switch (value) {
			case JsonObject(fields): fields;
			case JsonNull: throw failureMessage(sourceLabel, "missing required object `" + fieldPath + "`");
			case _: throw failureMessage(sourceLabel, "field `" + fieldPath + "` must be an object");
		}
	}

	static function requireField(object:JsonObject, fieldName:String, fieldPath:String, sourceLabel:String):CompilerJsonValue {
		if (!object.exists(fieldName))
			throw failureMessage(sourceLabel, "missing required field `" + fieldPath + "`");
		return object.get(fieldName);
	}

	static function requireString(value:CompilerJsonValue, fieldPath:String, sourceLabel:String):String {
		final s = switch (value) {
			case JsonString(text): text;
			case _: throw failureMessage(sourceLabel, "field `" + fieldPath + "` must be a string");
		}
		final normalized = StringTools.trim(s);
		if (normalized.length == 0)
			throw failureMessage(sourceLabel, "field `" + fieldPath + "` must be a non-empty string");
		return normalized;
	}

	static function requireInt(value:CompilerJsonValue, fieldPath:String, sourceLabel:String):Int {
		switch (value) {
			case JsonInt(number):
				return number;
			case JsonFloat(number):
				final i = Std.int(number);
				final iAsFloat:Float = i;
				if (iAsFloat == number)
					return i;
			case _:
		}
		throw failureMessage(sourceLabel, "field `" + fieldPath + "` must be an integer");
	}

	static function requireStringArray(value:CompilerJsonValue, fieldPath:String, sourceLabel:String):Array<String> {
		final raw = switch (value) {
			case JsonArray(values): values;
			case _: throw failureMessage(sourceLabel, "field `" + fieldPath + "` must be an array of strings");
		}
		final out = new Array<String>();
		var index = 0;
		for (entry in raw) {
			final itemPath = fieldPath + "[" + index + "]";
			out.push(requireString(entry, itemPath, sourceLabel));
			index++;
		}
		return out;
	}

	static function parseKind(value:String, sourceLabel:String):BackendPluginManifestKind {
		return switch (value) {
			case BackendPluginManifestKind.LinkedProvider: BackendPluginManifestKind.LinkedProvider;
			case BackendPluginManifestKind.OcamlDynlink: BackendPluginManifestKind.OcamlDynlink;
			case _:
				throw failureMessage(sourceLabel, "unsupported backend kind `" + value + "` (supported: linked-provider, ocaml-dynlink)");
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
			throw failureMessage(source, "content is empty");

		final raw = try {
			CompilerJsonParser.parse(content);
		} catch (error:haxe.Exception) {
			throw failureMessage(source, "invalid JSON: " + error.message);
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
			throw failureMessage(source, validationError);

		return manifest;
	}
}
