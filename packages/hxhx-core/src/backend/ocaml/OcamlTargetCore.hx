package backend.ocaml;

import backend.BackendContext;
import backend.EmitArtifact;
import backend.EmitResult;
import backend.GenIrBoundary;
import backend.GenIrProgram;
import backend.ITargetCore;
import backend.OcamlProfile;

/**
	Compatibility wrapper around the independent Stage3 OCaml emitter.

	This class keeps the existing native bootstrap route available while the
	standalone `reflaxe.ocaml` target is adapted to native `hxhx` facts. Its ID
	intentionally names Stage3: delegation to `EmitterStage.emitToDir` is not
	evidence that both compiler hosts execute the standalone semantic target.
**/
class OcamlTargetCore implements ITargetCore {
	public static inline var CORE_ID = "hxhx.stage3.ocaml-emitter";

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
