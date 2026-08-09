package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime || eval)
import haxe.crypto.Sha256;
import reflaxe.ocaml.lowered.OcamlBytesRepresentationModel.OcamlBytesRepresentationContract;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

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
	final runtimeUseOccurrences:Array<OcamlRuntimeUseOccurrence>;
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
	public static inline final NULLABLE_INT_RUNTIME_CAPABILITY = "haxe-bytes-mutation-nullable-int";
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

	/** Returns the direct HxBytes requirement for one mutation decision. */
	public static function runtimeRequirementId(decisionId:String):String {
		return decisionId + ":runtime:" + RUNTIME_CAPABILITY;
	}

	/** Returns the direct HxRuntime requirement for nullable integer inputs. */
	public static function nullableIntRuntimeRequirementId(decisionId:String):String {
		return decisionId + ":runtime:" + NULLABLE_INT_RUNTIME_CAPABILITY;
	}

	/** Returns every direct runtime root selected by one mutation. */
	public static function runtimeRequirementIdsFor(decision:OcamlBytesMutationDecision):Array<String> {
		final result = [runtimeRequirementId(decision.id)];
		if (Lambda.exists(decision.argumentConversions, conversion -> conversion == OcamlBytesMutationArgumentConversion.RequireNonNullInt))
			result.push(nullableIntRuntimeRequirementId(decision.id));
		return result;
	}

	/**
		Builds the exact private-runtime names target syntax must consume.

		Nullable argument conversions run while arguments are evaluated. The final
		HxBytes call runs after every argument has been materialized, so its use is
		last in this owner-local order.
	**/
	public static function runtimeUseOccurrencesFor(decision:OcamlBytesMutationDecision):Array<OcamlRuntimeUseOccurrence> {
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

		for (index in 0...decision.argumentConversions.length)
			if (decision.argumentConversions[index] == OcamlBytesMutationArgumentConversion.RequireNonNullInt)
				add(nullableIntRuntimeRequirementId(decision.id), "HxRuntime.nullable_int_unwrap", 'unwrap-argument:$index');
		add(runtimeRequirementId(decision.id), "HxBytes." + fieldName(decision.kind), "mutate-bytes");
		return result;
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
			|| decision.runtimeRequirementIds.join(",") != runtimeRequirementIdsFor(decision).join(",")
			|| decision.proofId != PROOF_ID
			|| decision.proofClaim != PROOF_CLAIM
			|| decision.functionId.length == 0
			|| decision.programRevision.length == 0
			|| decision.bodyRevision.length == 0
			|| decision.pipelineRevision.length == 0) {
			throw 'reflaxe.ocaml [ocaml-bytes:invalid-mutation]: mutation "${decision.id}" does not match the sealed Bytes mutation contract';
		}
		requireArguments(decision);
		final expectedUses = runtimeUseOccurrencesFor(decision);
		if (decision.runtimeUseOccurrences.length != expectedUses.length)
			throw 'reflaxe.ocaml [ocaml-bytes:invalid-mutation-runtime-use]: mutation "${decision.id}" does not own every private runtime use';
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
			throw 'reflaxe.ocaml [ocaml-bytes:invalid-mutation-runtime-use]: mutation "$ownerId" has a stale, missing, reordered, or conflicting runtime use at index $index';
		}
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
