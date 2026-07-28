package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.ds.ObjectMap;
import haxe.macro.Type;
import haxe.macro.Type.ClassField;
import haxe.macro.Type.ClassType;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessArgumentConversion;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessContract;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessDecision;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessInvocationKind;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessKind;
import reflaxe.ocaml.lowered.OcamlBytesAccessModel.OcamlBytesAccessResultKind;
import reflaxe.ocaml.lowered.OcamlBytesRepresentationModel.OcamlBytesRepresentationContract;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallPlanner;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDecision;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;

typedef OcamlBytesAccessOccurrence = {
	final kind:OcamlBytesAccessKind;
	final classType:ClassType;
	final field:ClassField;
	final receiver:Null<TypedExpr>;
	final arguments:Array<TypedExpr>;
}

typedef OcamlBytesAccessDecisionOccurrence = {
	final expression:TypedExpr;
	final occurrenceId:String;
	final decisionId:String;
}

/**
	Immutable inventory of exact byte access and BytesData alias operations.

	Each occurrence is tied to the target-selected `haxe.io.Bytes` declaration
	and exact carrier decisions. Production plans also retain an exact typed-node
	index because inlining can produce distinct calls with the same source span.
	Syntax cannot rediscover access, mutation, bounds, result, or alias behavior
	from names.
**/
class OcamlBytesAccessPlan {
	final ordered:Array<OcamlBytesAccessDecision>;
	final bySourceKey:Map<String, Array<OcamlBytesAccessDecision>> = [];
	final decisionsById:Map<String, OcamlBytesAccessDecision> = [];
	final decisionIdByExpression:ObjectMap<TypedExpr, String> = new ObjectMap();
	final hasOccurrenceIndex:Bool;

	public final revision:String;

	public function new(decisions:Array<OcamlBytesAccessDecision>, ?occurrences:Array<OcamlBytesAccessDecisionOccurrence>) {
		hasOccurrenceIndex = occurrences != null;
		final sorted = decisions.map(copyDecision);
		sorted.sort((left, right) -> Reflect.compare(left.id, right.id));
		final normalized:Array<OcamlBytesAccessDecision> = [];
		for (decision in sorted) {
			OcamlBytesAccessContract.requireDecision(decision);
			final existingById = decisionsById.get(decision.id);
			if (existingById != null) {
				if (fingerprint(existingById) != fingerprint(decision))
					throw 'reflaxe.ocaml [ocaml-bytes:conflicting-access]: Bytes access identity "${decision.id}" selects different facts';
				throw 'reflaxe.ocaml [ocaml-bytes:duplicate-access]: Bytes access identity "${decision.id}" appears more than once';
			}
			final key = sourceKey(decision.source);
			final candidates = bySourceKey.get(key) ?? [];
			if (!hasOccurrenceIndex) {
				final duplicate = Lambda.find(candidates,
					existing -> existing.kind == decision.kind
						&& existing.calleeId == decision.calleeId
						&& existing.argumentCount == decision.argumentCount);
				if (duplicate != null)
					throw 'reflaxe.ocaml [ocaml-bytes:conflicting-access]: more than one Bytes access can match ${decision.calleeId} at "$key" without an exact occurrence index';
			}
			candidates.push(copyDecision(decision));
			bySourceKey.set(key, candidates);
			decisionsById.set(decision.id, copyDecision(decision));
			normalized.push(copyDecision(decision));
		}
		final indexedDecisionIds:Map<String, Bool> = [];
		for (occurrence in occurrences ?? []) {
			if (occurrence.occurrenceId.length == 0)
				throw "reflaxe.ocaml [ocaml-bytes:invalid-access-occurrence]: Bytes access occurrence identity is empty";
			final decision = decisionsById.get(occurrence.decisionId);
			if (decision == null)
				throw 'reflaxe.ocaml [ocaml-bytes:missing-access-occurrence]: typed access occurrence refers to missing decision "${occurrence.decisionId}"';
			if (decision.occurrenceId != occurrence.occurrenceId)
				throw 'reflaxe.ocaml [ocaml-bytes:stale-access-occurrence]: typed access occurrence "${occurrence.occurrenceId}" does not match decision "${decision.id}"';
			if (indexedDecisionIds.exists(decision.id))
				throw 'reflaxe.ocaml [ocaml-bytes:duplicate-access-occurrence]: decision "${decision.id}" is indexed by more than one typed occurrence';
			if (decisionIdByExpression.exists(occurrence.expression))
				throw "reflaxe.ocaml [ocaml-bytes:ambiguous-access-occurrence]: one typed node refers to more than one Bytes access decision";
			decisionIdByExpression.set(occurrence.expression, decision.id);
			indexedDecisionIds.set(decision.id, true);
		}
		if (hasOccurrenceIndex) {
			for (decision in normalized)
				if (!indexedDecisionIds.exists(decision.id))
					throw 'reflaxe.ocaml [ocaml-bytes:missing-access-occurrence]: decision "${decision.id}" has no exact typed occurrence';
		}
		ordered = normalized;
		revision = "sha256:" + Sha256.encode(ordered.map(fingerprint).join("\n"));
	}

