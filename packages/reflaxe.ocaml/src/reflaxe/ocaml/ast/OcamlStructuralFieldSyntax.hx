package reflaxe.ocaml.ast;

#if (macro || reflaxe_runtime)
import haxe.macro.Type.TypedExpr;
import reflaxe.ocaml.lowered.OcamlStructuralFieldPlan.OcamlStructuralFieldContract;
import reflaxe.ocaml.lowered.OcamlStructuralFieldPlan.OcamlStructuralFieldDecision;
import reflaxe.ocaml.lowered.OcamlStructuralFieldPlan.OcamlStructuralFieldLoadConversion;
import reflaxe.ocaml.lowered.OcamlStructuralFieldPlan.OcamlStructuralFieldOperation;
import reflaxe.ocaml.lowered.OcamlStructuralFieldPlan.OcamlStructuralFieldStoreConversion;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;

/** The completed field expression and the exact subtree owned by its runtime uses. */
typedef OcamlStructuralFieldMaterialization = {
	final expression:OcamlExpr;
	final runtimeOperation:OcamlExpr;
}

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
			freshName:String->String, runtimeAuthority:OcamlRuntimeUseAuthority):OcamlStructuralFieldMaterialization {
		OcamlStructuralFieldContract.require(decision);
		if (runtimeAuthority == null)
			throw 'reflaxe.ocaml [ocaml-structural-field:missing-runtime-authority]: decision "${decision.id}" cannot construct private runtime identifiers';
		final receiverName = freshName("structural_receiver");
		final receiverValue = OcamlExpr.EIdent(receiverName);
		return switch (decision.operation) {
			case ReadStoredField:
				if (value != null)
					throw 'reflaxe.ocaml [ocaml-structural-field:syntax]: read "${decision.id}" unexpectedly received a value';
				final raw = OcamlExpr.EApp(runtimeIdentifier(decision, runtimeAuthority, "read-field",
					decision.runtimeModule + "." + decision.runtimeOperation),
					[receiverValue, OcamlExpr.EConst(OcamlConst.CString(decision.fieldName))]);
				final loaded = switch (decision.loadConversion) {
					case ObjObj: OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "obj"), [raw]);
					case UnboxBool:
						OcamlExpr.EApp(runtimeIdentifier(decision, runtimeAuthority, "unbox-bool", "HxRuntime.unbox_bool_or_obj"), [raw]);
					case null: throw 'reflaxe.ocaml [ocaml-structural-field:syntax]: read "${decision.id}" has no load conversion';
				}
				{
					expression: OcamlExpr.ELet(receiverName, buildExpr(receiver), loaded, false),
					runtimeOperation: loaded
				};
			case WriteStoredField:
				if (value == null)
					throw 'reflaxe.ocaml [ocaml-structural-field:syntax]: write "${decision.id}" has no assigned value';
				final valueName = freshName("structural_value");
				final valueIdent = OcamlExpr.EIdent(valueName);
				final stored = switch (decision.storeConversion) {
					case ObjRepr: OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("Obj"), "repr"), [valueIdent]);
					case BoxBool: OcamlExpr.EApp(runtimeIdentifier(decision, runtimeAuthority, "box-bool", "HxRuntime.box_bool"), [valueIdent]);
					case null: throw 'reflaxe.ocaml [ocaml-structural-field:syntax]: write "${decision.id}" has no store conversion';
				}
				final write = OcamlExpr.EApp(runtimeIdentifier(decision, runtimeAuthority, "write-field",
					decision.runtimeModule + "." + decision.runtimeOperation),
					[receiverValue, OcamlExpr.EConst(OcamlConst.CString(decision.fieldName)), stored]);
				{
					expression: OcamlExpr.ELet(receiverName, buildExpr(receiver),
						OcamlExpr.ELet(valueName, buildExpr(value), OcamlExpr.ESeq([write, valueIdent]), false), false),
					runtimeOperation: write
				};
			case CaptureIteratorMethod:
				if (value != null || decision.iteratorTarget == null)
					throw 'reflaxe.ocaml [ocaml-structural-field:syntax]: Iterator method "${decision.id}" has conflicting inputs';
				final call = OcamlExpr.EApp(runtimeIdentifier(decision, runtimeAuthority, "capture-iterator-method",
					decision.runtimeModule + "." + decision.runtimeOperation),
					[receiverValue]);
				{
					expression: OcamlExpr.ELet(receiverName, buildExpr(receiver), OcamlExpr.EFun([OcamlPat.PConst(OcamlConst.CUnit)], call), false),
					runtimeOperation: call
				};
			case ProjectTupleKey, ProjectTupleValue:
				if (value != null || decision.keyValueTupleTarget == null)
					throw 'reflaxe.ocaml [ocaml-structural-field:syntax]: Map pair projection "${decision.id}" has conflicting inputs';
				final projected = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent(decision.runtimeModule), decision.runtimeOperation), [receiverValue]);
				{
					expression: OcamlExpr.ELet(receiverName, buildExpr(receiver), projected, false),
					runtimeOperation: projected
				};
		}
	}

	static function runtimeIdentifier(decision:OcamlStructuralFieldDecision, authority:OcamlRuntimeUseAuthority, role:String, exactSymbol:String):OcamlExpr {
		final matches = decision.runtimeUseOccurrences.filter(use -> use.role == role);
		if (matches.length != 1 || matches[0].exactSymbol != exactSymbol)
			throw 'reflaxe.ocaml [ocaml-structural-field:wrong-runtime-use]: decision "${decision.id}" has no exact $role/$exactSymbol occurrence';
		final use = matches[0];
		return OcamlExpr.ERuntimeIdent(authority.expressionIdentifier(use.id, use.planRevision, use.exactSymbol));
	}
}
#end
