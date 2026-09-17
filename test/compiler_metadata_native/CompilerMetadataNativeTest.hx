import backend.plugin.BackendPluginManifestParser;

/** Runs decoded metadata through the same native readers used before plugin loading. */
class CompilerMetadataNativeTest {
	static function main():Void {
		M14CompilerJsonValueIntegrationTest.run();
		final manifest = BackendPluginManifestParser.parse('{"schemaVersion":1,"pluginId":"fixture.native-json","pluginVersion":"1",'
			+ '"backend":{"kind":"linked-provider","entry":"FixtureProvider","targetIds":["js-native"]},'
			+ '"requires":{"abiVersion":1,"genIrVersion":1,"macroApiVersion":1}}',
			"fixture://native-json");
		if (manifest.pluginId != "fixture.native-json" || manifest.backend.targetIds[0] != "js-native")
			throw "native plugin metadata changed";
		@:privateAccess M14NativeMacroModuleReceiptIntegrationTest.main();
		Sys.println("OK native compiler metadata");
	}
}
