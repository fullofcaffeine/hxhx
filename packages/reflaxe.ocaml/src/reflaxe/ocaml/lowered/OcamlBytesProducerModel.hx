package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime || eval)
import haxe.crypto.Sha256;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlBytesRepresentationModel.OcamlBytesRepresentationContract;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

/** The supported Haxe operation that produces one non-null `haxe.io.Bytes`. */
enum abstract OcamlBytesProducerKind(String) from String to String {
	final Constructor = "constructor";
	final Alloc = "alloc";
	final OfString = "of-string";
	final OfData = "of-data";
	final OfHex = "of-hex";
}

/** How one admitted operation chooses the Bytes length and native data. */
enum abstract OcamlBytesConstructionPolicy(String) from String to String {
	final DerivedLengthOwnedData = "derived-length-owned-data";
	final DerivedLengthAliasedData = "derived-length-aliased-data";
	final ExplicitLengthAliasedData = "explicit-length-aliased-data";
}

/** How a supported `Bytes.ofString` occurrence selected its encoding. */
enum abstract OcamlBytesEncodingKind(String) from String to String {
	final NotApplicable = "not-applicable";
	final Omitted = "omitted";
	final ExplicitNull = "explicit-null";
	final UTF8 = "utf8";
	final RawNative = "raw-native";
}

/**
	One producer-local Bytes result fixed before OCaml syntax is constructed.

	The record is a host-neutral immutable fact. Macro-time planning creates it,
	syntax construction consumes it, and runtime reporting validates it without
	depending on compiler-only Reflaxe classes.
**/
typedef OcamlBytesProducerDecision = {
	final id:String;
	final source:OcamlLoweredSourceSpan;
	final kind:OcamlBytesProducerKind;
	final calleeId:String;
	final sourceModuleId:String;
	final sourceTypeName:String;
	final sourceFieldName:String;
	final argumentCount:Int;
	final argumentEvaluationOrder:Array<Int>;
	final argumentRuntimeUse:Array<Bool>;
	final encoding:OcamlBytesEncodingKind;
	final constructionPolicy:OcamlBytesConstructionPolicy;
	final resultSemanticTypeId:String;
	final resultCarrierTypeId:String;
	final resultNullability:String;
	final resultRepresentationId:String;
	final resultRepresentationRevision:String;
	final runtimeRequirementIds:Array<String>;
	final runtimeUseOccurrences:Array<OcamlRuntimeUseOccurrence>;
	final proofId:String;
	final proofClaim:String;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
}

/** Closed identities shared by planning, syntax, and runtime reporting. */
class OcamlBytesProducerContract {
	public static inline final SEMANTIC_TYPE_ID = OcamlBytesRepresentationContract.DIRECT_SEMANTIC_TYPE_ID;
	public static inline final RESULT_NULLABILITY = "non-null";
	public static inline final RUNTIME_CAPABILITY = "haxe-bytes-producer";
	public static inline final PROOF_ID = "non-null-haxe-bytes-producer-v3";
	public static inline final PROOF_CLAIM = "This exact supported operation evaluates each runtime argument once in Haxe source order, then calls one sealed HxBytes producer and returns a non-null Haxe Bytes value carried by one explicit-length/native-data HxBytes.t container. A supported encoding selector is a compile-time choice, not a runtime argument; the claim ends at the producer result.";

	/** Returns the occurrence-local requirement for one exact Bytes producer. */
	public static function runtimeRequirementId(decisionId:String):String {
		return decisionId + ":runtime:" + RUNTIME_CAPABILITY;
	}

	/** Returns the private runtime function selected by the producer kind. */
	public static function runtimeOperation(kind:OcamlBytesProducerKind):String {
		return switch (kind) {
			case Constructor: "create";
			case Alloc: "alloc";
			case OfString: "ofString";
			case OfData: "ofData";
			case OfHex: "ofHex";
		}
	}

	/**
		Marks which source arguments exist when the generated OCaml executes.

		The optional `Bytes.ofString` encoding is already a checked constant in the
		compiler decision. It selects behavior at compile time and is not evaluated
		again or passed through the runtime call.
	**/
	public static function argumentRuntimeUseFor(kind:OcamlBytesProducerKind, argumentCount:Int):Array<Bool> {
		return [
			for (index in 0...argumentCount)
				kind != OcamlBytesProducerKind.OfString || index == 0
		];
	}

	/** Builds the one exact private name that producer syntax must consume. */
	public static function runtimeUseOccurrenceFor(decisionId:String, source:OcamlLoweredSourceSpan, kind:OcamlBytesProducerKind,
			binding:OcamlFunctionPlanBinding):OcamlRuntimeUseOccurrence {
		return {
			id: decisionId + ":runtime-use:produce-bytes",
			planRevision: OcamlRuntimeUseModel.planRevision(binding),
			ownerId: decisionId,
			requirementId: runtimeRequirementId(decisionId),
			domain: OcamlRuntimeUseDomain.ExpressionIdentifier,
			exactSymbol: "HxBytes." + runtimeOperation(kind),
			role: "produce-bytes",
			order: 0,
			source: {
				file: source.file,
				min: source.min,
				max: source.max
			},
			profileEligibility: ["metal", "portable"],
			cardinality: 1
		};
	}

