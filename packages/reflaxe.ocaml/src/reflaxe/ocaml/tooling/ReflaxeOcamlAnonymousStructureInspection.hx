package reflaxe.ocaml.tooling;

import haxe.Json;
import haxe.crypto.Sha256;
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureContract;
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureDecision;
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureField;
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureLoadConversion;
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureOperationDecision;
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureOperationKind;
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureStoreConversion;
import reflaxe.ocaml.tooling.InspectionReport.InspectionAnonymousStructure;
import reflaxe.ocaml.tooling.InspectionReport.InspectionAnonymousStructureField;
import reflaxe.ocaml.tooling.InspectionReport.InspectionAnonymousStructureOperation;
import reflaxe.ocaml.tooling.InspectionReport.InspectionRepresentation;
import reflaxe.ocaml.tooling.InspectionReport.InspectionRepresentationDecision;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

/** Validated anonymous-object inventory returned to the public inspector. */
typedef InspectionAnonymousStructureInventory = {
	final revision:String;
	final structures:Array<InspectionAnonymousStructure>;
	final operations:Array<InspectionAnonymousStructureOperation>;
}

/**
	Validates anonymous-object decisions without reading generated OCaml source.

	The lowering report records which mutable runtime object shape and which
	create, initialize, read, or write operation the compiler selected before
	printing target syntax. This reader reconstructs those plain data records,
	runs the same fail-closed contract as code generation, and checks every
	carrier against the program-wide representation inventory. A corrupted report
	therefore fails inspection instead of being presented as trustworthy evidence.
**/
class ReflaxeOcamlAnonymousStructureInspection {
	/** Reads the complete anonymous-object family from one lowering report. */
	public static function inspect(value:Dynamic, representation:InspectionRepresentation):InspectionAnonymousStructureInventory {
		final model = requiredString(value, "anonymousStructureModel");
		if (model != OcamlAnonymousStructureContract.MODEL_REVISION)
			throw 'Unsupported anonymous-structure report model "$model".';
		final rawStructures = requiredArray(value, "anonymousStructures");
		final expectedStructureCount = requiredInt(value, "anonymousStructureCount");
		if (rawStructures.length != expectedStructureCount)
			throw 'Anonymous-structure count is $expectedStructureCount but the inventory contains ${rawStructures.length} entries.';
		final structures = [for (entry in rawStructures) structure(entry)];
		requireStrictIdentityOrder(structures.map(item -> item.id), "anonymous structure");

		final representationById:Map<String, InspectionRepresentationDecision> = [];
		for (decision in representation.decisions)
			representationById.set(decision.id, decision);
		final structureById:Map<String, OcamlAnonymousStructureDecision> = [];
		for (decision in structures) {
			OcamlAnonymousStructureContract.requireStructure(decision);
			requireRepresentation(representationById, decision.representationId, decision.semanticTypeId, decision.carrierTypeId,
				decision.representationRevision, 'Anonymous structure "${decision.id}"');
			for (field in decision.fields) {
				requireRepresentation(representationById, field.representationId, field.semanticTypeId, field.carrierTypeId, field.representationRevision,
					'Anonymous structure "${decision.id}" field "${field.name}"');
			}
			structureById.set(decision.id, decision);
		}

		final rawOperations = requiredArray(value, "anonymousStructureOperations");
		final expectedOperationCount = requiredInt(value, "anonymousStructureOperationCount");
		if (rawOperations.length != expectedOperationCount)
			throw 'Anonymous-structure operation count is $expectedOperationCount but the inventory contains ${rawOperations.length} entries.';
		final operations = [for (entry in rawOperations) operation(entry)];
		requireStrictIdentityOrder(operations.map(item -> item.id), "anonymous operation");
		for (decision in operations) {
			final owner = structureById.get(decision.structureId);
			if (owner == null)
				throw 'Anonymous operation "${decision.id}" refers to missing structure "${decision.structureId}".';
			OcamlAnonymousStructureContract.requireOperation(decision, owner);
		}

		final revision = requiredSha256Revision(value, "anonymousStructureRevision");
		final expectedRevision = "sha256:" + Sha256.encode(Json.stringify({
			structures: structures,
			operations: operations
		}));
		if (revision != expectedRevision)
			throw 'Anonymous-structure report revision is $revision but its validated inventory produces $expectedRevision.';
		return {
			revision: revision,
			structures: structures.map(inspectionStructure),
			operations: operations.map(inspectionOperation)
		};
	}

