package reflaxe.ocaml.runtimegen;

#if (macro || reflaxe_runtime)
import reflaxe.ocaml.lowered.OcamlStructuralFieldPlan.OcamlStructuralFieldContract;
import reflaxe.ocaml.lowered.OcamlStructuralFieldPlan.OcamlStructuralFieldDecision;
import reflaxe.ocaml.lowered.OcamlStructuralFieldPlan.OcamlStructuralFieldOperation;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementCause;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementSourceKind;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementSubjectKind;

/**
	Explains the runtime module selected for one ambiguous structural field.

	For example, a linked-node `next` field needs `HxAnon.get`, while a captured
	`Iterator.next` method needs `HxIterator.next`. The sealed field decision has
	already made that distinction from the final Haxe type; this recorder only
	transfers the answer into the request-owned runtime inventory.
**/
class OcamlStructuralFieldRuntimeRequirementRecorder {
	/** Builds the one runtime requirement owned by a sealed field decision. */
	public static function requirement(decision:OcamlStructuralFieldDecision):OcamlRuntimeRequirement {
		OcamlStructuralFieldContract.require(decision);
		final expectedId = OcamlStructuralFieldContract.runtimeRequirementId(decision.id, decision.operation);
		if (decision.runtimeRequirementIds.length != 1 || decision.runtimeRequirementIds[0] != expectedId)
			throw 'reflaxe.ocaml [ocaml-structural-field:wrong-runtime]: decision "${decision.id}" does not name its exact runtime requirement';
		final iteratorMethod = decision.operation == OcamlStructuralFieldOperation.CaptureIteratorMethod;
		return {
			id: expectedId,
			sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
			sourceId: decision.id,
			source: decision.source,
			semanticCapability: iteratorMethod ? OcamlStructuralFieldContract.HAXE_ITERATOR_CAPABILITY : OcamlStructuralFieldContract.HAXE_ANON_CAPABILITY,
			cause: OcamlRuntimeRequirementCause.LoweringDecision,
			decisionId: decision.id,
			subject: {
				kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
				id: decision.receiverSemanticTypeId
			},
			implementationFeature: iteratorMethod ? "haxe-iterator-v1" : "haxe-anonymous-structure-v1",
			rootModules: [decision.runtimeModule],
			profileEligibility: ["metal", "portable"],
			explanation: iteratorMethod ? 'The sealed ${decision.fieldName} method-value occurrence captures ${decision.runtimeModule}.${decision.runtimeOperation} from a complete structural Iterator receiver.' : 'The sealed ${decision.fieldName} field occurrence uses ${decision.runtimeModule}.${decision.runtimeOperation} because the final typed receiver is an ordinary stored structural object, not an Iterator method selected by name.'
		};
	}

	/** Adds the decision's exact runtime requirement to the active request. */
	public static function record(ledger:OcamlRuntimeRequirementLedger, decision:OcamlStructuralFieldDecision):Void {
		ledger.record(requirement(decision));
	}
}
#end