	/** Returns the sealed decision for one exact typed access occurrence. */
	public function decisionFor(expression:TypedExpr):Null<OcamlBytesAccessDecision> {
		if (hasOccurrenceIndex) {
			final decisionId = decisionIdByExpression.get(expression);
			if (decisionId == null)
				return null;
			final decision = decisionsById.get(decisionId);
			if (decision == null)
				throw 'reflaxe.ocaml [ocaml-bytes:missing-access]: typed access occurrence refers to missing decision "$decisionId"';
			if (!matchesTypedOccurrence(decision, expression))
				throw 'reflaxe.ocaml [ocaml-bytes:stale-access]: decision "$decisionId" no longer matches its exact typed occurrence';
			return copyDecision(decision);
		}
		final candidates = bySourceKey.get(sourceKey(OcamlLoweredOrigin.sourceSpan(expression.pos))) ?? [];
		final matching = candidates.filter(decision -> matchesTypedOccurrence(decision, expression));
		if (matching.length > 1)
			throw 'reflaxe.ocaml [ocaml-bytes:ambiguous-access]: ${matching.length} sealed Bytes accesses match one typed occurrence';
		return matching.length == 0 ? null : copyDecision(matching[0]);
	}

	/** Requires syntax to consume exactly one sealed access decision. */
	public function requireFor(expression:TypedExpr, representations:OcamlRepresentationRegistry):OcamlBytesAccessDecision {
		final expected = admittedOccurrence(expression);
		if (expected == null)
			throw "reflaxe.ocaml [ocaml-bytes:unadmitted-access]: syntax requested a Bytes access outside the sealed family";
		final decision = decisionFor(expression);
		if (decision == null)
			throw 'reflaxe.ocaml [ocaml-bytes:missing-access]: admitted Bytes access ${expected.kind} reached syntax without its sealed decision';
		OcamlBytesAccessContract.requireDecision(decision);
		requireRepresentationsForDecision(decision, representations);
		return decision;
	}

	/** Revalidates every receiver, argument, and result representation. */
	public function requireRepresentations(representations:OcamlRepresentationRegistry):Void {
		for (decision in ordered)
			requireRepresentationsForDecision(decision, representations);
	}

	public function decisions():Array<OcamlBytesAccessDecision> {
		return ordered.map(copyDecision);
	}

	public function requirePlanBinding(binding:OcamlFunctionPlanBinding):Void {
		for (decision in ordered) {
			if (decision.functionId != binding.functionId
				|| decision.programRevision != binding.programRevision
				|| decision.bodyRevision != binding.bodyRevision
				|| decision.pipelineRevision != binding.pipelineRevision) {
				throw 'reflaxe.ocaml [ocaml-bytes:stale-access]: access "${decision.id}" does not belong to ${binding.functionId}/${binding.bodyRevision}/${binding.pipelineRevision}';
			}
		}
	}

