package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Type.TypedExpr;
import reflaxe.ocaml.ast.OcamlAssignOp;
import reflaxe.ocaml.ast.OcamlConst;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlTypeExpr;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredCompoundAssignment;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredIntUpdate;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredSimpleAssignment;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredUpdateFixity;

/** Mechanically converts a validated place plan into OCaml target syntax. */
class OcamlPlaceAssignmentEmitter {
	public static function emitSimple(plan:OcamlLoweredSimpleAssignment, buildExpr:TypedExpr->OcamlExpr, freshTemporary:String->String):OcamlExpr {
		final receiverName = freshTemporary("place_receiver");
		final rightHandSideName = freshTemporary("place_rhs");
		final typedReceiver = OcamlExpr.EAnnot(OcamlExpr.EIdent(receiverName), OcamlTypeExpr.TIdent(plan.place.receiverCarrierTypeId));
		final target = OcamlExpr.EField(typedReceiver, plan.place.targetFieldName);
		return OcamlExpr.ELet(receiverName, buildExpr(plan.receiver), OcamlExpr.ELet(rightHandSideName, buildExpr(plan.rightHandSide), OcamlExpr.ESeq([
			OcamlExpr.EAssign(OcamlAssignOp.FieldSet, target, OcamlExpr.EIdent(rightHandSideName)),
			OcamlExpr.EIdent(rightHandSideName)
		]), false), false);
	}

	/** Emits the sealed load-before-RHS schedule for exact primitive-Int `+=`. */
	public static function emitCompoundIntAdd(plan:OcamlLoweredCompoundAssignment, buildExpr:TypedExpr->OcamlExpr, freshTemporary:String->String):OcamlExpr {
		final receiverName = freshTemporary("place_receiver");
		final oldValueName = freshTemporary("place_old");
		final rightHandSideName = freshTemporary("place_rhs");
		final newValueName = freshTemporary("place_new");
		final typedReceiver = OcamlExpr.EAnnot(OcamlExpr.EIdent(receiverName), OcamlTypeExpr.TIdent(plan.place.receiverCarrierTypeId));
		final target = OcamlExpr.EField(typedReceiver, plan.place.targetFieldName);
		final operation = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "add"),
			[OcamlExpr.EIdent(oldValueName), OcamlExpr.EIdent(rightHandSideName)]);
		return OcamlExpr.ELet(receiverName, buildExpr(plan.receiver),
			OcamlExpr.ELet(oldValueName, target,
				OcamlExpr.ELet(rightHandSideName, buildExpr(plan.rightHandSide), OcamlExpr.ELet(newValueName, operation, OcamlExpr.ESeq([
					OcamlExpr.EAssign(OcamlAssignOp.FieldSet, target, OcamlExpr.EIdent(newValueName)),
					OcamlExpr.EIdent(newValueName)
				]), false), false), false), false);
	}

	/** Emits the sealed ordinary-Int update schedule without reinterpreting token or fixity. */
	public static function emitIntUpdate(plan:OcamlLoweredIntUpdate, buildExpr:TypedExpr->OcamlExpr, freshTemporary:String->String):OcamlExpr {
		final receiverName = freshTemporary("place_receiver");
		final oldValueName = freshTemporary("place_old");
		final newValueName = freshTemporary("place_new");
		final typedReceiver = OcamlExpr.EAnnot(OcamlExpr.EIdent(receiverName), OcamlTypeExpr.TIdent(plan.place.receiverCarrierTypeId));
		final target = OcamlExpr.EField(typedReceiver, plan.place.targetFieldName);
		final operation = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxInt"), "add"),
			[OcamlExpr.EIdent(oldValueName), OcamlExpr.EConst(OcamlConst.CInt(plan.delta))]);
		final resultName = plan.fixity == OcamlLoweredUpdateFixity.Postfix ? oldValueName : newValueName;
		return OcamlExpr.ELet(receiverName, buildExpr(plan.receiver),
			OcamlExpr.ELet(oldValueName, target, OcamlExpr.ELet(newValueName, operation, OcamlExpr.ESeq([
				OcamlExpr.EAssign(OcamlAssignOp.FieldSet, target, OcamlExpr.EIdent(newValueName)),
				OcamlExpr.EIdent(resultName)
			]), false), false), false);
	}
}
#end
