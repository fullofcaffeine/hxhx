package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime || eval)
import haxe.crypto.Sha256;
import reflaxe.ocaml.lowered.OcamlBytesRepresentationModel.OcamlBytesRepresentationContract;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;

/** Exact byte access and data-alias operations admitted from the target Bytes override. */
enum abstract OcamlBytesAccessKind(String) from String to String {
	final Get = "get";
	final Set = "set";
	final GetData = "get-data";
	final FastGet = "fast-get";
}

/** Whether the target-selected declaration is an instance or static call. */
enum abstract OcamlBytesAccessInvocationKind(String) from String to String {
	final Instance = "instance";
	final Static = "static";
}

/** The exact carrier conversion performed before an access argument reaches `HxBytes`. */
enum abstract OcamlBytesAccessArgumentConversion(String) from String to String {
	final Identity = "identity";
	final RequireNonNullInt = "require-non-null-int";
}

/** Range semantics fixed before target syntax. */
enum abstract OcamlBytesAccessBoundsPolicy(String) from String to String {
	final DeclaredBytesChecked = "declared-bytes-checked";
	final NativeDataChecked = "native-data-checked";
	final NotApplicable = "not-applicable";
}

/** Byte-value semantics fixed before target syntax. */
enum abstract OcamlBytesAccessValuePolicy(String) from String to String {
	final UnsignedByteRead = "unsigned-byte-read";
	final MaskLowEightBits = "mask-low-eight-bits";
	final PreserveNativeData = "preserve-native-data";
}

/** Mutation behavior owned by one exact access decision. */
enum abstract OcamlBytesAccessMutationPolicy(String) from String to String {
	final ReadOnly = "read-only";
	final MutateReceiverByte = "mutate-receiver-byte";
	final ReturnMutableAlias = "return-mutable-alias";
}

/** Aliasing behavior owned by one exact access decision. */
enum abstract OcamlBytesAccessAliasPolicy(String) from String to String {
	final NoNewAlias = "no-new-alias";
	final SharedNativeDataAlias = "shared-native-data-alias";
}

/** Result shape fixed before target syntax. */
enum abstract OcamlBytesAccessResultKind(String) from String to String {
	final ExactInt = "exact-int";
	final EffectOnlyVoid = "effect-only-void";
	final ExactBytesData = "exact-bytes-data";
}

/**
	One immutable exact Bytes access selected before OCaml syntax is built.

	The decision records the target-owned declaration, receiver/argument
	evaluation, every input and result carrier, bounds and byte-value behavior,
	mutation/aliasing semantics, runtime operation, and enclosing revisions.
**/
typedef OcamlBytesAccessDecision = {
	final id:String;
	final occurrenceId:String;
	final source:OcamlLoweredSourceSpan;
	final kind:OcamlBytesAccessKind;
	final invocationKind:OcamlBytesAccessInvocationKind;
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
	final argumentConversions:Array<OcamlBytesAccessArgumentConversion>;
	final boundsPolicy:OcamlBytesAccessBoundsPolicy;
	final valuePolicy:OcamlBytesAccessValuePolicy;
	final mutationPolicy:OcamlBytesAccessMutationPolicy;
	final aliasPolicy:OcamlBytesAccessAliasPolicy;
	final resultKind:OcamlBytesAccessResultKind;
	final resultSemanticTypeId:String;
	final resultCarrierTypeId:String;
	final resultRepresentationId:String;
	final resultRepresentationRevision:String;
	final runtimeOperation:String;
	final runtimeRequirementIds:Array<String>;
	final proofId:String;
	final proofClaim:String;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
}

/** Closed facts shared by exact byte-access planning, syntax, and reporting. */
class OcamlBytesAccessContract {
	public static inline final RUNTIME_CAPABILITY = "haxe-bytes-access";
	public static inline final VOID_SEMANTIC_TYPE_ID = "Void";
	public static inline final OCCURRENCE_ID_PREFIX = "bytes-access-occurrence:";
	public static inline final PROOF_ID = "exact-haxe-bytes-access-v1";
	public static inline final PROOF_CLAIM = "This exact call from the reflaxe.ocaml haxe.io.Bytes override evaluates its receiver, when present, and every argument once in Haxe source order. Before syntax, the decision fixes exact Bytes, BytesData, and Int carriers; checked declared-Bytes or native-data bounds behavior; unsigned reads or low-eight-bit writes; result shape; shared getData aliasing; and the selected HxBytes operation. It does not reconstruct vanilla inline bodies, admit arbitrary BytesData indexing, promise unsafe invalid fastGet behavior, or cover multi-byte, Float, Int64, nullable Bytes or BytesData materialization, or user-defined lookalikes.";

