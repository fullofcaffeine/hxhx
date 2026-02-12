/**
	Current OCaml dialect implementation for the minimal backend seam.

	Why
	- Stage3 bring-up still emits OCaml source directly and expects `HxRuntime` helpers.
	- We want the first extraction to be behavior-preserving, so this class mirrors the
	  exact expressions the emitter already used.

	What
	- Produces OCaml snippets for null checks, dynamic equality, and null sentinel values.

	How
	- Each method returns the same textual form previously inlined in `EmitterStage`.
	- Callers pass already-lowered expression fragments (`lhsExpr`, `rhsExpr`).
**/
class HihOcamlBackendDialect implements HihBackendDialect {
	public function new() {}

	public function runtimeIsNull(scrutineeExpr:String):String {
		return "(HxRuntime.is_null (Obj.repr " + scrutineeExpr + "))";
	}

	public function runtimeDynamicEquals(lhsExpr:String, rhsExpr:String):String {
		return "(HxRuntime.dynamic_equals (Obj.repr " + lhsExpr + ") (Obj.repr " + rhsExpr + "))";
	}

	public function dynamicNullValue():String {
		return "(Obj.magic HxRuntime.hx_null)";
	}
}
