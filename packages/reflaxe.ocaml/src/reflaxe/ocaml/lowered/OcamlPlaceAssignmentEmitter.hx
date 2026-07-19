package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Type.TypedExpr;
import reflaxe.ocaml.ast.OcamlAssignOp;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlTypeExpr;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredSimpleAssignment;

/** Mechanically converts a validated place plan into OCaml target syntax. */
class OcamlPlaceAssignmentEmitter {
	public static function emit(plan:OcamlLoweredSimpleAssignment, buildExpr:TypedExpr->OcamlExpr, freshTemporary:String->String):OcamlExpr {
		final receiverName = freshTemporary("place_receiver");
		final rightHandSideName = freshTemporary("place_rhs");
		final typedReceiver = OcamlExpr.EAnnot(OcamlExpr.EIdent(receiverName), OcamlTypeExpr.TIdent(plan.place.receiverCarrierTypeId));
		final target = OcamlExpr.EField(typedReceiver, plan.place.targetFieldName);
		return OcamlExpr.ELet(receiverName, buildExpr(plan.receiver), OcamlExpr.ELet(rightHandSideName, buildExpr(plan.rightHandSide), OcamlExpr.ESeq([
			OcamlExpr.EAssign(OcamlAssignOp.FieldSet, target, OcamlExpr.EIdent(rightHandSideName)),
			OcamlExpr.EIdent(rightHandSideName)
		]), false), false);
	}
}
#end
