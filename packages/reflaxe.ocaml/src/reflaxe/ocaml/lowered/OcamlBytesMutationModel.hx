package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime || eval)
import haxe.crypto.Sha256;
import reflaxe.ocaml.lowered.OcamlBytesRepresentationModel.OcamlBytesRepresentationContract;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;

/** One exact mutating operation on the Haxe standard-library Bytes surface. */
enum abstract OcamlBytesMutationKind(String) from String to String {
	final Fill = "fill";
	final Blit = "blit";
}

/** The only admitted result contract for Bytes mutation calls. */
enum abstract OcamlBytesMutationResultKind(String) from String to String {
	final EffectOnlyVoid = "effect-only-void";
}

/** How an admitted mutation uses a distinct source value. */
enum abstract OcamlBytesMutationSourcePolicy(String) from String to String {
	final NoSource = "no-source";
	final ReadSourceRange = "read-source-range";
}

/** How an admitted mutation behaves when source and destination storage overlap. */
enum abstract OcamlBytesMutationOverlapPolicy(String) from String to String {
	final NotApplicable = "not-applicable";
	final MemmoveCompatible = "memmove-compatible";
}

/** How the operation converts or copies the byte values it writes. */
enum abstract OcamlBytesMutationValuePolicy(String) from String to String {
	final MaskLowEightBits = "mask-low-eight-bits";
	final ExactByteCopy = "exact-byte-copy";
}

/** The exact carrier conversion applied before an argument reaches `HxBytes`. */
enum abstract OcamlBytesMutationArgumentConversion(String) from String to String {
	final Identity = "identity";
	final RequireNonNullInt = "require-non-null-int";
}

/**
	One immutable Bytes mutation fixed before OCaml syntax is constructed.

	The decision owns evaluation order, exact receiver and argument carriers,
	range validation, write behavior, overlap behavior, and the absence of a
	result carrier. Syntax may only materialize these facts and call `HxBytes`.
**/
typedef OcamlBytesMutationDecision = {
	final id:String;
	final source:OcamlLoweredSourceSpan;
	final kind:OcamlBytesMutationKind;
	final calleeId:String;
	final sourceModuleId:String;
	final sourceTypeName:String;
	final sourceFieldName:String;
	final receiverSemanticTypeId:String;
	final receiverCarrierTypeId:String;
	final receiverRepresentationId:String;
	final receiverRepresentationRevision:String;
	final argumentCount:Int;
	final evaluationOrder:Array<Int>;
	final argumentInputSemanticTypeIds:Array<String>;
	final argumentInputCarrierTypeIds:Array<String>;
	final argumentInputRepresentationIds:Array<String>;
	final argumentInputRepresentationRevisions:Array<String>;
	final argumentSemanticTypeIds:Array<String>;
	final argumentCarrierTypeIds:Array<String>;
	final argumentRepresentationIds:Array<String>;
	final argumentRepresentationRevisions:Array<String>;
	final argumentConversions:Array<OcamlBytesMutationArgumentConversion>;
	final destinationPolicy:String;
	final sourcePolicy:OcamlBytesMutationSourcePolicy;
	final overlapPolicy:OcamlBytesMutationOverlapPolicy;
	final boundsPolicy:String;
	final valuePolicy:OcamlBytesMutationValuePolicy;
	final resultKind:OcamlBytesMutationResultKind;
	final resultSemanticTypeId:String;
	final runtimeRequirementIds:Array<String>;
	final proofId:String;
	final proofClaim:String;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
}

/** Closed facts shared by Bytes mutation planning, syntax, and runtime reporting. */
class OcamlBytesMutationContract {
	public static inline final RUNTIME_CAPABILITY = "haxe-bytes-mutation";
	public static inline final DESTINATION_POLICY = "mutate-receiver-range-only";
	public static inline final BOUNDS_POLICY = "validate-all-ranges-before-mutation";
	public static inline final VOID_SEMANTIC_TYPE_ID = "Void";
	public static inline final PROOF_ID = "exact-haxe-bytes-mutation-v1";
	public static inline final PROOF_CLAIM = "This exact standard-library Bytes mutation evaluates its receiver first and every argument once in source order, validates all ranges before mutation, fixes destination/source/overlap/value behavior, returns effect-only Void with no carrier, and calls HxBytes before target syntax. The proof does not admit indexed Bytes access, inline-expanded BytesData storage operations, Float or Int64 operations, nullable materialization, or user-defined lookalikes.";