	/** Classifies one exact target-selected Bytes access call. */
	public static function admittedOccurrence(expression:TypedExpr):Null<OcamlBytesAccessOccurrence> {
		return switch (expression.expr) {
			case TCall({expr: TField(receiver, FInstance(classRef, _, fieldRef))}, arguments):
				final classType = classRef.get();
				final field = fieldRef.get();
				if (!OcamlBytesProducerPlan.isBytesClass(classType) || !OcamlRepresentationRegistry.isExactBytes(receiver.t)) {
					null;
				} else {
					final kind = instanceKind(field.name, arguments, expression.t);
					kind == null ? null : {
						kind: kind,
						classType: classType,
						field: field,
						receiver: receiver,
						arguments: arguments
					};
				}
			case TCall({expr: TField(_, FStatic(classRef, fieldRef))}, arguments):
				final classType = classRef.get();
				final field = fieldRef.get();
				if (!OcamlBytesProducerPlan.isBytesClass(classType)
					|| field.name != "fastGet"
					|| arguments.length != 2
					|| !OcamlRepresentationRegistry.isExactBytesData(arguments[0].t)
					|| !isAdmittedIntInput(arguments[1].t)
					|| !OcamlRepresentationRegistry.isExactInt(expression.t)) {
					null;
				} else {
					{
						kind: OcamlBytesAccessKind.FastGet,
						classType: classType,
						field: field,
						receiver: null,
						arguments: arguments
					};
				}
			case _:
				null;
		}
	}

	static function instanceKind(fieldName:String, arguments:Array<TypedExpr>, resultType:Type):Null<OcamlBytesAccessKind> {
		return switch (fieldName) {
			case "get" if (matchesExactArguments(arguments, [isAdmittedIntInput]) && OcamlRepresentationRegistry.isExactInt(resultType)):
				OcamlBytesAccessKind.Get;
			case "set" if (matchesExactArguments(arguments, [isAdmittedIntInput, isAdmittedIntInput]) && isExactVoid(resultType)):
				OcamlBytesAccessKind.Set;
			case "getUInt16" if (matchesExactArguments(arguments, [isExactIntInput])
				&& OcamlRepresentationRegistry.isExactInt(resultType)):
				OcamlBytesAccessKind.GetUInt16;
			case "setUInt16" if (matchesExactArguments(arguments, [isExactIntInput, isExactIntInput]) && isExactVoid(resultType)):
				OcamlBytesAccessKind.SetUInt16;
			case "getInt32" if (matchesExactArguments(arguments, [isExactIntInput]) && OcamlRepresentationRegistry.isExactInt(resultType)):
				OcamlBytesAccessKind.GetInt32;
			case "setInt32" if (matchesExactArguments(arguments, [isExactIntInput, isExactIntInput]) && isExactVoid(resultType)):
				OcamlBytesAccessKind.SetInt32;
			case "getData" if (arguments.length == 0 && OcamlRepresentationRegistry.isExactBytesData(resultType)):
				OcamlBytesAccessKind.GetData;
			case _:
				null;
		}
	}

	static function isAdmittedIntInput(type:Type):Bool {
		return OcamlRepresentationRegistry.isExactInt(type) || OcamlRepresentationRegistry.isExactNullInt(type);
	}

	static function isExactIntInput(type:Type):Bool {
		return OcamlRepresentationRegistry.isExactInt(type);
	}

	static function matchesExactArguments(arguments:Array<TypedExpr>, predicates:Array<Type->Bool>):Bool {
		if (arguments.length != predicates.length)
			return false;
		for (index in 0...arguments.length)
			if (!predicates[index](arguments[index].t))
				return false;
		return true;
	}

	static function isExactVoid(type:Type):Bool {
		return switch (TypeTools.follow(type)) {
			case TAbstract(abstractRef, _): final abstractType = abstractRef.get(); abstractType.pack.length == 0 && abstractType.name == "Void";
			case _:
				false;
		}
	}

	static function matchesTypedOccurrence(decision:OcamlBytesAccessDecision, expression:TypedExpr):Bool {
		final occurrence = admittedOccurrence(expression);
		return occurrence != null
			&& occurrence.kind == decision.kind
			&& occurrence.arguments.length == decision.argumentCount
			&& OcamlCallPlanner.calleeId(occurrence.classType, occurrence.field) == decision.calleeId;
	}

