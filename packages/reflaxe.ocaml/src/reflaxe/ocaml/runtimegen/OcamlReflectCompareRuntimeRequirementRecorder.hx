package reflaxe.ocaml.runtimegen;

#if (macro || reflaxe_runtime)
import reflaxe.ocaml.lowered.OcamlReflectComparePlan;
import reflaxe.ocaml.lowered.OcamlReflectComparePlan.OcamlReflectCompareDecision;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementCause;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementSourceKind;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementSubjectKind;

/**
	Connects one typed exceptional comparison to its Haxe exception runtime.

	The comparator plan has already decided whether invalid input is possible.
	This adapter only turns that immutable decision into the requirement consumed
	by packaging and reports; it does not inspect generated OCaml or choose
	comparison behavior.
**/
class OcamlReflectCompareRuntimeRequirementRecorder {
	/** Returns the runtime reason owned by one exceptional typed comparator. */
	public static function requirementsFor(decision:OcamlReflectCompareDecision):Array<OcamlRuntimeRequirement> {
		OcamlReflectComparePlan.requireDecision(decision);
		if (decision.runtimeRequirementIds.length == 0)
			return [];
		return [
			{
				id: decision.runtimeRequirementIds[0],
				sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
				sourceId: decision.id,
				source: decision.source,
				semanticCapability: OcamlRuntimeRequirementLedger.HAXE_REFLECT_COMPARE_FAILURE,
				cause: OcamlRuntimeRequirementCause.LoweringDecision,
				decisionId: decision.id,
				subject: {
					kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
					id: "Reflect.compare:" + (decision.domain : String)
				},
				implementationFeature: "haxe-typed-throw-v1",
				rootModules: ["HxRuntime"],
				profileEligibility: ["metal", "portable"],
				explanation: "The sealed typed comparator rejects an invalid Float or String ordering through the Haxe exception channel, so generated OCaml needs the catchable HxRuntime throw helper."
			}
		];
	}

	/** Records the runtime dependency selected by one exceptional comparator. */
	public static function record(ledger:OcamlRuntimeRequirementLedger, decision:OcamlReflectCompareDecision):Void {
		for (requirement in requirementsFor(decision))
			ledger.record(requirement);
	}
}
#end
