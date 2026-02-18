package backend.ocaml;

import backend.BackendCapabilities;
import backend.BackendContext;
import backend.EmitResult;
import backend.GenIrProgram;
import backend.ITargetCore;
import backend.IBackend;
import backend.TargetDescriptor;
import backend.TargetCoreBackend;

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
	public static inline var ABI_VERSION = 1;
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
				genIrVersion: 1,
				macroApiVersion: 1,
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

	public static function targetCore():ITargetCore {
		return new OcamlTargetCore();
	}

	public function new() {
		delegate = new TargetCoreBackend(descriptor(), targetCore());
	}

	public function emit(program:GenIrProgram, context:BackendContext):EmitResult {
		return delegate.emit(program, context);
	}
}
