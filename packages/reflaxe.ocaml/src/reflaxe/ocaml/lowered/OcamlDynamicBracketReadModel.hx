package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime || eval)
import haxe.crypto.Sha256;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

/** One immutable compatibility decision for a numeric bracket read from a non-Array value. */
typedef OcamlDynamicBracketReadDecision = {
	final id:String;
	final source:OcamlLoweredSourceSpan;
	final readOrdinal:Int;
	final receiverSemanticTypeId:String;
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

/** Closed identities shared by non-Array bracket-read planning and syntax. */
class OcamlDynamicBracketReadContract {
	public static inline final MODEL_REVISION = "ocaml-dynamic-bracket-read-v1";
	public static inline final RUNTIME_CAPABILITY = "haxe-dynamic-numeric-bracket-read";
	public static inline final PROOF_ID = "dynamic-numeric-bracket-read-v1";
	public static inline final PROOF_CLAIM = "This occurrence evaluates one non-Array, non-Bytes receiver, then one non-string bracket index, and performs the existing Haxe-compatible read once through HxArray.get. It does not weaken the stricter standard Array read contract or admit string-key access, writes, or updates.";

	public static function idFor(binding:OcamlFunctionPlanBinding, source:OcamlLoweredSourceSpan, readOrdinal:Int, receiverSemanticTypeId:String,
			indexSemanticTypeId:String, resultSemanticTypeId:String):String {
		return "dynamic-bracket-read:" + Sha256.encode([
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
			indexSemanticTypeId,
			resultSemanticTypeId
		].join("\n")).substr(0, 32);
	}

	public static function runtimeRequirementId(readId:String):String {
		if (readId == null || readId.length == 0)
			throw "reflaxe.ocaml [ocaml-dynamic-bracket-read:invalid-runtime-owner]: a bracket read requires a stable owner";
		return readId + ":runtime:" + RUNTIME_CAPABILITY;
	}

	public static function runtimeUse(binding:OcamlFunctionPlanBinding, readId:String, source:OcamlLoweredSourceSpan,
			profileEligibility:Array<String>):OcamlRuntimeUseOccurrence {
		return {
			id: readId + ":runtime-use:get",
			planRevision: OcamlRuntimeUseModel.planRevision(binding),
			ownerId: readId,
			requirementId: runtimeRequirementId(readId),
			domain: OcamlRuntimeUseDomain.ExpressionIdentifier,
			exactSymbol: "HxArray.get",
			role: "read-dynamic-index",
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

	/** Rejects a decision that no longer proves the exact compatibility call. */
	public static function requireDecision(decision:OcamlDynamicBracketReadDecision):Void {
		if (decision == null
			|| decision.id.length == 0
			|| decision.source.file.length == 0
			|| decision.source.min < 0
			|| decision.source.max < decision.source.min
			|| decision.readOrdinal < 0
			|| decision.receiverSemanticTypeId.length == 0
			|| decision.indexSemanticTypeId.length == 0
			|| decision.resultSemanticTypeId.length == 0
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
			throw 'reflaxe.ocaml [ocaml-dynamic-bracket-read:invalid-decision]: bracket read "${decision == null ? "<null>" : decision.id}" has incomplete type, order, runtime, proof, or binding facts';
		}
		final binding:OcamlFunctionPlanBinding = {
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
		final expectedId = idFor(binding, decision.source, decision.readOrdinal, decision.receiverSemanticTypeId, decision.indexSemanticTypeId,
			decision.resultSemanticTypeId);
		if (decision.id != expectedId)
			throw 'reflaxe.ocaml [ocaml-dynamic-bracket-read:noncanonical-identity]: bracket read "${decision.id}" does not match its typed owner and ordinal';
		final expectedUse = runtimeUse(binding, decision.id, decision.source, decision.profileEligibility);
		if (haxe.Json.stringify(decision.runtimeUseOccurrences[0]) != haxe.Json.stringify(expectedUse))
			throw 'reflaxe.ocaml [ocaml-dynamic-bracket-read:invalid-runtime-use]: bracket read "${decision.id}" does not own the exact HxArray.get occurrence';
	}

	public static function planRevision(decisions:Array<OcamlDynamicBracketReadDecision>):String {
		final ordered = decisions.copy();
		ordered.sort((left, right) -> Reflect.compare(left.id, right.id));
		for (decision in ordered)
			requireDecision(decision);
		return "sha256:" + Sha256.encode(ordered.map(decision -> haxe.Json.stringify(decision)).join("\n"));
	}
}
#end
