import backend.BackendAbi;
import backend.BackendContext;
import backend.EmitArtifact;
import backend.EmitResult;
import backend.GenIrProgram;
import backend.TargetCoreBackend;
import backend.reflaxe.ReflaxeTargetAdapter;
import backend.js.JsBackend;
import backend.ocaml.OcamlStage3Backend;

class M14ReflaxeTargetAdapterIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function main():Void {
		final descriptor:backend.TargetDescriptor = {
			id: "fixture-target",
			implId: "plugin/fixture-target@adapter",
			abiVersion: BackendAbi.VERSION,
			priority: 250,
			description: "Fixture reflaxe adapter backend",
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

		final wrapped = ReflaxeTargetAdapter.backend(descriptor, fixtureCoreEmitFactory);
		assertTrue(wrapped.id() == descriptor.id, "adapter backend should expose descriptor id");
		assertTrue(wrapped.describe() == descriptor.description, "adapter backend should expose descriptor description");
		assertTrue(wrapped.capabilities().supportsNoEmit, "adapter backend should preserve descriptor capabilities");

		final regs = ReflaxeTargetAdapter.registrations(descriptor, fixtureCoreEmitFactory);
		assertTrue(regs.length == 1, "adapter registrations should emit a single registration");
		final created = regs[0].create();
		assertTrue(Std.isOfType(created, TargetCoreBackend), "adapter registration should create TargetCoreBackend wrapper");
		assertTrue(created.id() == descriptor.id, "adapter registration should preserve backend id");

		final jsProviderRegs = JsBackend.providerRegistrations();
		assertTrue(jsProviderRegs.length == 1, "js backend provider should expose one adapter registration");
		assertTrue(jsProviderRegs[0].descriptor.implId == JsBackend.PROVIDER_IMPL_ID, "js backend provider implId should match descriptor");
		assertTrue(jsProviderRegs[0].create().id() == JsBackend.TARGET_ID, "js backend provider registration should create js-native backend");

		final ocamlBackend = new OcamlStage3Backend();
		assertTrue(ocamlBackend.id() == OcamlStage3Backend.TARGET_ID, "ocaml backend should remain constructible through adapter path");
	}

	static function fixtureCoreEmitFactory():GenIrProgram->BackendContext->EmitResult {
		final core = new _FixtureCore();
		return function(program:GenIrProgram, context:BackendContext):EmitResult {
			return _FixtureCore.emitBridge(core, program, context);
		};
	}
}

private class _FixtureCore {
	public static inline var CORE_ID = "fixture.target-core";

	public function new() {}

	public function coreId():String {
		return CORE_ID;
	}

	public static function emitBridge(core:_FixtureCore, program:GenIrProgram, context:BackendContext):EmitResult {
		return core.emit(program, context);
	}

	public function emit(_program:GenIrProgram, _context:BackendContext):EmitResult {
		return new EmitResult("fixture.out", [new EmitArtifact("fixture", "fixture.out")], false);
	}
}
