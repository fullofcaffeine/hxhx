package reflaxe.ocaml.runtimegen;

#if (macro || reflaxe_runtime)
import reflaxe.ocaml.lowered.OcamlContainerElementPlan;
import reflaxe.ocaml.lowered.OcamlContainerElementPlan.OcamlContainerElementDecision;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan.OcamlLocalCarrierConversion;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;

/** Maps a checked array-element conversion to the runtime module that preserves its type. */
class OcamlContainerRuntimeRequirementRecorder {
	/** Keeps the source occurrence as the owner of Boolean or enum boxing support. */
	public static function requirement(decision:OcamlContainerElementDecision):OcamlRuntimeRequirement {
		new OcamlContainerElementPlan([decision]);
		if (decision.conversion != OcamlLocalCarrierConversion.BoxExactBoolToDynamic)
			return OcamlEnumRuntimeRequirementRecorder.containerElementRequirement(decision);
		return {
			id: decision.id + ":runtime:haxe-bool-dynamic-box",
			sourceKind: HaxeExpression,
			sourceId: decision.id,
			source: decision.source,
			semanticCapability: "haxe-bool-dynamic-box",
			cause: LoweringDecision,
			decisionId: decision.id,
			subject: {
				kind: HaxeType,
				id: "Bool"
			},
			implementationFeature: "haxe-bool-dynamic-box-v1",
			rootModules: ["HxRuntime"],
			profileEligibility: decision.profileEligibility,
			explanation: "The sealed array element calls HxRuntime.box_bool before storage, so Dynamic observers distinguish Booleans from integer zero and one."
		};
	}

	/** Adds one source-bound requirement to the current compilation only. */
	public static function record(ledger:OcamlRuntimeRequirementLedger, decision:OcamlContainerElementDecision):Void {
		ledger.record(requirement(decision));
	}
}
#end