	/** Computes the deterministic identity shared by planning and validation. */
	public static function idFor(decision:OcamlBytesMutationDecision):String {
		return "bytes-mutation:" + Sha256.encode([
			decision.functionId,
			decision.programRevision,
			decision.bodyRevision,
			decision.pipelineRevision,
			decision.source.file,
			Std.string(decision.source.min),
			Std.string(decision.source.max),
			(decision.kind : String),
			decision.calleeId,
			decision.receiverRepresentationId,
			decision.receiverRepresentationRevision,
			Std.string(decision.argumentCount),
			decision.evaluationOrder.join(","),
			decision.argumentInputSemanticTypeIds.join(","),
			decision.argumentInputCarrierTypeIds.join(","),
			decision.argumentInputRepresentationIds.join(","),
			decision.argumentInputRepresentationRevisions.join(","),
			decision.argumentSemanticTypeIds.join(","),
			decision.argumentCarrierTypeIds.join(","),
			decision.argumentRepresentationIds.join(","),
			decision.argumentRepresentationRevisions.join(","),
			decision.argumentConversions.join(","),
			decision.destinationPolicy,
			(decision.sourcePolicy : String),
			(decision.overlapPolicy : String),
			decision.boundsPolicy,
			(decision.valuePolicy : String),
			(decision.resultKind : String)
		].join("\n")).substr(0, 24);
	}

	/** Returns the exact source field represented by one closed mutation kind. */
	public static function fieldName(kind:OcamlBytesMutationKind):String {
		return switch (kind) {
			case Fill: "fill";
			case Blit: "blit";
		}
	}

	/** Returns the exact supported argument count for one mutation kind. */
	public static function expectedArgumentCount(kind:OcamlBytesMutationKind):Int {
		return switch (kind) {
			case Fill: 3;
			case Blit: 4;
		}
	}

	/** Returns the exact source policy for one mutation kind. */
	public static function sourcePolicy(kind:OcamlBytesMutationKind):OcamlBytesMutationSourcePolicy {
		return switch (kind) {
			case Fill: NoSource;
			case Blit: ReadSourceRange;
		}
	}

	/** Returns the exact overlap policy for one mutation kind. */
	public static function overlapPolicy(kind:OcamlBytesMutationKind):OcamlBytesMutationOverlapPolicy {
		return switch (kind) {
			case Fill: NotApplicable;
			case Blit: MemmoveCompatible;
		}
	}

	/** Returns the exact byte-write policy for one mutation kind. */
	public static function valuePolicy(kind:OcamlBytesMutationKind):OcamlBytesMutationValuePolicy {
		return switch (kind) {
			case Fill: MaskLowEightBits;
			case Blit: ExactByteCopy;
		}
	}