	static function sourceKey(source:OcamlLoweredSourceSpan):String {
		return source.file + ":" + source.min + ":" + source.max;
	}

	static function fingerprint(decision:OcamlBytesAccessDecision):String {
		return [
			decision.id,
			decision.occurrenceId,
			decision.source.file,
			Std.string(decision.source.min),
			Std.string(decision.source.max),
			(decision.kind : String),
			(decision.invocationKind : String),
			decision.calleeId,
			decision.sourceModuleId,
			decision.sourceTypeName,
			decision.sourceFieldName,
			decision.receiverSemanticTypeId,
			decision.receiverCarrierTypeId,
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
			Std.string(decision.accessWidthBytes),
			(decision.byteOrderPolicy : String),
			(decision.valuePolicy : String),
			(decision.mutationPolicy : String),
			(decision.aliasPolicy : String),
			(decision.resultKind : String),
			decision.resultSemanticTypeId,
			decision.resultCarrierTypeId,
			decision.resultRepresentationId,
			decision.resultRepresentationRevision,
			decision.runtimeOperation,
			decision.runtimeRequirementIds.join(","),
			decision.proofId,
			decision.proofClaim,
			decision.functionId,
			decision.programRevision,
			decision.bodyRevision,
			decision.pipelineRevision
		].join("|");
	}

