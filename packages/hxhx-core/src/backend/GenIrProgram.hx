package backend;

/**
	Stage3 codegen IR contract (v0 alias).

	Why
	- Backend APIs should consume an explicit "codegen IR" type rather than exposing
	  internal compiler pipeline classes directly.
	- We need a migration-safe bridge while the dedicated backend-neutral IR is extracted.

	What
	- `GenIrProgram` is currently an alias to `MacroExpandedProgram` (v0).
	- Backends should treat this as the canonical codegen input contract.

	How
	- Keep the alias in one place so we can swap to a dedicated IR structure later with
	  minimal API churn.
**/
typedef GenIrProgram = MacroExpandedProgram;

