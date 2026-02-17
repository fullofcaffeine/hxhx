package backend.ocaml;

import backend.BackendCapabilities;
import backend.BackendContext;
import backend.EmitArtifact;
import backend.EmitResult;
import backend.IBackend;

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
	public function new() {}

	public function id():String {
		return "ocaml-stage3";
	}

	public function describe():String {
		return "Linked Stage3 OCaml emitter";
	}

	public function capabilities():BackendCapabilities {
		return {
			supportsNoEmit: true,
			supportsBuildExecutable: true,
			supportsCustomOutputFile: false
		};
	}

	public function emit(program:MacroExpandedProgram, context:BackendContext):EmitResult {
		final entryPath = EmitterStage.emitToDir(program, context.outputDir, context.emitFullBodies, context.buildExecutable);
		return new EmitResult(
			entryPath,
			[
				new EmitArtifact(context.buildExecutable ? "entry_executable" : "entry_planned_executable", entryPath)
			],
			context.buildExecutable
		);
	}
}

