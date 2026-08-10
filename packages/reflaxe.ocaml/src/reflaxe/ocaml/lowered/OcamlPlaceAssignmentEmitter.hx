package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Type.TypedExpr;
import reflaxe.ocaml.ast.OcamlAssignOp;
import reflaxe.ocaml.ast.OcamlConst;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlTypeExpr;
import reflaxe.ocaml.ast.OcamlExpr.OcamlUnop;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlAssignmentResultKind;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredArrayCompoundAssignment;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredArrayIntUpdate;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredArraySimpleAssignment;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredCompoundAssignment;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredIntUpdate;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredSimpleAssignment;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredStaticFieldAccess;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredStaticFieldPlace;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredStaticCompoundAssignment;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredStaticIntUpdate;
import reflaxe.ocaml.lowered.OcamlLoweredPlace.OcamlLoweredStaticSimpleAssignment;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeReference;

/** The completed array assignment plus the exact store subtree that uses runtime authority. */
typedef OcamlArraySimpleEmission = {
	final expression:OcamlExpr;
	final runtimeStore:OcamlExpr;
}

/** The completed mutation plus its exact authorized Haxe Int32 addition call. */
typedef OcamlIntAdditionEmission = {
	final expression:OcamlExpr;
	final runtimeAddition:OcamlExpr;
}

/** Mechanically converts a validated place plan into OCaml target syntax. */
class OcamlPlaceAssignmentEmitter {
	static function staticTarget(place:OcamlLoweredStaticFieldPlace):OcamlExpr {
		if (place.staticAccess == OcamlLoweredStaticFieldAccess.Local)
			return OcamlExpr.EIdent(place.targetValueName);
		return OcamlExpr.EField(OcamlExpr.EIdent(place.targetModuleName), place.targetValueName);
	}

	static function updateResultName(result:OcamlAssignmentResultKind, oldValueName:String, newValueName:String):String {
		return switch (result) {
			case OldValue: oldValueName;
			case ComputedValue: newValueName;
			case AssignedValue: throw "validated update cannot use the assigned-value result contract";
		}
	}

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

	/** Emits a validated static-ref assignment without inventing a receiver occurrence. */
	public static function emitStaticSimple(plan:OcamlLoweredStaticSimpleAssignment, buildExpr:TypedExpr->OcamlExpr, freshTemporary:String->String):OcamlExpr {
		final rightHandSideName = freshTemporary("place_rhs");
		final target = staticTarget(plan.place);
		return OcamlExpr.ELet(rightHandSideName, buildExpr(plan.rightHandSide), OcamlExpr.ESeq([
			OcamlExpr.EAssign(OcamlAssignOp.RefSet, target, OcamlExpr.EIdent(rightHandSideName)),
			OcamlExpr.EIdent(rightHandSideName)
		]), false);
	}

	/** Emits a validated static load-before-RHS compound assignment. */
	public static function emitStaticCompoundIntAdd(plan:OcamlLoweredStaticCompoundAssignment, runtimeAdditionReference:OcamlRuntimeReference,
			buildExpr:TypedExpr->OcamlExpr, freshTemporary:String->String):OcamlIntAdditionEmission {
		final oldValueName = freshTemporary("place_old");
		final rightHandSideName = freshTemporary("place_rhs");
		final newValueName = freshTemporary("place_new");
		final target = staticTarget(plan.place);
		final operation = OcamlExpr.EApp(OcamlExpr.ERuntimeIdent(runtimeAdditionReference),
			[OcamlExpr.EIdent(oldValueName), OcamlExpr.EIdent(rightHandSideName)]);
		return {
			expression: OcamlExpr.ELet(oldValueName, OcamlExpr.EUnop(OcamlUnop.Deref, target),
				OcamlExpr.ELet(rightHandSideName, buildExpr(plan.rightHandSide), OcamlExpr.ELet(newValueName, operation, OcamlExpr.ESeq([
					OcamlExpr.EAssign(OcamlAssignOp.RefSet, target, OcamlExpr.EIdent(newValueName)),
					OcamlExpr.EIdent(newValueName)
				]), false), false), false),
			runtimeAddition: operation
		};
	}

