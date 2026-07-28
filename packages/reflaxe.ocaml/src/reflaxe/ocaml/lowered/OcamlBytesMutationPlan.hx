package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.macro.Type;
import haxe.macro.Type.ClassField;
import haxe.macro.Type.ClassType;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.lowered.OcamlBytesMutationModel.OcamlBytesMutationArgumentConversion;
import reflaxe.ocaml.lowered.OcamlBytesMutationModel.OcamlBytesMutationContract;
import reflaxe.ocaml.lowered.OcamlBytesMutationModel.OcamlBytesMutationDecision;
import reflaxe.ocaml.lowered.OcamlBytesMutationModel.OcamlBytesMutationKind;
import reflaxe.ocaml.lowered.OcamlBytesMutationModel.OcamlBytesMutationResultKind;
import reflaxe.ocaml.lowered.OcamlBytesRepresentationModel.OcamlBytesRepresentationContract;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallPlanner;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDecision;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;

typedef OcamlBytesMutationOccurrence = {
	final kind:OcamlBytesMutationKind;
	final classType:ClassType;
	final field:ClassField;
	final receiver:TypedExpr;
	final arguments:Array<TypedExpr>;
}

/**
	Immutable inventory of exact mutating Bytes operations in one typed root.

	Each source occurrence binds to one exact standard-library declaration and
	one revisioned decision. Syntax cannot infer mutation or overlap behavior
	from a generated method name.
**/
class OcamlBytesMutationPlan {
	final ordered:Array<OcamlBytesMutationDecision>;
	final bySourceKey:Map<String, Array<OcamlBytesMutationDecision>> = [];

	public final revision:String;

	public function new(decisions:Array<OcamlBytesMutationDecision>) {
		final sorted = decisions.map(copyDecision);
		sorted.sort((left, right) -> Reflect.compare(left.id, right.id));
		final normalized:Array<OcamlBytesMutationDecision> = [];
		for (decision in sorted) {
			OcamlBytesMutationContract.requireDecision(decision);
			final key = sourceKey(decision.source);
			final candidates = bySourceKey.get(key) ?? [];
			final duplicate = Lambda.find(candidates,
				existing -> existing.kind == decision.kind
					&& existing.calleeId == decision.calleeId
					&& existing.argumentCount == decision.argumentCount);
			if (duplicate != null) {
				if (fingerprint(duplicate) != fingerprint(decision))
					throw 'reflaxe.ocaml [ocaml-bytes:conflicting-mutation]: Bytes mutation identity "${decision.id}" selects different facts';
				throw 'reflaxe.ocaml [ocaml-bytes:duplicate-mutation]: more than one Bytes mutation can match ${decision.calleeId} at "$key"';
			}
			candidates.push(copyDecision(decision));
			bySourceKey.set(key, candidates);
			normalized.push(copyDecision(decision));
		}
		ordered = normalized;
		revision = "sha256:" + Sha256.encode(ordered.map(fingerprint).join("\n"));
	}

	/** Returns the sealed decision for one exact typed mutation occurrence. */
	public function decisionFor(expression:TypedExpr):Null<OcamlBytesMutationDecision> {
		final candidates = bySourceKey.get(sourceKey(OcamlLoweredOrigin.sourceSpan(expression.pos))) ?? [];
		final matching = candidates.filter(decision -> matchesTypedOccurrence(decision, expression));
		if (matching.length > 1)
			throw 'reflaxe.ocaml [ocaml-bytes:ambiguous-mutation]: ${matching.length} sealed Bytes mutations match one typed occurrence';
		return matching.length == 0 ? null : copyDecision(matching[0]);
	}

	/** Requires syntax to consume exactly one sealed mutation decision. */
	public function requireFor(expression:TypedExpr, representations:OcamlRepresentationRegistry):OcamlBytesMutationDecision {
		final expected = admittedOccurrence(expression);
		if (expected == null)
			throw "reflaxe.ocaml [ocaml-bytes:unadmitted-mutation]: syntax requested a Bytes mutation outside the sealed family";
		final decision = decisionFor(expression);
		if (decision == null)
			throw 'reflaxe.ocaml [ocaml-bytes:missing-mutation]: admitted Bytes mutation ${expected.kind} reached syntax without its sealed decision';
		OcamlBytesMutationContract.requireDecision(decision);
		requireRepresentationsForDecision(decision, representations);
		return decision;
	}

