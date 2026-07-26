package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlLocalCarrierConversion;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlLocalRepresentationChoice;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlLocalRepresentationDecision;
import reflaxe.ocaml.lowered.OcamlLocalStoragePlan.OcamlLocalStorageDecision;
import reflaxe.ocaml.lowered.OcamlLocalStoragePlan.OcamlLocalStorageKind;
import reflaxe.ocaml.lowered.OcamlLocalStoragePlan.OcamlLocalStorageReason;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;

/**
	Connects local carrier choices to the program representation registry.

	Mutated locals retain the existing exact-Int migration. Exact `Array<Int>`
	locals are admitted only when the declaration and every whole-value
	replacement use the same non-null carrier, including locals shared with nested
	functions.
**/
class OcamlLocalRepresentationPlanner {
	/**
		Returns whether an expression already produces the exact direct Array<Int>
		carrier selected by the registry.

		Metadata and parentheses do not change a carrier. A cast is eligible only
		when its child already has the same exact type; a cast from Dynamic, a
		typedef, a nullable wrapper, or another representation is a separate
		conversion boundary and stays on the legacy path.
	**/
	static function isExactArrayIntCarrierExpression(expression:TypedExpr):Bool {
		if (!OcamlRepresentationRegistry.isExactArrayInt(expression.t))
			return false;
		return switch (expression.expr) {
			case TConst(TNull):
				false;
			case TMeta(_, child), TParenthesis(child):
				isExactArrayIntCarrierExpression(child);
			case TCast(child, _): OcamlRepresentationRegistry.isExactArrayInt(child.t) && isExactArrayIntCarrierExpression(child);
			case _:
				true;
		}
	}

	/** Plans registry references and initializer conversions from one final typed body. */
	public static function planExpression(expression:TypedExpr, storage:OcamlLocalStoragePlan,
			representations:OcamlRepresentationRegistry):OcamlLocalRepresentationPlan {
		final typeByLocalId:Map<Int, Type> = [];
		final identityArrayInitializerByLocalId:Map<Int, Bool> = [];
		final identityArrayAssignmentsByLocalId:Map<Int, Bool> = [];

		function record(localId:Int, type:Type):Void {
			final existing = typeByLocalId.get(localId);
			if (existing != null && TypeTools.toString(existing) != TypeTools.toString(type)) {
				throw 'reflaxe.ocaml [ocaml-representation:conflicting-local-type]: local $localId appears as both ${TypeTools.toString(existing)} and ${TypeTools.toString(type)}';
			}
			typeByLocalId.set(localId, type);
		}

		function visit(current:TypedExpr):Void {
			switch (current.expr) {
				case TVar(local, initializer):
					record(local.id, local.t);
					if (OcamlRepresentationRegistry.isExactArrayInt(local.t)) {
						final identityInitializer = initializer != null && isExactArrayIntCarrierExpression(initializer);
						identityArrayInitializerByLocalId.set(local.id, identityInitializer);
					}
				case TLocal(local):
					record(local.id, local.t);
				case TBinop(OpAssign, left, right):
					switch (left.expr) {
						case TLocal(local) if (OcamlRepresentationRegistry.isExactArrayInt(local.t)):
							final identityAssignment = isExactArrayIntCarrierExpression(right);
							if (!identityAssignment
								|| !identityArrayAssignmentsByLocalId.exists(local.id)) identityArrayAssignmentsByLocalId.set(local.id, identityAssignment);
						case _:
					}
				case _:
			}
			TypedExprTools.iter(current, visit);
		}

		visit(expression);
		final decisions:Array<OcamlLocalRepresentationDecision> = [];
		final plannedLocalIds:Map<Int, Bool> = [];
		for (decision in storage.decisions()) {
			plannedLocalIds.set(decision.localId, true);
			final type = typeByLocalId.get(decision.localId);
			if (type == null)
				throw 'reflaxe.ocaml [ocaml-representation:missing-local-type]: storage decision for local ${decision.localId} has no typed local occurrence in the sealed function body';
			if (OcamlRepresentationRegistry.isExactArrayInt(type)) {
				if (identityArrayInitializerByLocalId.get(decision.localId) == true
					&& identityArrayAssignmentsByLocalId.get(decision.localId) != false) {
					final domain = localDomain(decision);
					final representation = representations.selectExactArrayInt(domain);
					decisions.push({
						localId: decision.localId,
						choice: OcamlLocalRepresentationChoice.ProgramDecision(representation.id, representation.semanticTypeId, domain),
						initializerConversion: OcamlLocalCarrierConversion.Identity,
						assignmentConversion: OcamlLocalCarrierConversion.Identity,
						readConversion: OcamlLocalCarrierConversion.Identity
					});
				} else {
					decisions.push(unmigratedDecision(decision.localId, TypeTools.toString(type)));
				}
				continue;
			}
			if (!OcamlRepresentationRegistry.isExactInt(type)) {
				decisions.push(unmigratedDecision(decision.localId, TypeTools.toString(type)));
				continue;
			}
			final domain = localDomain(decision);
			final representation = representations.selectExactInt(domain);
			decisions.push({
				localId: decision.localId,
				choice: OcamlLocalRepresentationChoice.ProgramDecision(representation.id, representation.semanticTypeId, domain),
				initializerConversion: OcamlLocalCarrierConversion.LegacyCoercion,
				assignmentConversion: OcamlLocalCarrierConversion.LegacyCoercion,
				readConversion: OcamlLocalCarrierConversion.LegacyCoercion
			});
		}
		final localIds = [for (localId in typeByLocalId.keys()) localId];
		localIds.sort((left, right) -> left - right);
		for (localId in localIds) {
			if (plannedLocalIds.exists(localId))
				continue;
			final type = cast typeByLocalId.get(localId);
			if (!OcamlRepresentationRegistry.isExactArrayInt(type) || identityArrayInitializerByLocalId.get(localId) != true) {
				continue;
			}
			final representation = representations.selectExactArrayInt(OcamlRepresentationDomain.InternalValue);
			decisions.push({
				localId: localId,
				choice: OcamlLocalRepresentationChoice.ProgramDecision(representation.id, representation.semanticTypeId,
					OcamlRepresentationDomain.InternalValue),
				initializerConversion: OcamlLocalCarrierConversion.Identity,
				assignmentConversion: OcamlLocalCarrierConversion.Identity,
				readConversion: OcamlLocalCarrierConversion.Identity
			});
		}
		return new OcamlLocalRepresentationPlan(decisions);
	}

	static function unmigratedDecision(localId:Int, semanticTypeId:String):OcamlLocalRepresentationDecision {
		return {
			localId: localId,
			choice: OcamlLocalRepresentationChoice.Unmigrated(semanticTypeId),
			initializerConversion: OcamlLocalCarrierConversion.LegacyCoercion,
			assignmentConversion: OcamlLocalCarrierConversion.LegacyCoercion,
			readConversion: OcamlLocalCarrierConversion.LegacyCoercion
		};
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
