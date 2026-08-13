package reflaxe.ocaml.tooling;

import haxe.Json;
import haxe.crypto.Sha256;
import reflaxe.ocaml.lowered.OcamlStructuralFieldPlan.OcamlStructuralFieldContract;
import reflaxe.ocaml.lowered.OcamlStructuralFieldPlan.OcamlStructuralFieldDecision;
import reflaxe.ocaml.lowered.OcamlStructuralFieldPlan.OcamlKeyValueTupleProjectionTarget;
import reflaxe.ocaml.lowered.OcamlStructuralIteratorCallModel.OcamlStructuralIteratorCallTarget;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;
import reflaxe.ocaml.tooling.InspectionReport.InspectionStructuralField;
import reflaxe.ocaml.tooling.InspectionReport.InspectionStructuralIteratorCallTarget;

/** Validated structural-field inventory returned to the public inspector. */
typedef InspectionStructuralFieldInventory = {
	final revision:String;
	final decisions:Array<InspectionStructuralField>;
}

/**
	Validates ambiguous structural fields without reading generated OCaml.

	The saved lowering report must say whether each overlapping field occurrence
	was an ordinary stored field, a captured Iterator method, or a proven Map-pair
	projection. This reader rebuilds the plain decision, applies the same contract
	used before syntax generation, and recomputes the inventory digest. Missing or
	edited evidence therefore makes public inspection fail instead of presenting a
	plausible but unowned runtime use.
**/
class ReflaxeOcamlStructuralFieldInspection {
	/** Reads and validates the complete structural-field inventory. */
	public static function inspect(value:Dynamic):InspectionStructuralFieldInventory {
		final model = requiredString(value, "structuralFieldModel");
		if (model != OcamlStructuralFieldContract.MODEL)
			throw 'Unsupported structural-field report model "$model".';
		final rawDecisions = requiredArray(value, "structuralFields");
		final expectedCount = requiredInt(value, "structuralFieldCount");
		if (rawDecisions.length != expectedCount)
			throw 'Structural-field count is $expectedCount but the inventory contains ${rawDecisions.length} entries.';
		final decisions = [for (entry in rawDecisions) decision(entry)];
		for (index in 0...decisions.length) {
			final current = decisions[index];
			OcamlStructuralFieldContract.require(current);
			if (current.pipelineRevision != "ocaml-function-plans-v111"
				&& current.pipelineRevision != "ocaml-standalone-expression-plans-v4")
				throw 'Structural field decision "${current.id}" belongs to unsupported pipeline "${current.pipelineRevision}".';
			if (index > 0 && Reflect.compare(decisions[index - 1].id, current.id) >= 0)
				throw 'The structural-field inventory is not in strict identity order at "${current.id}".';
		}
		final revision = requiredSha256Revision(value, "structuralFieldRevision");
		final expectedRevision = "sha256:" + Sha256.encode(Json.stringify(decisions));
		if (revision != expectedRevision)
			throw 'Structural-field report revision is $revision but its validated inventory produces $expectedRevision.';
		return {
			revision: revision,
			decisions: decisions.map(inspectionDecision)
		};
	}

	static function decision(value:Dynamic):OcamlStructuralFieldDecision {
		final source = requiredObject(value, "source");
		final sourceMin = requiredInt(source, "min");
		final sourceMax = requiredInt(source, "max");
		if (sourceMin < 0 || sourceMax < sourceMin)
			throw "Structural field decision has an invalid source span.";
		final rawIteratorTarget = Reflect.hasField(value, "iteratorTarget") ? Reflect.field(value, "iteratorTarget") : null;
		if (!Reflect.hasField(value, "keyValueTupleTarget"))
			throw 'Expected structural-field field "keyValueTupleTarget".';
		final rawTupleTarget = Reflect.field(value, "keyValueTupleTarget");
		return {
			id: requiredString(value, "id"),
			occurrenceOrdinal: requiredInt(value, "occurrenceOrdinal"),
			source: {
				file: requiredString(source, "file"),
				min: sourceMin,
				max: sourceMax
			},
			operation: cast requiredString(value, "operation"),
			fieldName: requiredString(value, "fieldName"),
			receiverSemanticTypeId: requiredString(value, "receiverSemanticTypeId"),
			receiverCarrierTypeId: requiredString(value, "receiverCarrierTypeId"),
			fieldSemanticTypeId: requiredString(value, "fieldSemanticTypeId"),
			resultSemanticTypeId: requiredString(value, "resultSemanticTypeId"),
			loadConversion: cast optionalString(value, "loadConversion"),
			storeConversion: cast optionalString(value, "storeConversion"),
			runtimeModule: requiredString(value, "runtimeModule"),
			runtimeOperation: requiredString(value, "runtimeOperation"),
			runtimeRequirementIds: requiredStringArray(value, "runtimeRequirementIds"),
			runtimeUseOccurrences: runtimeUseOccurrences(value),
			evaluationSchedule: requiredStringArray(value, "evaluationSchedule"),
			iteratorTarget: rawIteratorTarget == null ? null : iteratorTarget(requiredObject(value, "iteratorTarget")),
			keyValueTupleTarget: rawTupleTarget == null ? null : keyValueTupleTarget(requiredObject(value, "keyValueTupleTarget")),
			proofId: requiredString(value, "proofId"),
			proofClaim: requiredString(value, "proofClaim"),
			functionId: requiredString(value, "functionId"),
			programRevision: requiredString(value, "programRevision"),
			bodyRevision: requiredString(value, "bodyRevision"),
			pipelineRevision: requiredString(value, "pipelineRevision")
		};
	}

