package backend.source;

import backend.BackendContext;
import backend.EmitResult;
import backend.GenIrProgram;

/**
	Dedicated Java source-target entry module.

	This owns the Java backend seam at the registration layer even though the
	shared support module still provides the underlying renderer and packaging
	helper implementation for this first extraction slice.
**/
class JavaSourceTargetCore {
	public static function emit(program:GenIrProgram, context:BackendContext):EmitResult {
		return SourceTargetCommon.emitTarget(Java, program, context);
	}
}