	static function copyDecision(decision:OcamlBytesAccessDecision):OcamlBytesAccessDecision {
		return {
			id: decision.id,
			occurrenceId: decision.occurrenceId,
			source: {file: decision.source.file, min: decision.source.min, max: decision.source.max},
			kind: decision.kind,
			invocationKind: decision.invocationKind,
			calleeId: decision.calleeId,
			sourceModuleId: decision.sourceModuleId,
			sourceTypeName: decision.sourceTypeName,
			sourceFieldName: decision.sourceFieldName,
			receiverSemanticTypeId: decision.receiverSemanticTypeId,
			receiverCarrierTypeId: decision.receiverCarrierTypeId,
			receiverRepresentationId: decision.receiverRepresentationId,
			receiverRepresentationRevision: decision.receiverRepresentationRevision,
			argumentCount: decision.argumentCount,
			evaluationOrder: decision.evaluationOrder.copy(),
			argumentInputSemanticTypeIds: decision.argumentInputSemanticTypeIds.copy(),
			argumentInputCarrierTypeIds: decision.argumentInputCarrierTypeIds.copy(),
			argumentInputRepresentationIds: decision.argumentInputRepresentationIds.copy(),
			argumentInputRepresentationRevisions: decision.argumentInputRepresentationRevisions.copy(),
			argumentSemanticTypeIds: decision.argumentSemanticTypeIds.copy(),
			argumentCarrierTypeIds: decision.argumentCarrierTypeIds.copy(),
			argumentRepresentationIds: decision.argumentRepresentationIds.copy(),
			argumentRepresentationRevisions: decision.argumentRepresentationRevisions.copy(),
			argumentConversions: decision.argumentConversions.copy(),
			boundsPolicy: decision.boundsPolicy,
			accessWidthBytes: decision.accessWidthBytes,
			byteOrderPolicy: decision.byteOrderPolicy,
			valuePolicy: decision.valuePolicy,
			mutationPolicy: decision.mutationPolicy,
			aliasPolicy: decision.aliasPolicy,
			resultKind: decision.resultKind,
			resultSemanticTypeId: decision.resultSemanticTypeId,
			resultCarrierTypeId: decision.resultCarrierTypeId,
			resultRepresentationId: decision.resultRepresentationId,
			resultRepresentationRevision: decision.resultRepresentationRevision,
			runtimeOperation: decision.runtimeOperation,
			runtimeRequirementIds: decision.runtimeRequirementIds.copy(),
			proofId: decision.proofId,
			proofClaim: decision.proofClaim,
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
	}

	static function requireRepresentationsForDecision(decision:OcamlBytesAccessDecision, representations:OcamlRepresentationRegistry):Void {
		if (decision.invocationKind == OcamlBytesAccessInvocationKind.Instance) {
			representations.requireExactBytesInternal(decision.receiverRepresentationId, decision.receiverRepresentationRevision, decision.programRevision);
		}
		for (index in 0...decision.argumentCount) {
			requireRepresentationReference(decision.argumentInputSemanticTypeIds[index], decision.argumentInputCarrierTypeIds[index],
				decision.argumentInputRepresentationIds[index], decision.argumentInputRepresentationRevisions[index], decision.programRevision,
				representations, 'access "${decision.id}" input argument $index');
			requireRepresentationReference(decision.argumentSemanticTypeIds[index], decision.argumentCarrierTypeIds[index],
				decision.argumentRepresentationIds[index], decision.argumentRepresentationRevisions[index], decision.programRevision, representations,
				'access "${decision.id}" output argument $index');
		}
		if (decision.resultKind != OcamlBytesAccessResultKind.EffectOnlyVoid) {
			requireRepresentationReference(decision.resultSemanticTypeId, decision.resultCarrierTypeId, decision.resultRepresentationId,
				decision.resultRepresentationRevision, decision.programRevision, representations, 'access "${decision.id}" result');
		}
	}

	static function requireRepresentationReference(semanticTypeId:String, carrierTypeId:String, representationId:String, representationRevision:String,
			programRevision:String, representations:OcamlRepresentationRegistry, owner:String):Void {
		final represented = if (semanticTypeId == OcamlBytesRepresentationContract.DIRECT_SEMANTIC_TYPE_ID) {
			representations.requireExactBytesInternal(representationId, representationRevision, programRevision);
		} else if (semanticTypeId == OcamlBytesRepresentationContract.DATA_SEMANTIC_TYPE_ID) {
			representations.requireExactBytesDataInternal(representationId, representationRevision, programRevision);
		} else {
			representations.require(representationId, programRevision);
		}
		if (represented.revision != representationRevision
			|| represented.semanticTypeId != semanticTypeId
			|| represented.carrierTypeId != carrierTypeId
			|| represented.domain != OcamlRepresentationDomain.InternalValue) {
			throw 'reflaxe.ocaml [ocaml-bytes:access-representation-mismatch]: $owner no longer matches $representationId@$representationRevision';
		}
	}
}

/** Finds exact target-override Bytes access calls in one final typed root. */
class OcamlBytesAccessPlanner {
	final binding:OcamlFunctionPlanBinding;
	final representations:OcamlRepresentationRegistry;

	public function new(binding:OcamlFunctionPlanBinding, representations:OcamlRepresentationRegistry) {
		this.binding = binding;
		this.representations = representations;
	}

	public function plan(root:TypedExpr):OcamlBytesAccessPlan {
		final decisions:Array<OcamlBytesAccessDecision> = [];
		final occurrences:Array<OcamlBytesAccessDecisionOccurrence> = [];
		function visit(expression:TypedExpr, path:String):Void {
			final occurrenceId = occurrenceIdFor(path);
			final decision = decisionFor(expression, occurrenceId);
			if (decision != null) {
				decisions.push(decision);
				occurrences.push({
					expression: expression,
					occurrenceId: occurrenceId,
					decisionId: decision.id
				});
			}
			var childIndex = 0;
			TypedExprTools.iter(expression, child -> {
				final childPath = path + "/child:" + childIndex;
				childIndex++;
				visit(child, childPath);
			});
		}
		visit(root, "root");
		return new OcamlBytesAccessPlan(decisions, occurrences);
	}

