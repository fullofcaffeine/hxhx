package reflaxe.ocaml.tooling;

import haxe.Json;
import haxe.crypto.Sha256;
import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapInterfaceCallDecision;
import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapInterfaceContract;
import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapInterfaceConversionDecision;
import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapInterfaceConversionRole;
import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapInterfaceMethodDecision;
import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapInterfaceSourceKind;
import reflaxe.ocaml.lowered.OcamlIMapInterfaceModel.OcamlIMapInterfaceSourceSpan;
import reflaxe.ocaml.lowered.OcamlStandardIMapCallModel.OcamlStandardIMapCallContract;
import reflaxe.ocaml.lowered.OcamlStandardIMapCallModel.OcamlStandardIMapKeyKind;
import reflaxe.ocaml.lowered.OcamlStandardIMapCallModel.OcamlStandardIMapOperation;
import reflaxe.ocaml.lowered.OcamlStandardIMapCallModel.OcamlStandardIMapStringifier;
import reflaxe.ocaml.tooling.InspectionReport.InspectionIMapInterfaceCall;
import reflaxe.ocaml.tooling.InspectionReport.InspectionIMapInterfaceConversion;
import reflaxe.ocaml.tooling.InspectionReport.InspectionIMapInterfaceMethod;

/** Validated `IMap` conversion and dispatch inventory returned by inspection. */
typedef InspectionIMapInterfaceInventory = {
	final revision:String;
	final conversions:Array<InspectionIMapInterfaceConversion>;
	final calls:Array<InspectionIMapInterfaceCall>;
}

/**
	Validates saved `IMap` evidence without consulting generated OCaml text.

	A concrete standard map and a user class can both become `IMap<K, V>`, but
	they do not share the same storage. The lowering report therefore records the
	exact conversion at each boundary and records later interface calls separately.
	This reader reconstructs those plain decisions, applies the same contract used
	before code generation, and recomputes the inventory digest. Edited, missing,
	or stale evidence makes inspection fail instead of presenting a plausible cast.
**/
class ReflaxeOcamlIMapInterfaceInspection {
	/** Reads and validates every concrete-to-interface conversion and interface call. */
	public static function inspect(value:Dynamic):InspectionIMapInterfaceInventory {
		final model = requiredString(value, "iMapInterfaceModel");
		if (model != OcamlIMapInterfaceContract.MODEL)
			throw 'Unsupported IMap interface report model "$model".';

		final rawConversions = requiredArray(value, "iMapInterfaceConversions");
		final conversionCount = requiredInt(value, "iMapInterfaceConversionCount");
		if (rawConversions.length != conversionCount)
			throw 'IMap interface conversion count is $conversionCount but the inventory contains ${rawConversions.length} entries.';
		final conversions = [for (entry in rawConversions) conversion(entry)];
		validateOrderedConversions(conversions);

		final rawCalls = requiredArray(value, "iMapInterfaceCalls");
		final callCount = requiredInt(value, "iMapInterfaceCallCount");
		if (rawCalls.length != callCount)
			throw 'IMap interface call count is $callCount but the inventory contains ${rawCalls.length} entries.';
		final calls = [for (entry in rawCalls) call(entry)];
		validateOrderedCalls(calls);
		validateRetainedSurface(conversions, calls);

		final revision = requiredSha256Revision(value, "iMapInterfaceRevision");
		final expectedRevision = "sha256:" + Sha256.encode(Json.stringify({conversions: conversions, calls: calls}));
		if (revision != expectedRevision)
			throw 'IMap interface report revision is $revision but its validated inventory produces $expectedRevision.';

		return {
			revision: revision,
			conversions: conversions.map(inspectionConversion),
			calls: calls.map(inspectionCall)
		};
	}

	static function validateOrderedConversions(conversions:Array<OcamlIMapInterfaceConversionDecision>):Void {
		for (index in 0...conversions.length) {
			final current = conversions[index];
			OcamlIMapInterfaceContract.requireConversion(current);
			if (current.pipelineRevision != "ocaml-function-plans-v74")
				throw 'IMap interface conversion "${current.id}" belongs to unsupported pipeline "${current.pipelineRevision}".';
			if (index > 0 && Reflect.compare(conversions[index - 1].id, current.id) >= 0)
				throw 'The IMap interface conversion inventory is not in strict identity order at "${current.id}".';
		}
	}

	static function validateOrderedCalls(calls:Array<OcamlIMapInterfaceCallDecision>):Void {
		for (index in 0...calls.length) {
			final current = calls[index];
			OcamlIMapInterfaceContract.requireCall(current);
			if (current.pipelineRevision != "ocaml-function-plans-v74")
				throw 'IMap interface call "${current.id}" belongs to unsupported pipeline "${current.pipelineRevision}".';
			if (index > 0 && Reflect.compare(calls[index - 1].id, current.id) >= 0)
				throw 'The IMap interface call inventory is not in strict identity order at "${current.id}".';
		}
	}