	static function requireRepresentation(byId:Map<String, InspectionRepresentationDecision>, id:String, semanticTypeId:String, carrierTypeId:String,
			revision:String, owner:String):Void {
		final decision = byId.get(id);
		if (decision == null)
			throw '$owner refers to missing program representation "$id".';
		if (decision.semanticTypeId != semanticTypeId
			|| decision.carrierTypeId != carrierTypeId
			|| decision.domain != "internal-value"
			|| decision.revision != revision) {
			throw '$owner expects $semanticTypeId -> $carrierTypeId in internal-value at $revision, but "$id" selects ${decision.semanticTypeId} -> ${decision.carrierTypeId} in ${decision.domain} at ${decision.revision}.';
		}
	}

	static function requireStrictIdentityOrder(ids:Array<String>, label:String):Void {
		for (index in 0...ids.length) {
			if (ids[index].length == 0)
				throw 'The $label inventory contains an empty identity.';
			if (index > 0 && Reflect.compare(ids[index - 1], ids[index]) >= 0)
				throw 'The $label inventory is not in strict identity order at "${ids[index]}".';
		}
	}

	static function structure(value:Dynamic):OcamlAnonymousStructureDecision {
		return {
			id: requiredString(value, "id"),
			semanticTypeId: requiredString(value, "semanticTypeId"),
			carrierTypeId: requiredString(value, "carrierTypeId"),
			fields: [for (entry in requiredArray(value, "fields")) structureField(entry)],
			representationId: requiredString(value, "representationId"),
			representationRevision: requiredSha256Revision(value, "representationRevision"),
			representationDomain: requiredString(value, "representationDomain"),
			nullPolicy: requiredString(value, "nullPolicy"),
			identityPolicy: requiredString(value, "identityPolicy"),
			aliasingPolicy: requiredString(value, "aliasingPolicy"),
			mutationPolicy: requiredString(value, "mutationPolicy"),
			proofId: requiredString(value, "proofId"),
			proofClaim: requiredString(value, "proofClaim"),
			programRevision: requiredString(value, "programRevision"),
			revision: requiredSha256Revision(value, "revision")
		};
	}

	static function structureField(value:Dynamic):OcamlAnonymousStructureField {
		return {
			name: requiredString(value, "name"),
			canonicalOrder: requiredInt(value, "canonicalOrder"),
			semanticTypeId: requiredString(value, "semanticTypeId"),
			carrierTypeId: requiredString(value, "carrierTypeId"),
			representationId: requiredString(value, "representationId"),
			representationRevision: requiredSha256Revision(value, "representationRevision"),
			storeConversion: cast requiredString(value, "storeConversion"),
			loadConversion: cast requiredString(value, "loadConversion")
		};
	}

