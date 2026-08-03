package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.ds.ObjectMap;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerModel.OcamlArrayLiteralElementProducer;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerModel.OcamlArrayLiteralEvaluationStep;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerModel.OcamlArrayLiteralProducerContract;
import reflaxe.ocaml.lowered.OcamlArrayLiteralProducerModel.OcamlArrayLiteralProducerDecision;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlNormalizedRepresentedArray;

/** What syntax planning knows about one typed array-literal occurrence. */
enum OcamlArrayLiteralProducerLookup {
	/** The literal was not present in the typed root used to build this plan. */
	Unknown;

	/** The planner saw the literal but deliberately left its shape unsupported. */
	Excluded;

	/** The literal must consume this exact sealed construction decision. */
	Required(decision:OcamlArrayLiteralProducerDecision);
}

/**
	Owns represented direct-array literal construction for one typed expression root.

	The stable decisions contain only plain values. `decisionIdByExpression` is a
	request-local adapter from the active Haxe typed nodes to those decisions; it
	is discarded with the function plan and must never be used as cache payload.
**/
class OcamlArrayLiteralProducerPlan {
	final ordered:Array<OcamlArrayLiteralProducerDecision>;
	final byId:Map<String, OcamlArrayLiteralProducerDecision> = [];
	final decisionIdByExpression:ObjectMap<TypedExpr, Null<String>>;
	final lookupPrepared:Bool;

	public final revision:String;

	public function new(decisions:Array<OcamlArrayLiteralProducerDecision>, ?decisionIdByExpression:ObjectMap<TypedExpr, Null<String>>) {
		this.decisionIdByExpression = decisionIdByExpression == null ? new ObjectMap() : decisionIdByExpression;
		lookupPrepared = decisionIdByExpression != null;
		final sorted = decisions.map(copyDecision);
		sorted.sort((left, right) -> Reflect.compare(left.id, right.id));
		for (decision in sorted) {
			OcamlArrayLiteralProducerContract.requireDecision(decision);
			if (byId.exists(decision.id))
				throw 'reflaxe.ocaml [ocaml-array-literal:duplicate-producer]: producer "${decision.id}" is sealed more than once';
			byId.set(decision.id, copyDecision(decision));
		}
		ordered = sorted;
		if (lookupPrepared)
			requireLookupCompleteness();
		revision = OcamlArrayLiteralProducerContract.planRevision(ordered);
	}

	/** Returns one typed occurrence's sealed decision, or null when excluded. */
	public function decisionFor(expression:TypedExpr):Null<OcamlArrayLiteralProducerDecision> {
		if (!lookupPrepared || !decisionIdByExpression.exists(expression))
			return null;
		final id = decisionIdByExpression.get(expression);
		if (id == null)
			return null;
		final decision = byId.get(id);
		return decision == null ? null : copyDecision(decision);
	}

	/** Resolves one literal for the syntax phase without reclassifying its type. */
	public function syntaxLookup(expression:TypedExpr):OcamlArrayLiteralProducerLookup {
		if (!lookupPrepared || !decisionIdByExpression.exists(expression))
			return Unknown;
		final id = decisionIdByExpression.get(expression);
		if (id == null)
			return Excluded;
		final decision = byId.get(id);
		if (decision == null)
			throw 'reflaxe.ocaml [ocaml-array-literal:missing-producer]: required occurrence "$id" has no sealed decision';
		return Required(copyDecision(decision));
	}

	/** Rechecks one supported literal and all representation graph edges. */
	public function requireFor(expression:TypedExpr, representations:OcamlRepresentationRegistry):OcamlArrayLiteralProducerDecision {
		if (!isAdmittedLiteral(expression))
			throw "reflaxe.ocaml [ocaml-array-literal:unadmitted-producer]: syntax requested a represented producer for an unsupported array literal";
		return switch (syntaxLookup(expression)) {
			case Required(decision):
				requireRepresentationGraph(decision, representations);
				decision;
			case Excluded:
				throw "reflaxe.ocaml [ocaml-array-literal:missing-producer]: an admitted direct array literal was explicitly excluded from its producer plan";
			case Unknown:
				throw "reflaxe.ocaml [ocaml-array-literal:unknown-occurrence]: an admitted direct array literal was absent from the typed root used to seal its producer plan";
		};
	}

