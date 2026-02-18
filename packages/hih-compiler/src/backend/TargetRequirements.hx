package backend;

/**
	Compatibility requirements declared by a backend implementation.

	Why
	- Target plugins/builtins must be selected against explicit compatibility boundaries
	  instead of ad-hoc assumptions.
	- This keeps backend loading deterministic as `hxhx` evolves toward a stable plugin ABI.

	What
	- `genIrVersion`: required codegen IR contract version.
	- `macroApiVersion`: required macro host/client contract version.
	- `hostCaps`: host capability tags required by the backend at runtime.

	How
	- Start intentionally minimal and additive.
	- New requirements should be appended as explicit fields rather than inferred from
	  backend IDs or target names.
**/
typedef TargetRequirements = {
	final genIrVersion:Int;
	final macroApiVersion:Int;
	final hostCaps:Array<String>;
}

