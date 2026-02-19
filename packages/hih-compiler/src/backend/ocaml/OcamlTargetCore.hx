package backend.ocaml;

import backend.BackendContext;
import backend.EmitArtifact;
import backend.EmitResult;
import backend.GenIrBoundary;
import backend.GenIrProgram;
import backend.ITargetCore;

/**
	Reusable OCaml target core.

	Why
	- `reflaxe.ocaml` should be promotable across activation modes (plugin/builtin)
	  without rewriting codegen logic.
	- The Stage3 OCaml builtin backend is our first promotion pilot.

	What
	- Provides one `emit(...)` entrypoint that wraps the existing OCaml Stage3 emitter.
	- Returns the same artifact shape currently expected by Stage3 callers.

	How
	- Keep behavior-preserving delegation to `EmitterStage.emitToDir`.
	- Wrapper backends can call this core directly.
**/
class OcamlTargetCore implements ITargetCore {
	public static inline var CORE_ID = "reflaxe.ocaml.target-core";

	public function new() {}

	public function coreId():String {
		return CORE_ID;
	}

	public function emit(program:GenIrProgram, context:BackendContext):EmitResult {
		final typedProgram = GenIrBoundary.requireProgram(program);
		final entryPath = EmitterStage.emitToDir(typedProgram, context.outputDir, context.emitFullBodies, context.buildExecutable);
		return new EmitResult(
			entryPath,
			[
				new EmitArtifact(context.buildExecutable ? "entry_executable" : "entry_planned_executable", entryPath)
			],
			context.buildExecutable
		);
	}
}
