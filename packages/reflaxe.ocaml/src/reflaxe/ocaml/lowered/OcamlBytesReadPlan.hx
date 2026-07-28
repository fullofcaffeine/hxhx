package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.macro.Type;
import haxe.macro.Type.ClassField;
import haxe.macro.Type.ClassType;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.lowered.OcamlBytesProducerModel.OcamlBytesEncodingKind;
import reflaxe.ocaml.lowered.OcamlBytesReadModel.OcamlBytesReadContract;
import reflaxe.ocaml.lowered.OcamlBytesReadModel.OcamlBytesReadDecision;
import reflaxe.ocaml.lowered.OcamlBytesReadModel.OcamlBytesReadKind;
import reflaxe.ocaml.lowered.OcamlBytesReadModel.OcamlBytesReadResultKind;
import reflaxe.ocaml.lowered.OcamlBytesRepresentationModel.OcamlBytesRepresentationContract;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallPlanner;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDecision;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;

typedef OcamlBytesReadOccurrence = {
	final kind:OcamlBytesReadKind;
	final classType:ClassType;
	final field:ClassField;
	final receiver:TypedExpr;
	final arguments:Array<TypedExpr>;
	final encoding:OcamlBytesEncodingKind;
}

private typedef OcamlBytesReadArgumentRepresentation = {
	final semanticTypeId:String;
	final carrierTypeId:String;
	final representationId:String;
	final representationRevision:String;
	final runtimeUse:Bool;
}

/**
	Immutable inventory of exact read-only Bytes operations in one typed root.

	Lookups use the normalized source span plus the exact typed declaration,
	arity, and encoding shape. This lets syntax consume one sealed occurrence
	without using generated names as semantic authority.
**/
class OcamlBytesReadPlan {
	final ordered:Array<OcamlBytesReadDecision>;
	final bySourceKey:Map<String, Array<OcamlBytesReadDecision>> = [];

	public final revision:String;

	public function new(decisions:Array<OcamlBytesReadDecision>) {
		final sorted = decisions.map(copyDecision);
		sorted.sort((left, right) -> Reflect.compare(left.id, right.id));
		final normalized:Array<OcamlBytesReadDecision> = [];
		for (decision in sorted) {
			OcamlBytesReadContract.requireDecision(decision);
			final key = sourceKey(decision.source);
			final candidates = bySourceKey.get(key) ?? [];
			final duplicate = Lambda.find(candidates,
				existing -> existing.kind == decision.kind
					&& existing.calleeId == decision.calleeId
					&& existing.argumentCount == decision.argumentCount
					&& existing.encoding == decision.encoding);
			if (duplicate != null) {
				if (fingerprint(duplicate) != fingerprint(decision))
					throw 'reflaxe.ocaml [ocaml-bytes:conflicting-read]: Bytes read identity "${decision.id}" selects different facts';
				throw 'reflaxe.ocaml [ocaml-bytes:duplicate-read]: more than one Bytes read can match ${decision.calleeId} at "$key"';
			}
			candidates.push(copyDecision(decision));
			bySourceKey.set(key, candidates);
			normalized.push(copyDecision(decision));
		}
		ordered = normalized;
		revision = "sha256:" + Sha256.encode(ordered.map(fingerprint).join("\n"));
	}

	/** Returns the sealed decision for one exact typed read occurrence. */
	public function decisionFor(expression:TypedExpr):Null<OcamlBytesReadDecision> {
		final candidates = bySourceKey.get(sourceKey(OcamlLoweredOrigin.sourceSpan(expression.pos))) ?? [];
		final matching = candidates.filter(decision -> matchesTypedOccurrence(decision, expression));
		if (matching.length > 1)
			throw 'reflaxe.ocaml [ocaml-bytes:ambiguous-read]: ${matching.length} sealed Bytes reads match one typed occurrence';
		return matching.length == 0 ? null : copyDecision(matching[0]);
	}

	/** Requires syntax to consume exactly one sealed read decision. */
	public function requireFor(expression:TypedExpr, representations:OcamlRepresentationRegistry):OcamlBytesReadDecision {
		final expected = admittedOccurrence(expression);
		if (expected == null)
			throw "reflaxe.ocaml [ocaml-bytes:unadmitted-read]: syntax requested a Bytes read outside the sealed family";
		final decision = decisionFor(expression);
		if (decision == null)
			throw 'reflaxe.ocaml [ocaml-bytes:missing-read]: admitted Bytes read ${expected.kind} reached syntax without its sealed decision';
		OcamlBytesReadContract.requireDecision(decision);
		requireRepresentationsForDecision(decision, representations);
		return decision;
	}