	/** Revalidates every receiver and argument representation. */
	public function requireRepresentations(representations:OcamlRepresentationRegistry):Void {
		for (decision in ordered)
			requireRepresentationsForDecision(decision, representations);
	}

	/** Returns all mutation decisions in deterministic identity order. */
	public function decisions():Array<OcamlBytesMutationDecision> {
		return ordered.map(copyDecision);
	}

	/** Verifies that every decision belongs to the enclosing typed-root seal. */
	public function requirePlanBinding(binding:OcamlFunctionPlanBinding):Void {
		for (decision in ordered) {
			if (decision.functionId != binding.functionId
				|| decision.programRevision != binding.programRevision
				|| decision.bodyRevision != binding.bodyRevision
				|| decision.pipelineRevision != binding.pipelineRevision) {
				throw 'reflaxe.ocaml [ocaml-bytes:stale-mutation]: mutation "${decision.id}" does not belong to ${binding.functionId}/${binding.bodyRevision}/${binding.pipelineRevision}';
			}
		}
	}

	/** Returns the exact typed receiver and arguments for an admitted mutation. */
	public static function admittedOccurrence(expression:TypedExpr):Null<OcamlBytesMutationOccurrence> {
		return switch (expression.expr) {
			case TCall({expr: TField(receiver, FInstance(classRef, _, fieldRef))}, arguments):
				final classType = classRef.get();
				final field = fieldRef.get();
				if (!OcamlBytesProducerPlan.isBytesClass(classType)
					|| !OcamlRepresentationRegistry.isExactBytes(receiver.t)
					|| !isExactVoid(expression.t)) {
					null;
				} else {
					final kind = instanceKind(field.name, arguments);
					kind == null ? null : {
						kind: kind,
						classType: classType,
						field: field,
						receiver: receiver,
						arguments: arguments
					};
				}
			case _:
				null;
		}
	}

	static function instanceKind(fieldName:String, arguments:Array<TypedExpr>):Null<OcamlBytesMutationKind> {
		return switch (fieldName) {
			case "fill" if (matchesExactArguments(arguments, [isAdmittedIntInput, isAdmittedIntInput, isAdmittedIntInput])):
				OcamlBytesMutationKind.Fill;
			case "blit" if (matchesExactArguments(arguments, [
				isAdmittedIntInput,
				OcamlRepresentationRegistry.isExactBytes,
				isAdmittedIntInput,
				isAdmittedIntInput
			])):
				OcamlBytesMutationKind.Blit;
			case _:
				null;
		}
	}

	static function isAdmittedIntInput(type:Type):Bool {
		return OcamlRepresentationRegistry.isExactInt(type) || OcamlRepresentationRegistry.isExactNullInt(type);
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

	static function matchesTypedOccurrence(decision:OcamlBytesMutationDecision, expression:TypedExpr):Bool {
		final occurrence = admittedOccurrence(expression);
		return occurrence != null
			&& occurrence.kind == decision.kind
			&& occurrence.arguments.length == decision.argumentCount
			&& OcamlCallPlanner.calleeId(occurrence.classType, occurrence.field) == decision.calleeId;
	}

	static function sourceKey(source:OcamlLoweredSourceSpan):String {
		return source.file + ":" + source.min + ":" + source.max;
	}

	static function fingerprint(decision:OcamlBytesMutationDecision):String {
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
			decision.destinationPolicy,
			(decision.sourcePolicy : String),
			(decision.overlapPolicy : String),
			decision.boundsPolicy,
			(decision.valuePolicy : String),
			(decision.resultKind : String),
			decision.resultSemanticTypeId,
			decision.runtimeRequirementIds.join(","),
			decision.proofId,
			decision.proofClaim,
			decision.functionId,
			decision.programRevision,
			decision.bodyRevision,
			decision.pipelineRevision
		].join("|");
	}

