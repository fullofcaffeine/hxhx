package reflaxe.ocaml.ast;

#if macro
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypeTools;
import reflaxe.ocaml.ast.OcamlExpr.OcamlBinop;
import reflaxe.ocaml.CompilationContext;
import reflaxe.ocaml.OcamlBuildContext;
import reflaxe.ocaml.OcamlProfileContract;
import reflaxe.ocaml.lowered.OcamlEnumIdentityPlan;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;

/** Named inputs keep the two operands and their compiler context explicit. */
typedef OcamlEnumEqualityInput = {
	final context:CompilationContext;
	final plan:OcamlEnumIdentityPlan;
	final binding:OcamlFunctionPlanBinding;
	final expression:TypedExpr;
	final left:TypedExpr;
	final right:TypedExpr;
	final negate:Bool;
	final buildExpr:TypedExpr->OcamlExpr;
	final freshTmp:String->String;
}

/** Builds enum identity comparison from an exact, request-owned selection. */
function build(input:OcamlEnumEqualityInput):OcamlExpr {
	final decision = input.plan.requireFor(input.expression);
	if (!OcamlEnumIdentityPlan.sameBinding(decision.binding, input.binding)
		|| decision.leftType != TypeTools.toString(input.left.t)
		|| decision.rightType != TypeTools.toString(input.right.t)
		|| decision.negate != input.negate
		|| TypeTools.toString(input.expression.t) != "Bool")
		throw "reflaxe.ocaml [enum-equality:operand]: comparison operands or operator changed after planning";
	final uses = OcamlEnumIdentityPlan.runtimeUses(decision);
	final profile = OcamlProfileContract.toDefineValue(OcamlBuildContext.resolve().profile);
	final authority = new OcamlRuntimeUseAuthority(decision.revision, profile,
		input.context.runtimeRequirementsByIds([OcamlEnumIdentityPlan.requirementId(decision)]), uses, input.context.finalRuntimeUses);
	final leftName = input.freshTmp("enum_eq_left");
	final rightName = input.freshTmp("enum_eq_right");
	final operands = [OcamlExpr.EIdent(leftName), OcamlExpr.EIdent(rightName)];
	final recovered:Array<OcamlExpr> = [];
	for (index in 0...2) {
		final use = uses[index];
		final helper = OcamlExpr.ERuntimeIdent(authority.expressionIdentifier(use.id, use.planRevision, use.exactSymbol));
		// Obj.repr is a representation view, not a fresh box or unchecked cast.
		// Recovery accepts either a native enum or its nullable runtime box.
		final value = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [operands[index]]);
		recovered.push(OcamlExpr.EApp(helper, [OcamlExpr.EConst(OcamlConst.CString(decision.enumName)), value]));
	}
	final comparison = OcamlExpr.EBinop(input.negate ? OcamlBinop.PhysNeq : OcamlBinop.PhysEq, recovered[0], recovered[1]);
	// Operand subtrees own their runtime uses. Reconcile only this operation.
	authority.reconcileExpression(comparison);
	return OcamlExpr.ELet(leftName, input.buildExpr(input.left), OcamlExpr.ELet(rightName, input.buildExpr(input.right), comparison, false), false);
}
#end
