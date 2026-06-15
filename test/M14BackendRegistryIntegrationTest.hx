import backend.BackendAbi;
import backend.BackendRegistry;
import backend.BackendRegistrationSpec;
import backend.ITargetBackendProvider;
import backend.TargetCoreBackend;

class M14BackendRegistryIntegrationTest {
	static function assertTrue(cond:Bool, message:String):Void {
		if (!cond)
			throw message;
	}

	static function assertFailsContains(fn:Void->Void, expected:String):Void {
		var message = "";
		try {
			fn();
		} catch (e:haxe.Exception) {
			message = e.message;
		}
		assertTrue(message.length > 0, "expected failing call with message containing: " + expected);
		assertTrue(message.indexOf(expected) >= 0, "error mismatch: " + message);
	}

	static function has(values:Array<String>, target:String):Bool {
		for (v in values)
			if (v == target)
				return true;
		return false;
	}

	static function compatSpec(implId:String, abiVersion:Int, genIrVersion:Int, macroApiVersion:Int, hostCaps:Array<String>):BackendRegistrationSpec {
		final descriptor:backend.TargetDescriptor = {
			id: "compat-fixture",
			implId: implId,
			abiVersion: abiVersion,
			priority: 10,
			description: "ABI compatibility fixture",
			capabilities: {
				supportsNoEmit: true,
				supportsBuildExecutable: false,
				supportsCustomOutputFile: true
			},
			requires: {
				genIrVersion: genIrVersion,
				macroApiVersion: macroApiVersion,
				hostCaps: hostCaps
			}
		};
		return {
			descriptor: descriptor,
			create: function() return new TargetCoreBackend(descriptor, function(_program, _context) throw "compat fixture should not emit")
		};
	}

	static function main():Void {
		BackendRegistry.clearDynamicRegistrations();

		final ids = BackendRegistry.supportedTargetIds();
		assertTrue(has(ids, "ocaml-stage3"), "backend registry missing ocaml-stage3 target id");
		assertTrue(has(ids, "js-native"), "backend registry missing js-native target id");
		assertTrue(has(ids, "neko-native"), "backend registry missing neko-native target id");
		assertTrue(has(ids, "hl-native"), "backend registry missing hl-native target id");
		assertTrue(has(ids, "cpp-native"), "backend registry missing cpp-native target id");

		final ocaml = BackendRegistry.descriptorForTarget("ocaml-stage3");
		assertTrue(ocaml != null, "descriptorForTarget(ocaml-stage3) returned null");
		assertTrue(ocaml.implId == "builtin/ocaml-stage3", "unexpected ocaml-stage3 implId");
		assertTrue(ocaml.requires.genIrVersion == BackendAbi.GEN_IR_VERSION, "unexpected ocaml-stage3 GenIR version");

		final js = BackendRegistry.descriptorForTarget("js-native");
		assertTrue(js != null, "descriptorForTarget(js-native) returned null");
		assertTrue(js.implId == "builtin/js-native", "unexpected js-native implId");
		assertTrue(js.requires.macroApiVersion == BackendAbi.MACRO_API_VERSION, "unexpected js-native macro API version");

		final neko = BackendRegistry.descriptorForTarget("neko-native");
		assertTrue(neko != null, "descriptorForTarget(neko-native) returned null");
		assertTrue(neko.implId == "builtin/neko-native-source-mvp", "unexpected neko-native implId");

		final hl = BackendRegistry.descriptorForTarget("hl-native");
		assertTrue(hl != null, "descriptorForTarget(hl-native) returned null");
		assertTrue(hl.implId == "builtin/hl-native-placeholder", "unexpected hl-native implId");

		final cpp = BackendRegistry.descriptorForTarget("cpp-native");
		assertTrue(cpp != null, "descriptorForTarget(cpp-native) returned null");
		assertTrue(cpp.implId == "builtin/cpp-native-placeholder", "unexpected cpp-native implId");

		final python = BackendRegistry.descriptorForTarget("python-native");
		assertTrue(python != null, "descriptorForTarget(python-native) returned null");
		assertTrue(python.implId == "builtin/python-native-source-mvp", "unexpected python-native implId");

		final java = BackendRegistry.descriptorForTarget("java-native");
		assertTrue(java != null, "descriptorForTarget(java-native) returned null");
		assertTrue(java.implId == "builtin/java-native-source-mvp", "unexpected java-native implId");

		final cs = BackendRegistry.descriptorForTarget("cs-native");
		assertTrue(cs != null, "descriptorForTarget(cs-native) returned null");
		assertTrue(cs.implId == "builtin/cs-native-source-mvp", "unexpected cs-native implId");

		final php = BackendRegistry.descriptorForTarget("php-native");
		assertTrue(php != null, "descriptorForTarget(php-native) returned null");
		assertTrue(php.implId == "builtin/php-native-source-mvp", "unexpected php-native implId");

		final lua = BackendRegistry.descriptorForTarget("lua-native");
		assertTrue(lua != null, "descriptorForTarget(lua-native) returned null");
		assertTrue(lua.implId == "builtin/lua-native-source-mvp", "unexpected lua-native implId");

		assertFailsContains(function() BackendRegistry.requireForTarget("does-not-exist"), "does-not-exist");
		assertFailsContains(function() BackendRegistry.requireForTarget("does-not-exist"), "ocaml-stage3");

		assertFailsContains(function() BackendRegistry.register(compatSpec("plugin/compat-abi-mismatch", BackendAbi.VERSION + 1, BackendAbi.GEN_IR_VERSION,
			BackendAbi.MACRO_API_VERSION, ["filesystem"])),
			"backend ABI mismatch");

		assertFailsContains(function() BackendRegistry.register(compatSpec("plugin/compat-genir-mismatch", BackendAbi.VERSION, BackendAbi.GEN_IR_VERSION + 1,
			BackendAbi.MACRO_API_VERSION, ["filesystem"])),
			"backend GenIR mismatch");

		assertFailsContains(function() BackendRegistry.register(compatSpec("plugin/compat-macro-mismatch", BackendAbi.VERSION, BackendAbi.GEN_IR_VERSION,
			BackendAbi.MACRO_API_VERSION + 1, ["filesystem"])),
			"backend macro API mismatch");

		assertFailsContains(function() BackendRegistry.register(compatSpec("plugin/compat-hostcap-invalid", BackendAbi.VERSION, BackendAbi.GEN_IR_VERSION,
			BackendAbi.MACRO_API_VERSION, ["filesystem", ""])),
			"invalid backend host capability");

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
			abiVersion: BackendAbi.VERSION,
			priority: 200,
			description: "Plugin JS backend for test",
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
		};
		return [
			{
				descriptor: descriptor,
				create: function() return new TargetCoreBackend(descriptor, function(_program, _context) throw "noop core should not emit in this test")
			}
		];
	}
}
