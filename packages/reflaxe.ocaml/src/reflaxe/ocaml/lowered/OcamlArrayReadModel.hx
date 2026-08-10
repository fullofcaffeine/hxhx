package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime || eval)
import haxe.crypto.Sha256;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

/** One immutable decision for a numeric bracket read from a standard Haxe Array. */
typedef OcamlArrayReadDecision = {
	final id:String;
	final source:OcamlLoweredSourceSpan;
	final readOrdinal:Int;
	final receiverSemanticTypeId:String;
	final elementSemanticTypeId:String;
	final indexSemanticTypeId:String;
	final resultSemanticTypeId:String;
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
	public static inline final MODEL_REVISION = "ocaml-array-read-v1";
	public static inline final RUNTIME_CAPABILITY = "haxe-array-index-read";
	public static inline final PROOF_ID = "standard-array-index-read-v1";
	public static inline final PROOF_CLAIM = "This occurrence evaluates one standard Haxe Array receiver, then one Int index, and reads that element once through HxArray.get. The claim does not admit a write target, update target, string-key Dynamic access, Bytes access, Array method, or another runtime call.";

	/** Returns the stable identity for one typed read in its enclosing body. */
	public static function idFor(binding:OcamlFunctionPlanBinding, source:OcamlLoweredSourceSpan, readOrdinal:Int, receiverSemanticTypeId:String,
			elementSemanticTypeId:String):String {
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
			elementSemanticTypeId
		].join("\n")).substr(0, 32);
	}

	/** Returns the one runtime-requirement identity owned by a read. */
	public static function runtimeRequirementId(readId:String):String {
		if (readId == null || readId.length == 0)
			throw "reflaxe.ocaml [ocaml-array-read:invalid-runtime-owner]: an Array read requires a stable owner";
		return readId + ":runtime:" + RUNTIME_CAPABILITY;
	}

	/** Creates the only private runtime occurrence that this read can consume. */
	public static function runtimeUse(binding:OcamlFunctionPlanBinding, readId:String, source:OcamlLoweredSourceSpan,
			profileEligibility:Array<String>):OcamlRuntimeUseOccurrence {
		return {
			id: readId + ":runtime-use:get",
			planRevision: OcamlRuntimeUseModel.planRevision(binding),
			ownerId: readId,
			requirementId: runtimeRequirementId(readId),
			domain: OcamlRuntimeUseDomain.ExpressionIdentifier,
			exactSymbol: "HxArray.get",
			role: "read-element",
			order: 0,
			source: {
				file: source.file,
				min: source.min,
				max: source.max
			},
			profileEligibility: profileEligibility.copy(),
			cardinality: 1
		};
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
			|| decision.indexSemanticTypeId != "Int"
			|| decision.resultSemanticTypeId != decision.elementSemanticTypeId
			|| decision.evaluationOrder.join(",") != "receiver,index,runtime-read"
			|| decision.profileEligibility.join(",") != "metal,portable"
			|| decision.runtimeRequirementIds.length != 1
			|| decision.runtimeRequirementIds[0] != runtimeRequirementId(decision.id)
			|| decision.runtimeUseOccurrences.length != 1
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
		}, decision.source, decision.readOrdinal,
			decision.receiverSemanticTypeId, decision.elementSemanticTypeId);
		if (decision.id != expectedId)
			throw 'reflaxe.ocaml [ocaml-array-read:noncanonical-identity]: Array read "${decision.id}" does not match its typed owner and ordinal';
		final expectedUse = runtimeUse({
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		}, decision.id, decision.source, decision.profileEligibility);
		final actualUse = decision.runtimeUseOccurrences[0];
		if (haxe.Json.stringify(actualUse) != haxe.Json.stringify(expectedUse))
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