	/** Computes the deterministic identity shared by planning and validation. */
	public static function idFor(decision:OcamlBytesAccessDecision):String {
		return "bytes-access:" + Sha256.encode([
			decision.functionId,
			decision.programRevision,
			decision.bodyRevision,
			decision.pipelineRevision,
			decision.occurrenceId,
			decision.source.file,
			Std.string(decision.source.min),
			Std.string(decision.source.max),
			(decision.kind : String),
			(decision.invocationKind : String),
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
			(decision.boundsPolicy : String),
			(decision.valuePolicy : String),
			(decision.mutationPolicy : String),
			(decision.aliasPolicy : String),
			(decision.resultKind : String),
			decision.resultRepresentationId,
			decision.resultRepresentationRevision,
			decision.runtimeOperation
		].join("\n")).substr(0, 24);
	}

	public static function fieldName(kind:OcamlBytesAccessKind):String {
		return switch (kind) {
			case Get: "get";
			case Set: "set";
			case GetData: "getData";
			case FastGet: "fastGet";
		}
	}

	public static function invocationKind(kind:OcamlBytesAccessKind):OcamlBytesAccessInvocationKind {
		return kind == OcamlBytesAccessKind.FastGet ? OcamlBytesAccessInvocationKind.Static : OcamlBytesAccessInvocationKind.Instance;
	}

	public static function expectedArgumentCount(kind:OcamlBytesAccessKind):Int {
		return switch (kind) {
			case Get: 1;
			case Set, FastGet: 2;
			case GetData: 0;
		}
	}

	public static function boundsPolicy(kind:OcamlBytesAccessKind):OcamlBytesAccessBoundsPolicy {
		return switch (kind) {
			case Get, Set: DeclaredBytesChecked;
			case FastGet: NativeDataChecked;
			case GetData: NotApplicable;
		}
	}

	public static function valuePolicy(kind:OcamlBytesAccessKind):OcamlBytesAccessValuePolicy {
		return switch (kind) {
			case Get, FastGet: UnsignedByteRead;
			case Set: MaskLowEightBits;
			case GetData: PreserveNativeData;
		}
	}

	public static function mutationPolicy(kind:OcamlBytesAccessKind):OcamlBytesAccessMutationPolicy {
		return switch (kind) {
			case Get, FastGet: ReadOnly;
			case Set: MutateReceiverByte;
			case GetData: ReturnMutableAlias;
		}
	}

	public static function aliasPolicy(kind:OcamlBytesAccessKind):OcamlBytesAccessAliasPolicy {
		return kind == OcamlBytesAccessKind.GetData ? SharedNativeDataAlias : NoNewAlias;
	}

	public static function resultKind(kind:OcamlBytesAccessKind):OcamlBytesAccessResultKind {
		return switch (kind) {
			case Get, FastGet: ExactInt;
			case Set: EffectOnlyVoid;
			case GetData: ExactBytesData;
		}
	}

	/** Rejects incomplete, stale-shaped, or internally conflicting access facts. */
	public static function requireDecision(decision:OcamlBytesAccessDecision):Void {
		if (decision == null)
			throw "reflaxe.ocaml [ocaml-bytes:invalid-access]: Bytes access decision is null";
		final expectedField = fieldName(decision.kind);
		final expectedInvocation = invocationKind(decision.kind);
		final expectedArgumentCount = expectedArgumentCount(decision.kind);
		final expectedOrder = expectedInvocation == OcamlBytesAccessInvocationKind.Instance ? [-1].concat([
			for (index in 0...expectedArgumentCount)
				index
		]) : [for (index in 0...expectedArgumentCount) index];
		final hasReceiver = expectedInvocation == OcamlBytesAccessInvocationKind.Instance;
		final expectedCalleeId = "haxe.io.Bytes|haxe.io.Bytes::" + expectedField;
		if (decision.id != idFor(decision)
			|| !isOccurrenceId(decision.occurrenceId)
			|| decision.source.file.length == 0
			|| decision.source.min < 0
			|| decision.source.max < decision.source.min
			|| decision.invocationKind != expectedInvocation
			|| decision.sourceModuleId != "haxe.io.Bytes"
			|| decision.sourceTypeName != "Bytes"
			|| decision.sourceFieldName != expectedField
			|| decision.calleeId != expectedCalleeId
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
			|| decision.boundsPolicy != boundsPolicy(decision.kind)
			|| decision.valuePolicy != valuePolicy(decision.kind)
			|| decision.mutationPolicy != mutationPolicy(decision.kind)
			|| decision.aliasPolicy != aliasPolicy(decision.kind)
			|| decision.resultKind != resultKind(decision.kind)
			|| decision.runtimeOperation != expectedField
			|| decision.runtimeRequirementIds.length != 1
			|| decision.runtimeRequirementIds[0] != decision.id + ":runtime:" + RUNTIME_CAPABILITY
			|| decision.proofId != PROOF_ID
			|| decision.proofClaim != PROOF_CLAIM
			|| decision.functionId.length == 0
			|| decision.programRevision.length == 0
			|| decision.bodyRevision.length == 0
			|| decision.pipelineRevision.length == 0) {
			throw 'reflaxe.ocaml [ocaml-bytes:invalid-access]: access "${decision.id}" does not match the sealed Bytes access contract';
		}
		requireReceiver(decision, hasReceiver);
		requireArguments(decision);
		requireResult(decision);
	}

