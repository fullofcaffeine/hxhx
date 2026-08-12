package reflaxe.ocaml.runtimegen;

#if (macro || reflaxe_runtime)
import reflaxe.ocaml.lowered.OcamlReflectComparePlan;
import reflaxe.ocaml.lowered.OcamlReflectComparePlan.OcamlReflectCompareDecision;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementCause;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementSourceKind;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementSubjectKind;

/**
	Connects one typed comparison to its exact private runtime modules.

	The comparator plan has already decided the value domain, null policy, and
	failure policy. This adapter only converts those immutable choices into the
	requirements used by packaging and reports.
**/
class OcamlReflectCompareRuntimeRequirementRecorder {
	/** Returns the runtime reasons owned by one typed comparator. */
	public static function requirementsFor(decision:OcamlReflectCompareDecision):Array<OcamlRuntimeRequirement> {
		OcamlReflectComparePlan.requireDecision(decision);
		return decision.runtimeRequirementIds.map(requirementId -> {
			final stringNull = StringTools.endsWith(requirementId, ":" + OcamlReflectComparePlan.STRING_NULL_RUNTIME_CAPABILITY);
			return {
				id: requirementId,
				sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
				sourceId: decision.id,
				source: decision.source,
				semanticCapability: stringNull ? OcamlReflectComparePlan.STRING_NULL_RUNTIME_CAPABILITY : OcamlRuntimeRequirementLedger.HAXE_REFLECT_COMPARE_FAILURE,
				cause: OcamlRuntimeRequirementCause.LoweringDecision,
				decisionId: decision.id,
				subject: {
					kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
					id: "Reflect.compare:" + (decision.domain : String)
				},
				implementationFeature: stringNull ? "haxe-string-null-check-v1" : "haxe-typed-throw-v1",
				rootModules: [stringNull ? "HxString" : "HxRuntime"],
				profileEligibility: ["metal", "portable"],
				explanation: stringNull ? "The sealed String comparator checks each operand against Haxe's String null sentinel before it applies its selected ordering policy." : "The sealed typed comparator rejects an invalid Float or String ordering through the Haxe exception channel, so generated OCaml needs the catchable HxRuntime throw helper."
			};
		});
	}

	/** Records the runtime dependencies selected by one typed comparator. */
	public static function record(ledger:OcamlRuntimeRequirementLedger, decision:OcamlReflectCompareDecision):Void {
		for (requirement in requirementsFor(decision))
			ledger.record(requirement);
	}
}
#end
