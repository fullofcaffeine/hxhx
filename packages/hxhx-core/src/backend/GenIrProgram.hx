package backend;

/**
	Names the typed program value passed from Stage3 into a backend.

	What it is today
	- `GenIrProgram` is an alias to `MacroExpandedProgram`.
	- It gives backend APIs one stable, readable name for their current input.

	What it is not
	- It is not a normalized or target-neutral IR.
	- Its name does not authorize moving target runtime behavior or backend-specific
	  lowering into a new shared compiler layer.

	Future rule
	- Introduce a separate IR only after two or more backends demonstrate the same
	  repeated transformation and behavior tests define the shared invariant.
**/
typedef GenIrProgram = MacroExpandedProgram;