	function decisionFor(expression:TypedExpr, occurrenceId:String):Null<OcamlBytesAccessDecision> {
		final occurrence = OcamlBytesAccessPlan.admittedOccurrence(expression);
		if (occurrence == null)
			return null;
		final receiverRepresentation = occurrence.receiver == null ? null : representations.selectExactBytes(OcamlRepresentationDomain.InternalValue);
		final argumentInputRepresentations = occurrence.arguments.map(argument -> inputRepresentation(argument.t));
		final argumentRepresentations = occurrence.arguments.map(argument -> outputRepresentation(argument.t));
		final resultRepresentation = switch (OcamlBytesAccessContract.resultKind(occurrence.kind)) {
			case ExactInt: representations.selectExactInt(OcamlRepresentationDomain.InternalValue);
			case ExactBytesData: representations.selectExactBytesData(OcamlRepresentationDomain.InternalValue);
			case EffectOnlyVoid: null;
		}
		final invocation = OcamlBytesAccessContract.invocationKind(occurrence.kind);
		final provisional:OcamlBytesAccessDecision = {
			id: "",
			occurrenceId: occurrenceId,
			source: OcamlLoweredOrigin.sourceSpan(expression.pos),
			kind: occurrence.kind,
			invocationKind: invocation,
			calleeId: OcamlCallPlanner.calleeId(occurrence.classType, occurrence.field),
			sourceModuleId: occurrence.classType.module,
			sourceTypeName: occurrence.classType.name,
			sourceFieldName: occurrence.field.name,
			receiverSemanticTypeId: receiverRepresentation == null ? "" : receiverRepresentation.semanticTypeId,
			receiverCarrierTypeId: receiverRepresentation == null ? "" : receiverRepresentation.carrierTypeId,
			receiverRepresentationId: receiverRepresentation == null ? "" : receiverRepresentation.id,
			receiverRepresentationRevision: receiverRepresentation == null ? "" : receiverRepresentation.revision,
			argumentCount: occurrence.arguments.length,
			evaluationOrder: invocation == OcamlBytesAccessInvocationKind.Instance ? [-1].concat([
				for (index in 0...occurrence.arguments.length)
					index
			]) : [for (index in 0...occurrence.arguments.length) index],
			argumentInputSemanticTypeIds: argumentInputRepresentations.map(value -> value.semanticTypeId),
			argumentInputCarrierTypeIds: argumentInputRepresentations.map(value -> value.carrierTypeId),
			argumentInputRepresentationIds: argumentInputRepresentations.map(value -> value.id),
			argumentInputRepresentationRevisions: argumentInputRepresentations.map(value -> value.revision),
			argumentSemanticTypeIds: argumentRepresentations.map(value -> value.semanticTypeId),
			argumentCarrierTypeIds: argumentRepresentations.map(value -> value.carrierTypeId),
			argumentRepresentationIds: argumentRepresentations.map(value -> value.id),
			argumentRepresentationRevisions: argumentRepresentations.map(value -> value.revision),
			argumentConversions: argumentInputRepresentations.map(value ->
				value.semanticTypeId == "Null<Int>" ? OcamlBytesAccessArgumentConversion.RequireNonNullInt : OcamlBytesAccessArgumentConversion.Identity),
			boundsPolicy: OcamlBytesAccessContract.boundsPolicy(occurrence.kind),
			accessWidthBytes: OcamlBytesAccessContract.accessWidthBytes(occurrence.kind),
			byteOrderPolicy: OcamlBytesAccessContract.byteOrderPolicy(occurrence.kind),
			valuePolicy: OcamlBytesAccessContract.valuePolicy(occurrence.kind),
			mutationPolicy: OcamlBytesAccessContract.mutationPolicy(occurrence.kind),
			aliasPolicy: OcamlBytesAccessContract.aliasPolicy(occurrence.kind),
			resultKind: OcamlBytesAccessContract.resultKind(occurrence.kind),
			resultSemanticTypeId: resultRepresentation == null ? OcamlBytesAccessContract.VOID_SEMANTIC_TYPE_ID : resultRepresentation.semanticTypeId,
			resultCarrierTypeId: resultRepresentation == null ? "" : resultRepresentation.carrierTypeId,
			resultRepresentationId: resultRepresentation == null ? "" : resultRepresentation.id,
			resultRepresentationRevision: resultRepresentation == null ? "" : resultRepresentation.revision,
			runtimeOperation: OcamlBytesAccessContract.fieldName(occurrence.kind),
			runtimeRequirementIds: [],
			proofId: OcamlBytesAccessContract.PROOF_ID,
			proofClaim: OcamlBytesAccessContract.PROOF_CLAIM,
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: binding.bodyRevision,
			pipelineRevision: binding.pipelineRevision
		};
		final id = OcamlBytesAccessContract.idFor(provisional);
		final decision = copyWithIdentity(provisional, id);
		OcamlBytesAccessContract.requireDecision(decision);
		return decision;
	}