	static function operation(value:Dynamic):OcamlAnonymousStructureOperationDecision {
		final source = requiredObject(value, "source");
		final kindValue = requiredString(value, "kind");
		if (kindValue != OcamlAnonymousStructureOperationKind.Create
			&& kindValue != OcamlAnonymousStructureOperationKind.InitializeField
			&& kindValue != OcamlAnonymousStructureOperationKind.ReadField
			&& kindValue != OcamlAnonymousStructureOperationKind.WriteField
			&& kindValue != OcamlAnonymousStructureOperationKind.CompoundWriteField) {
			throw 'Anonymous operation has unsupported kind "$kindValue".';
		}
		final sourceMin = requiredInt(source, "min");
		final sourceMax = requiredInt(source, "max");
		if (sourceMin < 0 || sourceMax < sourceMin)
			throw "Anonymous operation has an invalid source span.";
		final runtimeUseOccurrences:Array<OcamlRuntimeUseOccurrence> = [
			for (entry in requiredArray(value, "runtimeUseOccurrences")) {
				final useSource = requiredObject(entry, "source");
				{
					id: requiredString(entry, "id"),
					planRevision: requiredSha256Revision(entry, "planRevision"),
					ownerId: requiredString(entry, "ownerId"),
					requirementId: requiredString(entry, "requirementId"),
					domain: cast requiredString(entry, "domain"),
					exactSymbol: requiredString(entry, "exactSymbol"),
					role: requiredString(entry, "role"),
					order: requiredInt(entry, "order"),
					source: {
						file: requiredString(useSource, "file"),
						min: requiredInt(useSource, "min"),
						max: requiredInt(useSource, "max")
					},
					profileEligibility: requiredStringArray(entry, "profileEligibility"),
					cardinality: requiredInt(entry, "cardinality")
				};
			}
		];
		return {
			id: requiredString(value, "id"),
			occurrenceId: requiredString(value, "occurrenceId"),
			source: {
				file: requiredString(source, "file"),
				min: sourceMin,
				max: sourceMax
			},
			kind: cast kindValue,
			structureId: requiredString(value, "structureId"),
			structureRevision: requiredSha256Revision(value, "structureRevision"),
			structureRepresentationId: requiredString(value, "structureRepresentationId"),
			structureRepresentationRevision: requiredSha256Revision(value, "structureRepresentationRevision"),
			fieldName: optionalString(value, "fieldName"),
			fieldCanonicalOrder: requiredInt(value, "fieldCanonicalOrder"),
			fieldSourceOrder: requiredInt(value, "fieldSourceOrder"),
			fieldSemanticTypeId: requiredString(value, "fieldSemanticTypeId"),
			fieldCarrierTypeId: requiredString(value, "fieldCarrierTypeId"),
			fieldRepresentationId: requiredString(value, "fieldRepresentationId"),
			fieldRepresentationRevision: requiredString(value, "fieldRepresentationRevision"),
			storeConversion: cast optionalString(value, "storeConversion"),
			loadConversion: cast optionalString(value, "loadConversion"),
			fieldOperator: cast optionalString(value, "fieldOperator"),
			evaluationSchedule: requiredStringArray(value, "evaluationSchedule"),
			resultSemanticTypeId: requiredString(value, "resultSemanticTypeId"),
			resultCarrierTypeId: requiredString(value, "resultCarrierTypeId"),
			resultRepresentationId: requiredString(value, "resultRepresentationId"),
			resultRepresentationRevision: requiredString(value, "resultRepresentationRevision"),
			runtimeModule: requiredString(value, "runtimeModule"),
			runtimeReadOperation: optionalString(value, "runtimeReadOperation"),
			runtimeOperation: requiredString(value, "runtimeOperation"),
			runtimeRequirementIds: requiredStringArray(value, "runtimeRequirementIds"),
			runtimeUseOccurrences: runtimeUseOccurrences,
			proofId: requiredString(value, "proofId"),
			proofClaim: requiredString(value, "proofClaim"),
			functionId: requiredString(value, "functionId"),
			programRevision: requiredString(value, "programRevision"),
			bodyRevision: requiredString(value, "bodyRevision"),
			pipelineRevision: requiredString(value, "pipelineRevision")
		};
	}

	static function inspectionStructure(decision:OcamlAnonymousStructureDecision):InspectionAnonymousStructure {
		return {
			id: decision.id,
			semanticTypeId: decision.semanticTypeId,
			carrierTypeId: decision.carrierTypeId,
			fields: decision.fields.map(inspectionField),
			representationId: decision.representationId,
			representationRevision: decision.representationRevision,
			representationDomain: decision.representationDomain,
			nullPolicy: decision.nullPolicy,
			identityPolicy: decision.identityPolicy,
			aliasingPolicy: decision.aliasingPolicy,
			mutationPolicy: decision.mutationPolicy,
			proofId: decision.proofId,
			proofClaim: decision.proofClaim,
			programRevision: decision.programRevision,
			revision: decision.revision
		};
	}

	static function inspectionField(field:OcamlAnonymousStructureField):InspectionAnonymousStructureField {
		return {
			name: field.name,
			canonicalOrder: field.canonicalOrder,
			semanticTypeId: field.semanticTypeId,
			carrierTypeId: field.carrierTypeId,
			representationId: field.representationId,
			representationRevision: field.representationRevision,
			storeConversion: field.storeConversion,
			loadConversion: field.loadConversion
		};
	}

