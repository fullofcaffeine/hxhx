import backend.BackendAbi;
import backend.plugin.BackendPluginManifestKind;
import backend.plugin.BackendPluginManifestParser;
import hxhx.BackendPluginManifestResolver;

class M14BackendPluginManifestIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function assertFailsContains(fn:Void->Void, expected:String):Void {
		var message = "";
		try {
			fn();
		} catch (error:haxe.Exception) {
			message = error.message;
		}
		assertTrue(message.length > 0, "expected failing call with message containing: " + expected);
		assertTrue(message.indexOf(expected) >= 0, "error mismatch: " + message);
	}

	static function manifestJson(kind:String, entry:String, ?schemaVersion:Int, ?abiVersion:Int):String {
		final manifest = {
			schemaVersion: schemaVersion == null ? BackendPluginManifestParser.SCHEMA_VERSION : schemaVersion,
			pluginId: "fixture.backend.plugin",
			pluginVersion: "0.1.0",
			backend: {
				kind: kind,
				entry: entry,
				targetIds: ["js-native"]
			},
			requires: {
				abiVersion: abiVersion == null ? BackendAbi.VERSION : abiVersion,
				genIrVersion: BackendAbi.GEN_IR_VERSION,
				macroApiVersion: BackendAbi.MACRO_API_VERSION
			}
		};
		return haxe.Json.stringify(manifest);
	}

	static function writeManifest(path:String, content:String):Void {
		sys.io.File.saveContent(path, content);
	}

	static function deleteIfExists(path:String):Void {
		if (sys.FileSystem.exists(path) && !sys.FileSystem.isDirectory(path))
			sys.FileSystem.deleteFile(path);
	}

	static function ensureDir(path:String):Void {
		if (!sys.FileSystem.exists(path))
			sys.FileSystem.createDirectory(path);
	}

	static function main():Void {
		final parsed = BackendPluginManifestParser.parse(manifestJson("haxe-provider", "M14ResolverFixtureProvider"), "fixture://valid-haxe");
		assertTrue(parsed.schemaVersion == BackendPluginManifestParser.SCHEMA_VERSION, "unexpected schema version");
		assertTrue(parsed.backend.kind == BackendPluginManifestKind.HaxeProvider, "unexpected backend kind");
		assertTrue(parsed.backend.entry == "M14ResolverFixtureProvider", "unexpected backend entry");
		assertTrue(parsed.requires.abiVersion == BackendAbi.VERSION, "unexpected abiVersion");

		final parsedNative = BackendPluginManifestParser.parse(manifestJson("ocaml-cmxs", "plugin/backend.cmxs"), "fixture://valid-native");
		assertTrue(parsedNative.backend.kind == BackendPluginManifestKind.OcamlCmxs, "unexpected native backend kind");
		final parsedNativeBytecode = BackendPluginManifestParser.parse(manifestJson("ocaml-cmxs", "plugin/backend.cma"), "fixture://valid-native-bytecode");
		assertTrue(parsedNativeBytecode.backend.kind == BackendPluginManifestKind.OcamlCmxs, "unexpected native bytecode backend kind");
		final parsedWithTrailingWhitespace = BackendPluginManifestParser.parse(manifestJson("haxe-provider", "M14ResolverFixtureProvider") + "\n \t\r",
			"fixture://valid-trailing-whitespace");
		assertTrue(parsedWithTrailingWhitespace.pluginId == "fixture.backend.plugin", "unexpected pluginId with trailing whitespace");

		assertFailsContains(function() BackendPluginManifestParser.parse("{}", "fixture://missing-fields"), "missing required field `backend`");
		assertFailsContains(function() BackendPluginManifestParser.parse(haxe.Json.stringify({
			schemaVersion: "1",
			pluginId: "fixture.backend.plugin",
			pluginVersion: "0.1.0",
			backend: {
				kind: "haxe-provider",
				entry: "M14ResolverFixtureProvider",
				targetIds: ["js-native"]
			},
			requires: {
				abiVersion: BackendAbi.VERSION,
				genIrVersion: BackendAbi.GEN_IR_VERSION,
				macroApiVersion: BackendAbi.MACRO_API_VERSION
			}
		}), "fixture://bad-schema-type"), "schemaVersion");
		assertFailsContains(function() BackendPluginManifestParser.parse(manifestJson("haxe-provider", "M14ResolverFixtureProvider", null,
			BackendAbi.VERSION + 1), "fixture://abi-mismatch"),
			"backend ABI mismatch");
		assertFailsContains(function() BackendPluginManifestParser.parse(manifestJson("unknown", "M14ResolverFixtureProvider"), "fixture://unknown-kind"),
			"unsupported backend kind");
		assertFailsContains(function() BackendPluginManifestParser.parse(haxe.Json.stringify({
			schemaVersion: BackendPluginManifestParser.SCHEMA_VERSION,
			pluginId: "fixture.backend.plugin",
			pluginVersion: "0.1.0",
			backend: {
				kind: "haxe-provider",
				entry: "M14ResolverFixtureProvider",
				targetIds: []
			},
			requires: {
				abiVersion: BackendAbi.VERSION,
				genIrVersion: BackendAbi.GEN_IR_VERSION,
				macroApiVersion: BackendAbi.MACRO_API_VERSION
			}
		}), "fixture://empty-target-ids"), "targetIds");

		final rootTmp = ".tmp";
		final tmpDir = rootTmp + "/m14_backend_plugin_manifest";
		final haxeManifestPath = tmpDir + "/provider.json";
		final nativeManifestPath = tmpDir + "/native.json";
		ensureDir(rootTmp);
		ensureDir(tmpDir);
		deleteIfExists(haxeManifestPath);
		deleteIfExists(nativeManifestPath);

		writeManifest(haxeManifestPath, manifestJson("haxe-provider", "M14ResolverFixtureProvider"));
		final providerTypes = BackendPluginManifestResolver.providerTypeNamesForManifestPath(haxeManifestPath);
		assertTrue(providerTypes.length == 1, "expected one provider type from haxe-provider manifest");
		assertTrue(providerTypes[0] == "M14ResolverFixtureProvider", "unexpected provider type resolved from manifest");

		writeManifest(nativeManifestPath, manifestJson("ocaml-cmxs", "plugin/backend.cmxs"));
		assertFailsContains(function() BackendPluginManifestResolver.providerTypeNamesForManifestPath(nativeManifestPath),
			"native `.cmxs` loading requires an OCaml runtime build of hxhx");

		deleteIfExists(haxeManifestPath);
		deleteIfExists(nativeManifestPath);
	}
}
