package backend.vm;

import backend.BackendContext;
import backend.EmitResult;
import backend.GenIrProgram;

/**
	Native HashLink target boundary.

	Why
	- `--hl` already routes through Stage3 under `HXHX_FORBID_STAGE0=1`, but keeping it
	  behind the generic unsupported-target placeholder hides the real implementation
	  shape.
	- Unlike Neko, HashLink does not give us a useful text-source MVP seam. The product
	  path is a real `.hl` bytecode emitter plus runtime/toolchain evidence, not a fake
	  source-only file that would make the target look more complete than it is.

	What
	- Owns the HashLink target-core dispatch point.
	- Fails with a precise, implementation-level blocker until the bytecode writer
	  exists.

	How
	- Keep this boundary small until the first bytecode writer slice lands.
	- Future work should add focused smoke coverage for the smallest executable
	  HashLink module before expanding stdlib/runtime support.
**/
class HashLinkTargetCore {
	public static function emit(_program:GenIrProgram, _context:BackendContext):EmitResult {
		final detail = "HashLink output is binary .hl bytecode, so this target must implement a real bytecode writer/runtime contract "
			+ "rather than a source-only placeholder.";
		throw "HashLink native backend reached Stage3 dispatch, but hxhx does not yet have a HashLink bytecode emitter. " + detail;
	}
}
