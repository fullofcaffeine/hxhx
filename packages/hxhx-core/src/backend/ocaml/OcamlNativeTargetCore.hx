package backend.ocaml;

import backend.BackendContext;
import backend.EmitArtifact;
import backend.EmitResult;
import backend.GenIrBoundary;
import backend.GenIrProgram;
import backend.ITargetCore;
import backend.OcamlProfile;
import haxe.io.Path;
import reflaxe.ocaml.target.OcamlTargetProgramCore;
import reflaxe.ocaml.target.OcamlTargetProgramCore.OcamlTargetProgramPublisher;

/**
	Native `hxhx` adapter for the standalone `reflaxe.ocaml` target core.

	The wrapper selects no OCaml syntax or runtime behavior. It copies sealed
	native facts, invokes the package-owned core, and publishes the returned plan.
**/
class OcamlNativeTargetCore implements ITargetCore {
	public function new() {}

	public static function emitBridge(core:OcamlNativeTargetCore, program:GenIrProgram, context:BackendContext):EmitResult
		return core.emit(program, context);

	public function coreId():String
		return OcamlTargetProgramCore.CORE_ID;

	public function emit(program:GenIrProgram, context:BackendContext):EmitResult {
		final typedProgram = GenIrBoundary.requireProgram(program);
		final profile = context.ensureOcamlProfileDefine();
		OcamlTargetProgramCore.requireProfile(OcamlProfile.toDefineValue(profile));
		final request = HxhxOcamlTargetProgramAdapter.fromProgram(typedProgram, context.mainModule);
		final plan = OcamlTargetProgramCore.lower(request);
		final executable = OcamlTargetProgramPublisher.publish(plan, context.outputDir, "native-hxhx", context.buildExecutable);
		final entryPath = context.buildExecutable ? executable : Path.join([context.outputDir, OcamlTargetProgramCore.REPORT_FILE]);
		return new EmitResult(entryPath, [
			new EmitArtifact("shared_target_report", Path.join([context.outputDir, OcamlTargetProgramCore.REPORT_FILE])),
			new EmitArtifact("shared_target_manifest", Path.join([context.outputDir, OcamlTargetProgramCore.MANIFEST_FILE])),
			new EmitArtifact(context.buildExecutable ? "entry_executable" : "entry_source", entryPath)
		], context.buildExecutable);
	}
}
