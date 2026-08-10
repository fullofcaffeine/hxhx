package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.ds.ObjectMap;
import haxe.macro.Expr.Binop;
import haxe.macro.Expr.Unop;
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.lowered.OcamlArrayReadModel.OcamlArrayReadContract;
import reflaxe.ocaml.lowered.OcamlArrayReadModel.OcamlArrayReadDecision;

typedef OcamlArrayReadOccurrence = {
	final receiver:TypedExpr;
	final index:TypedExpr;
	final receiverSemanticTypeId:String;
	final elementSemanticTypeId:String;
	final indexSemanticTypeId:String;
	final resultSemanticTypeId:String;
}

/**
	Owns each standard Array bracket read in one final typed expression root.

	The persistent decisions contain plain values. The object-keyed map is only a
	request-local bridge from the active Haxe typed nodes to those decisions.
**/
class OcamlArrayReadPlan {
	final ordered:Array<OcamlArrayReadDecision>;
	final idByExpression:ObjectMap<TypedExpr, String>;
	final byId:Map<String, OcamlArrayReadDecision> = [];

	public final revision:String;

	public function new(decisions:Array<OcamlArrayReadDecision>, ?idByExpression:ObjectMap<TypedExpr, String>) {
		this.idByExpression = idByExpression == null ? new ObjectMap() : idByExpression;
		ordered = decisions.map(copyDecision);
		ordered.sort((left, right) -> Reflect.compare(left.id, right.id));
		for (decision in ordered) {
			OcamlArrayReadContract.requireDecision(decision);
			if (byId.exists(decision.id))
				throw 'reflaxe.ocaml [ocaml-array-read:duplicate-decision]: Array read "${decision.id}" is sealed more than once';
			byId.set(decision.id, copyDecision(decision));
		}
		if (idByExpression != null)
			requireLookupCompleteness();
		revision = OcamlArrayReadContract.planRevision(ordered);
	}

	/** Returns the sealed decision for one exact request-local typed read. */
	public function decisionFor(expression:TypedExpr):Null<OcamlArrayReadDecision> {
		if (!idByExpression.exists(expression))
			return null;
		final id = idByExpression.get(expression);
		final decision = byId.get(id);
		return decision == null ? null : copyDecision(decision);
	}

	/** Requires syntax to consume the decision selected for this typed read. */
	public function requireFor(expression:TypedExpr):OcamlArrayReadDecision {
		final occurrence = admittedOccurrence(expression);
		if (occurrence == null)
			throw "reflaxe.ocaml [ocaml-array-read:unadmitted-read]: syntax requested an Array read outside the sealed family";
		final decision = decisionFor(expression);
		if (decision == null)
			throw "reflaxe.ocaml [ocaml-array-read:missing-decision]: an admitted Array read reached syntax without its sealed decision";
		if (decision.receiverSemanticTypeId != occurrence.receiverSemanticTypeId
			|| decision.elementSemanticTypeId != occurrence.elementSemanticTypeId
			|| decision.indexSemanticTypeId != occurrence.indexSemanticTypeId
			|| decision.resultSemanticTypeId != occurrence.resultSemanticTypeId) {
			throw 'reflaxe.ocaml [ocaml-array-read:typed-mismatch]: Array read "${decision.id}" no longer matches its final typed occurrence';
		}
		OcamlArrayReadContract.requireDecision(decision);
		return decision;
	}

	/** Returns all read decisions in deterministic identity order. */
	public function decisions():Array<OcamlArrayReadDecision> {
		return ordered.map(copyDecision);
	}

	/** Rejects a plan retained for another function body or target pipeline. */
	public function requirePlanBinding(binding:OcamlFunctionPlanBinding):Void {
		for (decision in ordered) {
			if (decision.functionId != binding.functionId
				|| decision.programRevision != binding.programRevision
				|| decision.bodyRevision != binding.bodyRevision
				|| decision.pipelineRevision != binding.pipelineRevision) {
				throw 'reflaxe.ocaml [ocaml-array-read:stale-plan]: Array read "${decision.id}" does not belong to ${binding.functionId}/${binding.bodyRevision}/${binding.pipelineRevision}';
			}
		}
	}

	/** Returns the standard Array receiver and Int index for one admitted read. */
	public static function admittedOccurrence(expression:TypedExpr):Null<OcamlArrayReadOccurrence> {
		return switch (expression.expr) {
			case TArray(receiver, index):
				final elementSemanticTypeId = arrayElementSemanticTypeId(receiver.t);
				final resultSemanticTypeId = TypeTools.toString(expression.t);
				if (elementSemanticTypeId == null
					|| !OcamlRepresentationRegistry.isExactInt(index.t)
					|| resultSemanticTypeId != elementSemanticTypeId) {
					null;
				} else {
					{
						receiver: receiver,
						index: index,
						receiverSemanticTypeId: 'Array<$elementSemanticTypeId>',
						elementSemanticTypeId: elementSemanticTypeId,
						indexSemanticTypeId: "Int",
						resultSemanticTypeId: resultSemanticTypeId
					};
				}
			case _:
				null;
		};
	}

	/** Returns true only when the receiver is statically a standard Haxe Array. */
	public static function hasStandardArrayReceiver(expression:TypedExpr):Bool {
		return switch (expression.expr) {
			case TArray(receiver, _): arrayElementSemanticTypeId(receiver.t) != null;
			case _: false;
		};
	}

