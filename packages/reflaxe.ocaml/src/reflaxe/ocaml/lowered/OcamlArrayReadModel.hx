package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime || eval)
import haxe.crypto.Sha256;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

/** How OCaml learns the result type of one standard Array read. */
enum abstract OcamlArrayReadResultCarrier(String) from String to String {
	/** The surrounding OCaml expression already determines the element type. */
	var Inferred = "inferred";

	/** The final Haxe function type must be attached at the read boundary. */
	var ExactCallable = "exact-callable";
}

/** How one Array index becomes the exact OCaml integer required by HxArray. */
enum abstract OcamlArrayReadIndexCarrier(String) from String to String {
	/** The typed index already has the exact core Int representation. */
	var ExactInt = "exact-int";

	/** A core Null<Int> index must reject null before it becomes an OCaml int. */
	var CheckedNullableInt = "checked-nullable-int";
}

/** One immutable decision for a numeric bracket read from a standard Haxe Array. */
typedef OcamlArrayReadDecision = {
	final id:String;
	final source:OcamlLoweredSourceSpan;
	final readOrdinal:Int;
	final receiverSemanticTypeId:String;
	final elementSemanticTypeId:String;
	final indexSemanticTypeId:String;
	final indexCarrier:OcamlArrayReadIndexCarrier;
	final resultSemanticTypeId:String;
	final resultCarrier:OcamlArrayReadResultCarrier;
	final evaluationOrder:Array<String>;
	final profileEligibility:Array<String>;
	final runtimeRequirementIds:Array<String>;
	final runtimeUseOccurrences:Array<OcamlRuntimeUseOccurrence>;
	final proofId:String;
	final proofClaim:String;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
}

/** Closed identities and validation shared by Array-read planning and syntax. */
class OcamlArrayReadContract {
	public static inline final MODEL_REVISION = "ocaml-array-read-v3";
	public static inline final RUNTIME_CAPABILITY = "haxe-array-index-read";
	public static inline final NULLABLE_INT_RUNTIME_CAPABILITY = "nullable-int-checked-read";
	public static inline final PROOF_ID = "standard-array-index-read-v2";
	public static inline final PROOF_CLAIM = "This occurrence evaluates one standard Haxe Array receiver, then one exact Int or core Null<Int> index. A nullable index is checked once and null fails before HxArray.get reads the element. The claim does not admit a write target, update target, string-key Dynamic access, Bytes access, Array method, or another runtime call.";

	/** Returns the stable identity for one typed read in its enclosing body. */
	public static function idFor(binding:OcamlFunctionPlanBinding, source:OcamlLoweredSourceSpan, readOrdinal:Int, receiverSemanticTypeId:String,
			elementSemanticTypeId:String, indexCarrier:OcamlArrayReadIndexCarrier, resultCarrier:OcamlArrayReadResultCarrier):String {
		return "array-read:" + Sha256.encode([
			MODEL_REVISION,
			binding.functionId,
			binding.programRevision,
			binding.bodyRevision,
			binding.pipelineRevision,
			source.file,
			Std.string(source.min),
			Std.string(source.max),
			Std.string(readOrdinal),
			receiverSemanticTypeId,
			elementSemanticTypeId,
			indexCarrier,
			resultCarrier
		].join("\n")).substr(0, 32);
	}

	/** Returns the one runtime-requirement identity owned by a read. */
	public static function runtimeRequirementId(readId:String):String {
		if (readId == null || readId.length == 0)
			throw "reflaxe.ocaml [ocaml-array-read:invalid-runtime-owner]: an Array read requires a stable owner";
		return readId + ":runtime:" + RUNTIME_CAPABILITY;
	}

	/** Returns the checked nullable-index runtime requirement owned by one read. */
	public static function nullableIntRuntimeRequirementId(readId:String):String {
		if (readId == null || readId.length == 0)
			throw "reflaxe.ocaml [ocaml-array-read:invalid-runtime-owner]: a nullable Array index requires a stable owner";
		return readId + ":runtime:" + NULLABLE_INT_RUNTIME_CAPABILITY;
	}

	/** Returns every runtime requirement selected by the index carrier. */
	public static function runtimeRequirementIdsFor(readId:String, indexCarrier:OcamlArrayReadIndexCarrier):Array<String> {
		final result = new Array<String>();
		if (indexCarrier == OcamlArrayReadIndexCarrier.CheckedNullableInt)
			result.push(nullableIntRuntimeRequirementId(readId));
		result.push(runtimeRequirementId(readId));
		return result;
	}

