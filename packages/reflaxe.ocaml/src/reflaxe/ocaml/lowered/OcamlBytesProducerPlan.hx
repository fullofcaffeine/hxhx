package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.macro.Type;
import haxe.macro.Type.ClassType;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.lowered.OcamlBytesProducerModel.OcamlBytesEncodingKind;
import reflaxe.ocaml.lowered.OcamlBytesProducerModel.OcamlBytesProducerContract;
import reflaxe.ocaml.lowered.OcamlBytesProducerModel.OcamlBytesProducerDecision;
import reflaxe.ocaml.lowered.OcamlBytesProducerModel.OcamlBytesProducerKind;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallPlanner;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;

/**
	Immutable inventory of supported non-null Bytes producers in one typed root.

	Lookups use a normalized source span plus the exact typed static field. This
	prevents a nested expression that shares a host source span from borrowing
	another producer's decision.
**/
class OcamlBytesProducerPlan {
	final ordered:Array<OcamlBytesProducerDecision>;
	final bySourceKey:Map<String, Array<OcamlBytesProducerDecision>> = [];

	public final revision:String;

	public function new(decisions:Array<OcamlBytesProducerDecision>) {
		final sorted = decisions.map(copyDecision);
		sorted.sort((left, right) -> Reflect.compare(left.id, right.id));
		final normalized:Array<OcamlBytesProducerDecision> = [];
		for (decision in sorted) {
			OcamlBytesProducerContract.requireDecision(decision);
			final key = sourceKey(decision.source);
			final candidates = bySourceKey.get(key) ?? [];
			final duplicate = Lambda.find(candidates,
				existing -> existing.kind == decision.kind
					&& existing.calleeId == decision.calleeId
					&& existing.argumentCount == decision.argumentCount
					&& existing.encoding == decision.encoding);
			if (duplicate != null) {
				if (fingerprint(duplicate) != fingerprint(decision))
					throw 'reflaxe.ocaml [ocaml-bytes:conflicting-producer]: Bytes producer identity "${decision.id}" selects different facts';
				throw 'reflaxe.ocaml [ocaml-bytes:duplicate-producer]: more than one Bytes producer can match ${decision.calleeId} at "$key"';
			}
			candidates.push(copyDecision(decision));
			bySourceKey.set(key, candidates);
			normalized.push(copyDecision(decision));
		}
		ordered = normalized;
		revision = "sha256:" + Sha256.encode(ordered.map(fingerprint).join("\n"));
	}

	/** Returns the sealed decision for one exact typed producer occurrence. */
	public function decisionFor(expression:TypedExpr):Null<OcamlBytesProducerDecision> {
		final candidates = bySourceKey.get(sourceKey(OcamlLoweredOrigin.sourceSpan(expression.pos))) ?? [];
		final matching = candidates.filter(decision -> matchesTypedOccurrence(decision, expression));
		if (matching.length > 1)
			throw 'reflaxe.ocaml [ocaml-bytes:ambiguous-producer]: ${matching.length} sealed Bytes producers match one typed occurrence';
		return matching.length == 0 ? null : copyDecision(matching[0]);
	}

	/** Requires syntax construction to consume exactly one sealed producer. */
	public function requireFor(expression:TypedExpr, representations:OcamlRepresentationRegistry):OcamlBytesProducerDecision {
		final expectedKind = admittedKind(expression);
		if (expectedKind == null)
			throw "reflaxe.ocaml [ocaml-bytes:unadmitted-producer]: syntax requested a Bytes producer outside the sealed producer family";
		final decision = decisionFor(expression);
		if (decision == null)
			throw 'reflaxe.ocaml [ocaml-bytes:missing-producer]: admitted Bytes producer ${expectedKind} reached syntax without its sealed decision';
		OcamlBytesProducerContract.requireDecision(decision);
		requireResultRepresentation(decision, representations);
		return decision;
	}

	/** Revalidates every producer result against the request-owned registry. */
	public function requireRepresentations(representations:OcamlRepresentationRegistry):Void {
		for (decision in ordered)
			requireResultRepresentation(decision, representations);
	}

	/** Returns all producer decisions in deterministic identity order. */
	public function decisions():Array<OcamlBytesProducerDecision> {
		return ordered.map(copyDecision);
	}

	/** Verifies that every decision belongs to the enclosing typed-root seal. */
	public function requirePlanBinding(binding:OcamlFunctionPlanBinding):Void {
		for (decision in ordered) {
			if (decision.functionId != binding.functionId
				|| decision.programRevision != binding.programRevision
				|| decision.bodyRevision != binding.bodyRevision
				|| decision.pipelineRevision != binding.pipelineRevision) {
				throw 'reflaxe.ocaml [ocaml-bytes:stale-producer]: producer "${decision.id}" does not belong to ${binding.functionId}/${binding.bodyRevision}/${binding.pipelineRevision}';
			}
		}
	}