	static function copyDecision(decision:OcamlBytesMutationDecision):OcamlBytesMutationDecision {
		return {
			id: decision.id,
			source: {file: decision.source.file, min: decision.source.min, max: decision.source.max},
			kind: decision.kind,
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
			destinationPolicy: decision.destinationPolicy,
			sourcePolicy: decision.sourcePolicy,
			overlapPolicy: decision.overlapPolicy,
			boundsPolicy: decision.boundsPolicy,
			valuePolicy: decision.valuePolicy,
			resultKind: decision.resultKind,
			resultSemanticTypeId: decision.resultSemanticTypeId,
			runtimeRequirementIds: decision.runtimeRequirementIds.copy(),
			proofId: decision.proofId,
			proofClaim: decision.proofClaim,
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
	}

	static function requireRepresentationsForDecision(decision:OcamlBytesMutationDecision, representations:OcamlRepresentationRegistry):Void {
		representations.requireExactBytesInternal(decision.receiverRepresentationId, decision.receiverRepresentationRevision, decision.programRevision);
		for (index in 0...decision.argumentCount) {
			requireRepresentationReference(decision.argumentInputSemanticTypeIds[index], decision.argumentInputCarrierTypeIds[index],
				decision.argumentInputRepresentationIds[index], decision.argumentInputRepresentationRevisions[index], decision.programRevision,
				representations, 'mutation "${decision.id}" input argument $index');
			requireRepresentationReference(decision.argumentSemanticTypeIds[index], decision.argumentCarrierTypeIds[index],
				decision.argumentRepresentationIds[index], decision.argumentRepresentationRevisions[index], decision.programRevision, representations,
				'mutation "${decision.id}" output argument $index');
		}
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
			throw 'reflaxe.ocaml [ocaml-bytes:mutation-representation-mismatch]: $owner no longer matches $representationId@$representationRevision';
		}
	}
}

/**
	Finds exact `fill` and `blit` calls in one final typed expression root.

	The planner deliberately excludes inline-expanded BytesData operations,
	invalid bracket access, Float/Int64 operations, nullable materialization,
	and user-defined methods with the same names.
**/
class OcamlBytesMutationPlanner {
	final binding:OcamlFunctionPlanBinding;
	final representations:OcamlRepresentationRegistry;

	public function new(binding:OcamlFunctionPlanBinding, representations:OcamlRepresentationRegistry) {
		this.binding = binding;
		this.representations = representations;
	}

	/** Builds the complete mutation inventory for one final typed expression root. */
	public function plan(root:TypedExpr):OcamlBytesMutationPlan {
		final decisions:Array<OcamlBytesMutationDecision> = [];
		function visit(expression:TypedExpr):Void {
			final decision = decisionFor(expression);
			if (decision != null)
				decisions.push(decision);
			TypedExprTools.iter(expression, visit);
		}
		visit(root);
		return new OcamlBytesMutationPlan(decisions);
	}

