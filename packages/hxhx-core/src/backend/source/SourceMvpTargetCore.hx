package backend.source;

import backend.BackendContext;
import backend.EmitResult;
import backend.GenIrProgram;
import backend.source.SourceTargetCommon.SourceNativeTarget;

/**
	Shared MVP target-core entry for the source targets that still share one
	rendering path: Python, C#, and Lua.
**/
class SourceMvpTargetCore {
	public static function emit(target:SourceNativeTarget, program:GenIrProgram, context:BackendContext):EmitResult {
		return SourceTargetCommon.emitTarget(target, program, context);
	}
}
