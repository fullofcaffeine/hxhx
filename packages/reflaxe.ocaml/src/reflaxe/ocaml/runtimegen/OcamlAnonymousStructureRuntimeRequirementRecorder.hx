package reflaxe.ocaml.runtimegen;

#if (macro || reflaxe_runtime)
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureContract;
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureOperationDecision;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementCause;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementSourceKind;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementSubjectKind;

/**
	Explains why one sealed anonymous operation needs the checked `HxAnon` module.

	The generated module-name scan remains a consistency check. This recorder is
	the semantic cause: it names the exact Haxe occurrence and operation that
	selected construction, initialization, lookup, or mutation behavior.
**/
class OcamlAnonymousStructureRuntimeRequirementRecorder {
	/** Builds the one runtime requirement owned by an admitted operation. */
	public static function requirement(operation:OcamlAnonymousStructureOperationDecision):OcamlRuntimeRequirement {
		if (operation.runtimeRequirementIds.length != 1
			|| operation.runtimeRequirementIds[0] != OcamlAnonymousStructureContract.runtimeRequirementId(operation.id)
			|| operation.runtimeModule != OcamlAnonymousStructureContract.RUNTIME_MODULE) {
			throw 'reflaxe.ocaml [ocaml-anonymous:wrong-runtime]: operation "${operation.id}" does not name the exact HxAnon requirement selected by its sealed plan';
		}
		return {
			id: operation.runtimeRequirementIds[0],
			sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
			sourceId: operation.occurrenceId,
			source: operation.source,
			semanticCapability: OcamlAnonymousStructureContract.RUNTIME_CAPABILITY,
			cause: OcamlRuntimeRequirementCause.LoweringDecision,
			decisionId: operation.id,
			subject: {
				kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
				id: operation.resultSemanticTypeId.length == 0 ? operation.structureId : operation.resultSemanticTypeId
			},
			implementationFeature: "haxe-anonymous-structure-v1",
			rootModules: [OcamlAnonymousStructureContract.RUNTIME_MODULE],
			profileEligibility: ["metal", "portable"],
			explanation: 'The sealed ${operation.kind} occurrence uses HxAnon.${operation.runtimeOperation} so one mutable anonymous object preserves Haxe field lookup, assignment, reference identity, aliases, and source-order evaluation.'
		};
	}

	/** Adds one operation requirement to the request-owned runtime ledger. */
	public static function record(ledger:OcamlRuntimeRequirementLedger, operation:OcamlAnonymousStructureOperationDecision):Void {
		ledger.record(requirement(operation));
	}
}
#end
