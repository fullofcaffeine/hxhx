package backend.js;

import backend.BackendCapabilities;
import backend.BackendContext;
import backend.EmitResult;
import backend.IBackend;

/**
	Stage3 JS backend placeholder (`js-native`).

	Why
	- We want to expose the non-delegating JS target preset now, while making the
	  backend status explicit and fail-fast until semantic lowering/printer work lands.

	What
	- Advertises JS backend identity and capabilities.
	- Throws a clear error from `emit(...)` so callers never silently fall back to stage0.

	How
	- Keep this as a minimal, explicit placeholder.
	- Replace with a real implementation in follow-up phases.
**/
class JsBackend implements IBackend {
	public function new() {}

	public function id():String {
		return "js-native";
	}

	public function describe():String {
		return "Native JS backend (placeholder)";
	}

	public function capabilities():BackendCapabilities {
		return {
			supportsNoEmit: true,
			supportsBuildExecutable: false,
			supportsCustomOutputFile: true
		};
	}

	public function emit(_:MacroExpandedProgram, _:BackendContext):EmitResult {
		throw "JS native backend is not implemented yet (target js-native)";
	}
}

