package backend;

/**
	Backend interface for Stage3 emission.

	Why
	- Stage3 currently hardcodes OCaml emission (`EmitterStage.emitToDir`), which blocks
	  incremental addition of non-OCaml builtin targets.
	- We need a narrow backend seam so the compiler driver can choose a target backend
	  without branching on target-specific internals.

	What
	- `id()`: stable backend identifier used by target presets/dispatch.
	- `describe()`: human-readable short description for diagnostics.
	- `capabilities()`: explicit capability flags consumed by driver logic.
	- `emit(...)`: perform target emission/build and return structured artifacts.

	How
	- Keep this interface focused on Stage3 use-cases.
	- Do not pull macro/plugin behavior into this layer; those remain in Stage4 pipeline code.
**/
interface IBackend {
	public function id():String;
	public function describe():String;
	public function capabilities():BackendCapabilities;
	public function emit(program:MacroExpandedProgram, context:BackendContext):EmitResult;
}