	/** Classifies one exact supported producer, or returns null. */
	public static function admittedKind(expression:TypedExpr):Null<OcamlBytesProducerKind> {
		if (!isExactBytesType(expression.t))
			return null;
		return switch (expression.expr) {
			case TCall({expr: TField(_, FStatic(classRef, fieldRef))}, arguments):
				final classType = classRef.get();
				final field = fieldRef.get();
				if (!isBytesClass(classType)) null; else switch (field.name) {
					case "alloc" if (arguments.length == 1): OcamlBytesProducerKind.Alloc;
					case "ofString" if (encodingForArguments(arguments) != null): OcamlBytesProducerKind.OfString;
					case "ofData" if (arguments.length == 1): OcamlBytesProducerKind.OfData;
					case "ofHex" if (arguments.length == 1): OcamlBytesProducerKind.OfHex;
					case _: null;
				}
			case _:
				null;
		}
	}

	/** Whether a class is the exact Haxe standard-library Bytes class. */
	public static function isBytesClass(classType:ClassType):Bool {
		return classType.pack != null && classType.pack.length == 2 && classType.pack[0] == "haxe" && classType.pack[1] == "io" && classType.name == "Bytes";
	}

	/** Whether a type is the direct typed `haxe.io.Bytes` form. */
	public static function isExactBytesType(type:Type):Bool {
		return OcamlRepresentationRegistry.isExactBytes(type);
	}

	/** Classifies the supported optional encoding argument shape. */
	public static function encodingForArguments(arguments:Array<TypedExpr>):Null<OcamlBytesEncodingKind> {
		if (arguments.length == 1)
			return OcamlBytesEncodingKind.Omitted;
		if (arguments.length != 2)
			return null;
		return encodingExpression(arguments[1]);
	}

	/** Whether one explicit expression is a supported Bytes encoding value. */
	public static function isSupportedEncodingExpression(expression:TypedExpr):Bool {
		return encodingExpression(expression) != null;
	}

	static function encodingExpression(expression:TypedExpr):Null<OcamlBytesEncodingKind> {
		return switch (unwrapMeta(expression).expr) {
			case TConst(TNull):
				OcamlBytesEncodingKind.ExplicitNull;
			case TField(_, FEnum(enumRef, field)):
				final enumType = enumRef.get();
				if (enumType.pack != null && enumType.pack.length == 2 && enumType.pack[0] == "haxe" && enumType.pack[1] == "io" && enumType.name == "Encoding") {
					switch (field.name) {
						case "UTF8": OcamlBytesEncodingKind.UTF8;
						case "RawNative": OcamlBytesEncodingKind.RawNative;
						case _: null;
					}
				} else {
					null;
				}
			case _:
				null;
		}
	}

	static function matchesTypedOccurrence(decision:OcamlBytesProducerDecision, expression:TypedExpr):Bool {
		if (!isExactBytesType(expression.t) || admittedKind(expression) != decision.kind)
			return false;
		return switch (expression.expr) {
			case TCall({expr: TField(_, FStatic(classRef, fieldRef))}, arguments): arguments.length == decision.argumentCount && OcamlCallPlanner.calleeId(classRef.get(),
					fieldRef.get()) == decision.calleeId && encodingForKind(decision.kind, arguments) == decision.encoding;
			case _:
				false;
		}
	}

	static function encodingForKind(kind:OcamlBytesProducerKind, arguments:Array<TypedExpr>):Null<OcamlBytesEncodingKind> {
		return kind == OcamlBytesProducerKind.OfString ? encodingForArguments(arguments) : OcamlBytesEncodingKind.NotApplicable;
	}

	static function sourceKey(source:OcamlLoweredSourceSpan):String {
		return source.file + ":" + source.min + ":" + source.max;
	}

	static function fingerprint(decision:OcamlBytesProducerDecision):String {
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
			Std.string(decision.argumentCount),
			decision.argumentEvaluationOrder.join(","),
			(decision.encoding : String),
			decision.resultSemanticTypeId,
			decision.resultCarrierTypeId,
			decision.resultNullability,
			decision.resultRepresentationId,
			decision.resultRepresentationRevision,
			decision.runtimeRequirementIds.join(","),
			decision.proofId,
			decision.proofClaim,
			decision.functionId,
			decision.programRevision,
			decision.bodyRevision,
			decision.pipelineRevision
		].join("|");
	}

	static function copyDecision(decision:OcamlBytesProducerDecision):OcamlBytesProducerDecision {
		return {
			id: decision.id,
			source: {file: decision.source.file, min: decision.source.min, max: decision.source.max},
			kind: decision.kind,
			calleeId: decision.calleeId,
			sourceModuleId: decision.sourceModuleId,
			sourceTypeName: decision.sourceTypeName,
			sourceFieldName: decision.sourceFieldName,
			argumentCount: decision.argumentCount,
			argumentEvaluationOrder: decision.argumentEvaluationOrder.copy(),
			encoding: decision.encoding,
			resultSemanticTypeId: decision.resultSemanticTypeId,
			resultCarrierTypeId: decision.resultCarrierTypeId,
			resultNullability: decision.resultNullability,
			resultRepresentationId: decision.resultRepresentationId,
			resultRepresentationRevision: decision.resultRepresentationRevision,
			runtimeRequirementIds: decision.runtimeRequirementIds.copy(),
			proofId: decision.proofId,
			proofClaim: decision.proofClaim,
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision
		};
	}

	static function requireResultRepresentation(decision:OcamlBytesProducerDecision, representations:OcamlRepresentationRegistry):Void {
		representations.requireExactBytesInternal(decision.resultRepresentationId, decision.resultRepresentationRevision, decision.programRevision);
	}

	static function unwrapMeta(expression:TypedExpr):TypedExpr {
		return switch (expression.expr) {
			case TMeta(_, child): unwrapMeta(child);
			case _: expression;
		}
	}
}