	/** Returns defensive copies in deterministic identity order. */
	public function decisions():Array<OcamlArrayLiteralProducerDecision> {
		return ordered.map(copyDecision);
	}

	/** Rejects a plan retained for another function body or target pipeline. */
	public function requirePlanBinding(binding:OcamlFunctionPlanBinding):Void {
		for (decision in ordered) {
			if (decision.functionId != binding.functionId
				|| decision.programRevision != binding.programRevision
				|| decision.bodyRevision != binding.bodyRevision
				|| decision.pipelineRevision != binding.pipelineRevision) {
				throw 'reflaxe.ocaml [ocaml-array-literal:stale-producer]: producer "${decision.id}" does not belong to ${binding.functionId}/${binding.bodyRevision}/${binding.pipelineRevision}';
			}
		}
	}

	/** Revalidates every producer against the current program-owned registry. */
	public function requireRepresentations(representations:OcamlRepresentationRegistry):Void {
		for (decision in ordered)
			requireRepresentationGraph(decision, representations);
	}

	/** True only for direct flat Int or String literals with already-proved producer families. */
	public static function isAdmittedLiteral(expression:TypedExpr):Bool {
		final normalized = OcamlDirectArraySourceIdentity.normalize(expression.t);
		if (normalized == null)
			return false;
		return switch (expression.expr) {
			case TArrayDecl(items): Lambda.foreach(items, item -> OcamlDirectArraySourceIdentity.matchesElement(item.t, normalized.elementSemanticTypeId));
			case _: false;
		};
	}

	static function requireRepresentationGraph(decision:OcamlArrayLiteralProducerDecision, representations:OcamlRepresentationRegistry):Void {
		OcamlArrayLiteralProducerContract.requireDecision(decision);
		final representation = representations.require(decision.resultRepresentationId, decision.programRevision);
		if (representation.revision != decision.resultRepresentationRevision
			|| representation.semanticTypeId != decision.arraySemanticTypeId
			|| representation.carrierTypeId != decision.arrayCarrierTypeId
			|| representation.domain != OcamlRepresentationDomain.InternalValue
			|| representation.arrayDescriptorId != decision.arrayDescriptorId
			|| representation.arrayDescriptorRevision != decision.arrayDescriptorRevision) {
			throw 'reflaxe.ocaml [ocaml-array-literal:representation-mismatch]: producer "${decision.id}" does not match its represented array result';
		}
		final descriptor = representations.requireRepresentedArray(decision.arrayDescriptorId, decision.arrayDescriptorRevision, decision.programRevision);
		if (descriptor.arraySemanticTypeId != decision.arraySemanticTypeId
			|| descriptor.arrayCarrierTypeId != decision.arrayCarrierTypeId
			|| descriptor.elementSemanticTypeId != decision.elementSemanticTypeId
			|| descriptor.elementCarrierTypeId != decision.elementCarrierTypeId
			|| descriptor.elementRepresentationId != decision.elementRepresentationId
			|| descriptor.elementRepresentationRevision != decision.elementRepresentationRevision) {
			throw 'reflaxe.ocaml [ocaml-array-literal:descriptor-mismatch]: producer "${decision.id}" does not match its represented-array descriptor leaves';
		}
	}