	static function isOccurrenceId(value:String):Bool {
		if (!StringTools.startsWith(value, OCCURRENCE_ID_PREFIX) || value.length != OCCURRENCE_ID_PREFIX.length + 24)
			return false;
		for (index in OCCURRENCE_ID_PREFIX.length...value.length) {
			final code = value.charCodeAt(index);
			if (code == null || !((code >= "0".code && code <= "9".code) || (code >= "a".code && code <= "f".code)))
				return false;
		}
		return true;
	}

	static function requireReceiver(decision:OcamlBytesAccessDecision, present:Bool):Void {
		final valid = if (present) {
			decision.receiverSemanticTypeId == OcamlBytesRepresentationContract.DIRECT_SEMANTIC_TYPE_ID
			&& decision.receiverCarrierTypeId == OcamlBytesRepresentationContract.CARRIER_TYPE_ID
			&& decision.receiverRepresentationId == OcamlBytesRepresentationContract.DIRECT_INTERNAL_REPRESENTATION_ID
			&& StringTools.startsWith(decision.receiverRepresentationRevision, "sha256:");
		} else {
			decision.receiverSemanticTypeId.length == 0
			&& decision.receiverCarrierTypeId.length == 0
			&& decision.receiverRepresentationId.length == 0
			&& decision.receiverRepresentationRevision.length == 0;
		}
		if (!valid)
			throw 'reflaxe.ocaml [ocaml-bytes:invalid-access-receiver]: access "${decision.id}" has an incompatible receiver';
	}

	static function requireArguments(decision:OcamlBytesAccessDecision):Void {
		for (index in 0...decision.argumentCount) {
			final expectsData = decision.kind == OcamlBytesAccessKind.FastGet && index == 0;
			final inputSemantic = decision.argumentInputSemanticTypeIds[index];
			final inputCarrier = decision.argumentInputCarrierTypeIds[index];
			final outputSemantic = decision.argumentSemanticTypeIds[index];
			final outputCarrier = decision.argumentCarrierTypeIds[index];
			final conversion = decision.argumentConversions[index];
			final valid = if (expectsData) {
				inputSemantic == OcamlBytesRepresentationContract.DATA_SEMANTIC_TYPE_ID
				&& inputCarrier == OcamlBytesRepresentationContract.DATA_CARRIER_TYPE_ID
				&& outputSemantic == inputSemantic
				&& outputCarrier == inputCarrier
				&& conversion == OcamlBytesAccessArgumentConversion.Identity;
			} else {
				outputSemantic == "Int" && outputCarrier == "int" && ((inputSemantic == "Int"
					&& inputCarrier == "int"
					&& conversion == OcamlBytesAccessArgumentConversion.Identity)
					|| (inputSemantic == "Null<Int>"
						&& inputCarrier == "Obj.t"
						&& conversion == OcamlBytesAccessArgumentConversion.RequireNonNullInt));
			}
			if (!valid
				|| decision.argumentInputRepresentationIds[index].length == 0
				|| !StringTools.startsWith(decision.argumentInputRepresentationRevisions[index], "sha256:")
				|| decision.argumentRepresentationIds[index].length == 0
				|| !StringTools.startsWith(decision.argumentRepresentationRevisions[index], "sha256:")) {
				throw 'reflaxe.ocaml [ocaml-bytes:invalid-access-argument]: access "${decision.id}" has an incompatible argument $index';
			}
		}
	}

	static function requireResult(decision:OcamlBytesAccessDecision):Void {
		final valid = switch (decision.resultKind) {
			case ExactInt:
				decision.resultSemanticTypeId == "Int"
				&& decision.resultCarrierTypeId == "int"
				&& decision.resultRepresentationId.length > 0
				&& StringTools.startsWith(decision.resultRepresentationRevision, "sha256:");
			case EffectOnlyVoid:
				decision.resultSemanticTypeId == VOID_SEMANTIC_TYPE_ID
				&& decision.resultCarrierTypeId.length == 0
				&& decision.resultRepresentationId.length == 0
				&& decision.resultRepresentationRevision.length == 0;
			case ExactBytesData:
				decision.resultSemanticTypeId == OcamlBytesRepresentationContract.DATA_SEMANTIC_TYPE_ID
				&& decision.resultCarrierTypeId == OcamlBytesRepresentationContract.DATA_CARRIER_TYPE_ID
				&& decision.resultRepresentationId == OcamlBytesRepresentationContract.DATA_INTERNAL_REPRESENTATION_ID
				&& StringTools.startsWith(decision.resultRepresentationRevision, "sha256:");
		}
		if (!valid)
			throw 'reflaxe.ocaml [ocaml-bytes:invalid-access-result]: access "${decision.id}" has an incompatible result';
	}
}
#end
