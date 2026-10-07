package reflaxe.ocaml.ast;

#if macro
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypeTools;
import reflaxe.ocaml.ast.OcamlExpr.OcamlBinop;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlMapIdentityPlan;
import reflaxe.ocaml.lowered.OcamlMapIdentityPlan.OcamlMapIdentityPlanner;

/** The caller supplies the exact planned expression and the current function binding. */
typedef OcamlMapEqualityInput = {
	final plan:OcamlMapIdentityPlan;
	final binding:OcamlFunctionPlanBinding;
	final expression:TypedExpr;
	final buildExpr:TypedExpr->OcamlExpr;
	final freshTmp:String->String;
};

/** Materializes planned map identity without changing map storage or operand order. */
function build(input:OcamlMapEqualityInput):OcamlExpr {
	final decision = input.plan.requireFor(input.expression);
	final operands = switch (input.expression.expr) {
		case TBinop(op = (OpEq | OpNotEq), left, right): {left: left, right: right, negate: op == OpNotEq};
		case _: throw "reflaxe.ocaml [map-equality:operand]: planned comparison is no longer an equality";
	};
	final selected = OcamlMapIdentityPlanner.selection(operands.left.t, operands.right.t);
	if (selected == null
		|| !OcamlMapIdentityPlan.sameBinding(decision.binding, input.binding)
		|| decision.leftType != TypeTools.toString(operands.left.t)
		|| decision.rightType != TypeTools.toString(operands.right.t)
		|| decision.leftKind != selected.left
		|| decision.rightKind != selected.right
		|| decision.negate != operands.negate
		|| TypeTools.toString(input.expression.t) != "Bool")
		throw "reflaxe.ocaml [map-equality:operand]: comparison operands or operator changed after planning";
	final leftName = input.freshTmp("map_eq_left");
	final rightName = input.freshTmp("map_eq_right");
	function view(name:String):OcamlExpr {
		// Obj.repr preserves identity for both raw map references and existing Obj.t
		// values. It neither copies the table nor dereferences a null sentinel.
		return EApp(EField(EIdent("Obj"), "repr"), [EIdent(name)]);
	}
	final comparison:OcamlExpr = EBinop(decision.negate ? PhysNeq : PhysEq, view(leftName), view(rightName));
	return ELet(leftName, input.buildExpr(operands.left), ELet(rightName, input.buildExpr(operands.right), comparison, false), false);
}
#end