	/** Rejects incomplete, stale-shaped, or internally conflicting mutation facts. */
	public static function requireDecision(decision:OcamlBytesMutationDecision):Void {
		if (decision == null)
			throw "reflaxe.ocaml [ocaml-bytes:invalid-mutation]: Bytes mutation decision is null";
		final expectedField = fieldName(decision.kind);
		final expectedArgumentCount = expectedArgumentCount(decision.kind);
		final expectedOrder = [-1].concat([for (index in 0...expectedArgumentCount) index]);
		final expectedCalleeId = "haxe.io.Bytes|haxe.io.Bytes::" + expectedField;
		if (decision.id != idFor(decision)
			|| decision.source.file.length == 0
			|| decision.source.min < 0
			|| decision.source.max < decision.source.min
			|| decision.sourceModuleId != "haxe.io.Bytes"
			|| decision.sourceTypeName != "Bytes"
			|| decision.sourceFieldName != expectedField
			|| decision.calleeId != expectedCalleeId
			|| decision.receiverSemanticTypeId != OcamlBytesRepresentationContract.DIRECT_SEMANTIC_TYPE_ID
			|| decision.receiverCarrierTypeId != OcamlBytesRepresentationContract.CARRIER_TYPE_ID
			|| decision.receiverRepresentationId != OcamlBytesRepresentationContract.DIRECT_INTERNAL_REPRESENTATION_ID
			|| !StringTools.startsWith(decision.receiverRepresentationRevision, "sha256:")
			|| decision.argumentCount != expectedArgumentCount
			|| decision.evaluationOrder.join(",") != expectedOrder.join(",")
			|| decision.argumentInputSemanticTypeIds.length != expectedArgumentCount
			|| decision.argumentInputCarrierTypeIds.length != expectedArgumentCount
			|| decision.argumentInputRepresentationIds.length != expectedArgumentCount
			|| decision.argumentInputRepresentationRevisions.length != expectedArgumentCount
			|| decision.argumentSemanticTypeIds.length != expectedArgumentCount
			|| decision.argumentCarrierTypeIds.length != expectedArgumentCount
			|| decision.argumentRepresentationIds.length != expectedArgumentCount
			|| decision.argumentRepresentationRevisions.length != expectedArgumentCount
			|| decision.argumentConversions.length != expectedArgumentCount
			|| decision.destinationPolicy != DESTINATION_POLICY
			|| decision.sourcePolicy != sourcePolicy(decision.kind)
			|| decision.overlapPolicy != overlapPolicy(decision.kind)
			|| decision.boundsPolicy != BOUNDS_POLICY
			|| decision.valuePolicy != valuePolicy(decision.kind)
			|| decision.resultKind != OcamlBytesMutationResultKind.EffectOnlyVoid
			|| decision.resultSemanticTypeId != VOID_SEMANTIC_TYPE_ID
			|| decision.runtimeRequirementIds.length != 1
			|| decision.runtimeRequirementIds[0] != decision.id + ":runtime:" + RUNTIME_CAPABILITY
			|| decision.proofId != PROOF_ID
			|| decision.proofClaim != PROOF_CLAIM
			|| decision.functionId.length == 0
			|| decision.programRevision.length == 0
			|| decision.bodyRevision.length == 0
			|| decision.pipelineRevision.length == 0) {
			throw 'reflaxe.ocaml [ocaml-bytes:invalid-mutation]: mutation "${decision.id}" does not match the sealed Bytes mutation contract';
		}
		requireArguments(decision);
	}

	static function requireArguments(decision:OcamlBytesMutationDecision):Void {
		for (index in 0...decision.argumentCount) {
			final expectsBytes = decision.kind == OcamlBytesMutationKind.Blit && index == 1;
			final expectedSemanticTypeId = expectsBytes ? OcamlBytesRepresentationContract.DIRECT_SEMANTIC_TYPE_ID : "Int";
			final expectedCarrierTypeId = expectsBytes ? OcamlBytesRepresentationContract.CARRIER_TYPE_ID : "int";
			final expectedRepresentationId = expectsBytes ? OcamlBytesRepresentationContract.DIRECT_INTERNAL_REPRESENTATION_ID : "representation:Int:internal-value";
			final inputSemanticTypeId = decision.argumentInputSemanticTypeIds[index];
			final inputCarrierTypeId = decision.argumentInputCarrierTypeIds[index];
			final inputRepresentationId = decision.argumentInputRepresentationIds[index];
			final conversion = decision.argumentConversions[index];
			if (decision.argumentSemanticTypeIds[index] != expectedSemanticTypeId
				|| decision.argumentCarrierTypeIds[index] != expectedCarrierTypeId
				|| decision.argumentRepresentationIds[index] != expectedRepresentationId
				|| !StringTools.startsWith(decision.argumentRepresentationRevisions[index], "sha256:")) {
				throw 'reflaxe.ocaml [ocaml-bytes:invalid-mutation-argument]: mutation "${decision.id}" has an incompatible argument $index';
			}
			final validInput = if (expectsBytes) {
				inputSemanticTypeId == expectedSemanticTypeId
				&& inputCarrierTypeId == expectedCarrierTypeId
				&& inputRepresentationId == expectedRepresentationId
				&& conversion == OcamlBytesMutationArgumentConversion.Identity;
			} else {
				(inputSemanticTypeId == "Int"
					&& inputCarrierTypeId == "int"
					&& inputRepresentationId == "representation:Int:internal-value"
					&& conversion == OcamlBytesMutationArgumentConversion.Identity) || (inputSemanticTypeId == "Null<Int>"
					&& inputCarrierTypeId == "Obj.t"
					&& inputRepresentationId == "representation:Null<Int>:internal-value"
					&& conversion == OcamlBytesMutationArgumentConversion.RequireNonNullInt);
			}
			if (!validInput || !StringTools.startsWith(decision.argumentInputRepresentationRevisions[index], "sha256:"))
				throw 'reflaxe.ocaml [ocaml-bytes:invalid-mutation-conversion]: mutation "${decision.id}" has an incompatible input crossing at argument $index';
		}
	}
}
#end