	function decisionFor(expression:TypedExpr):Null<OcamlBytesMutationDecision> {
		final occurrence = OcamlBytesMutationPlan.admittedOccurrence(expression);
		if (occurrence == null)
			return null;
		final receiverRepresentation = representations.selectExactBytes(OcamlRepresentationDomain.InternalValue);
		final argumentInputRepresentations:Array<OcamlRepresentationDecision> = [
			for (argument in occurrence.arguments)
				if (OcamlRepresentationRegistry.isExactBytes(argument.t)) representations.selectExactBytes(OcamlRepresentationDomain.InternalValue) else
					if (OcamlRepresentationRegistry.isExactNullInt(argument.t))
						representations.selectExactNullInt(OcamlRepresentationDomain.InternalValue) else
						representations.selectExactInt(OcamlRepresentationDomain.InternalValue)
		];
		final argumentRepresentations:Array<OcamlRepresentationDecision> = [
			for (argument in occurrence.arguments)
				if (OcamlRepresentationRegistry.isExactBytes(argument.t)) representations.selectExactBytes(OcamlRepresentationDomain.InternalValue) else
					representations.selectExactInt(OcamlRepresentationDomain.InternalValue)
		];
		final provisional:OcamlBytesMutationDecision = {
			id: "",
			source: OcamlLoweredOrigin.sourceSpan(expression.pos),
			kind: occurrence.kind,
			calleeId: OcamlCallPlanner.calleeId(occurrence.classType, occurrence.field),
			sourceModuleId: occurrence.classType.module,
			sourceTypeName: occurrence.classType.name,
			sourceFieldName: occurrence.field.name,
			receiverSemanticTypeId: receiverRepresentation.semanticTypeId,
			receiverCarrierTypeId: receiverRepresentation.carrierTypeId,
			receiverRepresentationId: receiverRepresentation.id,
			receiverRepresentationRevision: receiverRepresentation.revision,
			argumentCount: occurrence.arguments.length,
			evaluationOrder: [-1].concat([for (index in 0...occurrence.arguments.length) index]),
			argumentInputSemanticTypeIds: argumentInputRepresentations.map(value -> value.semanticTypeId),
			argumentInputCarrierTypeIds: argumentInputRepresentations.map(value -> value.carrierTypeId),
			argumentInputRepresentationIds: argumentInputRepresentations.map(value -> value.id),
			argumentInputRepresentationRevisions: argumentInputRepresentations.map(value -> value.revision),
			argumentSemanticTypeIds: argumentRepresentations.map(value -> value.semanticTypeId),
			argumentCarrierTypeIds: argumentRepresentations.map(value -> value.carrierTypeId),
			argumentRepresentationIds: argumentRepresentations.map(value -> value.id),
			argumentRepresentationRevisions: argumentRepresentations.map(value -> value.revision),
			argumentConversions: [
				for (representation in argumentInputRepresentations)
					representation.semanticTypeId == "Null<Int>" ? OcamlBytesMutationArgumentConversion.RequireNonNullInt : OcamlBytesMutationArgumentConversion.Identity
			],
			destinationPolicy: OcamlBytesMutationContract.DESTINATION_POLICY,
			sourcePolicy: OcamlBytesMutationContract.sourcePolicy(occurrence.kind),
			overlapPolicy: OcamlBytesMutationContract.overlapPolicy(occurrence.kind),
			boundsPolicy: OcamlBytesMutationContract.BOUNDS_POLICY,
			valuePolicy: OcamlBytesMutationContract.valuePolicy(occurrence.kind),
			resultKind: OcamlBytesMutationResultKind.EffectOnlyVoid,
			resultSemanticTypeId: OcamlBytesMutationContract.VOID_SEMANTIC_TYPE_ID,
			runtimeRequirementIds: [],
			proofId: OcamlBytesMutationContract.PROOF_ID,
			proofClaim: OcamlBytesMutationContract.PROOF_CLAIM,
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: binding.bodyRevision,
			pipelineRevision: binding.pipelineRevision
		};
		final id = OcamlBytesMutationContract.idFor(provisional);
		final decision = copyWithIdentity(provisional, id);
		OcamlBytesMutationContract.requireDecision(decision);
		return decision;
	}

	static function copyWithIdentity(decision:OcamlBytesMutationDecision, id:String):OcamlBytesMutationDecision {
		return {
			id: id,
			source: decision.source,
			kind: decision.kind,
			calleeId: decision.calleeId,
			sourceModuleId: decision.sourceModuleId,
			sourceTypeName: decision.sourceTypeName,
			sourceFieldName: decision.sourceFieldName,
			receiverSemanticTypeId: decision.receiverSemanticTypeId,
			receiverCarrierTypeId: decision.receiverCarrierTypeId,
			receiverRepresentationId: decision.receiverRepresentationId,
			receiverRepresentationRevision: decision.receiverRepresentationRevision,
			argumentCount: decision.argumentCount,
			evaluationOrder: decision.evaluationOrder,
			argumentInputSemanticTypeIds: decision.argumentInputSemanticTypeIds,
			argumentInputCarrierTypeIds: decision.argumentInputCarrierTypeIds,
			argumentInputRepresentationIds: decision.argumentInputRepresentationIds,
			argumentInputRepresentationRevisions: decision.argumentInputRepresentationRevisions,
			argumentSemanticTypeIds: decision.argumentSemanticTypeIds,
			argumentCarrierTypeIds: decision.argumentCarrierTypeIds,
			argumentRepresentationIds: decision.argumentRepresentationIds,
			argumentRepresentationRevisions: decision.argumentRepresentationRevisions,
			argumentConversions: decision.argumentConversions,
			destinationPolicy: decision.destinationPolicy,
			sourcePolicy: decision.sourcePolicy,
			overlapPolicy: decision.overlapPolicy,
			boundsPolicy: decision.boundsPolicy,
			valuePolicy: decision.valuePolicy,
			resultKind: decision.resultKind,
			resultSemanticTypeId: decision.resultSemanticTypeId,
			runtimeRequirementIds: [id + ":runtime:" + OcamlBytesMutationContract.RUNTIME_CAPABILITY],
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
