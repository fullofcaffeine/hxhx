import backend.BackendAbi;
import backend.BackendContext;
import backend.BackendDispatchBoundary;
import backend.EmitArtifact;
import backend.EmitResult;
import backend.GenIrProgram;
import backend.IBackend;
import backend.TargetCoreBackend;

class M14BackendDispatchBoundaryIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function fixtureContext():BackendContext {
		return new BackendContext(".tmp/m14_backend_dispatch", null, "Main", true, false, new haxe.ds.StringMap<String>());
	}

	static function fixtureProgram():GenIrProgram {
		return new MacroExpandedProgram([], false, []);
	}

	static function main():Void {
		final context = fixtureContext();
		final program = fixtureProgram();

		final customBackend = new _M14CustomDispatchBackend();
		final customResult = BackendDispatchBoundary.emit(customBackend, program, context);
		assertTrue(customBackend.emitCalls == 1, "custom backend emit should run exactly once");
		assertTrue(customResult.entryPath == "custom-dispatch", "unexpected custom dispatch entry path");

		final descriptor:backend.TargetDescriptor = {
			id: "dispatch-fixture",
			implId: "plugin/dispatch-fixture",
			abiVersion: BackendAbi.VERSION,
			priority: 1,
			description: "Dispatch fixture backend",
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
		final targetCoreBackend = new TargetCoreBackend(descriptor, function(_program:GenIrProgram, _context:BackendContext):EmitResult {
			return new EmitResult("target-core-dispatch", [new EmitArtifact("entry", "target-core-dispatch.txt")], false);
		});
		final targetCoreResult = BackendDispatchBoundary.emit(targetCoreBackend, program, context);
		assertTrue(targetCoreResult.entryPath == "target-core-dispatch", "target-core bridge dispatch returned unexpected entry path");
	}
}

private class _M14CustomDispatchBackend implements IBackend {
	public var emitCalls(default, null):Int = 0;

	public function new() {}

	public function id():String {
		return "custom-dispatch";
	}

	public function describe():String {
		return "custom dispatch backend";
	}

	public function capabilities():backend.BackendCapabilities {
		return {
			supportsNoEmit: true,
			supportsBuildExecutable: false,
			supportsCustomOutputFile: true
		};
	}

	public function emit(_program:GenIrProgram, _context:BackendContext):EmitResult {
		emitCalls++;
		return new EmitResult("custom-dispatch", [new EmitArtifact("entry", "custom-dispatch.txt")], false);
	}
}
