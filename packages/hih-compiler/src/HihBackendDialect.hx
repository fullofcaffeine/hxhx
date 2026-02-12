/**
	Backend-specific expression-lowering seam for the HIH core emitter.

	Why
	- Today `EmitterStage` emits OCaml text directly, which is expected for the current
	  bootstrap target but makes it hard to reason about a future non-OCaml backend path.
	- We need a small, explicit abstraction boundary that can be expanded incrementally
	  without changing current behavior.

	What
	- `runtimeIsNull(scrutineeExpr)`: builds a runtime null-check expression.
	- `runtimeDynamicEquals(lhsExpr, rhsExpr)`: builds a dynamic equality expression.
	- `dynamicNullValue()`: returns the dynamic null sentinel expression.

	How
	- `EmitterStage` uses this interface for the current switch-pattern lowering seam.
	- `HihOcamlBackendDialect` preserves the exact OCaml text shape emitted before this
	  abstraction was introduced.

	Gotchas
	- This interface is intentionally tiny and string-based for the first extraction rung.
	- It does not yet define a target-agnostic IR; that is tracked as later design work.
**/
interface HihBackendDialect {
	public function runtimeIsNull(scrutineeExpr:String):String;
	public function runtimeDynamicEquals(lhsExpr:String, rhsExpr:String):String;
	public function dynamicNullValue():String;
}

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
