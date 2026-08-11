package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlDecision;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlTargetMechanism;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlTransferKind;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

/** The one private runtime call selected by an exact sealed Haxe throw. */
typedef OcamlThrowRuntimeUsePlan = {
	final decisionId:String;
	final planRevision:String;
	final runtimeRequirementIds:Array<String>;
	final runtimeUseOccurrences:Array<OcamlRuntimeUseOccurrence>;
}

/**
	Builds and checks private-runtime ownership for one planned Haxe throw.

	The control decision already fixes the payload conversion, runtime tags, and
	exception channel. This contract adds only permission to print the matching
	private `HxType` call once for that exact source occurrence.
**/
class OcamlThrowRuntimeUseContract {
	public static inline final SIGNAL_ROLE = "raise-typed-haxe-exception";
	public static inline final SIGNAL_SYMBOL = "HxType.hx_throw_typed_rtti";

	/** Returns the runtime requirement identity owned by one exact throw. */
	public static function requirementId(decision:OcamlControlDecision):String {
		return decision.id + ":runtime:" + decision.runtimeCapabilityId;
	}

	/** Returns the runtime-use identity owned by one exact throw. */
	public static function runtimeUseId(decisionId:String):String {
		return decisionId + ":runtime-use:" + SIGNAL_ROLE;
	}

	/** Derives the one private call selected by a valid throw decision. */
	public static function forDecision(decision:OcamlControlDecision):OcamlThrowRuntimeUsePlan {
		OcamlControlPlan.requireDecision(decision);
		if (decision.kind != OcamlControlTransferKind.Throw
			|| decision.mechanism != OcamlControlTargetMechanism.RuntimeTypedHaxeExceptionSignal) {
			throw 'reflaxe.ocaml [ocaml-throw:unexpected-runtime-use]: control decision "${decision.id}" is not a typed Haxe throw';
		}
		final binding:OcamlFunctionPlanBinding = {
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
		final planRevision = OcamlRuntimeUseModel.planRevision(binding);
		final selectedRequirementId = requirementId(decision);
		return {
			decisionId: decision.id,
			planRevision: planRevision,
			runtimeRequirementIds: [selectedRequirementId],
			runtimeUseOccurrences: [
				{
					id: runtimeUseId(decision.id),
					planRevision: planRevision,
					ownerId: decision.id,
					requirementId: selectedRequirementId,
					domain: OcamlRuntimeUseDomain.ExpressionIdentifier,
					exactSymbol: SIGNAL_SYMBOL,
					role: SIGNAL_ROLE,
					order: 0,
					source: {
						file: decision.source.file,
						min: decision.source.min,
						max: decision.source.max
					},
					profileEligibility: decision.profileEligibility.copy(),
					cardinality: 1
				}
			]
		};
	}

	/** Rejects a missing, stale, or conflicting throw runtime-use plan. */
	public static function requireForDecision(decision:OcamlControlDecision, plan:OcamlThrowRuntimeUsePlan):Void {
		final expected = forDecision(decision);
		if (plan == null
			|| plan.decisionId != expected.decisionId
			|| plan.planRevision != expected.planRevision
			|| plan.runtimeRequirementIds.join(",") != expected.runtimeRequirementIds.join(",")
			|| plan.runtimeUseOccurrences.length != 1
			|| !sameOccurrence(plan.runtimeUseOccurrences[0], expected.runtimeUseOccurrences[0])) {
			throw 'reflaxe.ocaml [ocaml-throw:invalid-runtime-use]: throw decision "${decision.id}" does not own its exact runtime requirement and signal occurrence';
		}
	}

	/** Returns the checked occurrence that prints the typed exception call. */
	public static function signalOccurrence(plan:OcamlThrowRuntimeUsePlan):OcamlRuntimeUseOccurrence {
		if (plan.runtimeUseOccurrences.length != 1 || plan.runtimeUseOccurrences[0].role != SIGNAL_ROLE)
			throw 'reflaxe.ocaml [ocaml-throw:invalid-runtime-use]: throw decision "${plan.decisionId}" has no unique signal occurrence';
		return copyOccurrence(plan.runtimeUseOccurrences[0]);
	}

	static function sameOccurrence(actual:OcamlRuntimeUseOccurrence, expected:OcamlRuntimeUseOccurrence):Bool {
		return actual != null
			&& actual.id == expected.id
			&& actual.planRevision == expected.planRevision
			&& actual.ownerId == expected.ownerId
			&& actual.requirementId == expected.requirementId
			&& actual.domain == expected.domain
			&& actual.exactSymbol == expected.exactSymbol
			&& actual.role == expected.role
			&& actual.order == expected.order
			&& actual.source.file == expected.source.file
			&& actual.source.min == expected.source.min
			&& actual.source.max == expected.source.max
			&& actual.profileEligibility.join(",") == expected.profileEligibility.join(",")
			&& actual.cardinality == expected.cardinality;
	}

	static function copyOccurrence(occurrence:OcamlRuntimeUseOccurrence):OcamlRuntimeUseOccurrence {
		return {
			id: occurrence.id,
			planRevision: occurrence.planRevision,
			ownerId: occurrence.ownerId,
			requirementId: occurrence.requirementId,
			domain: occurrence.domain,
			exactSymbol: occurrence.exactSymbol,
			role: occurrence.role,
			order: occurrence.order,
			source: {
				file: occurrence.source.file,
				min: occurrence.source.min,
				max: occurrence.source.max
			},
			profileEligibility: occurrence.profileEligibility.copy(),
			cardinality: occurrence.cardinality
		};
	}
}
#end