	/** Creates the only private runtime occurrence that this read can consume. */
	public static function runtimeUseOccurrencesFor(binding:OcamlFunctionPlanBinding, readId:String, source:OcamlLoweredSourceSpan,
			profileEligibility:Array<String>, indexCarrier:OcamlArrayReadIndexCarrier):Array<OcamlRuntimeUseOccurrence> {
		final result = new Array<OcamlRuntimeUseOccurrence>();
		function add(requirementId:String, exactSymbol:String, role:String):Void {
			result.push({
				id: readId + ":runtime-use:" + (role == "read-element" ? "get" : role),
				planRevision: OcamlRuntimeUseModel.planRevision(binding),
				ownerId: readId,
				requirementId: requirementId,
				domain: OcamlRuntimeUseDomain.ExpressionIdentifier,
				exactSymbol: exactSymbol,
				role: role,
				order: result.length,
				source: {
					file: source.file,
					min: source.min,
					max: source.max
				},
				profileEligibility: profileEligibility.copy(),
				cardinality: 1
			});
		}
		if (indexCarrier == OcamlArrayReadIndexCarrier.CheckedNullableInt)
			add(nullableIntRuntimeRequirementId(readId), "HxRuntime.nullable_int_unwrap", "unwrap-index");
		add(runtimeRequirementId(readId), "HxArray.get", "read-element");
		return result;
	}

	/** Rejects incomplete, stale-looking, or internally conflicting read facts. */
	public static function requireDecision(decision:OcamlArrayReadDecision):Void {
		if (decision == null
			|| decision.id.length == 0
			|| decision.source.file.length == 0
			|| decision.source.min < 0
			|| decision.source.max < decision.source.min
			|| decision.readOrdinal < 0
			|| decision.receiverSemanticTypeId != 'Array<${decision.elementSemanticTypeId}>'
			|| decision.elementSemanticTypeId.length == 0
			|| (decision.indexSemanticTypeId == "Int" && decision.indexCarrier != OcamlArrayReadIndexCarrier.ExactInt)
			|| (decision.indexSemanticTypeId == "Null<Int>" && decision.indexCarrier != OcamlArrayReadIndexCarrier.CheckedNullableInt)
			|| (decision.indexSemanticTypeId != "Int" && decision.indexSemanticTypeId != "Null<Int>")
			|| decision.resultSemanticTypeId != decision.elementSemanticTypeId
			|| (decision.resultCarrier != OcamlArrayReadResultCarrier.Inferred
				&& decision.resultCarrier != OcamlArrayReadResultCarrier.ExactCallable)
			|| decision.evaluationOrder.join(",") != "receiver,index,runtime-read"
			|| decision.profileEligibility.join(",") != "metal,portable"
			|| decision.runtimeRequirementIds.join(",") != runtimeRequirementIdsFor(decision.id, decision.indexCarrier).join(",")
			|| decision.runtimeUseOccurrences.length != decision.runtimeRequirementIds.length
			|| decision.proofId != PROOF_ID
			|| decision.proofClaim != PROOF_CLAIM
			|| decision.functionId.length == 0
			|| decision.programRevision.length == 0
			|| decision.bodyRevision.length == 0
			|| decision.pipelineRevision.length == 0) {
			throw 'reflaxe.ocaml [ocaml-array-read:invalid-decision]: Array read "${decision == null ? "<null>" : decision.id}" has incomplete type, order, runtime, proof, or binding facts';
		}
		final expectedId = idFor({
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		},
			decision.source, decision.readOrdinal, decision.receiverSemanticTypeId, decision.elementSemanticTypeId, decision.indexCarrier,
			decision.resultCarrier);
		if (decision.id != expectedId)
			throw 'reflaxe.ocaml [ocaml-array-read:noncanonical-identity]: Array read "${decision.id}" does not match its typed owner and ordinal';
		final expectedUses = runtimeUseOccurrencesFor({
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		}, decision.id, decision.source, decision.profileEligibility,
			decision.indexCarrier);
		if (haxe.Json.stringify(decision.runtimeUseOccurrences) != haxe.Json.stringify(expectedUses))
			throw 'reflaxe.ocaml [ocaml-array-read:invalid-runtime-use]: Array read "${decision.id}" does not own the exact HxArray.get occurrence';
	}

	/** Returns a stable revision for a complete body-local read inventory. */
	public static function planRevision(decisions:Array<OcamlArrayReadDecision>):String {
		final ordered = decisions.copy();
		ordered.sort((left, right) -> Reflect.compare(left.id, right.id));
		for (decision in ordered)
			requireDecision(decision);
		return "sha256:" + Sha256.encode(ordered.map(fingerprint).join("\n"));
	}

	/** Returns the plain-value fingerprint used by deterministic tests and reports. */
	public static function fingerprint(decision:OcamlArrayReadDecision):String {
		return haxe.Json.stringify(decision);
	}
}
#end