	/** Revalidates every receiver, argument, and result representation. */
	public function requireRepresentations(representations:OcamlRepresentationRegistry):Void {
		for (decision in ordered)
			requireRepresentationsForDecision(decision, representations);
	}

	/** Returns all read decisions in deterministic identity order. */
	public function decisions():Array<OcamlBytesReadDecision> {
		return ordered.map(copyDecision);
	}

	/** Verifies that every decision belongs to the enclosing typed-root seal. */
	public function requirePlanBinding(binding:OcamlFunctionPlanBinding):Void {
		for (decision in ordered) {
			if (decision.functionId != binding.functionId
				|| decision.programRevision != binding.programRevision
				|| decision.bodyRevision != binding.bodyRevision
				|| decision.pipelineRevision != binding.pipelineRevision) {
				throw 'reflaxe.ocaml [ocaml-bytes:stale-read]: read "${decision.id}" does not belong to ${binding.functionId}/${binding.bodyRevision}/${binding.pipelineRevision}';
			}
		}
	}

	/** Classifies one admitted read kind, or returns null. */
	public static function admittedKind(expression:TypedExpr):Null<OcamlBytesReadKind> {
		final occurrence = admittedOccurrence(expression);
		return occurrence == null ? null : occurrence.kind;
	}

	/** Returns the exact typed receiver and arguments for an admitted read. */
	public static function admittedOccurrence(expression:TypedExpr):Null<OcamlBytesReadOccurrence> {
		return switch (expression.expr) {
			case TField(receiver, FInstance(classRef, _, fieldRef)):
				final classType = classRef.get();
				final field = fieldRef.get();
				if (!OcamlBytesProducerPlan.isBytesClass(classType)
					|| !OcamlRepresentationRegistry.isExactBytes(receiver.t)
					|| field.name != "length"
					|| !OcamlRepresentationRegistry.isExactInt(expression.t)) {
					null;
				} else {
					{
						kind: OcamlBytesReadKind.Length,
						classType: classType,
						field: field,
						receiver: receiver,
						arguments: [],
						encoding: OcamlBytesEncodingKind.NotApplicable
					};
				}
			case TCall({expr: TField(receiver, FInstance(classRef, _, fieldRef))}, arguments):
				final classType = classRef.get();
				final field = fieldRef.get();
				if (!OcamlBytesProducerPlan.isBytesClass(classType) || !OcamlRepresentationRegistry.isExactBytes(receiver.t)) {
					null;
				} else {
					final classified = instanceKind(field.name, arguments, expression.t);
					classified == null ? null : {
						kind: classified.kind,
						classType: classType,
						field: field,
						receiver: receiver,
						arguments: arguments,
						encoding: classified.encoding
					};
				}
			case _:
				null;
		}
	}

	static function instanceKind(fieldName:String, arguments:Array<TypedExpr>, resultType:Type):Null<{
		kind:OcamlBytesReadKind,
		encoding:OcamlBytesEncodingKind
	}> {
		final notApplicable = OcamlBytesEncodingKind.NotApplicable;
		return switch (fieldName) {
			case "sub"
				if (matchesExactArguments(arguments, [OcamlRepresentationRegistry.isExactInt, OcamlRepresentationRegistry.isExactInt])
					&& OcamlRepresentationRegistry.isExactBytes(resultType)):
				{kind: OcamlBytesReadKind.Sub, encoding: notApplicable};
			case "compare"
				if (matchesExactArguments(arguments, [OcamlRepresentationRegistry.isExactBytes])
					&& OcamlRepresentationRegistry.isExactInt(resultType)):
				{kind: OcamlBytesReadKind.Compare, encoding: notApplicable};
			case "getString"
				if (arguments.length == 2
					&& OcamlRepresentationRegistry.isExactInt(arguments[0].t)
					&& OcamlRepresentationRegistry.isExactInt(arguments[1].t)
					&& OcamlRepresentationRegistry.isExactString(resultType)):
				{kind: OcamlBytesReadKind.GetString, encoding: OcamlBytesEncodingKind.Omitted};
			case "getString"
				if (arguments.length == 3
					&& OcamlRepresentationRegistry.isExactInt(arguments[0].t)
					&& OcamlRepresentationRegistry.isExactInt(arguments[1].t)
					&& OcamlBytesProducerPlan.encodingKindForExpression(arguments[2]) != null
					&& OcamlRepresentationRegistry.isExactString(resultType)):
				{kind: OcamlBytesReadKind.GetString, encoding: OcamlBytesProducerPlan.encodingKindForExpression(arguments[2])};
			case "toString" if (arguments.length == 0 && OcamlRepresentationRegistry.isExactString(resultType)):
				{kind: OcamlBytesReadKind.ToString, encoding: notApplicable};
			case "toHex" if (arguments.length == 0 && OcamlRepresentationRegistry.isExactString(resultType)):
				{kind: OcamlBytesReadKind.ToHex, encoding: notApplicable};
			case _:
				null;
		}
	}

