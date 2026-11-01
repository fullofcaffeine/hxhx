package backend.ocaml;

/**
	What Stage3 emits for arithmetic whose operands it cannot classify.

	Stage3 picks OCaml integer or float operators for `+`, `-`, `*`, `/`, and
	`%` from what it knows about each operand. When neither operand looked like
	an Int or a Float, the emitter used to write the placeholder `(Obj.magic 0)`
	in place of the whole expression. The program still compiled and then
	silently computed `0` (for example `s.charCodeAt(0) + s.charCodeAt(1)`
	before nullable call results were recognized), or crashed when a Float was
	read from that immediate.

	When the typer recorded a type for both operands, a missing lowering is an
	emitter gap, so `unclassified` stops compilation with an error that names
	the location, the operator, and both types. Operands without a recorded
	type still come from `untyped` standard-library code (for example
	`haxe.io.Bytes.compare`); they keep the legacy placeholder until that gap
	is closed (haxe_ocaml-evi2o).
**/
/**
	Return the OCaml for `left op right` when no Int or Float lowering applied,
	or throw the named emit-time error. `location` names the generated module
	and function. `leftType` and `rightType` are the typer's recorded operand
	types, or null when the active typed body has no fact for that operand.
**/
function unclassified(location:String, op:String, leftType:Null<TyType>, rightType:Null<TyType>):String {
	if (leftType == null || rightType == null)
		return "(Obj.magic 0)";
	throw "stage3 emitter: "
		+ location
		+ ": unsupported arithmetic operands for `"
		+ op
		+ "`: "
		+ leftType.getDisplay()
		+ " and "
		+ rightType.getDisplay()
		+ " (no Int or Float lowering applies; refusing to emit a placeholder)";
}
