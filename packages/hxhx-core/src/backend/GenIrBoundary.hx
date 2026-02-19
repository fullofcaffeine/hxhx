package backend;

/**
	Centralized `GenIrProgram` boundary recovery helper.

	Why
	- In reflaxe-generated OCaml, interface calls can materialize strongly-typed Haxe
	  parameters as `Obj.t` at dispatch boundaries.
	- Backends must recover the concrete `GenIrProgram` type once at that seam so
	  downstream emit logic remains statically typed.

	Policy
	- This is the only allowed `Dynamic` boundary for `program` recovery in backend
	  target-core emit paths.
	- Do not duplicate local `program` recovery casts in individual target cores.
**/
class GenIrBoundary {
	/**
		Expose a `GenIrProgram` value at the backend dispatch seam.

		Why
		- Reflaxe OCaml interface dispatch can lower interface-typed parameters as `Obj.t`.
		- Stage3 backend dispatch therefore needs one explicit boundary cast when passing
		  typed IR into backend bridge methods.

		Policy
		- Keep this cast centralized here; do not spread `cast` at call sites.
	**/
	public static inline function asBackendProgram(program:GenIrProgram):Dynamic {
		return cast program;
	}

	public static inline function requireProgram(program:Dynamic):GenIrProgram {
		return cast program;
	}
}