	/**
		Proves that every concrete adapter implements the same DCE-retained fields.

		Haxe emits one `IMap` record type for the final program, so a standard Map
		and a user class cannot legitimately report different field subsets. Every
		recorded interface call must also name a field present on that shared record.
	**/
	static function validateRetainedSurface(conversions:Array<OcamlIMapInterfaceConversionDecision>, calls:Array<OcamlIMapInterfaceCallDecision>):Void {
		if (conversions.length == 0)
			return;
		final retainedNames = conversions[0].methods.map(method -> method.name);
		final retainedKey = retainedNames.join(",");
		for (conversion in conversions) {
			if (conversion.methods.map(method -> method.name).join(",") != retainedKey)
				throw 'IMap interface conversion "${conversion.id}" disagrees with the shared retained method surface "$retainedKey".';
		}
		for (call in calls) {
			final fieldName = OcamlStandardIMapCallContract.sourceFieldName(call.operation);
			if (retainedNames.indexOf(fieldName) < 0)
				throw 'IMap interface call "${call.id}" uses field "$fieldName", which is absent from the retained method surface "$retainedKey".';
		}
	}

	static function conversion(value:Dynamic):OcamlIMapInterfaceConversionDecision {
		final source = sourceSpan(value, "conversion");
		return {
			id: requiredString(value, "id"),
			source: source,
			role: cast(requiredString(value, "role"), OcamlIMapInterfaceConversionRole),
			roleIndex: requiredInt(value, "roleIndex"),
			sourceKind: cast(requiredString(value, "sourceKind"), OcamlIMapInterfaceSourceKind),
			sourceSemanticTypeId: requiredString(value, "sourceSemanticTypeId"),
			sourceCarrierTypeId: requiredString(value, "sourceCarrierTypeId"),
			targetSemanticTypeId: requiredString(value, "targetSemanticTypeId"),
			targetCarrierTypeId: requiredString(value, "targetCarrierTypeId"),
			keySemanticTypeId: requiredString(value, "keySemanticTypeId"),
			valueSemanticTypeId: requiredString(value, "valueSemanticTypeId"),
			standardKeyKind: cast(optionalString(value, "standardKeyKind"), Null<OcamlStandardIMapKeyKind>),
			keyStringifier: cast(optionalString(value, "keyStringifier"), Null<OcamlStandardIMapStringifier>),
			valueStringifier: cast(optionalString(value, "valueStringifier"), Null<OcamlStandardIMapStringifier>),
			methods: [for (entry in requiredArray(value, "methods")) method(entry)],
			runtimeCapabilities: requiredStringArray(value, "runtimeCapabilities"),
			proofId: requiredString(value, "proofId"),
			proofClaim: requiredString(value, "proofClaim"),
			functionId: requiredString(value, "functionId"),
			programRevision: requiredString(value, "programRevision"),
			bodyRevision: requiredString(value, "bodyRevision"),
			pipelineRevision: requiredString(value, "pipelineRevision")
		};
	}

	static function call(value:Dynamic):OcamlIMapInterfaceCallDecision {
		final source = sourceSpan(value, "call");
		return {
			id: requiredString(value, "id"),
			source: source,
			operation: cast(requiredString(value, "operation"), OcamlStandardIMapOperation),
			receiverSemanticTypeId: requiredString(value, "receiverSemanticTypeId"),
			receiverCarrierTypeId: requiredString(value, "receiverCarrierTypeId"),
			keySemanticTypeId: requiredString(value, "keySemanticTypeId"),
			valueSemanticTypeId: requiredString(value, "valueSemanticTypeId"),
			argumentSemanticTypeIds: requiredStringArray(value, "argumentSemanticTypeIds"),
			resultSemanticTypeId: requiredString(value, "resultSemanticTypeId"),
			proofId: requiredString(value, "proofId"),
			proofClaim: requiredString(value, "proofClaim"),
			functionId: requiredString(value, "functionId"),
			programRevision: requiredString(value, "programRevision"),
			bodyRevision: requiredString(value, "bodyRevision"),
			pipelineRevision: requiredString(value, "pipelineRevision")
		};
	}

	static function method(value:Dynamic):OcamlIMapInterfaceMethodDecision {
		return {
			name: requiredString(value, "name"),
			sourceOwnerModuleId: requiredString(value, "sourceOwnerModuleId"),
			sourceOwnerTypeName: requiredString(value, "sourceOwnerTypeName"),
			argumentSemanticTypeIds: requiredStringArray(value, "argumentSemanticTypeIds"),
			resultSemanticTypeId: requiredString(value, "resultSemanticTypeId")
		};
	}

