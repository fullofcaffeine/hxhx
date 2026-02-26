import backend.BackendAbi;
import backend.BackendRegistrationSpec;
import backend.IBackend;
import backend.js.JsBackend;
import hxhx.NativeBackendPluginHostAbi;

class M14NativeBackendPluginHostAbiIntegrationTest {
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

	static function createBackend():IBackend {
		return new JsBackend();
	}

	static function spec(targetId:String, implId:String):BackendRegistrationSpec {
		return {
			descriptor: {
				id: targetId,
				implId: implId,
				abiVersion: BackendAbi.VERSION,
				priority: 100,
				description: "fixture",
				capabilities: {
					supportsNoEmit: true,
					supportsBuildExecutable: false,
					supportsCustomOutputFile: true
				},
				requires: {
					genIrVersion: BackendAbi.GEN_IR_VERSION,
					macroApiVersion: BackendAbi.MACRO_API_VERSION,
					hostCaps: []
				}
			},
			create: createBackend
		};
	}

	static function main():Void {
		final snapshot = "v1\nfixture.native.plugin\tM14ResolverFixtureProvider\n";
		final providers = NativeBackendPluginHostAbi.providerTypesForPlugin(snapshot, "fixture.native.plugin", "fixture://native-plugin-host");
		assertTrue(providers.length == 1, "expected one provider type");
		assertTrue(providers[0] == "M14ResolverFixtureProvider", "unexpected provider type");

		assertFailsContains(function() NativeBackendPluginHostAbi.providerTypesForPlugin("v1\n", "fixture.native.plugin", "fixture://empty"),
			"did not register any provider types");
		assertFailsContains(function() NativeBackendPluginHostAbi.providerTypesForPlugin("v1\nother.plugin\tM14ResolverFixtureProvider\n",
			"fixture.native.plugin", "fixture://mismatch"),
			"registration pluginId mismatch");
		assertFailsContains(function()
			NativeBackendPluginHostAbi.providerTypesForPlugin("v1\nfixture.native.plugin\tM14ResolverFixtureProvider\nfixture.native.plugin\tM14ResolverFixtureProvider\n",
				"fixture.native.plugin",
			"fixture://duplicate"),
			"duplicate providerType registration");

		NativeBackendPluginHostAbi.assertNoDescriptorConflicts("fixture.native.plugin", [spec("js-native", "plugin/a"), spec("ocaml-stage3", "plugin/b")],
			"fixture://descriptor-ok");
		assertFailsContains(function() NativeBackendPluginHostAbi.assertNoDescriptorConflicts("fixture.native.plugin",
			[spec("js-native", "plugin/a"), spec("ocaml-stage3", "plugin/a")], "fixture://duplicate-impl"),
			"duplicate implId");
		assertFailsContains(function() NativeBackendPluginHostAbi.assertNoDescriptorConflicts("fixture.native.plugin",
			[spec("js-native", "plugin/a"), spec("js-native", "plugin/b")], "fixture://duplicate-target"),
			"duplicate target id");
	}
}
