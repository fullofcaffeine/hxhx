package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlDecision;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlTargetMechanism;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlTransferKind;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

/** The one private runtime identifier raised by an exact sealed Haxe return. */
typedef OcamlReturnRuntimeUsePlan = {
	final decisionId:String;
	final planRevision:String;
	final runtimeRequirementIds:Array<String>;
	final runtimeUseOccurrences:Array<OcamlRuntimeUseOccurrence>;
}

/**
	Builds and validates private-runtime ownership for one early return.

	The control decision already says which function exits and whether a value
	crosses the boundary. This contract adds only the narrower permission to print
	the matching private OCaml signal once for that exact typed return.
**/
class OcamlReturnRuntimeUseContract {
	public static inline final SIGNAL_ROLE = "raise-function-return-signal";

	/** Returns the requirement identity owned by one exact return decision. */
	public static function requirementId(decision:OcamlControlDecision):String {
		return decision.id + ":runtime:" + decision.runtimeCapabilityId;
	}

	/** Returns the occurrence identity owned by one exact return decision. */
	public static function runtimeUseId(decisionId:String):String {
		return decisionId + ":runtime-use:" + SIGNAL_ROLE;
	}

	/** Derives the one private signal use selected by a valid return decision. */
	public static function forDecision(decision:OcamlControlDecision):OcamlReturnRuntimeUsePlan {
		OcamlControlPlan.requireDecision(decision);
		if (decision.kind != OcamlControlTransferKind.Return)
			throw 'reflaxe.ocaml [ocaml-return:unexpected-runtime-use]: control decision "${decision.id}" is not a return';
		final exactSymbol = switch (decision.mechanism) {
			case RuntimeReturnSignal: "HxRuntime.Hx_return";
			case RuntimeVoidReturnSignal: "HxRuntime.Hx_return_void";
			case _: throw 'reflaxe.ocaml [ocaml-return:unexpected-runtime-use]: return decision "${decision.id}" has unsupported mechanism ${decision.mechanism}';
		};
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
					exactSymbol: exactSymbol,
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

	/** Rejects a missing, stale, or conflicting return runtime-use plan. */
	public static function requireForDecision(decision:OcamlControlDecision, plan:OcamlReturnRuntimeUsePlan):Void {
		final expected = forDecision(decision);
		if (plan == null
			|| plan.decisionId != expected.decisionId
			|| plan.planRevision != expected.planRevision
			|| plan.runtimeRequirementIds.join(",") != expected.runtimeRequirementIds.join(",")
			|| plan.runtimeUseOccurrences.length != 1
			|| !sameOccurrence(plan.runtimeUseOccurrences[0], expected.runtimeUseOccurrences[0])) {
			throw 'reflaxe.ocaml [ocaml-return:invalid-runtime-use]: return decision "${decision.id}" does not own its exact runtime requirement and signal occurrence';
		}
	}

	/** Returns the checked occurrence that prints the private return signal. */
	public static function signalOccurrence(plan:OcamlReturnRuntimeUsePlan):OcamlRuntimeUseOccurrence {
		if (plan.runtimeUseOccurrences.length != 1 || plan.runtimeUseOccurrences[0].role != SIGNAL_ROLE)
			throw 'reflaxe.ocaml [ocaml-return:invalid-runtime-use]: return decision "${plan.decisionId}" has no unique signal occurrence';
		return copyOccurrence(plan.runtimeUseOccurrences[0]);
	}

	/** Returns a detached copy suitable for request handoff and corruption tests. */
	public static function copy(plan:OcamlReturnRuntimeUsePlan):OcamlReturnRuntimeUsePlan {
		return {
			decisionId: plan.decisionId,
			planRevision: plan.planRevision,
			runtimeRequirementIds: plan.runtimeRequirementIds.copy(),
			runtimeUseOccurrences: plan.runtimeUseOccurrences.map(copyOccurrence)
		};
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
