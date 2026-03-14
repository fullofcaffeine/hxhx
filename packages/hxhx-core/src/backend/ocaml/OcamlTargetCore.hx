package backend.ocaml;

import backend.BackendContext;
import backend.EmitArtifact;
import backend.EmitResult;
import backend.GenIrBoundary;
import backend.GenIrProgram;
import backend.ITargetCore;
import backend.OcamlProfile;

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

	static inline function traceEnabled():Bool {
		final raw = Sys.getEnv("HXHX_TRACE_STAGE3_DRIVER");
		if (raw == null)
			return false;
		final s = StringTools.trim(raw).toLowerCase();
		return s == "1" || s == "true" || s == "yes" || s == "on";
	}

	public static function emitBridge(core:OcamlTargetCore, program:GenIrProgram, context:BackendContext):EmitResult {
		return core.emit(program, context);
	}

	public function coreId():String {
		return CORE_ID;
	}

	public function emit(program:GenIrProgram, context:BackendContext):EmitResult {
		final profile = context.ensureOcamlProfileDefine();
		if (traceEnabled())
			Sys.println("stage3_driver=ocaml_target_core_before_require_program");
		final typedProgram = GenIrBoundary.requireProgram(program);
		if (traceEnabled())
			Sys.println("stage3_driver=ocaml_target_core_after_require_program");
		if (profile == OcamlProfile.Metal) {
			if (traceEnabled())
				Sys.println("stage3_driver=ocaml_target_core_before_metal_verify");
			MetalProfileVerifier.verifyProgram(typedProgram);
			if (traceEnabled())
				Sys.println("stage3_driver=ocaml_target_core_after_metal_verify");
		}
		if (traceEnabled())
			Sys.println("stage3_driver=ocaml_target_core_before_plan");
		final portableMetalizationPlan = PortableMetalizationPlanner.buildPlan(typedProgram, profile);
		if (traceEnabled())
			Sys.println("stage3_driver=ocaml_target_core_after_plan");
		if (traceEnabled())
			Sys.println("stage3_driver=ocaml_target_core_before_emitter");
		final planScope = EmitterStage.installPortableMetalizationPlan(portableMetalizationPlan);
		final entryPath = try {
			if (traceEnabled())
				Sys.println("stage3_driver=ocaml_target_core_before_emitToDir_direct");
			final emitTypedProgram = typedProgram;
			if (traceEnabled())
				Sys.println("stage3_driver=ocaml_target_core_after_emit_arg_typedProgram modules=" + emitTypedProgram.getTypedModules().length);
			final emitOutDir = context.outputDir;
			if (traceEnabled())
				Sys.println("stage3_driver=ocaml_target_core_after_emit_arg_outDir value=" + emitOutDir);
			final emitFullBodies = context.emitFullBodies;
			if (traceEnabled())
				Sys.println("stage3_driver=ocaml_target_core_after_emit_arg_emitFullBodies value=" + emitFullBodies);
			final emitBuildExecutable = context.buildExecutable;
			if (traceEnabled())
				Sys.println("stage3_driver=ocaml_target_core_after_emit_arg_buildExecutable value=" + emitBuildExecutable);
			final emitProfile = profile;
			if (traceEnabled())
				Sys.println("stage3_driver=ocaml_target_core_after_emit_arg_profile value=" + backend.OcamlProfile.toDefineValue(emitProfile));
			final path = EmitterStage.emitToDir(emitTypedProgram, emitOutDir, emitFullBodies, emitBuildExecutable, emitProfile);
			if (traceEnabled())
				Sys.println("stage3_driver=ocaml_target_core_after_emitToDir_direct");
			path;
		} catch (error:haxe.Exception) {
			EmitterStage.restorePortableMetalizationPlan(planScope);
			throw error;
		}
		EmitterStage.restorePortableMetalizationPlan(planScope);
		if (traceEnabled())
			Sys.println("stage3_driver=ocaml_target_core_after_emitter");
		if (traceEnabled())
			Sys.println("stage3_driver=ocaml_target_core_before_plan_report");
		final portableMetalizationReportPath = PortableMetalizationPlanner.writeReport(context.outputDir, portableMetalizationPlan);
		if (traceEnabled())
			Sys.println("stage3_driver=ocaml_target_core_after_plan_report");
		return new EmitResult(entryPath, [
			new EmitArtifact(context.buildExecutable ? "entry_executable" : "entry_planned_executable", entryPath),
			new EmitArtifact("portable_metalization_report", portableMetalizationReportPath)
		], context.buildExecutable);
	}
}
