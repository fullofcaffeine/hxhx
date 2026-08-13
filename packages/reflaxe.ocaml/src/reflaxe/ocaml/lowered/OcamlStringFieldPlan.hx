package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.ds.ObjectMap;
import haxe.macro.Type.TypedExpr;
#if macro
import haxe.macro.Type.ClassType;
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;
#end
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

/** One source-bound read of the standard Haxe `String.length` field. */
typedef OcamlStringFieldDecision = {
	final id:String;
	final revision:String;
	final source:OcamlLoweredSourceSpan;
	final fieldName:String;
	final receiverSemanticTypeId:String;
	final resultSemanticTypeId:String;
	final evaluationOrder:Array<String>;
	final order:Int;
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

/**
	Owns direct reads of the standard Haxe `String.length` field.

	The plan proves that the final typed field still belongs to the root standard
	`String` class. It also fixes the receiver-first schedule and the one private
	`HxString.length` helper before target syntax starts. The expression lookup is
	valid only for the current compiler request.
**/
class OcamlStringFieldPlan {
	public static inline final MODEL_REVISION = "typed-ocaml-string-field-v1";
	public static inline final PROOF_ID = "string-length-field-runtime-use-v1";
	public static inline final PROOF_CLAIM = "The final typed expression is a direct read of the length field on the root standard Haxe String class. Its exact field owner, String receiver, Int result, and receiver-first schedule select one HxString.length use before target syntax.";
	public static inline final RUNTIME_CAPABILITY = "haxe-string-field-read";
	public static inline final EXACT_SYMBOL = "HxString.length";

	final ordered:Array<OcamlStringFieldDecision>;
	final byId:Map<String, OcamlStringFieldDecision> = [];
	final idByExpression:ObjectMap<TypedExpr, String>;

	public function new(decisions:Array<OcamlStringFieldDecision>, ?idByExpression:ObjectMap<TypedExpr, String>) {
		ordered = decisions.map(copyDecision);
		ordered.sort((left, right) -> left.order - right.order);
		this.idByExpression = idByExpression == null ? new ObjectMap() : idByExpression;
		for (decision in ordered) {
			requireDecision(decision);
			if (byId.exists(decision.id))
				throw 'reflaxe.ocaml [ocaml-string-field:duplicate-decision]: decision "${decision.id}" is sealed more than once';
			byId.set(decision.id, copyDecision(decision));
		}
		if (idByExpression != null)
			requireLookupCompleteness();
	}

	/** Returns the decision for this exact request-local field expression. */
	public function requireFor(expression:TypedExpr):OcamlStringFieldDecision {
		if (!idByExpression.exists(expression))
			throw "reflaxe.ocaml [ocaml-string-field:missing-decision]: String.length syntax has no sealed source occurrence";
		final id = idByExpression.get(expression);
		final decision = id == null ? null : byId.get(id);
		if (decision == null)
			throw "reflaxe.ocaml [ocaml-string-field:missing-decision]: the typed field names no sealed decision";
		requireDecision(decision);
		return copyDecision(decision);
	}

	/** Returns report-safe decisions in source order. */
	public function decisions():Array<OcamlStringFieldDecision>
		return ordered.map(copyDecision);

	/** Rejects decisions from another function, body, program, or pipeline. */
	public function requirePlanBinding(binding:OcamlFunctionPlanBinding):Void {
		for (decision in ordered)
			if (decision.functionId != binding.functionId
				|| decision.programRevision != binding.programRevision
				|| decision.bodyRevision != binding.bodyRevision
				|| decision.pipelineRevision != binding.pipelineRevision)
				throw 'reflaxe.ocaml [ocaml-string-field:stale-plan]: decision "${decision.id}" belongs to another function or target pipeline';
	}

	/** Rejects changed field, type, schedule, identity, or runtime-use facts. */
	public static function requireDecision(decision:OcamlStringFieldDecision):Void {
		if (decision == null
			|| decision.id.length == 0
			|| decision.source.file.length == 0
			|| decision.source.min < 0
			|| decision.source.max < decision.source.min
			|| decision.fieldName != "length"
			|| decision.receiverSemanticTypeId != "String"
			|| decision.resultSemanticTypeId != "Int"
			|| decision.evaluationOrder.join(",") != "receiver,runtime-read"
			|| decision.order < 0
			|| decision.profileEligibility.join(",") != "metal,portable"
			|| decision.runtimeRequirementIds.length != 1
			|| decision.runtimeUseOccurrences.length != 1
			|| decision.proofId != PROOF_ID
			|| decision.proofClaim != PROOF_CLAIM
			|| decision.functionId.length == 0
			|| decision.programRevision.length == 0
			|| decision.bodyRevision.length == 0
			|| decision.pipelineRevision.length == 0)
			throw "reflaxe.ocaml [ocaml-string-field:invalid-plan]: String field decision has incomplete or incompatible facts";

		final requirementId = runtimeRequirementId(decision.id);
		final expectedRevision = sealRevision(decision.id, decision.source, decision.fieldName, decision.receiverSemanticTypeId,
			decision.resultSemanticTypeId, decision.evaluationOrder, decision.order, bindingFor(decision), requirementId);
		final occurrence = decision.runtimeUseOccurrences[0];
		if (decision.revision != expectedRevision
			|| decision.runtimeRequirementIds[0] != requirementId
			|| occurrence.id != runtimeUseId(decision.id)
			|| occurrence.planRevision != decision.revision
			|| occurrence.ownerId != decision.id
			|| occurrence.requirementId != requirementId
			|| occurrence.domain != OcamlRuntimeUseDomain.ExpressionIdentifier
			|| occurrence.exactSymbol != EXACT_SYMBOL
			|| occurrence.role != "read-length"
			|| occurrence.order != 0
			|| occurrence.source.file != decision.source.file
			|| occurrence.source.min != decision.source.min
			|| occurrence.source.max != decision.source.max
			|| occurrence.profileEligibility.join(",") != "metal,portable"
			|| occurrence.cardinality != 1)
			throw 'reflaxe.ocaml [ocaml-string-field:invalid-runtime-use]: decision "${decision.id}" has stale or conflicting runtime facts';
	}

	public static function runtimeRequirementId(decisionId:String):String
		return decisionId + ":runtime:" + RUNTIME_CAPABILITY;

	public static function runtimeUseId(decisionId:String):String
		return decisionId + ":runtime-use:read-length";

	public static function sealRevision(id:String, source:OcamlLoweredSourceSpan, fieldName:String, receiverSemanticTypeId:String,
			resultSemanticTypeId:String, evaluationOrder:Array<String>, order:Int, binding:OcamlFunctionPlanBinding, requirementId:String):String {
		return "sha256:" + Sha256.encode([
			MODEL_REVISION,
			id,
			source.file,
			Std.string(source.min),
			Std.string(source.max),
			fieldName,
			receiverSemanticTypeId,
			resultSemanticTypeId,
			evaluationOrder.join(","),
			Std.string(order),
			binding.functionId,
			binding.programRevision,
			binding.bodyRevision,
			binding.pipelineRevision,
			requirementId,
			EXACT_SYMBOL
		].map(value -> value.length + ":" + value).join("|"));
	}

	function requireLookupCompleteness():Void {
		final seen:Map<String, Bool> = [];
		for (_ => decisionId in idByExpression) {
			if (seen.exists(decisionId))
				throw 'reflaxe.ocaml [ocaml-string-field:duplicate-lookup]: decision "$decisionId" is bound more than once';
			if (!byId.exists(decisionId))
				throw 'reflaxe.ocaml [ocaml-string-field:missing-decision]: typed expression "$decisionId" has no decision';
			seen.set(decisionId, true);
		}
		for (decision in ordered)
			if (!seen.exists(decision.id))
				throw 'reflaxe.ocaml [ocaml-string-field:unreachable-decision]: decision "${decision.id}" has no typed expression';
	}

	static function bindingFor(decision:OcamlStringFieldDecision):OcamlFunctionPlanBinding {
		return {
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
	}

	static function copyDecision(decision:OcamlStringFieldDecision):OcamlStringFieldDecision {
		return {
			id: decision.id,
			revision: decision.revision,
			source: copySource(decision.source),
			fieldName: decision.fieldName,
			receiverSemanticTypeId: decision.receiverSemanticTypeId,
			resultSemanticTypeId: decision.resultSemanticTypeId,
			evaluationOrder: decision.evaluationOrder.copy(),
			order: decision.order,
			profileEligibility: decision.profileEligibility.copy(),
			runtimeRequirementIds: decision.runtimeRequirementIds.copy(),
			runtimeUseOccurrences: decision.runtimeUseOccurrences.map(copyOccurrence),
			proofId: decision.proofId,
			proofClaim: decision.proofClaim,
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
	}

	static function copyOccurrence(occurrence:OcamlRuntimeUseOccurrence):OcamlRuntimeUseOccurrence {
		return {
			id: occurrence.id,
			planRevision: occurrence.planRevision,
			ownerId: occurrence.ownerId,
			requirementId: occurrence.requirementId,
			domain: occurrence.domain,
			exactSymbol: occurrence.exactSymbol,
			role: occurrence.role,
			order: occurrence.order,
			source: copySource(occurrence.source),
			profileEligibility: occurrence.profileEligibility.copy(),
			cardinality: occurrence.cardinality
		};
	}

	static function copySource(source:OcamlLoweredSourceSpan):OcamlLoweredSourceSpan
		return {file: source.file, min: source.min, max: source.max};
}

#if macro
/** Finds direct standard `String.length` reads before target syntax starts. */
class OcamlStringFieldPlanner {
	final binding:OcamlFunctionPlanBinding;

	public function new(binding:OcamlFunctionPlanBinding) {
		this.binding = binding;
	}

	public function plan(root:TypedExpr):OcamlStringFieldPlan {
		final decisions:Array<OcamlStringFieldDecision> = [];
		final lookup:ObjectMap<TypedExpr, String> = new ObjectMap();

		function visit(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TFunction(_):
					return;
				case TField(receiver, FInstance(classRef, _, fieldRef)):
					final owner = classRef.get();
					final field = fieldRef.get();
					if (isStandardString(owner) && field.name == "length" && field.kind.match(FVar(_, _))) {
						final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
						final order = decisions.length;
						// The resolved owner proves this is the root standard String field.
						// A typedef changes only the source spelling, not the carrier.
						final receiverSemanticTypeId = "String";
						final resultSemanticTypeId = TypeTools.toString(expression.t);
						final id = "string-field:" + Sha256.encode([
							binding.functionId,
							binding.programRevision,
							binding.bodyRevision,
							binding.pipelineRevision,
							Std.string(order),
							source.file,
							Std.string(source.min),
							Std.string(source.max),
							field.name,
							receiverSemanticTypeId,
							resultSemanticTypeId
						].join("\u001f")).substr(0, 24);
						final requirementId = OcamlStringFieldPlan.runtimeRequirementId(id);
						final evaluationOrder = ["receiver", "runtime-read"];
						final revision = OcamlStringFieldPlan.sealRevision(id, source, field.name, receiverSemanticTypeId, resultSemanticTypeId,
							evaluationOrder, order, binding, requirementId);
						final decision:OcamlStringFieldDecision = {
							id: id,
							revision: revision,
							source: copySource(source),
							fieldName: field.name,
							receiverSemanticTypeId: receiverSemanticTypeId,
							resultSemanticTypeId: resultSemanticTypeId,
							evaluationOrder: evaluationOrder,
							order: order,
							profileEligibility: ["metal", "portable"],
							runtimeRequirementIds: [requirementId],
							runtimeUseOccurrences: [
								{
									id: OcamlStringFieldPlan.runtimeUseId(id),
									planRevision: revision,
									ownerId: id,
									requirementId: requirementId,
									domain: OcamlRuntimeUseDomain.ExpressionIdentifier,
									exactSymbol: OcamlStringFieldPlan.EXACT_SYMBOL,
									role: "read-length",
									order: 0,
									source: copySource(source),
									profileEligibility: ["metal", "portable"],
									cardinality: 1
								}
							],
							proofId: OcamlStringFieldPlan.PROOF_ID,
							proofClaim: OcamlStringFieldPlan.PROOF_CLAIM,
							functionId: binding.functionId,
							programRevision: binding.programRevision,
							bodyRevision: binding.bodyRevision,
							pipelineRevision: binding.pipelineRevision
						};
						OcamlStringFieldPlan.requireDecision(decision);
						decisions.push(decision);
						lookup.set(expression, id);
						visit(receiver);
						return;
					}
				case _:
			}
			TypedExprTools.iter(expression, visit);
		}

		visit(root);
		final plan = new OcamlStringFieldPlan(decisions, lookup);
		plan.requirePlanBinding(binding);
		return plan;
	}

	/** Returns whether this expression is an exact standard String length read. */
	public static function isDirectStringLengthRead(expression:TypedExpr):Bool {
		return switch (expression.expr) {
			case TField(_, FInstance(classRef, _, fieldRef)): final owner = classRef.get(); final field = fieldRef.get(); isStandardString(owner) && field.name == "length" && field.kind.match(FVar(_,
					_));
			case _:
				false;
		};
	}

	static function isStandardString(classType:ClassType):Bool
		return classType.pack.length == 0 && classType.name == "String" && classType.module == "String";

	static function copySource(source:OcamlLoweredSourceSpan):OcamlLoweredSourceSpan
		return {file: source.file, min: source.min, max: source.max};
}
#end

#end
