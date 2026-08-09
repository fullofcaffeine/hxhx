package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime || eval)
import haxe.crypto.Sha256;
import reflaxe.ocaml.lowered.OcamlBytesProducerModel.OcamlBytesEncodingKind;
import reflaxe.ocaml.lowered.OcamlBytesRepresentationModel.OcamlBytesRepresentationContract;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

/** One exact read-only operation on the Haxe standard-library Bytes surface. */
enum abstract OcamlBytesReadKind(String) from String to String {
	final Length = "length";
	final Sub = "sub";
	final Compare = "compare";
	final GetString = "get-string";
	final ToString = "to-string";
	final ToHex = "to-hex";
}

/** The represented Haxe result family returned by one admitted Bytes read. */
enum abstract OcamlBytesReadResultKind(String) from String to String {
	final IntValue = "int";
	final StringValue = "string";
	final BytesValue = "bytes";
}

/** The exact conversion from the typed receiver into the direct Bytes carrier. */
enum abstract OcamlBytesReadReceiverConversion(String) from String to String {
	final Identity = "identity";
	final RequireNonNullBytes = "require-non-null-bytes";
}

/**
	One immutable Bytes read fixed before OCaml syntax is constructed.

	The receiver input preserves its exact typed representation. The receiver
	output is always direct Bytes, reached either unchanged or through the one
	Haxe-compatible checked `Null<Bytes>` conversion. Runtime arguments refer to
	request-owned representation decisions. An optional encoding selector is
	still recorded in source order, but it is a compile-time constant and
	therefore has no runtime carrier.
**/
typedef OcamlBytesReadDecision = {
	final id:String;
	final source:OcamlLoweredSourceSpan;
	final kind:OcamlBytesReadKind;
	final calleeId:String;
	final sourceModuleId:String;
	final sourceTypeName:String;
	final sourceFieldName:String;
	final hasReceiver:Bool;
	final receiverInputSemanticTypeId:String;
	final receiverInputCarrierTypeId:String;
	final receiverInputRepresentationId:String;
	final receiverInputRepresentationRevision:String;
	final receiverConversion:OcamlBytesReadReceiverConversion;
	final receiverSemanticTypeId:String;
	final receiverCarrierTypeId:String;
	final receiverRepresentationId:String;
	final receiverRepresentationRevision:String;
	final argumentCount:Int;
	final evaluationOrder:Array<Int>;
	final argumentSemanticTypeIds:Array<String>;
	final argumentCarrierTypeIds:Array<String>;
	final argumentRepresentationIds:Array<String>;
	final argumentRepresentationRevisions:Array<String>;
	final argumentRuntimeUse:Array<Bool>;
	final encoding:OcamlBytesEncodingKind;
	final resultKind:OcamlBytesReadResultKind;
	final resultSemanticTypeId:String;
	final resultCarrierTypeId:String;
	final resultRepresentationId:String;
	final resultRepresentationRevision:String;
	final resultNullability:String;
	final runtimeRequirementIds:Array<String>;
	final runtimeUseOccurrences:Array<OcamlRuntimeUseOccurrence>;
	final proofId:String;
	final proofClaim:String;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
}

/** Closed facts shared by Bytes read planning, syntax, and runtime reporting. */
class OcamlBytesReadContract {
	public static inline final RUNTIME_CAPABILITY = "haxe-bytes-read";
	public static inline final NULLABLE_RECEIVER_RUNTIME_CAPABILITY = "haxe-bytes-read-nullable-receiver";
	public static inline final RESULT_NULLABILITY = "non-null";
	public static inline final COMPILE_TIME_ENCODING_CARRIER = "compile-time-encoding-selector";
	public static inline final PROOF_ID = "exact-haxe-bytes-read-v1";
	public static inline final PROOF_CLAIM = "This exact standard-library Bytes read fixes its typed receiver input, optional checked Null<Bytes>-to-Bytes receiver conversion, source-ordered arguments, result representation, and HxBytes operation before target syntax. The receiver is evaluated once and a null receiver throws Null Access before any argument expression. The proof does not admit writes, inline-expanded storage reads, indexed access, other nullable materialization, Float or Int64 results, or non-Bytes calls.";

