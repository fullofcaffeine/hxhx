package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime || eval)
import haxe.crypto.Sha256;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;

/** One ordered action used to construct a represented Haxe array literal. */
enum abstract OcamlArrayLiteralEvaluationKind(String) from String to String {
	/** Allocate the empty `HxArray` container before evaluating any element. */
	final CreateArray = "create-array";

	/** Evaluate one source element and keep its value in a temporary binding. */
	final EvaluateElement = "evaluate-element";

	/** Append the already-evaluated temporary value to the array. */
	final StoreElement = "store-element";

	/** Return the same constructed array object as the literal's value. */
	final ResultArray = "result-array";
}

/** One element value produced by a represented array literal. */
typedef OcamlArrayLiteralElementProducer = {
	final id:String;
	final index:Int;
	final source:OcamlLoweredSourceSpan;
	final semanticTypeId:String;
	final carrierTypeId:String;
	final representationId:String;
	final representationRevision:String;
}

/** One exact step in the literal's create/evaluate/store/result schedule. */
typedef OcamlArrayLiteralEvaluationStep = {
	final ordinal:Int;
	final kind:OcamlArrayLiteralEvaluationKind;
	final elementIndex:Null<Int>;
	final elementProducerId:Null<String>;
}

/**
	One immutable construction decision for an admitted direct flat array literal.

	The decision is a plain-value receipt created before OCaml syntax exists. It
	binds the literal to the current program's represented-array descriptor and
	records exactly one evaluation and one store for each source element. The
	descriptor supplies the exact element family; this record never guesses it from
	the target carrier text.
**/
typedef OcamlArrayLiteralProducerDecision = {
	final id:String;
	final source:OcamlLoweredSourceSpan;
	final literalOrdinal:Int;
	final arraySemanticTypeId:String;
	final arrayCarrierTypeId:String;
	final resultRepresentationId:String;
	final resultRepresentationRevision:String;
	final arrayDescriptorId:String;
	final arrayDescriptorRevision:String;
	final elementSemanticTypeId:String;
	final elementCarrierTypeId:String;
	final elementRepresentationId:String;
	final elementRepresentationRevision:String;
	final elements:Array<OcamlArrayLiteralElementProducer>;
	final evaluationSchedule:Array<OcamlArrayLiteralEvaluationStep>;
	final constructionPolicy:String;
	final proofId:String;
	final proofClaim:String;
	final profileEligibility:Array<String>;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
}

/** Closed identities and validation shared by planning, reports, and syntax. */
class OcamlArrayLiteralProducerContract {
	public static inline final MODEL_REVISION = "ocaml-represented-array-literal-producer-v2";
	public static inline final CONSTRUCTION_POLICY = "create-then-evaluate-and-push-in-order";
	public static inline final INT_PROOF_ID = "direct-array-int-literal-construction-v1";
	public static inline final INT_PROOF_CLAIM = "This occurrence allocates one direct represented Array<Int>, evaluates each exact Int element once in increasing source order, stores each evaluated carrier once, and returns the same mutable HxArray object. The claim ends at literal construction and does not admit another array shape, element family, call, return, field, typed catch, or public/native boundary.";
	public static inline final STRING_PROOF_ID = "direct-array-string-literal-construction-v1";
	public static inline final STRING_PROOF_CLAIM = "This occurrence allocates one direct represented Array<String>, evaluates each exact String element once in increasing source order, stores each evaluated carrier once, and returns the same mutable HxArray object. The claim ends at literal construction and does not admit another array shape, element family, call, return, field, typed catch, or public/native boundary.";

	/** Returns the exact construction proof for one already-admitted element family. */
	public static function proofIdFor(elementSemanticTypeId:String):String {
		return requiredFamily(elementSemanticTypeId).proofId;
	}

	/** Returns the human-readable behavior protected by one family proof. */
	public static function proofClaimFor(elementSemanticTypeId:String):String {
		return requiredFamily(elementSemanticTypeId).proofClaim;
	}

	/** True only for the complete revision form emitted by the compiler. */
	static function isSha256Revision(value:String):Bool {
		return ~/^sha256:[0-9a-f]{64}$/.match(value);
	}

	/**
		Computes one deterministic revision for a function's complete literal plan.

		A control decision records this revision together with the exact literal ID.
		That pair prevents a stale throw decision from accepting a producer whose
		element order or construction schedule changed after control was planned.
	**/
	public static function planRevision(decisions:Array<OcamlArrayLiteralProducerDecision>):String {
		final ordered = decisions.copy();
		ordered.sort((left, right) -> Reflect.compare(left.id, right.id));
		for (decision in ordered)
			requireDecision(decision);
		return "sha256:" + Sha256.encode(ordered.map(decisionFingerprint).join("\n"));
	}

	/** Names the one function/body/pipeline plan that owns a producer or control. */
	public static function bindingKey(functionId:String, programRevision:String, bodyRevision:String, pipelineRevision:String):String {
		return [functionId, programRevision, bodyRevision, pipelineRevision].join("\u001f");
	}