/**
	Finds supported Bytes producer occurrences in one final typed expression root.

	The planner admits only exact non-null results and exact supported arities.
	Unsupported encodings and every consumer or mutation stay on their existing
	fail-closed path until the parent runtime-authority task models them.
**/
class OcamlBytesProducerPlanner {
	final binding:OcamlFunctionPlanBinding;
	final representations:OcamlRepresentationRegistry;

	public function new(binding:OcamlFunctionPlanBinding, representations:OcamlRepresentationRegistry) {
		this.binding = binding;
		this.representations = representations;
	}

	/** Builds the complete producer inventory for one final typed expression root. */
	public function plan(root:TypedExpr):OcamlBytesProducerPlan {
		final decisions:Array<OcamlBytesProducerDecision> = [];
		function visit(expression:TypedExpr):Void {
			final decision = decisionFor(expression);
			if (decision != null)
				decisions.push(decision);
			TypedExprTools.iter(expression, visit);
		}
		visit(root);
		return new OcamlBytesProducerPlan(decisions);
	}

	function decisionFor(expression:TypedExpr):Null<OcamlBytesProducerDecision> {
		final kind = OcamlBytesProducerPlan.admittedKind(expression);
		if (kind == null)
			return null;
		final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
		final operation = producerIdentity(expression, kind);
		final encoding = switch (expression.expr) {
			case TCall(_, arguments) if (kind == OcamlBytesProducerKind.OfString):
				OcamlBytesProducerPlan.encodingForArguments(arguments);
			case _:
				OcamlBytesEncodingKind.NotApplicable;
		}
		if (encoding == null)
			return null;
		final resultRepresentation = representations.selectExactBytes(OcamlRepresentationDomain.InternalValue);
		if (resultRepresentation.programRevision != binding.programRevision)
			throw 'reflaxe.ocaml [ocaml-bytes:stale-representation]: producer ${operation.calleeId} belongs to ${binding.programRevision}, but its Bytes carrier belongs to ${resultRepresentation.programRevision}';
		final argumentCount = switch (expression.expr) {
			case TCall(_, arguments): arguments.length;
			case _: 0;
		}
		final id = OcamlBytesProducerContract.idFor(binding.functionId, binding.programRevision, binding.bodyRevision, binding.pipelineRevision, source, kind,
			operation.calleeId, argumentCount, encoding, resultRepresentation.id, resultRepresentation.revision);
		return {
			id: id,
			source: source,
			kind: kind,
			calleeId: operation.calleeId,
			sourceModuleId: operation.moduleId,
			sourceTypeName: operation.typeName,
			sourceFieldName: operation.fieldName,
			argumentCount: argumentCount,
			argumentEvaluationOrder: [for (index in 0...argumentCount) index],
			encoding: encoding,
			resultSemanticTypeId: OcamlBytesProducerContract.SEMANTIC_TYPE_ID,
			resultCarrierTypeId: resultRepresentation.carrierTypeId,
			resultNullability: OcamlBytesProducerContract.RESULT_NULLABILITY,
			resultRepresentationId: resultRepresentation.id,
			resultRepresentationRevision: resultRepresentation.revision,
			runtimeRequirementIds: [id + ":runtime:" + OcamlBytesProducerContract.RUNTIME_CAPABILITY],
			proofId: OcamlBytesProducerContract.PROOF_ID,
			proofClaim: OcamlBytesProducerContract.PROOF_CLAIM,
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: binding.bodyRevision,
			pipelineRevision: binding.pipelineRevision
		};
	}

	static function producerIdentity(expression:TypedExpr, kind:OcamlBytesProducerKind):{
		calleeId:String,
		moduleId:String,
		typeName:String,
		fieldName:String
	} {
		return switch (expression.expr) {
			case TCall({expr: TField(_, FStatic(classRef, fieldRef))}, _):
				final classType = classRef.get();
				final field = fieldRef.get();
				{
					calleeId: OcamlCallPlanner.calleeId(classType, field),
					moduleId: classType.module,
					typeName: classType.name,
					fieldName: field.name
				};
			case _:
				throw 'reflaxe.ocaml [ocaml-bytes:invalid-producer]: admitted Bytes producer $kind has no typed declaration';
		}
	}
}
#end