	/** Computes the deterministic identity shared by planning and validation. */
	public static function idFor(decision:OcamlBytesReadDecision):String {
		return "bytes-read:" + Sha256.encode([
			decision.functionId,
			decision.programRevision,
			decision.bodyRevision,
			decision.pipelineRevision,
			decision.source.file,
			Std.string(decision.source.min),
			Std.string(decision.source.max),
			(decision.kind : String),
			decision.calleeId,
			Std.string(decision.hasReceiver),
			decision.receiverInputSemanticTypeId,
			decision.receiverInputCarrierTypeId,
			decision.receiverInputRepresentationId,
			decision.receiverInputRepresentationRevision,
			(decision.receiverConversion : String),
			decision.receiverRepresentationId,
			decision.receiverRepresentationRevision,
			Std.string(decision.argumentCount),
			decision.evaluationOrder.join(","),
			decision.argumentSemanticTypeIds.join(","),
			decision.argumentCarrierTypeIds.join(","),
			decision.argumentRepresentationIds.join(","),
			decision.argumentRepresentationRevisions.join(","),
			decision.argumentRuntimeUse.map(value -> Std.string(value)).join(","),
			(decision.encoding : String),
			(decision.resultKind : String),
			decision.resultRepresentationId,
			decision.resultRepresentationRevision
		].join("\n")).substr(0, 24);
	}

	/** Returns the exact source field represented by one closed read kind. */
	public static function fieldName(kind:OcamlBytesReadKind):String {
		return switch (kind) {
			case Length: "length";
			case Sub: "sub";
			case Compare: "compare";
			case GetString: "getString";
			case ToString: "toString";
			case ToHex: "toHex";
		}
	}

	/** Returns the occurrence-local requirement for the final `HxBytes` read. */
	public static function runtimeRequirementId(decisionId:String):String {
		return decisionId + ":runtime:" + RUNTIME_CAPABILITY;
	}

	/** Returns the requirement for a checked `Null<Bytes>` receiver conversion. */
	public static function nullableReceiverRuntimeRequirementId(decisionId:String):String {
		return decisionId + ":runtime:" + NULLABLE_RECEIVER_RUNTIME_CAPABILITY;
	}

	/** Returns every direct runtime root selected by one read decision. */
	public static function runtimeRequirementIdsFor(decision:OcamlBytesReadDecision):Array<String> {
		final result = [runtimeRequirementId(decision.id)];
		if (decision.receiverConversion == OcamlBytesReadReceiverConversion.RequireNonNullBytes)
			result.push(nullableReceiverRuntimeRequirementId(decision.id));
		return result;
	}

