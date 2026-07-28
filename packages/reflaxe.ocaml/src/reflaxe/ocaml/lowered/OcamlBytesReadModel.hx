package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime || eval)
import haxe.crypto.Sha256;
import reflaxe.ocaml.lowered.OcamlBytesProducerModel.OcamlBytesEncodingKind;
import reflaxe.ocaml.lowered.OcamlBytesRepresentationModel.OcamlBytesRepresentationContract;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;

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

/**
	One immutable Bytes read fixed before OCaml syntax is constructed.

	The receiver and runtime arguments refer to request-owned representation
	decisions. An optional encoding selector is still recorded in source order,
	but it is a compile-time constant and therefore has no runtime carrier.
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
	public static inline final RESULT_NULLABILITY = "non-null";
	public static inline final COMPILE_TIME_ENCODING_CARRIER = "compile-time-encoding-selector";
	public static inline final PROOF_ID = "exact-haxe-bytes-read-v1";
	public static inline final PROOF_CLAIM = "This exact standard-library Bytes read fixes its receiver, source-ordered arguments, result representation, and HxBytes operation before target syntax. The proof does not admit writes, inline-expanded storage reads, indexed access, nullable materialization, Float or Int64 results, or non-Bytes calls.";

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
			|| decision.runtimeRequirementIds.length != 1
			|| decision.runtimeRequirementIds[0] != decision.id + ":runtime:" + RUNTIME_CAPABILITY
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
	}

	static function requireReceiver(decision:OcamlBytesReadDecision):Void {
		if (decision.receiverSemanticTypeId != OcamlBytesRepresentationContract.DIRECT_SEMANTIC_TYPE_ID
			|| decision.receiverCarrierTypeId != OcamlBytesRepresentationContract.CARRIER_TYPE_ID
			|| decision.receiverRepresentationId != OcamlBytesRepresentationContract.DIRECT_INTERNAL_REPRESENTATION_ID
			|| !StringTools.startsWith(decision.receiverRepresentationRevision, "sha256:")) {
			throw 'reflaxe.ocaml [ocaml-bytes:invalid-read-receiver]: read "${decision.id}" has an incompatible Bytes receiver';
		}
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
