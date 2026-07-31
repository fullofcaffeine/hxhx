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
	/** Builds every runtime requirement owned by an admitted operation. */
	public static function requirements(operation:OcamlAnonymousStructureOperationDecision):Array<OcamlRuntimeRequirement> {
		final expectedIds = OcamlAnonymousStructureContract.runtimeRequirementIds(operation.id, operation.kind);
		if (operation.runtimeRequirementIds.join("\n") != expectedIds.join("\n")
			|| operation.runtimeModule != OcamlAnonymousStructureContract.RUNTIME_MODULE) {
			throw 'reflaxe.ocaml [ocaml-anonymous:wrong-runtime]: operation "${operation.id}" does not name the exact runtime requirements selected by its sealed plan';
		}
		final out:Array<OcamlRuntimeRequirement> = [
			{
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
			}
		];
		if (operation.runtimeRequirementIds.length == 2) {
			out.push(OcamlRuntimeRequirementLedger.requirementForPlaceCapability(operation.id, operation.id, operation.occurrenceId, operation.source,
				operation.fieldSemanticTypeId, operation.runtimeRequirementIds[1]));
		}
		return out;
	}

	/** Adds every operation requirement to the request-owned runtime ledger. */
	public static function record(ledger:OcamlRuntimeRequirementLedger, operation:OcamlAnonymousStructureOperationDecision):Void {
		for (requirement in requirements(operation))
			ledger.record(requirement);
	}
}
#end