	/**
		Builds the exact private names that syntax must use for this read.

		A nullable receiver is checked and throws before the final read call. Raw
		receiver and argument expressions are owned by their own decisions and are
		not duplicated here.
	**/
	public static function runtimeUseOccurrencesFor(decision:OcamlBytesReadDecision):Array<OcamlRuntimeUseOccurrence> {
		final binding:OcamlFunctionPlanBinding = {
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
		final planRevision = OcamlRuntimeUseModel.planRevision(binding);
		final result = new Array<OcamlRuntimeUseOccurrence>();

		function add(requirementId:String, exactSymbol:String, role:String):Void {
			result.push({
				id: decision.id + ":runtime-use:" + role,
				planRevision: planRevision,
				ownerId: decision.id,
				requirementId: requirementId,
				domain: OcamlRuntimeUseDomain.ExpressionIdentifier,
				exactSymbol: exactSymbol,
				role: role,
				order: result.length,
				source: {
					file: decision.source.file,
					min: decision.source.min,
					max: decision.source.max
				},
				profileEligibility: ["metal", "portable"],
				cardinality: 1
			});
		}

		if (decision.receiverConversion == OcamlBytesReadReceiverConversion.RequireNonNullBytes) {
			final requirementId = nullableReceiverRuntimeRequirementId(decision.id);
			add(requirementId, "HxRuntime.is_null", "check-null-receiver");
			add(requirementId, "HxRuntime.hx_throw_typed", "throw-null-receiver");
		}
		add(runtimeRequirementId(decision.id), "HxBytes." + fieldName(decision.kind), "read-bytes");
		return result;
	}

	/** Returns the exact represented result family for one read. */
	public static function resultKind(kind:OcamlBytesReadKind):OcamlBytesReadResultKind {
		return switch (kind) {
			case Length, Compare: IntValue;
			case Sub: BytesValue;
			case GetString, ToString, ToHex: StringValue;
		}
	}

	/** Returns the exact supported argument count for a decision. */
	public static function expectedArgumentCount(kind:OcamlBytesReadKind, encoding:OcamlBytesEncodingKind):Int {
		return switch (kind) {
			case Length, ToString, ToHex: 0;
			case Compare: 1;
			case Sub: 2;
			case GetString: encoding == OcamlBytesEncodingKind.Omitted ? 2 : 3;
		}
	}

	/** Rejects incomplete, stale-shaped, or internally conflicting read facts. */
	public static function requireDecision(decision:OcamlBytesReadDecision):Void {
		if (decision == null)
			throw "reflaxe.ocaml [ocaml-bytes:invalid-read]: Bytes read decision is null";
		final expectedField = fieldName(decision.kind);
		final expectedResultKind = resultKind(decision.kind);
		final expectedArgumentCount = expectedArgumentCount(decision.kind, decision.encoding);
		final expectedOrder = [-1].concat([for (index in 0...decision.argumentCount) index]);
		final expectedCalleeId = "haxe.io.Bytes|haxe.io.Bytes::" + expectedField;
		if (decision.id != idFor(decision)
			|| decision.source.file.length == 0
			|| decision.source.min < 0
			|| decision.source.max < decision.source.min
			|| decision.sourceModuleId != "haxe.io.Bytes"
			|| decision.sourceTypeName != "Bytes"
			|| decision.sourceFieldName != expectedField
			|| decision.calleeId != expectedCalleeId
			|| !decision.hasReceiver
			|| decision.argumentCount != expectedArgumentCount
			|| decision.evaluationOrder.join(",") != expectedOrder.join(",")
			|| decision.argumentSemanticTypeIds.length != decision.argumentCount
			|| decision.argumentCarrierTypeIds.length != decision.argumentCount
			|| decision.argumentRepresentationIds.length != decision.argumentCount
			|| decision.argumentRepresentationRevisions.length != decision.argumentCount
			|| decision.argumentRuntimeUse.length != decision.argumentCount
			|| decision.resultKind != expectedResultKind
			|| decision.resultNullability != RESULT_NULLABILITY
			|| decision.runtimeRequirementIds.join(",") != runtimeRequirementIdsFor(decision).join(",")
			|| decision.proofId != PROOF_ID
			|| decision.proofClaim != PROOF_CLAIM
			|| decision.functionId.length == 0
			|| decision.programRevision.length == 0
			|| decision.bodyRevision.length == 0
			|| decision.pipelineRevision.length == 0) {
			throw 'reflaxe.ocaml [ocaml-bytes:invalid-read]: read "${decision.id}" does not match the sealed Bytes read contract';
		}
		requireReceiver(decision);
		requireArguments(decision);
		requireResult(decision);
		final expectedUses = runtimeUseOccurrencesFor(decision);
		if (decision.runtimeUseOccurrences.length != expectedUses.length)
			throw 'reflaxe.ocaml [ocaml-bytes:invalid-read-runtime-use]: read "${decision.id}" does not own every private runtime use';
		for (index in 0...expectedUses.length)
			requireRuntimeUse(decision.id, index, decision.runtimeUseOccurrences[index], expectedUses[index]);
	}

	static function requireRuntimeUse(ownerId:String, index:Int, actual:OcamlRuntimeUseOccurrence, expected:OcamlRuntimeUseOccurrence):Void {
		if (actual == null
			|| actual.id != expected.id
			|| actual.planRevision != expected.planRevision
			|| actual.ownerId != expected.ownerId
			|| actual.requirementId != expected.requirementId
			|| actual.domain != expected.domain
			|| actual.exactSymbol != expected.exactSymbol
			|| actual.role != expected.role
			|| actual.order != expected.order
			|| actual.source.file != expected.source.file
			|| actual.source.min != expected.source.min
			|| actual.source.max != expected.source.max
			|| actual.profileEligibility.join(",") != expected.profileEligibility.join(",")
			|| actual.cardinality != expected.cardinality) {
			throw 'reflaxe.ocaml [ocaml-bytes:invalid-read-runtime-use]: read "$ownerId" has a stale, missing, reordered, or conflicting runtime use at index $index';
		}
	}

	static function requireReceiver(decision:OcamlBytesReadDecision):Void {
		if (decision.receiverSemanticTypeId != OcamlBytesRepresentationContract.DIRECT_SEMANTIC_TYPE_ID
			|| decision.receiverCarrierTypeId != OcamlBytesRepresentationContract.CARRIER_TYPE_ID
			|| decision.receiverRepresentationId != OcamlBytesRepresentationContract.DIRECT_INTERNAL_REPRESENTATION_ID
			|| !StringTools.startsWith(decision.receiverRepresentationRevision, "sha256:")) {
			throw 'reflaxe.ocaml [ocaml-bytes:invalid-read-receiver]: read "${decision.id}" has an incompatible Bytes receiver';
		}
		final validInput = switch (decision.receiverConversion) {
			case Identity:
				decision.receiverInputSemanticTypeId == OcamlBytesRepresentationContract.DIRECT_SEMANTIC_TYPE_ID
				&& decision.receiverInputCarrierTypeId == OcamlBytesRepresentationContract.CARRIER_TYPE_ID
				&& decision.receiverInputRepresentationId == OcamlBytesRepresentationContract.DIRECT_INTERNAL_REPRESENTATION_ID
				&& decision.receiverInputRepresentationRevision == decision.receiverRepresentationRevision;
			case RequireNonNullBytes:
				decision.receiverInputSemanticTypeId == OcamlBytesRepresentationContract.EXPLICIT_NULL_SEMANTIC_TYPE_ID
				&& decision.receiverInputCarrierTypeId == OcamlBytesRepresentationContract.CARRIER_TYPE_ID
				&& decision.receiverInputRepresentationId == OcamlBytesRepresentationContract.EXPLICIT_NULL_INTERNAL_REPRESENTATION_ID
				&& StringTools.startsWith(decision.receiverInputRepresentationRevision, "sha256:");
		}
		if (!validInput)
			throw 'reflaxe.ocaml [ocaml-bytes:invalid-read-receiver-conversion]: read "${decision.id}" has an incompatible ${decision.receiverConversion} receiver conversion';
	}

	static function requireArguments(decision:OcamlBytesReadDecision):Void {
		for (index in 0...decision.argumentCount) {
			final semanticTypeId = decision.argumentSemanticTypeIds[index];
			final carrierTypeId = decision.argumentCarrierTypeIds[index];
			final representationId = decision.argumentRepresentationIds[index];
			final representationRevision = decision.argumentRepresentationRevisions[index];
			final runtimeUse = decision.argumentRuntimeUse[index];
			final encodingSelector = decision.kind == OcamlBytesReadKind.GetString && index == 2;
			if (encodingSelector) {
				if (semanticTypeId != "haxe.io.Encoding"
					|| carrierTypeId != COMPILE_TIME_ENCODING_CARRIER
					|| representationId.length != 0
					|| representationRevision.length != 0
					|| runtimeUse) {
					throw 'reflaxe.ocaml [ocaml-bytes:invalid-read-argument]: read "${decision.id}" has an invalid compile-time encoding selector';
				}
			} else if (semanticTypeId.length == 0
				|| carrierTypeId.length == 0
				|| representationId.length == 0
				|| !StringTools.startsWith(representationRevision, "sha256:")
				|| !runtimeUse) {
				throw 'reflaxe.ocaml [ocaml-bytes:invalid-read-argument]: read "${decision.id}" has an incomplete runtime argument $index';
			}
		}
		if (decision.kind == OcamlBytesReadKind.GetString) {
			if (decision.argumentCount == 2 && decision.encoding != OcamlBytesEncodingKind.Omitted)
				throw 'reflaxe.ocaml [ocaml-bytes:invalid-read-encoding]: read "${decision.id}" omitted its encoding but recorded ${decision.encoding}';
			if (decision.argumentCount == 3
				&& (decision.encoding == OcamlBytesEncodingKind.NotApplicable || decision.encoding == OcamlBytesEncodingKind.Omitted)) {
				throw 'reflaxe.ocaml [ocaml-bytes:invalid-read-encoding]: read "${decision.id}" has no supported explicit encoding';
			}
		} else if (decision.encoding != OcamlBytesEncodingKind.NotApplicable) {
			throw 'reflaxe.ocaml [ocaml-bytes:invalid-read-encoding]: non-string read "${decision.id}" unexpectedly records ${decision.encoding}';
		}
	}

	static function requireResult(decision:OcamlBytesReadDecision):Void {
		final expected = switch (decision.resultKind) {
			case IntValue:
				{
					semanticTypeId: "Int",
					carrierTypeId: "int",
					representationId: "representation:Int:internal-value"
				};
			case StringValue:
				{
					semanticTypeId: "String",
					carrierTypeId: "string",
					representationId: "representation:String:internal-value"
				};
			case BytesValue:
				{
					semanticTypeId: OcamlBytesRepresentationContract.DIRECT_SEMANTIC_TYPE_ID,
					carrierTypeId: OcamlBytesRepresentationContract.CARRIER_TYPE_ID,
					representationId: OcamlBytesRepresentationContract.DIRECT_INTERNAL_REPRESENTATION_ID
				};
		}
		if (decision.resultSemanticTypeId != expected.semanticTypeId
			|| decision.resultCarrierTypeId != expected.carrierTypeId
			|| decision.resultRepresentationId != expected.representationId
			|| !StringTools.startsWith(decision.resultRepresentationRevision, "sha256:")) {
			throw 'reflaxe.ocaml [ocaml-bytes:invalid-read-result]: read "${decision.id}" has an incompatible result representation';
		}
	}
}
#end
