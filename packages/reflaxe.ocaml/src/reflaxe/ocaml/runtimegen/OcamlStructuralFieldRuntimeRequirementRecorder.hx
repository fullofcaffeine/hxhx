package reflaxe.ocaml.runtimegen;

#if (macro || reflaxe_runtime)
import reflaxe.ocaml.lowered.OcamlStructuralFieldPlan.OcamlStructuralFieldContract;
import reflaxe.ocaml.lowered.OcamlStructuralFieldPlan.OcamlStructuralFieldDecision;
import reflaxe.ocaml.lowered.OcamlStructuralFieldPlan.OcamlStructuralFieldLoadConversion;
import reflaxe.ocaml.lowered.OcamlStructuralFieldPlan.OcamlStructuralFieldOperation;
import reflaxe.ocaml.lowered.OcamlStructuralFieldPlan.OcamlStructuralFieldStoreConversion;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementCause;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementSourceKind;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirementSubjectKind;

/**
	Explains the runtime module selected for one ambiguous structural field.

	For example, a linked-node `next` field needs `HxAnon.get`, while a captured
	`Iterator.next` method needs `HxIterator.next`. A proven Map pair uses
	`Stdlib.fst` or `Stdlib.snd`, which ships with OCaml and therefore adds no
	repository-owned runtime module. The sealed field decision has already made
	that distinction; this recorder only transfers its runtime dependencies.
**/
class OcamlStructuralFieldRuntimeRequirementRecorder {
	/** Builds the repository runtime requirements owned by a sealed decision. */
	public static function requirements(decision:OcamlStructuralFieldDecision):Array<OcamlRuntimeRequirement> {
		OcamlStructuralFieldContract.require(decision);
		if (OcamlStructuralFieldContract.isTupleProjection(decision.operation))
			return [];
		final result = [requirement(decision)];
		if (decision.loadConversion == UnboxBool || decision.storeConversion == BoxBool)
			result.push(boolCarrierRequirement(decision));
		return result;
	}

	/** Builds the one runtime requirement for a non-Stdlib field operation. */
	public static function requirement(decision:OcamlStructuralFieldDecision):OcamlRuntimeRequirement {
		OcamlStructuralFieldContract.require(decision);
		if (OcamlStructuralFieldContract.isTupleProjection(decision.operation))
			throw 'reflaxe.ocaml [ocaml-structural-field:unexpected-runtime]: tuple projection "${decision.id}" uses OCaml Stdlib and has no repository runtime requirement';
		final expectedId = OcamlStructuralFieldContract.runtimeRequirementId(decision.id, decision.operation);
		if (!decision.runtimeRequirementIds.contains(expectedId))
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

	/** Builds the direct HxRuntime requirement for a stored Boolean conversion. */
	public static function boolCarrierRequirement(decision:OcamlStructuralFieldDecision):OcamlRuntimeRequirement {
		OcamlStructuralFieldContract.require(decision);
		if (decision.loadConversion != UnboxBool && decision.storeConversion != BoxBool)
			throw 'reflaxe.ocaml [ocaml-structural-field:unexpected-bool-runtime]: decision "${decision.id}" has no Boolean field conversion';
		final expectedId = OcamlStructuralFieldContract.boolCarrierRuntimeRequirementId(decision.id);
		if (!decision.runtimeRequirementIds.contains(expectedId))
			throw 'reflaxe.ocaml [ocaml-structural-field:wrong-bool-runtime]: decision "${decision.id}" does not name its exact Boolean carrier requirement';
		return {
			id: expectedId,
			sourceKind: OcamlRuntimeRequirementSourceKind.HaxeExpression,
			sourceId: decision.id,
			source: decision.source,
			semanticCapability: OcamlStructuralFieldContract.HAXE_BOOL_CARRIER_CAPABILITY,
			cause: OcamlRuntimeRequirementCause.LoweringDecision,
			decisionId: decision.id,
			subject: {
				kind: OcamlRuntimeRequirementSubjectKind.HaxeType,
				id: decision.fieldSemanticTypeId
			},
			implementationFeature: "haxe-boolean-carrier-v1",
			rootModules: ["HxRuntime"],
			profileEligibility: ["metal", "portable"],
			explanation: decision.loadConversion == UnboxBool ? "The sealed structural Boolean read uses HxRuntime to recover the typed Bool from universal field storage." : "The sealed structural Boolean write uses HxRuntime to place the typed Bool in universal field storage."
		};
	}

	/** Adds every repository runtime requirement to the active request. */
	public static function record(ledger:OcamlRuntimeRequirementLedger, decision:OcamlStructuralFieldDecision):Void {
		for (required in requirements(decision))
			ledger.record(required);
	}
}
#end
