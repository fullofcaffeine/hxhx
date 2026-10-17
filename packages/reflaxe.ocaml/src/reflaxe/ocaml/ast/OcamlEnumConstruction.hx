package reflaxe.ocaml.ast;

#if macro
import haxe.macro.Type.TypedExpr;
import reflaxe.ocaml.lowered.OcamlEnumIdentityPlan;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;

/** Inputs for a payload construction whose arguments already have their target representations. */
typedef OcamlEnumConstructionInput = {
	final plan:OcamlEnumIdentityPlan;
	final binding:OcamlFunctionPlanBinding;
	final expression:TypedExpr;
	final constructor:OcamlExpr;
	final arguments:Array<OcamlExpr>;
	final freshTmp:String->String;
}

/**
	Allocates one enum payload after evaluating its arguments in source order.

	OCaml can share a constant variant such as `Payload 7`. Haxe requires a fresh
	object for each payload construction. `Stdlib.Sys.opaque_identity` preserves the
	first argument's type and value while preventing that constant allocation.
	Native OCaml extern enums bypass this Haxe identity contract.
**/
function build(input:OcamlEnumConstructionInput):OcamlExpr {
	final decision = input.plan.requireAllocation(input.expression);
	if (!OcamlEnumIdentityPlan.sameBinding(decision.binding, input.binding))
		throw "reflaxe.ocaml [enum-allocation:stale]: constructor belongs to another function revision";
	if (decision.arity != input.arguments.length)
		throw "reflaxe.ocaml [enum-allocation:arity]: constructor arguments changed after planning";
	final names = [for (_ in input.arguments) input.freshTmp("enum_arg")];
	final values = [for (name in names) OcamlExpr.EIdent(name)];
	values[0] = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EField(OcamlExpr.EIdent("Stdlib"), "Sys"), "opaque_identity"), [values[0]]);
	var result = OcamlExpr.EApp(input.constructor, values.length == 1 ? values : [OcamlExpr.ETuple(values)]);
	var index = names.length;
	while (index > 0) {
		index--;
		result = OcamlExpr.ELet(names[index], input.arguments[index], result, false);
	}
	return result;
}
#end