	static function matchesExactArguments(arguments:Array<TypedExpr>, predicates:Array<Type->Bool>):Bool {
		if (arguments.length != predicates.length)
			return false;
		for (index in 0...arguments.length)
			if (!predicates[index](arguments[index].t))
				return false;
		return true;
	}

	static function matchesTypedOccurrence(decision:OcamlBytesReadDecision, expression:TypedExpr):Bool {
		final occurrence = admittedOccurrence(expression);
		return occurrence != null
			&& occurrence.kind == decision.kind
			&& occurrence.arguments.length == decision.argumentCount
			&& occurrence.encoding == decision.encoding
			&& OcamlCallPlanner.calleeId(occurrence.classType, occurrence.field) == decision.calleeId;
	}

	static function sourceKey(source:OcamlLoweredSourceSpan):String {
		return source.file + ":" + source.min + ":" + source.max;
	}

	static function fingerprint(decision:OcamlBytesReadDecision):String {
		return [
			decision.id,
			decision.source.file,
			Std.string(decision.source.min),
			Std.string(decision.source.max),
			(decision.kind : String),
			decision.calleeId,
			decision.sourceModuleId,
			decision.sourceTypeName,
			decision.sourceFieldName,
			Std.string(decision.hasReceiver),
			decision.receiverSemanticTypeId,
			decision.receiverCarrierTypeId,
			decision.receiverRepresentationId,
			decision.receiverRepresentationRevision,
			Std.string(decision.argumentCount),
			decision.evaluationOrder.join(","),
			decision.argumentSemanticTypeIds.join(","),
			decision.argumentCarrierTypeIds.join(","),
			decision.argumentRepresentationIds.join(","),
			decision.argumentRepresentationRevisions.join(","),
			decision.argumentRuntimeUse.map(value -> Std.string(value)).join(","),
			(decision.encoding : String),
			(decision.resultKind : String),
			decision.resultSemanticTypeId,
			decision.resultCarrierTypeId,
			decision.resultRepresentationId,
			decision.resultRepresentationRevision,
			decision.resultNullability,
			decision.runtimeRequirementIds.join(","),
			decision.proofId,
			decision.proofClaim,
			decision.functionId,
			decision.programRevision,
			decision.bodyRevision,
			decision.pipelineRevision
		].join("|");
	}

