package backend.source;

import backend.BackendContext;
import backend.EmitResult;
import backend.GenIrProgram;

/**
	Dedicated PHP source-target entry module.

	This owns the PHP backend seam at the registration layer even though the
	shared support module still provides the underlying renderer/runtime helper
	implementation for this first extraction slice.
**/
class PhpSourceTargetCore {
	public static function emit(program:GenIrProgram, context:BackendContext):EmitResult {
		return SourceTargetCommon.emitPhpTarget(program, context);
	}
}
