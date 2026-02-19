import backend.BackendRegistry;
import backend.BackendRegistrationSpec;
import backend.ITargetBackendProvider;
import backend.TargetCoreBackend;

class M14BackendRegistryIntegrationTest {
	static function assertTrue(cond:Bool, message:String):Void {
		if (!cond) throw message;
	}

	static function has(values:Array<String>, target:String):Bool {
		for (v in values) if (v == target) return true;
		return false;
	}

	static function main():Void {
		BackendRegistry.clearDynamicRegistrations();

		final ids = BackendRegistry.supportedTargetIds();
		assertTrue(has(ids, "ocaml-stage3"), "backend registry missing ocaml-stage3 target id");
		assertTrue(has(ids, "js-native"), "backend registry missing js-native target id");

		final ocaml = BackendRegistry.descriptorForTarget("ocaml-stage3");
		assertTrue(ocaml != null, "descriptorForTarget(ocaml-stage3) returned null");
		assertTrue(ocaml.implId == "builtin/ocaml-stage3", "unexpected ocaml-stage3 implId");
		assertTrue(ocaml.requires.genIrVersion == 1, "unexpected ocaml-stage3 GenIR version");

		final js = BackendRegistry.descriptorForTarget("js-native");
		assertTrue(js != null, "descriptorForTarget(js-native) returned null");
		assertTrue(js.implId == "builtin/js-native", "unexpected js-native implId");
		assertTrue(js.requires.macroApiVersion == 1, "unexpected js-native macro API version");

		var unknownError = "";
		try {
			BackendRegistry.requireForTarget("does-not-exist");
		} catch (e:Dynamic) {
			unknownError = Std.string(e);
		}
		assertTrue(unknownError.length > 0, "requireForTarget should fail for unknown backend");
		assertTrue(unknownError.indexOf("does-not-exist") >= 0, "unknown backend error should include target id");
		assertTrue(unknownError.indexOf("ocaml-stage3") >= 0, "unknown backend error should list supported backends");

		final pluginRegistered = BackendRegistry.registerProvider((new _M14PluginProvider()).registrations());
		assertTrue(pluginRegistered == 1, "expected exactly one plugin registration");
		final jsAfterPlugin = BackendRegistry.descriptorForTarget("js-native");
		assertTrue(jsAfterPlugin != null, "descriptorForTarget(js-native) returned null after plugin registration");
		assertTrue(jsAfterPlugin.implId == "plugin/js-native@test", "plugin registration should win js-native selection by priority");
		final created = BackendRegistry.createForTarget("js-native");
		assertTrue(created != null, "createForTarget(js-native) should return plugin backend after registration");
		assertTrue(created.describe() == "Plugin JS backend for test", "unexpected backend factory selected for js-native");

		BackendRegistry.clearDynamicRegistrations();
		final jsAfterClear = BackendRegistry.descriptorForTarget("js-native");
		assertTrue(jsAfterClear != null, "descriptorForTarget(js-native) should resolve after clearing dynamic registrations");
		assertTrue(jsAfterClear.implId == "builtin/js-native", "clearing dynamic registrations should restore builtin js-native");
	}
}

private class _M14PluginProvider implements ITargetBackendProvider {
	public function new() {}

	public function registrations():Array<BackendRegistrationSpec> {
		final descriptor:backend.TargetDescriptor = {
			id: "js-native",
			implId: "plugin/js-native@test",
			abiVersion: 1,
			priority: 200,
			description: "Plugin JS backend for test",
			capabilities: {
				supportsNoEmit: true,
				supportsBuildExecutable: false,
				supportsCustomOutputFile: true
			},
			requires: {
				genIrVersion: 1,
				macroApiVersion: 1,
				hostCaps: []
			}
		};
		return [
			{
				descriptor: descriptor,
				create: function() return new TargetCoreBackend(
					descriptor,
					function(_program, _context) throw "noop core should not emit in this test"
				)
			}
		];
	}
}
