package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlDecision;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlPayloadConversion;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlTargetMechanism;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlTransferKind;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

/** The runtime identifier and requirement owned by one sealed return operation. */
typedef OcamlReturnRuntimeUsePlan = {
	final decisionId:String;
	final planRevision:String;
	final runtimeRequirementIds:Array<String>;
	final runtimeUseOccurrences:Array<OcamlRuntimeUseOccurrence>;
}

/**
	Builds and validates private-runtime ownership for one early return.

	The control decision already says which function exits and whether a value
	crosses the boundary. This contract adds only the narrower permissions to use
	the matching private OCaml signal and, when required, the Boolean box that
	keeps `Dynamic` Boolean and integer values distinct.
**/
class OcamlReturnRuntimeUseContract {
	public static inline final SIGNAL_ROLE = "raise-function-return-signal";
	public static inline final BOUNDARY_PATTERN_ROLE = "catch-function-return-signal";
	public static inline final BOOL_PAYLOAD_ROLE = "box-dynamic-bool-return-payload";

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
		return planFor(decision, SIGNAL_ROLE, OcamlRuntimeUseDomain.ExpressionIdentifier);
	}

	/** Derives the checked constructor matched by the owning function boundary. */
	public static function forBoundaryDecision(decision:OcamlControlDecision):OcamlReturnRuntimeUsePlan {
		return planFor(decision, BOUNDARY_PATTERN_ROLE, OcamlRuntimeUseDomain.PatternConstructor);
	}

	/** Derives the Boolean box used by one typed Bool-to-Dynamic return. */
	public static function forBoolPayloadDecision(decision:OcamlControlDecision):OcamlReturnRuntimeUsePlan {
		OcamlControlPlan.requireDecision(decision);
		if (decision.payload == null
			|| decision.payload.conversion != OcamlControlPayloadConversion.BoxBoolAndRecoverDynamicTypedFunctionResult) {
			throw 'reflaxe.ocaml [ocaml-return:unexpected-runtime-use]: return decision "${decision.id}" does not own a Dynamic Boolean payload';
		}
		return planForSymbol(decision, BOOL_PAYLOAD_ROLE, OcamlRuntimeUseDomain.ExpressionIdentifier, "HxRuntime.box_bool", 1);
	}

	/** Rejects a missing, stale, or conflicting return runtime-use plan. */
	public static function requireForDecision(decision:OcamlControlDecision, plan:OcamlReturnRuntimeUsePlan):Void {
		final expected = forDecision(decision);
		requireExact(decision, plan, expected);
	}

	/** Rejects a missing, stale, or conflicting function-boundary pattern plan. */
	public static function requireForBoundaryDecision(decision:OcamlControlDecision, plan:OcamlReturnRuntimeUsePlan):Void {
		final expected = forBoundaryDecision(decision);
		requireExact(decision, plan, expected);
	}

	/** Rejects a missing or stale Boolean-payload runtime-use plan. */
	public static function requireForBoolPayloadDecision(decision:OcamlControlDecision, plan:OcamlReturnRuntimeUsePlan):Void {
		final expected = forBoolPayloadDecision(decision);
		requireExact(decision, plan, expected);
	}

	static function requireExact(decision:OcamlControlDecision, plan:OcamlReturnRuntimeUsePlan, expected:OcamlReturnRuntimeUsePlan):Void {
		if (plan == null
			|| plan.decisionId != expected.decisionId
			|| plan.planRevision != expected.planRevision
			|| plan.runtimeRequirementIds.join(",") != expected.runtimeRequirementIds.join(",")
			|| plan.runtimeUseOccurrences.length != 1
			|| !sameOccurrence(plan.runtimeUseOccurrences[0], expected.runtimeUseOccurrences[0])) {
			throw 'reflaxe.ocaml [ocaml-return:invalid-runtime-use]: return decision "${decision.id}" does not own its exact runtime requirement and occurrence';
		}
	}

	/** Returns the checked constructor occurrence for one function boundary. */
	public static function boundaryPatternOccurrence(plan:OcamlReturnRuntimeUsePlan):OcamlRuntimeUseOccurrence {
		if (plan.runtimeUseOccurrences.length != 1 || plan.runtimeUseOccurrences[0].role != BOUNDARY_PATTERN_ROLE)
			throw 'reflaxe.ocaml [ocaml-return:invalid-runtime-use]: return decision "${plan.decisionId}" has no unique boundary pattern occurrence';
		return copyOccurrence(plan.runtimeUseOccurrences[0]);
	}

	/** Returns the checked occurrence that prints the private return signal. */
	public static function signalOccurrence(plan:OcamlReturnRuntimeUsePlan):OcamlRuntimeUseOccurrence {
		if (plan.runtimeUseOccurrences.length != 1 || plan.runtimeUseOccurrences[0].role != SIGNAL_ROLE)
			throw 'reflaxe.ocaml [ocaml-return:invalid-runtime-use]: return decision "${plan.decisionId}" has no unique signal occurrence';
		return copyOccurrence(plan.runtimeUseOccurrences[0]);
	}

	/** Returns the checked occurrence that boxes one Dynamic Boolean payload. */
	public static function boolPayloadOccurrence(plan:OcamlReturnRuntimeUsePlan):OcamlRuntimeUseOccurrence {
		if (plan.runtimeUseOccurrences.length != 1 || plan.runtimeUseOccurrences[0].role != BOOL_PAYLOAD_ROLE)
			throw 'reflaxe.ocaml [ocaml-return:invalid-runtime-use]: return decision "${plan.decisionId}" has no unique Dynamic Boolean payload occurrence';
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

	static function planFor(decision:OcamlControlDecision, role:String, domain:OcamlRuntimeUseDomain):OcamlReturnRuntimeUsePlan {
		OcamlControlPlan.requireDecision(decision);
		if (decision.kind != OcamlControlTransferKind.Return)
			throw 'reflaxe.ocaml [ocaml-return:unexpected-runtime-use]: control decision "${decision.id}" is not a return';
		// The final AST inventory visits the signal constructor before its payload.
		// A Dynamic Boolean helper is therefore second. The matching boundary
		// pattern is last for the same decision.
		final hasBoolPayload = decision.payload != null
			&& decision.payload.conversion == OcamlControlPayloadConversion.BoxBoolAndRecoverDynamicTypedFunctionResult;
		final order = role == SIGNAL_ROLE ? 0 : (hasBoolPayload ? 2 : 1);
		return planForSymbol(decision, role, domain, signalSymbol(decision), order);
	}

	static function planForSymbol(decision:OcamlControlDecision, role:String, domain:OcamlRuntimeUseDomain, exactSymbol:String,
			order:Int):OcamlReturnRuntimeUsePlan {
		OcamlControlPlan.requireDecision(decision);
		if (decision.kind != OcamlControlTransferKind.Return)
			throw 'reflaxe.ocaml [ocaml-return:unexpected-runtime-use]: control decision "${decision.id}" is not a return';
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
					id: decision.id + ":runtime-use:" + role,
					planRevision: planRevision,
					ownerId: decision.id,
					requirementId: selectedRequirementId,
					domain: domain,
					exactSymbol: exactSymbol,
					role: role,
					order: order,
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

	static function signalSymbol(decision:OcamlControlDecision):String {
		return switch (decision.mechanism) {
			case RuntimeReturnSignal: "HxRuntime.Hx_return";
			case RuntimeVoidReturnSignal: "HxRuntime.Hx_return_void";
			case _: throw 'reflaxe.ocaml [ocaml-return:unexpected-runtime-use]: return decision "${decision.id}" has unsupported mechanism ${decision.mechanism}';
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