	function requireLookupCompleteness():Void {
		final seen:Map<String, Bool> = [];
		for (expression => id in decisionIdByExpression) {
			if (id == null)
				continue;
			if (seen.exists(id))
				throw 'reflaxe.ocaml [ocaml-array-literal:duplicate-occurrence]: producer "$id" is bound to more than one typed literal';
			if (!byId.exists(id))
				throw 'reflaxe.ocaml [ocaml-array-literal:missing-producer]: required occurrence "$id" has no sealed decision';
			seen.set(id, true);
		}
		for (decision in ordered)
			if (!seen.exists(decision.id))
				throw 'reflaxe.ocaml [ocaml-array-literal:unreachable-producer]: producer "${decision.id}" has no request-local typed occurrence';
	}

	public static function copyDecision(decision:OcamlArrayLiteralProducerDecision):OcamlArrayLiteralProducerDecision {
		return {
			id: decision.id,
			source: {file: decision.source.file, min: decision.source.min, max: decision.source.max},
			literalOrdinal: decision.literalOrdinal,
			arraySemanticTypeId: decision.arraySemanticTypeId,
			arrayCarrierTypeId: decision.arrayCarrierTypeId,
			resultRepresentationId: decision.resultRepresentationId,
			resultRepresentationRevision: decision.resultRepresentationRevision,
			arrayDescriptorId: decision.arrayDescriptorId,
			arrayDescriptorRevision: decision.arrayDescriptorRevision,
			elementSemanticTypeId: decision.elementSemanticTypeId,
			elementCarrierTypeId: decision.elementCarrierTypeId,
			elementRepresentationId: decision.elementRepresentationId,
			elementRepresentationRevision: decision.elementRepresentationRevision,
			elements: decision.elements.map(copyElement),
			evaluationSchedule: decision.evaluationSchedule.map(copyStep),
			constructionPolicy: decision.constructionPolicy,
			proofId: decision.proofId,
			proofClaim: decision.proofClaim,
			profileEligibility: decision.profileEligibility.copy(),
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
	}

	static function copyElement(element:OcamlArrayLiteralElementProducer):OcamlArrayLiteralElementProducer {
		return {
			id: element.id,
			index: element.index,
			source: {file: element.source.file, min: element.source.min, max: element.source.max},
			semanticTypeId: element.semanticTypeId,
			carrierTypeId: element.carrierTypeId,
			representationId: element.representationId,
			representationRevision: element.representationRevision
		};
	}

	static function copyStep(step:OcamlArrayLiteralEvaluationStep):OcamlArrayLiteralEvaluationStep {
		return {
			ordinal: step.ordinal,
			kind: step.kind,
			elementIndex: step.elementIndex,
			elementProducerId: step.elementProducerId
		};
	}
}

/**
	Finds direct represented array literals before control or target syntax runs.

	Nested function bodies are separate ownership roots and are deliberately not
	visited here. Their own revision-bound plan is built when the function-literal
	registry seals that nested body.
**/
class OcamlArrayLiteralProducerPlanner {
	final binding:OcamlFunctionPlanBinding;
	final representations:OcamlRepresentationRegistry;

	public function new(binding:OcamlFunctionPlanBinding, representations:OcamlRepresentationRegistry) {
		this.binding = binding;
		this.representations = representations;
	}

	/** Builds the complete literal inventory for one exact typed root. */
	public function plan(root:TypedExpr):OcamlArrayLiteralProducerPlan {
		final decisions:Array<OcamlArrayLiteralProducerDecision> = [];
		final byExpression:ObjectMap<TypedExpr, Null<String>> = new ObjectMap();
		var literalOrdinal = 0;

		function visit(expression:TypedExpr, insideArrayLiteral:Bool):Void {
			switch (expression.expr) {
				case TFunction(_):
					// A nested function receives a different body revision and binding.
				case TArrayDecl(items):
					final ordinal = literalOrdinal++;
					byExpression.set(expression, null);
					if (!insideArrayLiteral && OcamlArrayLiteralProducerPlan.isAdmittedLiteral(expression)) {
						final decision = decisionFor(expression, items, ordinal);
						decisions.push(decision);
						byExpression.set(expression, decision.id);
					}
					for (item in items)
						visit(item, true);
				case _:
					TypedExprTools.iter(expression, child -> visit(child, insideArrayLiteral));
			}
		}

		visit(root, false);
		return new OcamlArrayLiteralProducerPlan(decisions, byExpression);
	}

