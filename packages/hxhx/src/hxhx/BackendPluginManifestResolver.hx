package hxhx;

import backend.plugin.BackendPluginManifest;
import backend.plugin.BackendPluginManifestKind;
import backend.plugin.BackendPluginManifestParser;

/**
	Resolves backend provider type names from plugin manifest files.

	Why
	- Stage3 accepts dynamic backend declarations at request time.
	- Plugin manifests provide a stable load contract that can represent both current
	  Haxe-provider plugins and future native `.cmxs` plugins.

	How
	- Read and parse manifest JSON using `BackendPluginManifestParser`.
	- Convert manifest entries to provider type names for current Stage3 loading.
	- Fail fast on unsupported activation kinds so users get explicit migration errors.
**/
class BackendPluginManifestResolver {
	static inline function normalizePath(manifestPath:String):String {
		return manifestPath == null ? "" : StringTools.trim(manifestPath);
	}

	static inline function fail(manifestPath:String, message:String):Dynamic {
		final source = normalizePath(manifestPath);
		final label = source.length == 0 ? "<unknown-manifest>" : source;
		throw "backend plugin manifest (" + label + "): " + message;
	}

	public static function providerTypeNamesForManifest(manifest:BackendPluginManifest, sourceLabel:String):Array<String> {
		switch (manifest.backend.kind) {
			case BackendPluginManifestKind.HaxeProvider:
				return [manifest.backend.entry];
			case BackendPluginManifestKind.OcamlCmxs:
				return NativeBackendPluginLoader.providerTypeNamesForNativeManifest(manifest, sourceLabel);
			case _:
				fail(sourceLabel, "unsupported backend kind `" + manifest.backend.kind + "`");
		}
		return [];
	}

	public static function providerTypeNamesForManifestPath(manifestPath:String):Array<String> {
		final normalized = normalizePath(manifestPath);
		if (normalized.length == 0)
			fail(manifestPath, "path is required");
		if (!sys.FileSystem.exists(normalized))
			fail(normalized, "path not found");
		if (sys.FileSystem.isDirectory(normalized))
			fail(normalized, "path must point to a file");

		final raw = try {
			sys.io.File.getContent(normalized);
		} catch (error:haxe.Exception) {
			fail(normalized, "failed to read manifest: " + error.message);
		}
		final manifest = BackendPluginManifestParser.parse(raw, normalized);
		return providerTypeNamesForManifest(manifest, normalized);
	}
}