	/** Computes the stable occurrence identity used by planning and reports. */
	public static function idFor(binding:OcamlFunctionPlanBinding, source:OcamlLoweredSourceSpan, literalOrdinal:Int, resultRepresentationId:String,
			resultRepresentationRevision:String, arrayDescriptorId:String, arrayDescriptorRevision:String):String {
		return "array-literal-producer:" + Sha256.encode([
			MODEL_REVISION,
			binding.functionId,
			binding.programRevision,
			binding.bodyRevision,
			binding.pipelineRevision,
			source.file,
			Std.string(source.min),
			Std.string(source.max),
			Std.string(literalOrdinal),
			resultRepresentationId,
			resultRepresentationRevision,
			arrayDescriptorId,
			arrayDescriptorRevision
		].join("\n")).substr(0, 32);
	}

	/** Computes one element identity without retaining the typed expression. */
	public static function elementIdFor(literalId:String, index:Int, source:OcamlLoweredSourceSpan, representationId:String,
			representationRevision:String):String {
		return literalId + ":element:" + Sha256.encode([
			literalId,
			Std.string(index),
			source.file,
			Std.string(source.min),
			Std.string(source.max),
			representationId,
			representationRevision
		].join("\n")).substr(0, 20);
	}

	/** Builds the only schedule accepted for this literal family. */
	public static function schedule(elements:Array<OcamlArrayLiteralElementProducer>):Array<OcamlArrayLiteralEvaluationStep> {
		final out:Array<OcamlArrayLiteralEvaluationStep> = [
			{
				ordinal: 0,
				kind: OcamlArrayLiteralEvaluationKind.CreateArray,
				elementIndex: null,
				elementProducerId: null
			}
		];
		for (element in elements) {
			out.push({
				ordinal: out.length,
				kind: OcamlArrayLiteralEvaluationKind.EvaluateElement,
				elementIndex: element.index,
				elementProducerId: element.id
			});
			out.push({
				ordinal: out.length,
				kind: OcamlArrayLiteralEvaluationKind.StoreElement,
				elementIndex: element.index,
				elementProducerId: element.id
			});
		}
		out.push({
			ordinal: out.length,
			kind: OcamlArrayLiteralEvaluationKind.ResultArray,
			elementIndex: null,
			elementProducerId: null
		});
		return out;
	}

	static function decisionFingerprint(decision:OcamlArrayLiteralProducerDecision):String {
		final elements = decision.elements.map(element -> [
			element.id,
			Std.string(element.index),
			element.source.file,
			Std.string(element.source.min),
			Std.string(element.source.max),
			element.semanticTypeId,
			element.carrierTypeId,
			element.representationId,
			element.representationRevision
		].join("|"));
		final schedule = decision.evaluationSchedule.map(step -> [
			Std.string(step.ordinal),
			(step.kind : String),
			step.elementIndex == null ? "" : Std.string(step.elementIndex),
			step.elementProducerId ?? ""
		].join("|"));
		return [
			decision.id,
			decision.source.file,
			Std.string(decision.source.min),
			Std.string(decision.source.max),
			Std.string(decision.literalOrdinal),
			decision.arraySemanticTypeId,
			decision.arrayCarrierTypeId,
			decision.resultRepresentationId,
			decision.resultRepresentationRevision,
			decision.arrayDescriptorId,
			decision.arrayDescriptorRevision,
			decision.elementSemanticTypeId,
			decision.elementCarrierTypeId,
			decision.elementRepresentationId,
			decision.elementRepresentationRevision,
			elements.join("\u001e"),
			schedule.join("\u001e"),
			decision.constructionPolicy,
			decision.proofId,
			decision.proofClaim,
			decision.profileEligibility.join(","),
			decision.functionId,
			decision.programRevision,
			decision.bodyRevision,
			decision.pipelineRevision
		].join("\u001f");
	}

