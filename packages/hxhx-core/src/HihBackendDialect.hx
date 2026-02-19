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