	static function runtimeUseOccurrences(value:Dynamic):Array<OcamlRuntimeUseOccurrence> {
		return [
			for (entry in requiredArray(value, "runtimeUseOccurrences")) {
				final source = requiredObject(entry, "source");
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
						file: requiredString(source, "file"),
						min: requiredInt(source, "min"),
						max: requiredInt(source, "max")
					},
					profileEligibility: requiredStringArray(entry, "profileEligibility"),
					cardinality: requiredInt(entry, "cardinality")
				};
			}
		];
	}

	static function keyValueTupleTarget(value:Dynamic):OcamlKeyValueTupleProjectionTarget {
		return {
			projection: requiredString(value, "projection"),
			iteratorProducerKind: requiredString(value, "iteratorProducerKind"),
			iteratorProducerId: requiredString(value, "iteratorProducerId"),
			iteratorProducerSourceId: requiredString(value, "iteratorProducerSourceId"),
			pairProducerCallId: requiredString(value, "pairProducerCallId"),
			iteratorLocalId: requiredString(value, "iteratorLocalId"),
			pairLocalId: requiredString(value, "pairLocalId"),
			iteratorSemanticTypeId: requiredString(value, "iteratorSemanticTypeId"),
			pairSemanticTypeId: requiredString(value, "pairSemanticTypeId"),
			keySemanticTypeId: requiredString(value, "keySemanticTypeId"),
			valueSemanticTypeId: requiredString(value, "valueSemanticTypeId"),
			proofId: requiredString(value, "proofId"),
			proofClaim: requiredString(value, "proofClaim")
		};
	}

	static function iteratorTarget(value:Dynamic):OcamlStructuralIteratorCallTarget {
		return {
			operation: cast requiredString(value, "operation"),
			receiverSemanticTypeId: requiredString(value, "receiverSemanticTypeId"),
			receiverCarrierTypeId: requiredString(value, "receiverCarrierTypeId"),
			resultSemanticTypeId: requiredString(value, "resultSemanticTypeId"),
			runtimeModule: requiredString(value, "runtimeModule"),
			runtimeFunction: requiredString(value, "runtimeFunction"),
			runtimeCapabilities: requiredStringArray(value, "runtimeCapabilities"),
			proofId: requiredString(value, "proofId"),
			proofClaim: requiredString(value, "proofClaim")
		};
	}

	static function inspectionDecision(decision:OcamlStructuralFieldDecision):InspectionStructuralField {
		return {
			id: decision.id,
			occurrenceOrdinal: decision.occurrenceOrdinal,
			sourceFile: decision.source.file,
			sourceMin: decision.source.min,
			sourceMax: decision.source.max,
			operation: decision.operation,
			fieldName: decision.fieldName,
			receiverSemanticTypeId: decision.receiverSemanticTypeId,
			receiverCarrierTypeId: decision.receiverCarrierTypeId,
			fieldSemanticTypeId: decision.fieldSemanticTypeId,
			resultSemanticTypeId: decision.resultSemanticTypeId,
			loadConversion: decision.loadConversion,
			storeConversion: decision.storeConversion,
			runtimeModule: decision.runtimeModule,
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
			evaluationSchedule: decision.evaluationSchedule.copy(),
			iteratorTarget: decision.iteratorTarget == null ? null : cast iteratorInspection(decision.iteratorTarget),
			proofId: decision.proofId,
			proofClaim: decision.proofClaim,
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
	}

	static function iteratorInspection(target:OcamlStructuralIteratorCallTarget):InspectionStructuralIteratorCallTarget {
		return {
			operation: target.operation,
			receiverSemanticTypeId: target.receiverSemanticTypeId,
			receiverCarrierTypeId: target.receiverCarrierTypeId,
			resultSemanticTypeId: target.resultSemanticTypeId,
			runtimeModule: target.runtimeModule,
			runtimeFunction: target.runtimeFunction,
			runtimeCapabilities: target.runtimeCapabilities.copy(),
			proofId: target.proofId,
			proofClaim: target.proofClaim
		};
	}

	static function requiredObject(value:Dynamic, field:String):Dynamic {
		if (!Reflect.hasField(value, field))
			throw 'Expected structural-field object "$field".';
		final result = Reflect.field(value, field);
		if (result == null || !Reflect.isObject(result) || Std.isOfType(result, Array))
			throw 'Expected structural-field object "$field".';
		return result;
	}

	static function requiredArray(value:Dynamic, field:String):Array<Dynamic> {
		final result = Reflect.field(value, field);
		if (!Std.isOfType(result, Array))
			throw 'Expected structural-field array "$field".';
		return cast result;
	}

	static function requiredStringArray(value:Dynamic, field:String):Array<String> {
		final result = requiredArray(value, field);
		for (entry in result)
			if (!Std.isOfType(entry, String))
				throw 'Expected structural-field string array "$field".';
		return cast result;
	}

	static function requiredString(value:Dynamic, field:String):String {
		final result = Reflect.field(value, field);
		if (!Std.isOfType(result, String) || (cast result : String).length == 0)
			throw 'Expected non-empty structural-field string "$field".';
		return cast result;
	}

	static function optionalString(value:Dynamic, field:String):Null<String> {
		if (!Reflect.hasField(value, field) || Reflect.field(value, field) == null)
			return null;
		return requiredString(value, field);
	}

	static function requiredInt(value:Dynamic, field:String):Int {
		final result = Reflect.field(value, field);
		if (!Std.isOfType(result, Int))
			throw 'Expected structural-field integer "$field".';
		return cast result;
	}

	static function requiredSha256Revision(value:Dynamic, field:String):String {
		final revision = requiredString(value, field);
		if (!~/^sha256:[0-9a-f]{64}$/.match(revision))
			throw 'Expected structural-field SHA-256 revision "$field".';
		return revision;
	}
}