	static function copyDecision(decision:OcamlBytesReadDecision):OcamlBytesReadDecision {
		return {
			id: decision.id,
			source: {file: decision.source.file, min: decision.source.min, max: decision.source.max},
			kind: decision.kind,
			calleeId: decision.calleeId,
			sourceModuleId: decision.sourceModuleId,
			sourceTypeName: decision.sourceTypeName,
			sourceFieldName: decision.sourceFieldName,
			hasReceiver: decision.hasReceiver,
			receiverSemanticTypeId: decision.receiverSemanticTypeId,
			receiverCarrierTypeId: decision.receiverCarrierTypeId,
			receiverRepresentationId: decision.receiverRepresentationId,
			receiverRepresentationRevision: decision.receiverRepresentationRevision,
			argumentCount: decision.argumentCount,
			evaluationOrder: decision.evaluationOrder.copy(),
			argumentSemanticTypeIds: decision.argumentSemanticTypeIds.copy(),
			argumentCarrierTypeIds: decision.argumentCarrierTypeIds.copy(),
			argumentRepresentationIds: decision.argumentRepresentationIds.copy(),
			argumentRepresentationRevisions: decision.argumentRepresentationRevisions.copy(),
			argumentRuntimeUse: decision.argumentRuntimeUse.copy(),
			encoding: decision.encoding,
			resultKind: decision.resultKind,
			resultSemanticTypeId: decision.resultSemanticTypeId,
			resultCarrierTypeId: decision.resultCarrierTypeId,
			resultRepresentationId: decision.resultRepresentationId,
			resultRepresentationRevision: decision.resultRepresentationRevision,
			resultNullability: decision.resultNullability,
			runtimeRequirementIds: decision.runtimeRequirementIds.copy(),
			proofId: decision.proofId,
			proofClaim: decision.proofClaim,
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
	}

	static function requireRepresentationsForDecision(decision:OcamlBytesReadDecision, representations:OcamlRepresentationRegistry):Void {
		if (decision.hasReceiver)
			representations.requireExactBytesInternal(decision.receiverRepresentationId, decision.receiverRepresentationRevision, decision.programRevision);
		for (index in 0...decision.argumentCount) {
			if (!decision.argumentRuntimeUse[index])
				continue;
			requireRepresentationReference(decision.argumentSemanticTypeIds[index], decision.argumentCarrierTypeIds[index],
				decision.argumentRepresentationIds[index], decision.argumentRepresentationRevisions[index], decision.programRevision, representations,
				'read "${decision.id}" argument $index');
		}
		requireRepresentationReference(decision.resultSemanticTypeId, decision.resultCarrierTypeId, decision.resultRepresentationId,
			decision.resultRepresentationRevision, decision.programRevision, representations, 'read "${decision.id}" result');
	}

	static function requireRepresentationReference(semanticTypeId:String, carrierTypeId:String, representationId:String, representationRevision:String,
			programRevision:String, representations:OcamlRepresentationRegistry, owner:String):Void {
		final represented = if (semanticTypeId == OcamlBytesRepresentationContract.DIRECT_SEMANTIC_TYPE_ID) {
			representations.requireExactBytesInternal(representationId, representationRevision, programRevision);
		} else {
			representations.require(representationId, programRevision);
		}
		if (represented.revision != representationRevision
			|| represented.semanticTypeId != semanticTypeId
			|| represented.carrierTypeId != carrierTypeId
			|| represented.domain != OcamlRepresentationDomain.InternalValue) {
			throw 'reflaxe.ocaml [ocaml-bytes:read-representation-mismatch]: $owner no longer matches $representationId@$representationRevision';
		}
	}
}

/**
	Finds exact read-only Bytes operations in one final typed expression root.

	The planner does not admit writes, inline-expanded storage reads, indexing,
	Float or Int64 results, nullable materialization, or user-defined lookalikes.
	Those families require separate representation or place-operation decisions.
**/
class OcamlBytesReadPlanner {
	final binding:OcamlFunctionPlanBinding;
	final representations:OcamlRepresentationRegistry;

	public function new(binding:OcamlFunctionPlanBinding, representations:OcamlRepresentationRegistry) {
		this.binding = binding;
		this.representations = representations;
	}

	/** Builds the complete read inventory for one final typed expression root. */
	public function plan(root:TypedExpr):OcamlBytesReadPlan {
		final decisions:Array<OcamlBytesReadDecision> = [];
		function visit(expression:TypedExpr):Void {
			final decision = decisionFor(expression);
			if (decision != null)
				decisions.push(decision);
			TypedExprTools.iter(expression, visit);
		}
		visit(root);
		return new OcamlBytesReadPlan(decisions);
	}

	function decisionFor(expression:TypedExpr):Null<OcamlBytesReadDecision> {
		final occurrence = OcamlBytesReadPlan.admittedOccurrence(expression);
		if (occurrence == null)
			return null;
		final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
		final receiverRepresentation = representations.selectExactBytes(OcamlRepresentationDomain.InternalValue);
		final argumentRepresentations = [
			for (index in 0...occurrence.arguments.length)
				argumentRepresentation(occurrence, index)
		];
		final resultRepresentation = resultRepresentation(occurrence.kind);
		final evaluationOrder = [-1].concat([for (index in 0...occurrence.arguments.length) index]);
		final provisional:OcamlBytesReadDecision = {
			id: "",
			source: source,
			kind: occurrence.kind,
			calleeId: OcamlCallPlanner.calleeId(occurrence.classType, occurrence.field),
			sourceModuleId: occurrence.classType.module,
			sourceTypeName: occurrence.classType.name,
			sourceFieldName: occurrence.field.name,
			hasReceiver: true,
			receiverSemanticTypeId: receiverRepresentation.semanticTypeId,
			receiverCarrierTypeId: receiverRepresentation.carrierTypeId,
			receiverRepresentationId: receiverRepresentation.id,
			receiverRepresentationRevision: receiverRepresentation.revision,
			argumentCount: occurrence.arguments.length,
			evaluationOrder: evaluationOrder,
			argumentSemanticTypeIds: argumentRepresentations.map(value -> value.semanticTypeId),
			argumentCarrierTypeIds: argumentRepresentations.map(value -> value.carrierTypeId),
			argumentRepresentationIds: argumentRepresentations.map(value -> value.representationId),
			argumentRepresentationRevisions: argumentRepresentations.map(value -> value.representationRevision),
			argumentRuntimeUse: argumentRepresentations.map(value -> value.runtimeUse),
			encoding: occurrence.encoding,
			resultKind: OcamlBytesReadContract.resultKind(occurrence.kind),
			resultSemanticTypeId: resultRepresentation.semanticTypeId,
			resultCarrierTypeId: resultRepresentation.carrierTypeId,
			resultRepresentationId: resultRepresentation.id,
			resultRepresentationRevision: resultRepresentation.revision,
			resultNullability: OcamlBytesReadContract.RESULT_NULLABILITY,
			runtimeRequirementIds: [],
			proofId: OcamlBytesReadContract.PROOF_ID,
			proofClaim: OcamlBytesReadContract.PROOF_CLAIM,
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: binding.bodyRevision,
			pipelineRevision: binding.pipelineRevision
		};
		final id = OcamlBytesReadContract.idFor(provisional);
		final decision = copyWithIdentity(provisional, id);
		OcamlBytesReadContract.requireDecision(decision);
		return decision;
	}