	function occurrenceIdFor(path:String):String {
		return OcamlBytesAccessContract.OCCURRENCE_ID_PREFIX + Sha256.encode(binding.functionId + "|" + path).substr(0, 24);
	}

	function inputRepresentation(type:Type):OcamlRepresentationDecision {
		if (OcamlRepresentationRegistry.isExactBytesData(type))
			return representations.selectExactBytesData(OcamlRepresentationDomain.InternalValue);
		if (OcamlRepresentationRegistry.isExactNullInt(type))
			return representations.selectExactNullInt(OcamlRepresentationDomain.InternalValue);
		return representations.selectExactInt(OcamlRepresentationDomain.InternalValue);
	}

	function outputRepresentation(type:Type):OcamlRepresentationDecision {
		return
			OcamlRepresentationRegistry.isExactBytesData(type) ? representations.selectExactBytesData(OcamlRepresentationDomain.InternalValue) : representations.selectExactInt(OcamlRepresentationDomain.InternalValue);
	}

	static function copyWithIdentity(decision:OcamlBytesAccessDecision, id:String):OcamlBytesAccessDecision {
		return {
			id: id,
			occurrenceId: decision.occurrenceId,
			source: {file: decision.source.file, min: decision.source.min, max: decision.source.max},
			kind: decision.kind,
			invocationKind: decision.invocationKind,
			calleeId: decision.calleeId,
			sourceModuleId: decision.sourceModuleId,
			sourceTypeName: decision.sourceTypeName,
			sourceFieldName: decision.sourceFieldName,
			receiverSemanticTypeId: decision.receiverSemanticTypeId,
			receiverCarrierTypeId: decision.receiverCarrierTypeId,
			receiverRepresentationId: decision.receiverRepresentationId,
			receiverRepresentationRevision: decision.receiverRepresentationRevision,
			argumentCount: decision.argumentCount,
			evaluationOrder: decision.evaluationOrder.copy(),
			argumentInputSemanticTypeIds: decision.argumentInputSemanticTypeIds.copy(),
			argumentInputCarrierTypeIds: decision.argumentInputCarrierTypeIds.copy(),
			argumentInputRepresentationIds: decision.argumentInputRepresentationIds.copy(),
			argumentInputRepresentationRevisions: decision.argumentInputRepresentationRevisions.copy(),
			argumentSemanticTypeIds: decision.argumentSemanticTypeIds.copy(),
			argumentCarrierTypeIds: decision.argumentCarrierTypeIds.copy(),
			argumentRepresentationIds: decision.argumentRepresentationIds.copy(),
			argumentRepresentationRevisions: decision.argumentRepresentationRevisions.copy(),
			argumentConversions: decision.argumentConversions.copy(),
			boundsPolicy: decision.boundsPolicy,
			accessWidthBytes: decision.accessWidthBytes,
			byteOrderPolicy: decision.byteOrderPolicy,
			valuePolicy: decision.valuePolicy,
			mutationPolicy: decision.mutationPolicy,
			aliasPolicy: decision.aliasPolicy,
			resultKind: decision.resultKind,
			resultSemanticTypeId: decision.resultSemanticTypeId,
			resultCarrierTypeId: decision.resultCarrierTypeId,
			resultRepresentationId: decision.resultRepresentationId,
			resultRepresentationRevision: decision.resultRepresentationRevision,
			runtimeOperation: decision.runtimeOperation,
			runtimeRequirementIds: [id + ":runtime:" + OcamlBytesAccessContract.RUNTIME_CAPABILITY],
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
