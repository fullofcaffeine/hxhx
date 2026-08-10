package reflaxe.ocaml.runtimegen;

#if (macro || reflaxe_runtime)
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallDecision;
import reflaxe.ocaml.lowered.OcamlCallRuntimeUseModel.OcamlCallRuntimeUseContract;
import reflaxe.ocaml.lowered.OcamlCallRuntimeUseModel.OcamlCallRuntimeUsePlan;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementCause;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementSourceKind;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementSubjectKind;

/**
	Transfers a sealed Boolean call conversion into the runtime inventory.

	The call planner has already proved that a particular argument must enter a
	`Dynamic` parameter through the distinguishable Boolean box. This recorder
	does not inspect generated OCaml or make another type decision; it only tells
	packaging why that exact call needs `HxRuntime`.
**/
class OcamlCallRuntimeRequirementRecorder {
	/** Builds one direct-root requirement for each runtime use owned by the call. */
	public static function requirements(call:OcamlCallDecision, plan:OcamlCallRuntimeUsePlan):Array<OcamlRuntimeRequirement> {
		OcamlCallRuntimeUseContract.requireForCall(call, plan);
		return [
			for (occurrence in plan.runtimeUseOccurrences)
				if (occurrence.role == "standard-array-operation" && call.standardArrayTarget != null) {
					id: occurrence.requirementId,
					sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
					sourceId: call.id,
					source: occurrence.source,
					semanticCapability: OcamlCallRuntimeUseContract.HAXE_ARRAY_CALL_CAPABILITY,
					cause: OcamlRuntimeRequirementCause.LoweringDecision,
					decisionId: call.id,
					subject: {
						kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
						id: call.standardArrayTarget.receiverSemanticTypeId
					},
					implementationFeature: "haxe-array-v1",
					rootModules: [call.standardArrayTarget.runtimeModule],
					profileEligibility: occurrence.profileEligibility.copy(),
					explanation: "The sealed standard Array call evaluates its receiver before source arguments and then invokes the exact HxArray operation selected from the final typed call."
				} else {
					id: occurrence.requirementId,
					sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
					sourceId: call.id,
					source: occurrence.source,
					semanticCapability: OcamlCallRuntimeUseContract.HAXE_BOOL_CARRIER_CAPABILITY,
					cause: OcamlRuntimeRequirementCause.LoweringDecision,
					decisionId: call.id,
					subject: {
						kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
						id: "Bool"
					},
					implementationFeature: "haxe-boolean-carrier-v1",
					rootModules: ["HxRuntime"],
					profileEligibility: occurrence.profileEligibility.copy(),
					explanation: "The sealed typed call boxes one exact Bool argument slot with HxRuntime so Dynamic preserves the difference between Bool and Int."
				}
		];
	}

	/** Records all requirements in the current request-local ledger. */
	public static function record(ledger:OcamlRuntimeRequirementLedger, call:OcamlCallDecision, plan:OcamlCallRuntimeUsePlan):Void {
		for (requirement in requirements(call, plan))
			ledger.record(requirement);
	}
}
#end
