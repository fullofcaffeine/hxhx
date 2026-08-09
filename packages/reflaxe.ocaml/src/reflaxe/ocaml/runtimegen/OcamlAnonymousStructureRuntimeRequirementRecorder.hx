package reflaxe.ocaml.runtimegen;

#if (macro || reflaxe_runtime)
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureContract;
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureLoadConversion;
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureOperationDecision;
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureOperationKind;
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureStoreConversion;
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
		final expectedIds = OcamlAnonymousStructureContract.runtimeRequirementIdsFor(operation);
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
		if (operation.storeConversion == OcamlAnonymousStructureStoreConversion.BoxBool
			|| operation.loadConversion == OcamlAnonymousStructureLoadConversion.UnboxBool) {
			out.push(boolCarrierRequirement(operation));
		}
		if (operation.kind == OcamlAnonymousStructureOperationKind.CompoundWriteField) {
			out.push(OcamlRuntimeRequirementLedger.requirementForPlaceCapability(operation.id, operation.id, operation.occurrenceId, operation.source,
				operation.fieldSemanticTypeId, OcamlAnonymousStructureContract.int32AddRuntimeRequirementId(operation.id)));
		}
		return out;
	}

	/** Builds the direct `HxRuntime` requirement for one Boolean field conversion. */
	static function boolCarrierRequirement(operation:OcamlAnonymousStructureOperationDecision):OcamlRuntimeRequirement {
		final convertsStoredBool = operation.storeConversion == OcamlAnonymousStructureStoreConversion.BoxBool
			|| operation.loadConversion == OcamlAnonymousStructureLoadConversion.UnboxBool;
		if (!convertsStoredBool)
			throw 'reflaxe.ocaml [ocaml-anonymous:unexpected-bool-runtime]: operation "${operation.id}" has no Boolean field conversion';
		final expectedId = OcamlAnonymousStructureContract.boolCarrierRuntimeRequirementId(operation.id);
		if (!operation.runtimeRequirementIds.contains(expectedId))
			throw 'reflaxe.ocaml [ocaml-anonymous:wrong-bool-runtime]: operation "${operation.id}" does not name its exact Boolean carrier requirement';
		return {
			id: expectedId,
			sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
			sourceId: operation.occurrenceId,
			source: operation.source,
			semanticCapability: OcamlAnonymousStructureContract.BOOL_CARRIER_CAPABILITY,
			cause: OcamlRuntimeRequirementCause.LoweringDecision,
			decisionId: operation.id,
			subject: {
				kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
				id: operation.fieldSemanticTypeId
			},
			implementationFeature: "haxe-boolean-carrier-v1",
			rootModules: ["HxRuntime"],
			profileEligibility: ["metal", "portable"],
			explanation: operation.loadConversion == OcamlAnonymousStructureLoadConversion.UnboxBool ? "The sealed anonymous Boolean read uses HxRuntime to recover the typed Bool from the object's universal field slot." : "The sealed anonymous Boolean write uses HxRuntime to place the typed Bool in the object's universal field slot."
		};
	}

	/** Adds every operation requirement to the request-owned runtime ledger. */
	public static function record(ledger:OcamlRuntimeRequirementLedger, operation:OcamlAnonymousStructureOperationDecision):Void {
		for (requirement in requirements(operation))
			ledger.record(requirement);
	}
}
#end
