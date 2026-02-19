package backend;

/**
	Target-core emission contract.

	Why
	- We want backend promotion (plugin wrapper -> builtin wrapper) to be a packaging
	  change instead of a full codegen rewrite.
	- A shared target-core contract makes that split explicit.

	What
	- `coreId()`: stable identifier for the reusable target core implementation.
	- `emit(...)`: pure emit entrypoint over `GenIrProgram` + `BackendContext`.

	How
	- Keep target-core APIs small and data-oriented.
	- Wrapper backends (`IBackend`) should delegate to a target core where practical.
**/
interface ITargetCore {
	public function coreId():String;
	public function emit(program:GenIrProgram, context:BackendContext):EmitResult;
}