	/** Rejects missing, duplicated, reordered, stale, or conflicting facts. */
	public static function requireDecision(decision:OcamlArrayLiteralProducerDecision):Void {
		if (decision == null)
			throw "reflaxe.ocaml [ocaml-array-literal:invalid-producer]: array literal producer decision is null";
		final family = familyFor(decision.elementSemanticTypeId);
		final binding:OcamlFunctionPlanBinding = {
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
		final expectedId = idFor(binding, decision.source, decision.literalOrdinal, decision.resultRepresentationId, decision.resultRepresentationRevision,
			decision.arrayDescriptorId, decision.arrayDescriptorRevision);
		if (decision.id != expectedId
			|| decision.source.file.length == 0
			|| decision.source.min < 0
			|| decision.source.max < decision.source.min
			|| decision.literalOrdinal < 0
			|| family == null
			|| decision.arraySemanticTypeId != family.arraySemanticTypeId
			|| decision.arrayCarrierTypeId != family.arrayCarrierTypeId
			|| decision.resultRepresentationId != family.resultRepresentationId
			|| !isSha256Revision(decision.resultRepresentationRevision)
			|| decision.arrayDescriptorId != family.arrayDescriptorId
			|| !isSha256Revision(decision.arrayDescriptorRevision)
			|| decision.elementCarrierTypeId != family.elementCarrierTypeId
			|| decision.elementRepresentationId != family.elementRepresentationId
			|| !isSha256Revision(decision.elementRepresentationRevision)
			|| decision.constructionPolicy != CONSTRUCTION_POLICY
			|| decision.proofId != family.proofId
			|| decision.proofClaim != family.proofClaim
			|| decision.profileEligibility.join(",") != "metal,portable"
			|| decision.functionId.length == 0
			|| decision.programRevision.length == 0
			|| decision.bodyRevision.length == 0
			|| decision.pipelineRevision.length == 0) {
			throw 'reflaxe.ocaml [ocaml-array-literal:invalid-producer]: producer "${decision.id}" does not match an admitted direct represented array literal contract';
		}
		final elementIds:Map<String, Bool> = [];
		for (index in 0...decision.elements.length) {
			final element = decision.elements[index];
			final expectedElementId = elementIdFor(decision.id, index, element.source, decision.elementRepresentationId,
				decision.elementRepresentationRevision);
			if (element.id != expectedElementId
				|| elementIds.exists(element.id)
				|| element.index != index
				|| element.source.file.length == 0
				|| element.source.min < 0
				|| element.source.max < element.source.min
				|| element.semanticTypeId != decision.elementSemanticTypeId
				|| element.carrierTypeId != decision.elementCarrierTypeId
				|| element.representationId != decision.elementRepresentationId
				|| element.representationRevision != decision.elementRepresentationRevision) {
				throw 'reflaxe.ocaml [ocaml-array-literal:invalid-element-producer]: producer "${decision.id}" has a missing, duplicated, reordered, or conflicting element at index $index';
			}
			elementIds.set(element.id, true);
		}
		final expectedSchedule = schedule(decision.elements);
		if (decision.evaluationSchedule.length != expectedSchedule.length)
			throw 'reflaxe.ocaml [ocaml-array-literal:invalid-evaluation-schedule]: producer "${decision.id}" does not evaluate and store every element exactly once';
		for (index in 0...expectedSchedule.length) {
			final actual = decision.evaluationSchedule[index];
			final expected = expectedSchedule[index];
			if (actual.ordinal != expected.ordinal
				|| actual.kind != expected.kind
				|| actual.elementIndex != expected.elementIndex
				|| actual.elementProducerId != expected.elementProducerId) {
				throw 'reflaxe.ocaml [ocaml-array-literal:invalid-evaluation-schedule]: producer "${decision.id}" changed construction step $index';
			}
		}
	}

	/**
		Returns the closed semantic and carrier identity for one producer family.

		This is deliberately a small exact table rather than a carrier-string parser.
		A new element family must first prove its own array-element representation and
		literal behavior before it can add another row.
	**/
	static function familyFor(elementSemanticTypeId:String):Null<{
		final arraySemanticTypeId:String;
		final arrayCarrierTypeId:String;
		final resultRepresentationId:String;
		final arrayDescriptorId:String;
		final elementCarrierTypeId:String;
		final elementRepresentationId:String;
		final proofId:String;
		final proofClaim:String;
	}> {
		return switch (elementSemanticTypeId) {
			case "Int": {
					arraySemanticTypeId: "Array<Int>",
					arrayCarrierTypeId: "int HxArray.t",
					resultRepresentationId: "representation:Array<Int>:internal-value",
					arrayDescriptorId: "represented-array:Array<Int>",
					elementCarrierTypeId: "int",
					elementRepresentationId: "representation:Int:array-element",
					proofId: INT_PROOF_ID,
					proofClaim: INT_PROOF_CLAIM
				};
			case "String": {
					arraySemanticTypeId: "Array<String>",
					arrayCarrierTypeId: "string HxArray.t",
					resultRepresentationId: "representation:Array<String>:internal-value",
					arrayDescriptorId: "represented-array:Array<String>",
					elementCarrierTypeId: "string",
					elementRepresentationId: "representation:String:array-element",
					proofId: STRING_PROOF_ID,
					proofClaim: STRING_PROOF_CLAIM
				};
			case _: null;
		};
	}

	static function requiredFamily(elementSemanticTypeId:String):{
		final arraySemanticTypeId:String;
		final arrayCarrierTypeId:String;
		final resultRepresentationId:String;
		final arrayDescriptorId:String;
		final elementCarrierTypeId:String;
		final elementRepresentationId:String;
		final proofId:String;
		final proofClaim:String;
	} {
		final family = familyFor(elementSemanticTypeId);
		if (family == null)
			throw 'reflaxe.ocaml [ocaml-array-literal:unsupported-element-family]: $elementSemanticTypeId has no literal-construction proof';
		return family;
	}
}
#end