	static function inspectionOperation(decision:OcamlAnonymousStructureOperationDecision):InspectionAnonymousStructureOperation {
		return {
			id: decision.id,
			occurrenceId: decision.occurrenceId,
			sourceFile: decision.source.file,
			sourceMin: decision.source.min,
			sourceMax: decision.source.max,
			kind: decision.kind,
			structureId: decision.structureId,
			structureRevision: decision.structureRevision,
			structureRepresentationId: decision.structureRepresentationId,
			structureRepresentationRevision: decision.structureRepresentationRevision,
			fieldName: decision.fieldName,
			fieldCanonicalOrder: decision.fieldCanonicalOrder,
			fieldSourceOrder: decision.fieldSourceOrder,
			fieldSemanticTypeId: decision.fieldSemanticTypeId,
			fieldCarrierTypeId: decision.fieldCarrierTypeId,
			fieldRepresentationId: decision.fieldRepresentationId,
			fieldRepresentationRevision: decision.fieldRepresentationRevision,
			storeConversion: decision.storeConversion,
			loadConversion: decision.loadConversion,
			fieldOperator: decision.fieldOperator,
			evaluationSchedule: decision.evaluationSchedule.copy(),
			resultSemanticTypeId: decision.resultSemanticTypeId,
			resultCarrierTypeId: decision.resultCarrierTypeId,
			resultRepresentationId: decision.resultRepresentationId,
			resultRepresentationRevision: decision.resultRepresentationRevision,
			runtimeModule: decision.runtimeModule,
			runtimeReadOperation: decision.runtimeReadOperation,
			runtimeOperation: decision.runtimeOperation,
			runtimeRequirementIds: decision.runtimeRequirementIds.copy(),
			runtimeUseOccurrences: decision.runtimeUseOccurrences.map(use -> {
				id: use.id,
				planRevision: use.planRevision,
				ownerId: use.ownerId,
				requirementId: use.requirementId,
				domain: use.domain,
				exactSymbol: use.exactSymbol,
				role: use.role,
				order: use.order,
				source: {
					file: use.source.file,
					min: use.source.min,
					max: use.source.max
				},
				profileEligibility: use.profileEligibility.copy(),
				cardinality: use.cardinality
			}),
			proofId: decision.proofId,
			proofClaim: decision.proofClaim,
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
	}

	static function requiredObject(value:Dynamic, name:String):Dynamic {
		final result = Reflect.field(value, name);
		if (result == null || Type.typeof(result) != TObject)
			throw 'Expected "$name" to be an object.';
		return result;
	}

	static function requiredArray(value:Dynamic, name:String):Array<Dynamic> {
		final result = Reflect.field(value, name);
		if (!Std.isOfType(result, Array))
			throw 'Expected "$name" to be an array.';
		return cast result;
	}

	static function requiredStringArray(value:Dynamic, name:String):Array<String> {
		final result = requiredArray(value, name);
		return [
			for (entry in result) {
				if (!Std.isOfType(entry, String)) throw 'Expected every "$name" entry to be a string.';
				(cast entry : String);
			}
		];
	}

	static function requiredString(value:Dynamic, name:String):String {
		final result = Reflect.field(value, name);
		if (!Std.isOfType(result, String))
			throw 'Expected "$name" to be a string.';
		return cast result;
	}

	static function optionalString(value:Dynamic, name:String):Null<String> {
		final result = Reflect.field(value, name);
		if (result == null)
			return null;
		if (!Std.isOfType(result, String))
			throw 'Expected "$name" to be a string or null.';
		return cast result;
	}

	static function requiredInt(value:Dynamic, name:String):Int {
		final result = Reflect.field(value, name);
		if (!Std.isOfType(result, Int))
			throw 'Expected "$name" to be an integer.';
		return cast result;
	}

	static function requiredSha256Revision(value:Dynamic, name:String):String {
		final result = requiredString(value, name);
		if (!~/^sha256:[0-9a-f]{64}$/.match(result))
			throw 'Expected "$name" to be a sha256: revision.';
		return result;
	}
}