	static function inspectionConversion(decision:OcamlIMapInterfaceConversionDecision):InspectionIMapInterfaceConversion {
		return {
			id: decision.id,
			sourceFile: decision.source.file,
			sourceMin: decision.source.min,
			sourceMax: decision.source.max,
			role: decision.role,
			roleIndex: decision.roleIndex,
			sourceKind: decision.sourceKind,
			sourceSemanticTypeId: decision.sourceSemanticTypeId,
			sourceCarrierTypeId: decision.sourceCarrierTypeId,
			targetSemanticTypeId: decision.targetSemanticTypeId,
			targetCarrierTypeId: decision.targetCarrierTypeId,
			keySemanticTypeId: decision.keySemanticTypeId,
			valueSemanticTypeId: decision.valueSemanticTypeId,
			standardKeyKind: decision.standardKeyKind,
			keyStringifier: decision.keyStringifier,
			valueStringifier: decision.valueStringifier,
			methods: decision.methods.map(inspectionMethod),
			runtimeCapabilities: decision.runtimeCapabilities.copy(),
			proofId: decision.proofId,
			proofClaim: decision.proofClaim,
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
	}

	static function inspectionCall(decision:OcamlIMapInterfaceCallDecision):InspectionIMapInterfaceCall {
		return {
			id: decision.id,
			sourceFile: decision.source.file,
			sourceMin: decision.source.min,
			sourceMax: decision.source.max,
			operation: decision.operation,
			receiverSemanticTypeId: decision.receiverSemanticTypeId,
			receiverCarrierTypeId: decision.receiverCarrierTypeId,
			keySemanticTypeId: decision.keySemanticTypeId,
			valueSemanticTypeId: decision.valueSemanticTypeId,
			argumentSemanticTypeIds: decision.argumentSemanticTypeIds.copy(),
			resultSemanticTypeId: decision.resultSemanticTypeId,
			proofId: decision.proofId,
			proofClaim: decision.proofClaim,
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
	}

	static function inspectionMethod(decision:OcamlIMapInterfaceMethodDecision):InspectionIMapInterfaceMethod {
		return {
			name: decision.name,
			sourceOwnerModuleId: decision.sourceOwnerModuleId,
			sourceOwnerTypeName: decision.sourceOwnerTypeName,
			argumentSemanticTypeIds: decision.argumentSemanticTypeIds.copy(),
			resultSemanticTypeId: decision.resultSemanticTypeId
		};
	}

	static function sourceSpan(value:Dynamic, owner:String):OcamlIMapInterfaceSourceSpan {
		final source = requiredObject(value, "source");
		final min = requiredInt(source, "min");
		final max = requiredInt(source, "max");
		if (min < 0 || max < min)
			throw 'IMap interface $owner has an invalid source span.';
		return {file: requiredString(source, "file"), min: min, max: max};
	}

	static function requiredObject(value:Dynamic, field:String):Dynamic {
		if (!Reflect.hasField(value, field))
			throw 'Expected IMap interface object "$field".';
		final result = Reflect.field(value, field);
		if (result == null || !Reflect.isObject(result) || Std.isOfType(result, Array))
			throw 'Expected IMap interface object "$field".';
		return result;
	}

	static function requiredArray(value:Dynamic, field:String):Array<Dynamic> {
		final result = Reflect.field(value, field);
		if (!Std.isOfType(result, Array))
			throw 'Expected IMap interface array "$field".';
		return cast result;
	}

	static function requiredStringArray(value:Dynamic, field:String):Array<String> {
		final result = requiredArray(value, field);
		for (entry in result)
			if (!Std.isOfType(entry, String))
				throw 'Expected IMap interface string array "$field".';
		return cast result;
	}

	static function requiredString(value:Dynamic, field:String):String {
		final result = Reflect.field(value, field);
		if (!Std.isOfType(result, String) || (cast result : String).length == 0)
			throw 'Expected non-empty IMap interface string "$field".';
		return cast result;
	}

	static function optionalString(value:Dynamic, field:String):Null<String> {
		if (!Reflect.hasField(value, field))
			throw 'Expected optional IMap interface string "$field".';
		final result = Reflect.field(value, field);
		if (result == null)
			return null;
		return requiredString(value, field);
	}

	static function requiredInt(value:Dynamic, field:String):Int {
		final result = Reflect.field(value, field);
		if (!Std.isOfType(result, Int))
			throw 'Expected IMap interface integer "$field".';
		return cast result;
	}

	static function requiredSha256Revision(value:Dynamic, field:String):String {
		final revision = requiredString(value, field);
		if (!~/^sha256:[0-9a-f]{64}$/.match(revision))
			throw 'Expected IMap interface SHA-256 revision "$field".';
		return revision;
	}
}