	/** Emits a validated static update from its explicit old/new result contract. */
	public static function emitStaticIntUpdate(plan:OcamlLoweredStaticIntUpdate, runtimeAdditionReference:OcamlRuntimeReference,
			freshTemporary:String->String):OcamlIntAdditionEmission {
		final oldValueName = freshTemporary("place_old");
		final newValueName = freshTemporary("place_new");
		final target = staticTarget(plan.place);
		final operation = OcamlExpr.EApp(OcamlExpr.ERuntimeIdent(runtimeAdditionReference),
			[OcamlExpr.EIdent(oldValueName), OcamlExpr.EConst(OcamlConst.CInt(plan.delta))]);
		final resultName = updateResultName(plan.result, oldValueName, newValueName);
		return {
			expression: OcamlExpr.ELet(oldValueName, OcamlExpr.EUnop(OcamlUnop.Deref, target), OcamlExpr.ELet(newValueName, operation, OcamlExpr.ESeq([
				OcamlExpr.EAssign(OcamlAssignOp.RefSet, target, OcamlExpr.EIdent(newValueName)),
				OcamlExpr.EIdent(resultName)
			]), false), false),
			runtimeAddition: operation
		};
	}

	/** Emits the sealed array, index, RHS, store, and assigned-result schedule. */
	public static function emitArraySimple(plan:OcamlLoweredArraySimpleAssignment, runtimeStoreReference:OcamlRuntimeReference,
			buildExpr:TypedExpr->OcamlExpr, freshTemporary:String->String):OcamlArraySimpleEmission {
		final receiverName = freshTemporary("place_array");
		final indexName = freshTemporary("place_index");
		final rightHandSideName = freshTemporary("place_rhs");
		final typedReceiver = OcamlExpr.EAnnot(OcamlExpr.EIdent(receiverName), OcamlTypeExpr.TIdent(plan.place.receiverCarrierTypeId));
		final typedIndex = OcamlExpr.EAnnot(OcamlExpr.EIdent(indexName), OcamlTypeExpr.TIdent(plan.place.indexCarrierTypeId));
		final store = OcamlExpr.EApp(OcamlExpr.ERuntimeIdent(runtimeStoreReference), [typedReceiver, typedIndex, OcamlExpr.EIdent(rightHandSideName)]);
		return {
			expression: OcamlExpr.ELet(receiverName, buildExpr(plan.receiver),
				OcamlExpr.ELet(indexName, buildExpr(plan.index), OcamlExpr.ELet(rightHandSideName, buildExpr(plan.rightHandSide), OcamlExpr.ESeq([
					OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [store]),
					OcamlExpr.EIdent(rightHandSideName)
				]), false), false), false),
			runtimeStore: store
		};
	}

	/** Emits the sealed array/index/load-before-RHS schedule for exact Int `+=`. */
	public static function emitArrayCompoundIntAdd(plan:OcamlLoweredArrayCompoundAssignment, runtimeAdditionReference:OcamlRuntimeReference,
			buildExpr:TypedExpr->OcamlExpr, freshTemporary:String->String):OcamlIntAdditionEmission {
		final receiverName = freshTemporary("place_array");
		final indexName = freshTemporary("place_index");
		final oldValueName = freshTemporary("place_old");
		final rightHandSideName = freshTemporary("place_rhs");
		final newValueName = freshTemporary("place_new");
		final typedReceiver = OcamlExpr.EAnnot(OcamlExpr.EIdent(receiverName), OcamlTypeExpr.TIdent(plan.place.receiverCarrierTypeId));
		final typedIndex = OcamlExpr.EAnnot(OcamlExpr.EIdent(indexName), OcamlTypeExpr.TIdent(plan.place.indexCarrierTypeId));
		final load = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent(plan.place.targetModuleName), plan.place.targetLoadName), [typedReceiver, typedIndex]);
		final operation = OcamlExpr.EApp(OcamlExpr.ERuntimeIdent(runtimeAdditionReference),
			[OcamlExpr.EIdent(oldValueName), OcamlExpr.EIdent(rightHandSideName)]);
		final store = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent(plan.place.targetModuleName), plan.place.targetStoreName),
			[typedReceiver, typedIndex, OcamlExpr.EIdent(newValueName)]);
		return {
			expression: OcamlExpr.ELet(receiverName, buildExpr(plan.receiver),
				OcamlExpr.ELet(indexName, buildExpr(plan.index),
					OcamlExpr.ELet(oldValueName, load,
						OcamlExpr.ELet(rightHandSideName, buildExpr(plan.rightHandSide), OcamlExpr.ELet(newValueName, operation, OcamlExpr.ESeq([
							OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [store]),
							OcamlExpr.EIdent(newValueName)
						]), false), false), false), false), false),
			runtimeAddition: operation
		};
	}

	/** Emits a validated array update from its explicit old/new result contract. */
	public static function emitArrayIntUpdate(plan:OcamlLoweredArrayIntUpdate, runtimeAdditionReference:OcamlRuntimeReference, buildExpr:TypedExpr->OcamlExpr,
			freshTemporary:String->String):OcamlIntAdditionEmission {
		final receiverName = freshTemporary("place_array");
		final indexName = freshTemporary("place_index");
		final oldValueName = freshTemporary("place_old");
		final newValueName = freshTemporary("place_new");
		final typedReceiver = OcamlExpr.EAnnot(OcamlExpr.EIdent(receiverName), OcamlTypeExpr.TIdent(plan.place.receiverCarrierTypeId));
		final typedIndex = OcamlExpr.EAnnot(OcamlExpr.EIdent(indexName), OcamlTypeExpr.TIdent(plan.place.indexCarrierTypeId));
		final load = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent(plan.place.targetModuleName), plan.place.targetLoadName), [typedReceiver, typedIndex]);
		final operation = OcamlExpr.EApp(OcamlExpr.ERuntimeIdent(runtimeAdditionReference),
			[OcamlExpr.EIdent(oldValueName), OcamlExpr.EConst(OcamlConst.CInt(plan.delta))]);
		final store = OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent(plan.place.targetModuleName), plan.place.targetStoreName),
			[typedReceiver, typedIndex, OcamlExpr.EIdent(newValueName)]);
		final resultName = updateResultName(plan.result, oldValueName, newValueName);
		return {
			expression: OcamlExpr.ELet(receiverName, buildExpr(plan.receiver),
				OcamlExpr.ELet(indexName, buildExpr(plan.index), OcamlExpr.ELet(oldValueName, load, OcamlExpr.ELet(newValueName, operation, OcamlExpr.ESeq([
					OcamlExpr.EApp(OcamlExpr.EIdent("ignore"), [store]),
					OcamlExpr.EIdent(resultName)
				]), false), false), false), false),
			runtimeAddition: operation
		};
	}

	/** Emits the sealed load-before-RHS schedule for exact primitive-Int `+=`. */
	public static function emitCompoundIntAdd(plan:OcamlLoweredCompoundAssignment, runtimeAdditionReference:OcamlRuntimeReference,
			buildExpr:TypedExpr->OcamlExpr, freshTemporary:String->String):OcamlIntAdditionEmission {
		final receiverName = freshTemporary("place_receiver");
		final oldValueName = freshTemporary("place_old");
		final rightHandSideName = freshTemporary("place_rhs");
		final newValueName = freshTemporary("place_new");
		final typedReceiver = OcamlExpr.EAnnot(OcamlExpr.EIdent(receiverName), OcamlTypeExpr.TIdent(plan.place.receiverCarrierTypeId));
		final target = OcamlExpr.EField(typedReceiver, plan.place.targetFieldName);
		final operation = OcamlExpr.EApp(OcamlExpr.ERuntimeIdent(runtimeAdditionReference),
			[OcamlExpr.EIdent(oldValueName), OcamlExpr.EIdent(rightHandSideName)]);
		return {
			expression: OcamlExpr.ELet(receiverName, buildExpr(plan.receiver),
				OcamlExpr.ELet(oldValueName, target,
					OcamlExpr.ELet(rightHandSideName, buildExpr(plan.rightHandSide), OcamlExpr.ELet(newValueName, operation, OcamlExpr.ESeq([
						OcamlExpr.EAssign(OcamlAssignOp.FieldSet, target, OcamlExpr.EIdent(newValueName)),
						OcamlExpr.EIdent(newValueName)
					]), false), false), false), false),
			runtimeAddition: operation
		};
	}

	/** Emits the sealed ordinary-Int update from its explicit result contract. */
	public static function emitIntUpdate(plan:OcamlLoweredIntUpdate, runtimeAdditionReference:OcamlRuntimeReference, buildExpr:TypedExpr->OcamlExpr,
			freshTemporary:String->String):OcamlIntAdditionEmission {
		final receiverName = freshTemporary("place_receiver");
		final oldValueName = freshTemporary("place_old");
		final newValueName = freshTemporary("place_new");
		final typedReceiver = OcamlExpr.EAnnot(OcamlExpr.EIdent(receiverName), OcamlTypeExpr.TIdent(plan.place.receiverCarrierTypeId));
		final target = OcamlExpr.EField(typedReceiver, plan.place.targetFieldName);
		final operation = OcamlExpr.EApp(OcamlExpr.ERuntimeIdent(runtimeAdditionReference),
			[OcamlExpr.EIdent(oldValueName), OcamlExpr.EConst(OcamlConst.CInt(plan.delta))]);
		final resultName = updateResultName(plan.result, oldValueName, newValueName);
		return {
			expression: OcamlExpr.ELet(receiverName, buildExpr(plan.receiver),
				OcamlExpr.ELet(oldValueName, target, OcamlExpr.ELet(newValueName, operation, OcamlExpr.ESeq([
					OcamlExpr.EAssign(OcamlAssignOp.FieldSet, target, OcamlExpr.EIdent(newValueName)),
					OcamlExpr.EIdent(resultName)
				]), false), false), false),
			runtimeAddition: operation
		};
	}
}
#end