	static function arrayElementSemanticTypeId(type:Type):Null<String> {
		return switch (TypeTools.follow(type)) {
			case TInst(classRef, [elementType]): final classType = classRef.get(); classType.pack.length == 0 && classType.name == "Array" ? TypeTools.toString(elementType) : null;
			case _:
				null;
		};
	}

	function requireLookupCompleteness():Void {
		final seen:Map<String, Bool> = [];
		for (expression => id in idByExpression) {
			if (seen.exists(id))
				throw 'reflaxe.ocaml [ocaml-array-read:duplicate-lookup]: Array read "$id" is bound to more than one typed expression';
			if (!byId.exists(id))
				throw 'reflaxe.ocaml [ocaml-array-read:missing-decision]: typed Array read "$id" has no sealed decision';
			if (admittedOccurrence(expression) == null)
				throw 'reflaxe.ocaml [ocaml-array-read:invalid-lookup]: Array read "$id" is bound to an unsupported typed expression';
			seen.set(id, true);
		}
		for (decision in ordered)
			if (!seen.exists(decision.id))
				throw 'reflaxe.ocaml [ocaml-array-read:unreachable-decision]: Array read "${decision.id}" has no request-local typed occurrence';
	}

	public static function copyDecision(decision:OcamlArrayReadDecision):OcamlArrayReadDecision {
		return {
			id: decision.id,
			source: {file: decision.source.file, min: decision.source.min, max: decision.source.max},
			readOrdinal: decision.readOrdinal,
			receiverSemanticTypeId: decision.receiverSemanticTypeId,
			elementSemanticTypeId: decision.elementSemanticTypeId,
			indexSemanticTypeId: decision.indexSemanticTypeId,
			resultSemanticTypeId: decision.resultSemanticTypeId,
			evaluationOrder: decision.evaluationOrder.copy(),
			profileEligibility: decision.profileEligibility.copy(),
			runtimeRequirementIds: decision.runtimeRequirementIds.copy(),
			runtimeUseOccurrences: decision.runtimeUseOccurrences.map(use -> {
				id: use.id,
				planRevision: use.planRevision,
				ownerId: use.ownerId,
				requirementId: use.requirementId,
				domain: use.domain,
				exactSymbol: use.exactSymbol,
				role: use.role,
				order: use.order,
				source: {
					file: use.source.file,
					min: use.source.min,
					max: use.source.max
				},
				profileEligibility: use.profileEligibility.copy(),
				cardinality: use.cardinality
			}),
			proofId: decision.proofId,
			proofClaim: decision.proofClaim,
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
	}
}

/** Finds value reads while it excludes assignment and update target roots. */
class OcamlArrayReadPlanner {
	final binding:OcamlFunctionPlanBinding;

	public function new(binding:OcamlFunctionPlanBinding) {
		this.binding = binding;
	}

	/** Builds the complete standard Array read inventory for one typed root. */
	public function plan(root:TypedExpr):OcamlArrayReadPlan {
		final decisions:Array<OcamlArrayReadDecision> = [];
		final idByExpression:ObjectMap<TypedExpr, String> = new ObjectMap();
		var readOrdinal = 0;

		function visit(expression:TypedExpr, admitSelf:Bool):Void {
			if (admitSelf) {
				final occurrence = OcamlArrayReadPlan.admittedOccurrence(expression);
				if (occurrence != null) {
					final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
					final id = OcamlArrayReadContract.idFor(binding, source, readOrdinal++, occurrence.receiverSemanticTypeId,
						occurrence.elementSemanticTypeId);
					final profileEligibility = ["metal", "portable"];
					final decision:OcamlArrayReadDecision = {
						id: id,
						source: source,
						readOrdinal: readOrdinal - 1,
						receiverSemanticTypeId: occurrence.receiverSemanticTypeId,
						elementSemanticTypeId: occurrence.elementSemanticTypeId,
						indexSemanticTypeId: occurrence.indexSemanticTypeId,
						resultSemanticTypeId: occurrence.resultSemanticTypeId,
						evaluationOrder: ["receiver", "index", "runtime-read"],
						profileEligibility: profileEligibility,
						runtimeRequirementIds: [OcamlArrayReadContract.runtimeRequirementId(id)],
						runtimeUseOccurrences: [OcamlArrayReadContract.runtimeUse(binding, id, source, profileEligibility)],
						proofId: OcamlArrayReadContract.PROOF_ID,
						proofClaim: OcamlArrayReadContract.PROOF_CLAIM,
						functionId: binding.functionId,
						programRevision: binding.programRevision,
						bodyRevision: binding.bodyRevision,
						pipelineRevision: binding.pipelineRevision
					};
					OcamlArrayReadContract.requireDecision(decision);
					decisions.push(decision);
					idByExpression.set(expression, id);
				}
			}

			switch (expression.expr) {
				case TFunction(_):
				case TBinop(OpAssign, left, right) | TBinop(OpAssignOp(_), left, right):
					visit(left, false);
					visit(right, true);
				case TUnop(OpIncrement | OpDecrement, _, target):
					visit(target, false);
				case _:
					TypedExprTools.iter(expression, child -> visit(child, true));
			}
		}

		visit(root, true);
		return new OcamlArrayReadPlan(decisions, idByExpression);
	}
}
#end