	/** Recomputes the private-runtime authority expected from one decision. */
	public static function runtimeUseOccurrencesFor(decision:OcamlBytesProducerDecision):Array<OcamlRuntimeUseOccurrence> {
		return [
			runtimeUseOccurrenceFor(decision.id, decision.source, decision.kind, {
				functionId: decision.functionId,
				programRevision: decision.programRevision,
				bodyRevision: decision.bodyRevision,
				pipelineRevision: decision.pipelineRevision
			})
		];
	}

	/** Computes the deterministic identity shared by planning and validation. */
	public static function idFor(functionId:String, programRevision:String, bodyRevision:String, pipelineRevision:String, source:OcamlLoweredSourceSpan,
			kind:OcamlBytesProducerKind, calleeId:String, argumentCount:Int, encoding:OcamlBytesEncodingKind, resultRepresentationId:String,
			resultRepresentationRevision:String, constructionPolicy:OcamlBytesConstructionPolicy):String {
		return "bytes-producer:" + Sha256.encode([
			functionId,
			programRevision,
			bodyRevision,
			pipelineRevision,
			source.file,
			Std.string(source.min),
			Std.string(source.max),
			(kind : String),
			calleeId,
			Std.string(argumentCount),
			(encoding : String),
			(constructionPolicy : String),
			resultRepresentationId,
			resultRepresentationRevision
		].join("\n")).substr(0, 24);
	}

	/** Rejects incomplete, stale, or internally conflicting producer facts. */
	public static function requireDecision(decision:OcamlBytesProducerDecision):Void {
		if (decision == null)
			throw "reflaxe.ocaml [ocaml-bytes:invalid-producer]: Bytes producer decision is null";
		final expectedOrder = [for (index in 0...decision.argumentCount) index];
		final expectedRuntimeUse = argumentRuntimeUseFor(decision.kind, decision.argumentCount);
		final expectedField = switch (decision.kind) {
			case Constructor: "new";
			case Alloc: "alloc";
			case OfString: "ofString";
			case OfData: "ofData";
			case OfHex: "ofHex";
		}
		final expectedArgumentCount = switch (decision.kind) {
			case Constructor: 2;
			case Alloc, OfData, OfHex: 1;
			case OfString: decision.encoding == OcamlBytesEncodingKind.Omitted ? 1 : 2;
		}
		final expectedConstructionPolicy = switch (decision.kind) {
			case Constructor: OcamlBytesConstructionPolicy.ExplicitLengthAliasedData;
			case OfData: OcamlBytesConstructionPolicy.DerivedLengthAliasedData;
			case Alloc, OfString, OfHex: OcamlBytesConstructionPolicy.DerivedLengthOwnedData;
		}
		final expectedCalleeId = "haxe.io.Bytes|haxe.io.Bytes::" + expectedField;
		final expectedId = idFor(decision.functionId, decision.programRevision, decision.bodyRevision, decision.pipelineRevision, decision.source,
			decision.kind, decision.calleeId, decision.argumentCount, decision.encoding, decision.resultRepresentationId,
			decision.resultRepresentationRevision, decision.constructionPolicy);
		if (decision.id != expectedId
			|| decision.source.file.length == 0
			|| decision.source.min < 0
			|| decision.source.max < decision.source.min
			|| decision.resultSemanticTypeId != SEMANTIC_TYPE_ID
			|| decision.resultCarrierTypeId != OcamlBytesRepresentationContract.CARRIER_TYPE_ID
			|| decision.resultNullability != RESULT_NULLABILITY
			|| decision.resultRepresentationId != OcamlBytesRepresentationContract.DIRECT_INTERNAL_REPRESENTATION_ID
			|| !StringTools.startsWith(decision.resultRepresentationRevision, "sha256:")
			|| decision.proofId != PROOF_ID
			|| decision.proofClaim != PROOF_CLAIM
			|| decision.sourceModuleId != "haxe.io.Bytes"
			|| decision.sourceTypeName != "Bytes"
			|| decision.sourceFieldName != expectedField
			|| decision.calleeId != expectedCalleeId
			|| decision.argumentCount != expectedArgumentCount
			|| decision.argumentEvaluationOrder.join(",") != expectedOrder.join(",")
			|| decision.argumentRuntimeUse.join(",") != expectedRuntimeUse.join(",")
			|| decision.constructionPolicy != expectedConstructionPolicy
			|| decision.runtimeRequirementIds.length != 1
			|| decision.runtimeRequirementIds[0] != runtimeRequirementId(decision.id)
			|| decision.functionId.length == 0
			|| decision.programRevision.length == 0
			|| decision.bodyRevision.length == 0
			|| decision.pipelineRevision.length == 0) {
			throw 'reflaxe.ocaml [ocaml-bytes:invalid-producer]: producer "${decision.id}" does not match the sealed non-null Bytes producer contract';
		}
		if ((decision.kind == OcamlBytesProducerKind.OfString) != (decision.encoding != OcamlBytesEncodingKind.NotApplicable))
			throw 'reflaxe.ocaml [ocaml-bytes:invalid-encoding]: producer "${decision.id}" has an invalid encoding decision';
		final expectedUses = runtimeUseOccurrencesFor(decision);
		if (decision.runtimeUseOccurrences.length != expectedUses.length)
			throw 'reflaxe.ocaml [ocaml-bytes:invalid-producer-runtime-use]: producer "${decision.id}" does not own its exact private runtime call';
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
			throw 'reflaxe.ocaml [ocaml-bytes:invalid-producer-runtime-use]: producer "$ownerId" has a stale, missing, reordered, or conflicting runtime use at index $index';
		}
	}
}
#end
