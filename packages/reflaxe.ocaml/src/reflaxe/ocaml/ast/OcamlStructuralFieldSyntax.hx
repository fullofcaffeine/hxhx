package reflaxe.ocaml.ast;

#if (macro || reflaxe_runtime)
import haxe.macro.Type.TypedExpr;
import reflaxe.ocaml.lowered.OcamlStructuralFieldPlan.OcamlStructuralFieldContract;
import reflaxe.ocaml.lowered.OcamlStructuralFieldPlan.OcamlStructuralFieldDecision;
import reflaxe.ocaml.lowered.OcamlStructuralFieldPlan.OcamlStructuralFieldLoadConversion;
import reflaxe.ocaml.lowered.OcamlStructuralFieldPlan.OcamlStructuralFieldOperation;
import reflaxe.ocaml.lowered.OcamlStructuralFieldPlan.OcamlStructuralFieldStoreConversion;

/**
	Renders one already selected structural field operation.

	This module never decides whether an overlapping name describes a normal
	object field, an Iterator method, or a Map pair component. It only
	materializes the receiver and optional assigned value in the recorded order,
	then renders the operation selected from the final typed Haxe body.
**/
class OcamlStructuralFieldSyntax {
	/** Builds a field read, write, or Iterator method capture from sealed facts. */
	public static function build(decision:OcamlStructuralFieldDecision, receiver:TypedExpr, value:Null<TypedExpr>, buildExpr:TypedExpr->OcamlExpr,
			freshName:String->String):OcamlExpr {
		OcamlStructuralFieldContract.require(decision);
		final receiverName = freshName("structural_receiver");
		final receiverValue = OcamlExpr.EIdent(receiverName);
		return switch (decision.operation) {
			case ReadStoredField:
				if (value != null)
					throw 'reflaxe.ocaml [ocaml-structural-field:syntax]: read "${decision.id}" unexpectedly received a value';
				final raw = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent(decision.runtimeModule), decision.runtimeOperation),
					[receiverValue, OcamlExpr.EConst(OcamlConst.CString(decision.fieldName))]);
				final loaded = switch (decision.loadConversion) {
					case ObjObj: OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [raw]);
					case UnboxBool: OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "unbox_bool_or_obj"), [raw]);
					case null: throw 'reflaxe.ocaml [ocaml-structural-field:syntax]: read "${decision.id}" has no load conversion';
				}
				OcamlExpr.ELet(receiverName, buildExpr(receiver), loaded, false);
			case WriteStoredField:
				if (value == null)
					throw 'reflaxe.ocaml [ocaml-structural-field:syntax]: write "${decision.id}" has no assigned value';
				final valueName = freshName("structural_value");
				final valueIdent = OcamlExpr.EIdent(valueName);
				final stored = switch (decision.storeConversion) {
					case ObjRepr: OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [valueIdent]);
					case BoxBool: OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "box_bool"), [valueIdent]);
					case null: throw 'reflaxe.ocaml [ocaml-structural-field:syntax]: write "${decision.id}" has no store conversion';
				}
				final write = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent(decision.runtimeModule), decision.runtimeOperation),
					[receiverValue, OcamlExpr.EConst(OcamlConst.CString(decision.fieldName)), stored]);
				OcamlExpr.ELet(receiverName, buildExpr(receiver), OcamlExpr.ELet(valueName, buildExpr(value), OcamlExpr.ESeq([write, valueIdent]), false),
					false);
			case CaptureIteratorMethod:
				if (value != null || decision.iteratorTarget == null)
					throw 'reflaxe.ocaml [ocaml-structural-field:syntax]: Iterator method "${decision.id}" has conflicting inputs';
				final call = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent(decision.runtimeModule), decision.runtimeOperation), [receiverValue]);
				OcamlExpr.ELet(receiverName, buildExpr(receiver), OcamlExpr.EFun([OcamlPat.PConst(OcamlConst.CUnit)], call), false);
			case ProjectTupleKey, ProjectTupleValue:
				if (value != null || decision.keyValueTupleTarget == null)
					throw 'reflaxe.ocaml [ocaml-structural-field:syntax]: Map pair projection "${decision.id}" has conflicting inputs';
				final projected = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent(decision.runtimeModule), decision.runtimeOperation), [receiverValue]);
				OcamlExpr.ELet(receiverName, buildExpr(receiver), projected, false);
		}
	}
}
#end