	function argumentRepresentation(occurrence:OcamlBytesReadOccurrence, index:Int):OcamlBytesReadArgumentRepresentation {
		if (occurrence.kind == OcamlBytesReadKind.GetString && index == 2) {
			return {
				semanticTypeId: "haxe.io.Encoding",
				carrierTypeId: OcamlBytesReadContract.COMPILE_TIME_ENCODING_CARRIER,
				representationId: "",
				representationRevision: "",
				runtimeUse: false
			};
		}
		final type = occurrence.arguments[index].t;
		final represented = if (OcamlRepresentationRegistry.isExactInt(type)) {
			representations.selectExactInt(OcamlRepresentationDomain.InternalValue);
		} else if (OcamlRepresentationRegistry.isExactBytes(type)) {
			representations.selectExactBytes(OcamlRepresentationDomain.InternalValue);
		} else {
			throw 'reflaxe.ocaml [ocaml-bytes:unsupported-read-argument]: admitted ${occurrence.kind} argument $index has no exact representation';
		}
		return representationArgument(represented);
	}

	function resultRepresentation(kind:OcamlBytesReadKind):OcamlRepresentationDecision {
		return switch (OcamlBytesReadContract.resultKind(kind)) {
			case IntValue: representations.selectExactInt(OcamlRepresentationDomain.InternalValue);
			case StringValue: representations.selectExactString(OcamlRepresentationDomain.InternalValue);
			case BytesValue: representations.selectExactBytes(OcamlRepresentationDomain.InternalValue);
		}
	}

	static function representationArgument(represented:OcamlRepresentationDecision):OcamlBytesReadArgumentRepresentation {
		return {
			semanticTypeId: represented.semanticTypeId,
			carrierTypeId: represented.carrierTypeId,
			representationId: represented.id,
			representationRevision: represented.revision,
			runtimeUse: true
		};
	}

	static function copyWithIdentity(decision:OcamlBytesReadDecision, id:String):OcamlBytesReadDecision {
		final runtimeRequirementId = id + ":runtime:" + OcamlBytesReadContract.RUNTIME_CAPABILITY;
		return {
			id: id,
			source: decision.source,
			kind: decision.kind,
			calleeId: decision.calleeId,
			sourceModuleId: decision.sourceModuleId,
			sourceTypeName: decision.sourceTypeName,
			sourceFieldName: decision.sourceFieldName,
			hasReceiver: decision.hasReceiver,
			receiverSemanticTypeId: decision.receiverSemanticTypeId,
			receiverCarrierTypeId: decision.receiverCarrierTypeId,
			receiverRepresentationId: decision.receiverRepresentationId,
			receiverRepresentationRevision: decision.receiverRepresentationRevision,
			argumentCount: decision.argumentCount,
			evaluationOrder: decision.evaluationOrder,
			argumentSemanticTypeIds: decision.argumentSemanticTypeIds,
			argumentCarrierTypeIds: decision.argumentCarrierTypeIds,
			argumentRepresentationIds: decision.argumentRepresentationIds,
			argumentRepresentationRevisions: decision.argumentRepresentationRevisions,
			argumentRuntimeUse: decision.argumentRuntimeUse,
			encoding: decision.encoding,
			resultKind: decision.resultKind,
			resultSemanticTypeId: decision.resultSemanticTypeId,
			resultCarrierTypeId: decision.resultCarrierTypeId,
			resultRepresentationId: decision.resultRepresentationId,
			resultRepresentationRevision: decision.resultRepresentationRevision,
			resultNullability: decision.resultNullability,
			runtimeRequirementIds: [runtimeRequirementId],
			proofId: decision.proofId,
			proofClaim: decision.proofClaim,
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
	}
}
#end
