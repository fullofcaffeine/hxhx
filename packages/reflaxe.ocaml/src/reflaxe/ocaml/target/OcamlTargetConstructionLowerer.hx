package reflaxe.ocaml.target;

import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlPat;

/** Target syntax selected by the class owner before constructor assembly. **/
typedef OcamlTargetAllocationInput = {
	final parameters:Array<OcamlPat>;
	final initializer:OcamlExpr;
	final body:OcamlExpr;
}

/**
	Allocate an instance, run its constructor body, and return that same instance.

	The class owner supplies the checked record initializer and body, whose receiver
	is named `self`. Zero source arguments must already use the target's unit pattern.
	The initializer and body each occur once. A constructor exception propagates
	before the return, preserving effects already made on the allocated record.
	Record layout, dispatch, argument conversions and runtime authorization remain
	with their existing owners. This function does not infer them from syntax.
**/
function buildAllocation(input:OcamlTargetAllocationInput):OcamlExpr {
	if (input == null
		|| input.parameters == null
		|| input.parameters.length == 0
		|| input.initializer == null
		|| input.body == null)
		throw "OCaml constructor assembly requires parameters, an initializer and a body";
	final body = OcamlExpr.ELet("self", input.initializer, OcamlExpr.ESeq([
		OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [input.body]),
		OcamlExpr.EIdent("self")
	]), false);
	return OcamlExpr.EFun(input.parameters.copy(), body);
}
