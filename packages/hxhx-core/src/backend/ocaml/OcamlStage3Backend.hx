package backend.ocaml;

import backend.BackendCapabilities;
import backend.BackendAbi;
import backend.BackendContext;
import backend.EmitResult;
import backend.GenIrProgram;
import backend.IBackend;
import backend.TargetDescriptor;
import backend.TargetCoreBackend;
import backend.reflaxe.ReflaxeTargetAdapter;

/**
	OCaml Stage3 backend adapter.

	Why
	- Stage3 already has a working OCaml emission/build path in `EmitterStage.emitToDir`.
	- We are extracting a backend seam, so this adapter preserves current behavior while
	  allowing the Stage3 driver to dispatch by backend ID.

	What
	- Delegates to `EmitterStage.emitToDir`.
	- Returns a structured `EmitResult` with one primary executable artifact.

	How
	- This is intentionally thin and behavior-preserving.
	- Any OCaml-specific emission logic remains in `EmitterStage` for now.
**/
class OcamlStage3Backend implements IBackend {
	public static inline var TARGET_ID = "ocaml-stage3";
	public static inline var IMPL_ID = "builtin/ocaml-stage3";
	public static inline var ABI_VERSION = BackendAbi.VERSION;
	public static inline var PRIORITY = 100;

	final delegate:TargetCoreBackend;

	public function id():String {
		return delegate.id();
	}

	public function describe():String {
		return delegate.describe();
	}

	public static function descriptor():TargetDescriptor {
		return {
			id: TARGET_ID,
			implId: IMPL_ID,
			abiVersion: ABI_VERSION,
			priority: PRIORITY,
			description: "Linked Stage3 OCaml emitter",
			capabilities: capabilitiesStatic(),
			requires: {
				genIrVersion: BackendAbi.GEN_IR_VERSION,
				macroApiVersion: BackendAbi.MACRO_API_VERSION,
				hostCaps: ["filesystem", "process", "ocaml", "dune"]
			}
		};
	}

	static function capabilitiesStatic():BackendCapabilities {
		return {
			supportsNoEmit: true,
			supportsBuildExecutable: true,
			supportsCustomOutputFile: false
		};
	}

	public function capabilities():BackendCapabilities {
		return delegate.capabilities();
	}

	public static function targetCore():OcamlTargetCore {
		return new OcamlTargetCore();
	}

	public static function targetCoreEmit():GenIrProgram->BackendContext->EmitResult {
		final core = targetCore();
		return function(program:GenIrProgram, context:BackendContext):EmitResult {
			return OcamlTargetCore.emitBridge(core, program, context);
		};
	}

	public static function emitBridge(backend:OcamlStage3Backend, program:GenIrProgram, context:BackendContext):EmitResult {
		return backend.emit(program, context);
	}

	public function new() {
		delegate = ReflaxeTargetAdapter.backend(descriptor(), targetCoreEmit);
	}

	public function emit(program:GenIrProgram, context:BackendContext):EmitResult {
		return delegate.emit(program, context);
	}
}