	function decisionFor(expression:TypedExpr, items:Array<TypedExpr>, literalOrdinal:Int):OcamlArrayLiteralProducerDecision {
		final normalized = OcamlDirectArraySourceIdentity.normalize(expression.t);
		if (normalized == null)
			throw "reflaxe.ocaml [ocaml-array-literal:unsupported-array-shape]: the active producer accepts only direct flat arrays with a proved literal family";
		return decisionForNormalized(expression, items, literalOrdinal, normalized);
	}

	function decisionForNormalized(expression:TypedExpr, items:Array<TypedExpr>, literalOrdinal:Int,
			normalized:OcamlNormalizedRepresentedArray):OcamlArrayLiteralProducerDecision {
		final resultRepresentation = representations.selectNormalizedRepresentedArray(normalized, OcamlRepresentationDomain.InternalValue);
		if (resultRepresentation.programRevision != binding.programRevision
			|| resultRepresentation.arrayDescriptorId == null
			|| resultRepresentation.arrayDescriptorRevision == null) {
			throw "reflaxe.ocaml [ocaml-array-literal:stale-representation]: literal result does not belong to its function's current represented-array registry";
		}
		final descriptor = representations.requireRepresentedArray(resultRepresentation.arrayDescriptorId, resultRepresentation.arrayDescriptorRevision,
			binding.programRevision);
		final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
		final id = OcamlArrayLiteralProducerContract.idFor(binding, source, literalOrdinal, resultRepresentation.id, resultRepresentation.revision,
			descriptor.id, descriptor.revision);
		final elements:Array<OcamlArrayLiteralElementProducer> = [];
		for (index in 0...items.length) {
			final elementSource = OcamlLoweredOrigin.sourceSpan(items[index].pos);
			elements.push({
				id: OcamlArrayLiteralProducerContract.elementIdFor(id, index, elementSource, descriptor.elementRepresentationId,
					descriptor.elementRepresentationRevision),
				index: index,
				source: elementSource,
				semanticTypeId: descriptor.elementSemanticTypeId,
				carrierTypeId: descriptor.elementCarrierTypeId,
				representationId: descriptor.elementRepresentationId,
				representationRevision: descriptor.elementRepresentationRevision
			});
		}
		return {
			id: id,
			source: source,
			literalOrdinal: literalOrdinal,
			arraySemanticTypeId: descriptor.arraySemanticTypeId,
			arrayCarrierTypeId: descriptor.arrayCarrierTypeId,
			resultRepresentationId: resultRepresentation.id,
			resultRepresentationRevision: resultRepresentation.revision,
			arrayDescriptorId: descriptor.id,
			arrayDescriptorRevision: descriptor.revision,
			elementSemanticTypeId: descriptor.elementSemanticTypeId,
			elementCarrierTypeId: descriptor.elementCarrierTypeId,
			elementRepresentationId: descriptor.elementRepresentationId,
			elementRepresentationRevision: descriptor.elementRepresentationRevision,
			elements: elements,
			evaluationSchedule: OcamlArrayLiteralProducerContract.schedule(elements),
			constructionPolicy: OcamlArrayLiteralProducerContract.CONSTRUCTION_POLICY,
			proofId: OcamlArrayLiteralProducerContract.proofIdFor(descriptor.elementSemanticTypeId),
			proofClaim: OcamlArrayLiteralProducerContract.proofClaimFor(descriptor.elementSemanticTypeId),
			profileEligibility: descriptor.profileEligibility.copy(),
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: binding.bodyRevision,
			pipelineRevision: binding.pipelineRevision
		};
	}
}
#end
