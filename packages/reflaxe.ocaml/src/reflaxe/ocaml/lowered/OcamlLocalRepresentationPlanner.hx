package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlLocalRepresentationChoice;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlLocalRepresentationDecision;
import reflaxe.ocaml.lowered.OcamlLocalStoragePlan.OcamlLocalStorageDecision;
import reflaxe.ocaml.lowered.OcamlLocalStoragePlan.OcamlLocalStorageKind;
import reflaxe.ocaml.lowered.OcamlLocalStoragePlan.OcamlLocalStorageReason;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;

/** Connects exact-Int local-storage choices to the program representation registry. */
class OcamlLocalRepresentationPlanner {
	/** Plans registry references for the mutated locals in one final typed body. */
	public static function planExpression(expression:TypedExpr, storage:OcamlLocalStoragePlan,
			representations:OcamlRepresentationRegistry):OcamlLocalRepresentationPlan {
		final typeByLocalId:Map<Int, Type> = [];

		function record(localId:Int, type:Type):Void {
			final existing = typeByLocalId.get(localId);
			if (existing != null && TypeTools.toString(existing) != TypeTools.toString(type)) {
				throw 'reflaxe.ocaml [ocaml-representation:conflicting-local-type]: local $localId appears as both ${TypeTools.toString(existing)} and ${TypeTools.toString(type)}';
			}
			typeByLocalId.set(localId, type);
		}

		function visit(current:TypedExpr):Void {
			switch (current.expr) {
				case TVar(local, _):
					record(local.id, local.t);
				case TLocal(local):
					record(local.id, local.t);
				case _:
			}
			TypedExprTools.iter(current, visit);
		}

		visit(expression);
		final decisions:Array<OcamlLocalRepresentationDecision> = [];
		for (decision in storage.decisions()) {
			final type = typeByLocalId.get(decision.localId);
			if (type == null)
				throw 'reflaxe.ocaml [ocaml-representation:missing-local-type]: storage decision for local ${decision.localId} has no typed local occurrence in the sealed function body';
			if (!OcamlRepresentationRegistry.isExactInt(type)) {
				decisions.push({
					localId: decision.localId,
					choice: OcamlLocalRepresentationChoice.Unmigrated(TypeTools.toString(type))
				});
				continue;
			}
			final domain = localDomain(decision);
			final representation = representations.selectExactInt(domain);
			decisions.push({
				localId: decision.localId,
				choice: OcamlLocalRepresentationChoice.ProgramDecision(representation.id, representation.semanticTypeId, domain)
			});
		}
		return new OcamlLocalRepresentationPlan(decisions);
	}

	static function localDomain(decision:OcamlLocalStorageDecision):OcamlRepresentationDomain {
		if (decision.storage == OcamlLocalStorageKind.ImmutableRebinding)
			return OcamlRepresentationDomain.InternalValue;
		for (reason in decision.reasons) {
			if (reason == OcamlLocalStorageReason.CapturedAndMutated)
				return OcamlRepresentationDomain.CapturedLocalStorage;
		}
		return OcamlRepresentationDomain.MutableLocalStorage;
	}
}
#end
