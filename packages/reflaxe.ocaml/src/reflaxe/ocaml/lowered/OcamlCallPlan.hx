package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.macro.Type;
import haxe.macro.Type.ClassField;
import haxe.macro.Type.ClassType;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypeTools;
import haxe.macro.TypedExprTools;
import reflaxe.data.ClassFuncData;
import reflaxe.lifecycle.LexicalLocalIdentityPlan;
import reflaxe.ocaml.lowered.OcamlCallRuntimeUseModel.OcamlCallRuntimeUseContract;
import reflaxe.ocaml.lowered.OcamlCallRuntimeUseModel.OcamlCallRuntimeUsePlan;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDecision;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;
import reflaxe.ocaml.lowered.OcamlStandardArrayCallModel.OcamlStandardArrayCallContract;
import reflaxe.ocaml.lowered.OcamlStandardArrayCallModel.OcamlStandardArrayResultKind;
import reflaxe.ocaml.lowered.OcamlStandardArrayCallModel.OcamlStandardArrayCallTarget;
import reflaxe.ocaml.lowered.OcamlStandardIMapCallModel.OcamlStandardIMapCallContract;
import reflaxe.ocaml.lowered.OcamlStandardIMapCallModel.OcamlStandardIMapCallTarget;
import reflaxe.ocaml.lowered.OcamlStructuralIteratorCallModel.OcamlStructuralIteratorCallContract;
import reflaxe.ocaml.lowered.OcamlStructuralIteratorCallModel.OcamlStructuralIteratorCallTarget;

/** The source-language dispatch selected before OCaml syntax is constructed. */
enum abstract OcamlCallKind(String) from String to String {
	final DirectStaticHaxeMethod = "direct-static-haxe-method";
	final DirectInstanceHaxeMethod = "direct-instance-haxe-method";
	final DirectHaxeConstructor = "direct-haxe-constructor";
	final TypedFunctionValue = "typed-function-value";
	final StandardArrayMethod = "standard-array-method";
	final StandardIMapMethod = "standard-imap-method";
	final StructuralIteratorMethod = "structural-iterator-method";
}

/**
	Whether an admitted call produces a represented Haxe value.

	`EffectOnlyVoid` is an explicit absence of a value. It never owns a carrier,
	representation identity, or conversion record.
**/
enum abstract OcamlCallResultKind(String) from String to String {
	final Value = "value";
	final EffectOnlyVoid = "effect-only-void";
}

/** How one represented value crosses an admitted call boundary. */
enum abstract OcamlCallCarrierConversion(String) from String to String {
	final Identity = "identity";
	final PreserveNullableIntCarrier = "preserve-nullable-int-carrier";
	final BoxExactIntToNullableInt = "box-exact-int-to-nullable-int";
	final CheckedUnboxNullableInt = "checked-unbox-nullable-int";
	final PreserveNullableBoolCarrier = "preserve-nullable-bool-carrier";
	final BoxExactBoolToNullableBool = "box-exact-bool-to-nullable-bool";
	final PreserveDynamicCarrier = "preserve-dynamic-carrier";
	final BoxConcreteToDynamic = "box-concrete-to-dynamic";
	final BoxExactBoolToDynamic = "box-exact-bool-to-dynamic";
	final MaterializeOmittedNullableInt = "materialize-omitted-nullable-int";
	final MaterializeOmittedNullableBool = "materialize-omitted-nullable-bool";
	final MaterializeOmittedString = "materialize-omitted-string";
	final MaterializeOmittedDynamic = "materialize-omitted-dynamic";
	final MaterializeExplicitNullString = "materialize-explicit-null-string";
	final MaterializeExplicitNullDynamic = "materialize-explicit-null-dynamic";
}

/** The only runtime actions admitted in a sealed typed-call schedule. */
enum abstract OcamlCallEvaluationStepKind(String) from String to String {
	final MaterializeCallee = "materialize-callee";
	final MaterializeReceiver = "materialize-receiver";
	final MaterializeArgument = "materialize-argument";
	final MaterializeOmittedArgument = "materialize-omitted-argument";
	final InvokeCallee = "invoke-callee";
}

/**
	One typed source-order step that must complete before the call can run.

	A supplied materialization step names both the callable parameter and the
	source argument. An omitted optional parameter has no source argument, but
	still owns one stable plan-local carrier slot. The final invocation step
	deliberately owns neither.
**/
typedef OcamlCallEvaluationStep = {
	final kind:OcamlCallEvaluationStepKind;
	final argumentIndex:Null<Int>;
	final sourceArgumentIndex:Null<Int>;
	final slotId:Null<String>;
}

/**
	One directional argument or result crossing fixed by the typed call contract.

	Arguments flow from the source-expression representation into the callable
	boundary. Results flow from the callable boundary into the call-expression
	representation. A callable definition's result instead flows from its final
	straight-line body value into the exported callable carrier. Program-wide
	declarations use identical sides because they describe only that carrier.
**/
typedef OcamlCallValuePlan = {
	final index:Int;
	final parameterOptional:Bool;
	final inputSemanticTypeId:String;
	final inputCarrierTypeId:String;
	final inputRepresentationId:String;
	final outputSemanticTypeId:String;
	final outputCarrierTypeId:String;
	final outputRepresentationId:String;
	final conversion:OcamlCallCarrierConversion;
	final proofId:String;
	final proofClaim:String;
}

/**
	The program-wide typed declaration shape available before module emission.

	It deliberately excludes body identity. A later callable boundary must match
	this declaration and also prove which final function body implements it.
**/
typedef OcamlCallableDeclarationPlan = {
	final id:String;
	final calleeId:String;
	final sourceModuleId:String;
	final sourceTypeName:String;
	final sourceFieldName:String;
	final kind:OcamlCallKind;
	final receiver:Null<OcamlCallValuePlan>;
	final arguments:Array<OcamlCallValuePlan>;
	final resultKind:OcamlCallResultKind;
	final result:Null<OcamlCallValuePlan>;
	final profileEligibility:Array<String>;
	final reason:String;
	final proofId:String;
	final proofClaim:String;
	final programRevision:String;
	final pipelineRevision:String;
}

/**
	The callable shape exported by one exact final Haxe function body.

	This boundary deliberately admits ordinary static methods whose required
	arguments independently use the closed exact `Int`, `Bool`, `Null<Int>`,
	`Null<Bool>`, `String`, or `Dynamic` representation matrix. A result either
	uses the same represented matrix or explicitly records effect-only Haxe
	`Void`, which has no carrier. `Dynamic` always crosses as its already-sealed
	`Obj.t`; concrete-to-Dynamic boxing belongs to the local occurrence that
	created that carrier. The argument vector may be empty; OCaml's synthetic
	unit parameter is added mechanically at the syntax boundary and is not
	represented as a Haxe argument. Later call kinds extend the planner rather
	than teaching the syntax builder new rules.
**/
typedef OcamlCallableBoundaryPlan = {
	final id:String;
	final calleeId:String;
	final sourceModuleId:String;
	final sourceTypeName:String;
	final sourceFieldName:String;
	final kind:OcamlCallKind;
	final receiver:Null<OcamlCallValuePlan>;
	final arguments:Array<OcamlCallValuePlan>;
	final resultKind:OcamlCallResultKind;
	final result:Null<OcamlCallValuePlan>;
	final profileEligibility:Array<String>;
	final reason:String;
	final proofId:String;
	final proofClaim:String;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
}

/** One typed call occurrence sealed against its exact caller body. */
typedef OcamlCallDecision = {
	final id:String;
	final source:OcamlLoweredSourceSpan;
	final calleeId:String;
	final sourceModuleId:String;
	final sourceTypeName:String;
	final sourceFieldName:String;
	final kind:OcamlCallKind;
	final receiver:Null<OcamlCallValuePlan>;
	final arguments:Array<OcamlCallValuePlan>;
	final resultKind:OcamlCallResultKind;
	final result:Null<OcamlCallValuePlan>;
	final evaluationSchedule:Array<OcamlCallEvaluationStep>;
	final profileEligibility:Array<String>;
	final reason:String;
	final proofId:String;
	final proofClaim:String;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
	final ?standardArrayTarget:OcamlStandardArrayCallTarget;
	final ?standardIMapTarget:OcamlStandardIMapCallTarget;
	final ?structuralIteratorTarget:OcamlStructuralIteratorCallTarget;
}

/**
	Immutable call inventory for one final function body.

	The syntax builder can resolve an admitted occurrence by its normalized source
	span and exact typed callee shape, but it cannot add, replace, or infer a
	decision. The callee check matters because Haxe can assign the same source
	span to a nested call and its enclosing call. A source-only lookup could
	therefore apply a zero-argument plan to a different call that has arguments.
	Distinct typed callees may share a source span; two plans that could match the
	same typed occurrence are rejected during construction.
**/
class OcamlCallPlan {
	public static inline final DIRECT_STATIC_SIGNATURE_PROOF_ID = "direct-static-representation-signature-v3";
	public static inline final DIRECT_INSTANCE_SIGNATURE_PROOF_ID = "direct-instance-receiver-signature-v1";
	public static inline final DIRECT_CONSTRUCTOR_SIGNATURE_PROOF_ID = "direct-constructor-nominal-result-v1";
	public static inline final FUNCTION_VALUE_SIGNATURE_PROOF_ID_PREFIX = "typed-function-value-signature-matrix-v1:";

	final ordered:Array<OcamlCallDecision>;
	final bySourceKey:Map<String, Array<OcamlCallDecision>> = [];
	final runtimeUsesByCallId:Map<String, OcamlCallRuntimeUsePlan> = [];

	public final revision:String;

	public function new(decisions:Array<OcamlCallDecision>) {
		final sorted = decisions.map(copyDecision);
		sorted.sort((left, right) -> Reflect.compare(left.id, right.id));
		final normalized:Array<OcamlCallDecision> = [];
		for (decision in sorted) {
			final key = sourceKey(decision.source);
			final candidates = bySourceKey.get(key) ?? [];
			final exact = Lambda.find(candidates, existing -> existing.id == decision.id);
			if (exact != null) {
				if (decisionFingerprint(exact) != decisionFingerprint(decision))
					throw 'reflaxe.ocaml [ocaml-call:conflicting-source-occurrence]: call identity "${decision.id}" selects two different plans';
				continue;
			}
			if (Lambda.exists(candidates,
				existing -> existing.kind == decision.kind
					&& existing.calleeId == decision.calleeId
					&& suppliedArgumentCountForDecision(existing) == suppliedArgumentCountForDecision(decision))) {
				throw 'reflaxe.ocaml [ocaml-call:duplicate-source-occurrence]: more than one admitted call can match ${decision.kind}/${decision.calleeId} at source occurrence "$key"';
			}
			candidates.push(copyDecision(decision));
			bySourceKey.set(key, candidates);
			normalized.push(copyDecision(decision));
			final runtimeUsePlan = OcamlCallRuntimeUseContract.forCall(decision);
			if (runtimeUsePlan != null)
				runtimeUsesByCallId.set(decision.id, OcamlCallRuntimeUseContract.copy(runtimeUsePlan));
		}
		ordered = normalized;
		revision = "sha256:" + Sha256.encode(ordered.map(decisionFingerprint).join("\n"));
	}

	/** Returns one admitted call by its exact final-body source occurrence. */
	public function decisionFor(expression:TypedExpr):Null<OcamlCallDecision> {
		final candidates = bySourceKey.get(sourceKey(OcamlLoweredOrigin.sourceSpan(expression.pos))) ?? [];
		final matching = candidates.filter(decision -> matchesTypedOccurrence(decision, expression));
		if (matching.length > 1)
			throw 'reflaxe.ocaml [ocaml-call:ambiguous-source-occurrence]: ${matching.length} sealed calls match one typed occurrence at ${sourceKey(OcamlLoweredOrigin.sourceSpan(expression.pos))}';
		return matching.length == 0 ? null : copyDecision(matching[0]);
	}

	static function matchesTypedOccurrence(decision:OcamlCallDecision, expression:TypedExpr):Bool {
		return switch (expression.expr) {
			case TNew(classRef, parameters, arguments) if (decision.kind == OcamlCallKind.DirectHaxeConstructor):
				parameters.length == 0
				&& arguments.length == suppliedArgumentCount(decision.arguments)
				&& classRef.get().constructor != null
				&& OcamlCallPlanner.calleeId(classRef.get(), classRef.get().constructor.get()) == decision.calleeId;
			case TCall({expr: TField(_, FStatic(classRef, fieldRef))}, arguments): arguments.length == suppliedArgumentCount(decision.arguments) && OcamlCallPlanner.calleeId(classRef.get(),
					fieldRef.get()) == decision.calleeId;
			case TCall({expr: TField(_, FInstance(classRef, _, fieldRef))}, arguments) if (decision.kind == OcamlCallKind.DirectInstanceHaxeMethod):
				arguments.length == suppliedArgumentCount(decision.arguments)
				&& OcamlCallPlanner.calleeId(classRef.get(), fieldRef.get()) == decision.calleeId;
			case TCall({expr: TField(receiver, FInstance(classRef, parameters, fieldRef))}, arguments)
				if (decision.kind == OcamlCallKind.StandardArrayMethod && decision.standardArrayTarget != null): OcamlStandardArrayCallContract.matches(decision.standardArrayTarget,
					classRef.get(), parameters, fieldRef.get(), receiver, arguments,
					expression.t) && OcamlCallPlanner.calleeId(classRef.get(), fieldRef.get()) == decision.calleeId;
			case TCall({expr: TField(receiver, FInstance(classRef, parameters, fieldRef))}, arguments)
				if (decision.kind == OcamlCallKind.StandardIMapMethod && decision.standardIMapTarget != null): OcamlStandardIMapCallContract.matches(decision.standardIMapTarget,
					classRef.get(), parameters, fieldRef.get(), receiver, arguments,
					expression.t) && OcamlCallPlanner.calleeId(classRef.get(), fieldRef.get()) == decision.calleeId;
			case TCall({expr: TField(receiver, FAnon(fieldRef))}, arguments)
				if (decision.kind == OcamlCallKind.StructuralIteratorMethod
					&& decision.structuralIteratorTarget != null): OcamlStructuralIteratorCallContract.matches(decision.structuralIteratorTarget, receiver,
					fieldRef.get(), arguments, expression.t);
			case TCall(callee, arguments) if (decision.kind == OcamlCallKind.TypedFunctionValue): final binding:OcamlFunctionPlanBinding = {
					functionId: decision.functionId,
					programRevision: decision.programRevision,
					bodyRevision: decision.bodyRevision,
					pipelineRevision: decision.pipelineRevision
				}; final signatureId = OcamlCallPlanner.functionValueSignatureIdForDecision(callee, arguments, expression.t,
					decision.result); signatureId != null && OcamlCallPlanner.functionValueCalleeId(callee, binding, signatureId) == decision.calleeId;
			case _:
				false;
		}
	}

	static function suppliedArgumentCount(arguments:Array<OcamlCallValuePlan>):Int {
		var count = 0;
		for (argument in arguments) {
			if (!isOmittedConversion(argument.conversion)) {
				count += 1;
			}
		}
		return count;
	}

	static function suppliedArgumentCountForDecision(decision:OcamlCallDecision):Int {
		if (decision.standardArrayTarget != null)
			return decision.standardArrayTarget.argumentSemanticTypeIds.length;
		if (decision.standardIMapTarget != null)
			return decision.standardIMapTarget.argumentSemanticTypeIds.length;
		return decision.structuralIteratorTarget != null ? 0 : suppliedArgumentCount(decision.arguments);
	}

	/** Returns whether a crossing materializes an omitted source argument. */
	public static function isOmittedConversion(conversion:OcamlCallCarrierConversion):Bool {
		return conversion == OcamlCallCarrierConversion.MaterializeOmittedNullableInt
			|| conversion == OcamlCallCarrierConversion.MaterializeOmittedNullableBool
			|| conversion == OcamlCallCarrierConversion.MaterializeOmittedString
			|| conversion == OcamlCallCarrierConversion.MaterializeOmittedDynamic;
	}

	/** Returns whether one exact argument preserves the sealed `Null<Bool>` carrier. */
	public function preservesNullableBoolArgument(expression:TypedExpr, argumentIndex:Int):Bool {
		final decision = decisionFor(expression);
		if (decision == null || argumentIndex < 0 || argumentIndex >= decision.arguments.length)
			return false;
		final argument = decision.arguments[argumentIndex];
		return argument.inputSemanticTypeId == "Null<Bool>"
			&& argument.inputCarrierTypeId == "Obj.t"
			&& argument.outputSemanticTypeId == "Null<Bool>"
			&& argument.outputCarrierTypeId == "Obj.t"
			&& argument.conversion == OcamlCallCarrierConversion.PreserveNullableBoolCarrier;
	}

	/** Returns whether one exact call produces the sealed `Null<Bool>` carrier. */
	public function producesNullableBool(expression:TypedExpr):Bool {
		final decision = decisionFor(expression);
		if (decision != null && decision.standardIMapTarget != null)
			return decision.standardIMapTarget.resultSemanticTypeId == "Null<Bool>";
		return decision != null
			&& decision.resultKind == OcamlCallResultKind.Value
			&& decision.result != null
			&& decision.result.inputSemanticTypeId == "Null<Bool>"
			&& decision.result.inputCarrierTypeId == "Obj.t"
			&& decision.result.outputSemanticTypeId == "Null<Bool>"
			&& decision.result.outputCarrierTypeId == "Obj.t"
			&& decision.result.conversion == OcamlCallCarrierConversion.Identity;
	}

	/** Returns whether one exact call produces the sealed core String carrier. */
	public function producesExactString(expression:TypedExpr):Bool {
		final decision = decisionFor(expression);
		if (decision != null && decision.standardIMapTarget != null)
			return decision.standardIMapTarget.resultSemanticTypeId == "String";
		return decision != null
			&& decision.resultKind == OcamlCallResultKind.Value
			&& decision.result != null
			&& decision.result.inputSemanticTypeId == "String"
			&& decision.result.inputCarrierTypeId == "string"
			&& decision.result.inputRepresentationId == "representation:String:internal-value"
			&& decision.result.outputSemanticTypeId == "String"
			&& decision.result.outputCarrierTypeId == "string"
			&& decision.result.outputRepresentationId == "representation:String:internal-value"
			&& decision.result.conversion == OcamlCallCarrierConversion.Identity;
	}

	/** Returns every admitted call in deterministic identity order. */
	public function decisions():Array<OcamlCallDecision> {
		return ordered.map(copyDecision);
	}

	/**
		Returns the private runtime uses owned by one exact call occurrence.

		`null` means that the call uses direct OCaml carriers only. It is not
		permission for syntax to infer a helper from a value type.
	**/
	public function runtimeUsePlanFor(callId:String):Null<OcamlCallRuntimeUsePlan> {
		final plan = runtimeUsesByCallId.get(callId);
		return plan == null ? null : OcamlCallRuntimeUseContract.copy(plan);
	}

	public static function sourceKey(source:OcamlLoweredSourceSpan):String {
		return source.file + ":" + source.min + ":" + source.max;
	}

	static function decisionFingerprint(decision:OcamlCallDecision):String {
		return [
			decision.id,
			decision.calleeId,
			(decision.kind : String),
			decision.receiver == null ? "" : valueFingerprint(decision.receiver),
			decision.arguments.map(valueFingerprint).join(","),
			resultFingerprint(decision.resultKind, decision.result),
			decision.evaluationSchedule.map(evaluationStepFingerprint).join(","),
			decision.standardArrayTarget == null ? "" : OcamlStandardArrayCallContract.fingerprint(decision.standardArrayTarget),
			decision.standardIMapTarget == null ? "" : OcamlStandardIMapCallContract.fingerprint(decision.standardIMapTarget),
			decision.structuralIteratorTarget == null ? "" : OcamlStructuralIteratorCallContract.fingerprint(decision.structuralIteratorTarget),
			decision.functionId,
			decision.programRevision,
			decision.bodyRevision,
			decision.pipelineRevision
		].join("|");
	}

	static function resultFingerprint(kind:OcamlCallResultKind, value:Null<OcamlCallValuePlan>):String {
		return (kind : String) + ":" + (value == null ? "" : valueFingerprint(value));
	}

	static function valueFingerprint(value:OcamlCallValuePlan):String {
		return [
			Std.string(value.index),
			Std.string(value.parameterOptional),
			value.inputSemanticTypeId,
			value.inputCarrierTypeId,
			value.inputRepresentationId,
			value.outputSemanticTypeId,
			value.outputCarrierTypeId,
			value.outputRepresentationId,
			(value.conversion : String),
			value.proofId,
			value.proofClaim
		].join(":");
	}

	static function evaluationStepFingerprint(step:OcamlCallEvaluationStep):String {
		return [
			(step.kind : String),
			step.argumentIndex == null ? "" : Std.string(step.argumentIndex),
			step.sourceArgumentIndex == null ? "" : Std.string(step.sourceArgumentIndex),
			step.slotId ?? ""
		].join(":");
	}

	static function copyDecision(decision:OcamlCallDecision):OcamlCallDecision {
		return {
			id: decision.id,
			source: copySource(decision.source),
			calleeId: decision.calleeId,
			sourceModuleId: decision.sourceModuleId,
			sourceTypeName: decision.sourceTypeName,
			sourceFieldName: decision.sourceFieldName,
			kind: decision.kind,
			receiver: copyOptionalValue(decision.receiver),
			arguments: decision.arguments.map(copyValue),
			resultKind: decision.resultKind,
			result: copyOptionalValue(decision.result),
			evaluationSchedule: decision.evaluationSchedule.map(copyEvaluationStep),
			profileEligibility: decision.profileEligibility.copy(),
			reason: decision.reason,
			proofId: decision.proofId,
			proofClaim: decision.proofClaim,
			functionId: decision.functionId,
			programRevision: decision.programRevision,
			bodyRevision: decision.bodyRevision,
			pipelineRevision: decision.pipelineRevision,
			standardArrayTarget: decision.standardArrayTarget == null ? null : OcamlStandardArrayCallContract.copy(decision.standardArrayTarget),
			standardIMapTarget: decision.standardIMapTarget == null ? null : OcamlStandardIMapCallContract.copy(decision.standardIMapTarget),
			structuralIteratorTarget: decision.structuralIteratorTarget == null ? null : OcamlStructuralIteratorCallContract.copy(decision.structuralIteratorTarget)
		};
	}

	public static function copyBoundary(boundary:OcamlCallableBoundaryPlan):OcamlCallableBoundaryPlan {
		return {
			id: boundary.id,
			calleeId: boundary.calleeId,
			sourceModuleId: boundary.sourceModuleId,
			sourceTypeName: boundary.sourceTypeName,
			sourceFieldName: boundary.sourceFieldName,
			kind: boundary.kind,
			receiver: copyOptionalValue(boundary.receiver),
			arguments: boundary.arguments.map(copyValue),
			resultKind: boundary.resultKind,
			result: copyOptionalValue(boundary.result),
			profileEligibility: boundary.profileEligibility.copy(),
			reason: boundary.reason,
			proofId: boundary.proofId,
			proofClaim: boundary.proofClaim,
			functionId: boundary.functionId,
			programRevision: boundary.programRevision,
			bodyRevision: boundary.bodyRevision,
			pipelineRevision: boundary.pipelineRevision
		};
	}

	public static function copyDeclaration(declaration:OcamlCallableDeclarationPlan):OcamlCallableDeclarationPlan {
		return {
			id: declaration.id,
			calleeId: declaration.calleeId,
			sourceModuleId: declaration.sourceModuleId,
			sourceTypeName: declaration.sourceTypeName,
			sourceFieldName: declaration.sourceFieldName,
			kind: declaration.kind,
			receiver: copyOptionalValue(declaration.receiver),
			arguments: declaration.arguments.map(copyValue),
			resultKind: declaration.resultKind,
			result: copyOptionalValue(declaration.result),
			profileEligibility: declaration.profileEligibility.copy(),
			reason: declaration.reason,
			proofId: declaration.proofId,
			proofClaim: declaration.proofClaim,
			programRevision: declaration.programRevision,
			pipelineRevision: declaration.pipelineRevision
		};
	}

	public static function copyOptionalValue(value:Null<OcamlCallValuePlan>):Null<OcamlCallValuePlan> {
		return value == null ? null : copyValue(value);
	}

	public static function copyValue(value:OcamlCallValuePlan):OcamlCallValuePlan {
		return {
			index: value.index,
			parameterOptional: value.parameterOptional,
			inputSemanticTypeId: value.inputSemanticTypeId,
			inputCarrierTypeId: value.inputCarrierTypeId,
			inputRepresentationId: value.inputRepresentationId,
			outputSemanticTypeId: value.outputSemanticTypeId,
			outputCarrierTypeId: value.outputCarrierTypeId,
			outputRepresentationId: value.outputRepresentationId,
			conversion: value.conversion,
			proofId: value.proofId,
			proofClaim: value.proofClaim
		};
	}

	public static function copyEvaluationStep(step:OcamlCallEvaluationStep):OcamlCallEvaluationStep {
		return {
			kind: step.kind,
			argumentIndex: step.argumentIndex,
			sourceArgumentIndex: step.sourceArgumentIndex,
			slotId: step.slotId
		};
	}

	/** Returns whether two values describe the same complete sealed crossing. */
	public static function sameValue(left:OcamlCallValuePlan, right:OcamlCallValuePlan):Bool {
		return left.index == right.index
			&& left.parameterOptional == right.parameterOptional
			&& left.inputSemanticTypeId == right.inputSemanticTypeId
			&& left.inputCarrierTypeId == right.inputCarrierTypeId
			&& left.inputRepresentationId == right.inputRepresentationId
			&& left.outputSemanticTypeId == right.outputSemanticTypeId
			&& left.outputCarrierTypeId == right.outputCarrierTypeId
			&& left.outputRepresentationId == right.outputRepresentationId
			&& left.conversion == right.conversion
			&& left.proofId == right.proofId
			&& left.proofClaim == right.proofClaim;
	}

	/**
		Returns whether a call occurrence agrees with one callable carrier.

		For an argument, the call's output is the value entering the function. For
		a result, the callable boundary's output is the value entering the call
		occurrence.
	**/
	public static function sameCallableBoundary(callValue:OcamlCallValuePlan, boundaryValue:OcamlCallValuePlan, isResult:Bool):Bool {
		return callValue.index == boundaryValue.index
			&& callValue.parameterOptional == boundaryValue.parameterOptional
			&& (isResult ? (callValue.inputSemanticTypeId == boundaryValue.outputSemanticTypeId
				&& callValue.inputCarrierTypeId == boundaryValue.outputCarrierTypeId
				&& callValue.inputRepresentationId == boundaryValue.outputRepresentationId) : (callValue.outputSemanticTypeId == boundaryValue.inputSemanticTypeId
					&& callValue.outputCarrierTypeId == boundaryValue.inputCarrierTypeId
					&& callValue.outputRepresentationId == boundaryValue.inputRepresentationId));
	}

	/** Returns whether a call and callable agree on value versus effect-only result. */
	public static function sameCallResult(callKind:OcamlCallResultKind, callValue:Null<OcamlCallValuePlan>, boundaryKind:OcamlCallResultKind,
			boundaryValue:Null<OcamlCallValuePlan>):Bool {
		if (callKind != boundaryKind)
			return false;
		return switch (callKind) {
			case Value: callValue != null && boundaryValue != null && sameCallableBoundary(callValue, boundaryValue, true);
			case EffectOnlyVoid: callValue == null && boundaryValue == null;
			case _:
				false;
		}
	}

	/** Returns whether a callable definition exports its declared result carrier. */
	public static function sameBoundaryDeclaration(boundaryValue:OcamlCallValuePlan, declarationValue:OcamlCallValuePlan):Bool {
		return boundaryValue.index == declarationValue.index
			&& boundaryValue.parameterOptional == declarationValue.parameterOptional
			&& boundaryValue.outputSemanticTypeId == declarationValue.inputSemanticTypeId
			&& boundaryValue.outputCarrierTypeId == declarationValue.inputCarrierTypeId
			&& boundaryValue.outputRepresentationId == declarationValue.inputRepresentationId;
	}

	/** Returns whether a callable definition and declaration agree on result shape. */
	public static function sameDeclaredResult(boundaryKind:OcamlCallResultKind, boundaryValue:Null<OcamlCallValuePlan>, declarationKind:OcamlCallResultKind,
			declarationValue:Null<OcamlCallValuePlan>):Bool {
		if (boundaryKind != declarationKind)
			return false;
		return switch (boundaryKind) {
			case Value: boundaryValue != null && declarationValue != null && sameBoundaryDeclaration(boundaryValue, declarationValue);
			case EffectOnlyVoid: boundaryValue == null && declarationValue == null;
			case _:
				false;
		}
	}

	/** Rejects a corrupted value outside the closed typed-call carrier families. */
	public static function requireCallValue(value:OcamlCallValuePlan, expectedIndex:Int, owner:String):Void {
		if (value.index != expectedIndex || value.proofId.length == 0 || value.proofClaim.length == 0)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has an invalid index or empty conversion proof';
		switch (value.conversion) {
			case Identity:
				if (!sameRepresentationSides(value)
					|| (!isExactIntSide(value.inputSemanticTypeId, value.inputCarrierTypeId, value.inputRepresentationId)
						&& !isExactBoolSide(value.inputSemanticTypeId, value.inputCarrierTypeId, value.inputRepresentationId)
						&& !isExactNullIntSide(value.inputSemanticTypeId, value.inputCarrierTypeId, value.inputRepresentationId)
						&& !isExactNullBoolSide(value.inputSemanticTypeId, value.inputCarrierTypeId, value.inputRepresentationId)
						&& !isExactStringSide(value.inputSemanticTypeId, value.inputCarrierTypeId, value.inputRepresentationId)
						&& !isExactDynamicSide(value.inputSemanticTypeId, value.inputCarrierTypeId, value.inputRepresentationId)
						&& !(expectedIndex < 0
							&& isNominalInternalSide(value.inputSemanticTypeId, value.inputCarrierTypeId, value.inputRepresentationId)))
					|| value.proofId != "identity-call-carrier-v1") {
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has an invalid identity crossing';
				}
			case PreserveNullableIntCarrier:
				if (!sameRepresentationSides(value)
					|| !isExactNullIntSide(value.inputSemanticTypeId, value.inputCarrierTypeId, value.inputRepresentationId)
					|| value.proofId != "nullable-int-call-carrier-preserve-v1") {
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner must preserve one exact Null<Int> Obj.t carrier';
				}
			case BoxExactIntToNullableInt:
				if (!isExactIntSide(value.inputSemanticTypeId, value.inputCarrierTypeId, value.inputRepresentationId)
					|| !isExactNullIntSide(value.outputSemanticTypeId, value.outputCarrierTypeId, value.outputRepresentationId)
					|| value.proofId != "nullable-int-call-box-v1") {
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner must box exact Int -> int once into exact Null<Int> -> Obj.t';
				}
			case CheckedUnboxNullableInt:
				if (expectedIndex < -1
					|| value.parameterOptional
					|| !isExactNullIntSide(value.inputSemanticTypeId, value.inputCarrierTypeId, value.inputRepresentationId)
					|| !isExactIntSide(value.outputSemanticTypeId, value.outputCarrierTypeId, value.outputRepresentationId)
					|| value.proofId != "nullable-int-call-checked-unbox-v1") {
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner must check exact Null<Int> -> Obj.t once into exact Int -> int at a required argument or callable result';
				}
			case PreserveNullableBoolCarrier:
				if (!sameRepresentationSides(value)
					|| !isExactNullBoolSide(value.inputSemanticTypeId, value.inputCarrierTypeId, value.inputRepresentationId)
					|| value.proofId != "nullable-bool-call-carrier-preserve-v1") {
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner must preserve one exact Null<Bool> Obj.t carrier';
				}
			case PreserveDynamicCarrier:
				if (!sameRepresentationSides(value)
					|| !isExactDynamicSide(value.inputSemanticTypeId, value.inputCarrierTypeId, value.inputRepresentationId)
					|| value.proofId != "dynamic-call-carrier-preserve-v1") {
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner must preserve one exact Dynamic Obj.t carrier';
				}
			case BoxConcreteToDynamic:
				if (expectedIndex < 0
					|| !isConcreteDynamicInputSide(value.inputSemanticTypeId, value.inputCarrierTypeId, value.inputRepresentationId)
					|| !isExactDynamicSide(value.outputSemanticTypeId, value.outputCarrierTypeId, value.outputRepresentationId)
					|| value.proofId != "dynamic-call-box-concrete-v1") {
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner must box one admitted non-Bool value into the exact Dynamic Obj.t carrier';
				}
			case BoxExactBoolToDynamic:
				if (expectedIndex < 0
					|| !isExactBoolSide(value.inputSemanticTypeId, value.inputCarrierTypeId, value.inputRepresentationId)
					|| !isExactDynamicSide(value.outputSemanticTypeId, value.outputCarrierTypeId, value.outputRepresentationId)
					|| value.proofId != "dynamic-call-box-bool-v1") {
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner must box exact Bool through the distinguishable runtime Bool carrier before Dynamic';
				}
			case BoxExactBoolToNullableBool:
				if (!isExactBoolSide(value.inputSemanticTypeId, value.inputCarrierTypeId, value.inputRepresentationId)
					|| !isExactNullBoolSide(value.outputSemanticTypeId, value.outputCarrierTypeId, value.outputRepresentationId)
					|| value.proofId != "nullable-bool-call-box-v1") {
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner must box exact Bool -> bool once into exact Null<Bool> -> Obj.t';
				}
			case MaterializeOmittedNullableInt:
				if (!value.parameterOptional
					|| !sameRepresentationSides(value)
					|| !isExactNullIntSide(value.inputSemanticTypeId, value.inputCarrierTypeId, value.inputRepresentationId)
					|| value.proofId != "omitted-nullable-int-call-materialization-v1") {
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner must materialize one omitted optional Null<Int> carrier';
				}
			case MaterializeOmittedNullableBool:
				if (!value.parameterOptional
					|| !sameRepresentationSides(value)
					|| !isExactNullBoolSide(value.inputSemanticTypeId, value.inputCarrierTypeId, value.inputRepresentationId)
					|| value.proofId != "omitted-nullable-bool-call-materialization-v1") {
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner must materialize one omitted optional Null<Bool> carrier';
				}
			case MaterializeOmittedString:
				if (!value.parameterOptional
					|| !sameRepresentationSides(value)
					|| !isExactStringSide(value.inputSemanticTypeId, value.inputCarrierTypeId, value.inputRepresentationId)
					|| value.proofId != "omitted-string-call-materialization-v1") {
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner must materialize one omitted optional String carrier';
				}
			case MaterializeOmittedDynamic:
				if (!value.parameterOptional
					|| !sameRepresentationSides(value)
					|| !isExactDynamicSide(value.inputSemanticTypeId, value.inputCarrierTypeId, value.inputRepresentationId)
					|| value.proofId != "omitted-dynamic-call-materialization-v1") {
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner must materialize one omitted optional Dynamic carrier';
				}
			case MaterializeExplicitNullString:
				if (!value.parameterOptional
					|| !sameRepresentationSides(value)
					|| !isExactStringSide(value.inputSemanticTypeId, value.inputCarrierTypeId, value.inputRepresentationId)
					|| value.proofId != "explicit-null-string-call-materialization-v1") {
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner must materialize one explicitly supplied null String carrier';
				}
			case MaterializeExplicitNullDynamic:
				if (!value.parameterOptional
					|| !sameRepresentationSides(value)
					|| !isExactDynamicSide(value.inputSemanticTypeId, value.inputCarrierTypeId, value.inputRepresentationId)
					|| value.proofId != "explicit-null-dynamic-call-materialization-v1") {
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner must materialize one explicitly supplied null Dynamic carrier';
				}
			case _:
				throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has unsupported conversion "${value.conversion}"';
		}
	}

	/** Rejects a corrupted program-wide declaration before it enters the catalog. */
	public static function requireCallableDeclarationPlan(declaration:OcamlCallableDeclarationPlan):Void {
		if (declaration.kind != OcamlCallKind.DirectStaticHaxeMethod
			&& declaration.kind != OcamlCallKind.DirectInstanceHaxeMethod
			&& declaration.kind != OcamlCallKind.DirectHaxeConstructor)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: callable declaration "${declaration.id}" cannot describe a computed function value';
		requireCallCommon(declaration.calleeId, declaration.sourceModuleId, declaration.sourceTypeName, declaration.sourceFieldName, declaration.kind,
			declaration.arguments, declaration.resultKind, declaration.result, declaration.profileEligibility, declaration.reason, declaration.proofId,
			declaration.proofClaim, declaration.programRevision, declaration.pipelineRevision, 'callable declaration "${declaration.id}"',
			declaration.receiver);
		if (declaration.receiver != null)
			requireCallValue(declaration.receiver, -2, 'callable declaration "${declaration.id}" receiver');
		if (!Lambda.foreach(declaration.arguments, value -> value.conversion == OcamlCallCarrierConversion.Identity)
			|| (declaration.receiver != null && declaration.receiver.conversion != OcamlCallCarrierConversion.Identity)
			|| (declaration.result != null && declaration.result.conversion != OcamlCallCarrierConversion.Identity)) {
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: callable declaration "${declaration.id}" must use identity carrier records';
		}
	}

	/** Rejects a corrupted call occurrence before syntax can consume it. */
	public static function requireCall(call:OcamlCallDecision):Void {
		if (call.kind == OcamlCallKind.StandardArrayMethod) {
			requireStandardArrayCall(call);
			return;
		}
		if (call.kind == OcamlCallKind.StandardIMapMethod) {
			requireStandardIMapCall(call);
			return;
		}
		if (call.kind == OcamlCallKind.StructuralIteratorMethod) {
			requireStructuralIteratorCall(call);
			return;
		}
		if (call.standardArrayTarget != null)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: non-Array call "${call.id}" owns a standard Array target';
		if (call.standardIMapTarget != null)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: non-IMap call "${call.id}" owns a standard IMap target';
		if (call.structuralIteratorTarget != null)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: ordinary call "${call.id}" owns a structural Iterator target';
		requireCallCommon(call.calleeId, call.sourceModuleId, call.sourceTypeName, call.sourceFieldName, call.kind, call.arguments, call.resultKind,
			call.result, call.profileEligibility, call.reason, call.proofId, call.proofClaim, call.programRevision, call.pipelineRevision,
			'call "${call.id}"', call.receiver);
		if (call.receiver != null) {
			requireCallValue(call.receiver, -2, 'call "${call.id}" receiver');
			if (call.receiver.conversion != OcamlCallCarrierConversion.Identity)
				throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: call "${call.id}" must preserve its exact receiver carrier';
		}
		if (call.result != null && call.result.conversion != OcamlCallCarrierConversion.Identity)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: call "${call.id}" must preserve its exact declared result carrier';
		for (argument in call.arguments) {
			if ((isNullableSemanticType(argument.outputSemanticTypeId) || argument.outputSemanticTypeId == "Dynamic")
				&& argument.conversion == OcamlCallCarrierConversion.Identity) {
				throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: call "${call.id}" must explicitly preserve an existing ${argument.outputSemanticTypeId} carrier or box its exact primitive';
			}
		}
		if (call.functionId.length == 0 || call.bodyRevision.length == 0)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: call "${call.id}" has an empty caller or body revision';
		if (call.source.file.length == 0 || call.source.min < 0 || call.source.max < call.source.min)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: call "${call.id}" has an invalid source occurrence';
		final hasMaterializedCallee = call.kind == OcamlCallKind.TypedFunctionValue;
		final hasMaterializedReceiver = call.kind == OcamlCallKind.DirectInstanceHaxeMethod;
		final scheduleOffset = (hasMaterializedCallee ? 1 : 0) + (hasMaterializedReceiver ? 1 : 0);
		if (call.evaluationSchedule.length != call.arguments.length + scheduleOffset + 1)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: call "${call.id}" has an invalid evaluation schedule';
		if (hasMaterializedCallee) {
			final callee = call.evaluationSchedule[0];
			if (callee.kind != OcamlCallEvaluationStepKind.MaterializeCallee
				|| callee.argumentIndex != null
				|| callee.sourceArgumentIndex != null
				|| callee.slotId != calleeSlotId(call.id)) {
				throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: call "${call.id}" has an invalid callee materialization';
			}
		}
		if (hasMaterializedReceiver) {
			final receiver = call.evaluationSchedule[0];
			if (call.receiver == null
				|| receiver.kind != OcamlCallEvaluationStepKind.MaterializeReceiver
				|| receiver.argumentIndex != null
				|| receiver.sourceArgumentIndex != null
				|| receiver.slotId != receiverSlotId(call.id)) {
				throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: call "${call.id}" has an invalid receiver materialization';
			}
		}
		var sourceArgumentIndex = 0;
		for (index in 0...call.arguments.length) {
			final argument = call.arguments[index];
			final step = call.evaluationSchedule[index + scheduleOffset];
			final omitted = isOmittedConversion(argument.conversion);
			final expectedKind = omitted ? OcamlCallEvaluationStepKind.MaterializeOmittedArgument : OcamlCallEvaluationStepKind.MaterializeArgument;
			final expectedSourceIndex:Null<Int> = omitted ? null : sourceArgumentIndex++;
			if (step.kind != expectedKind
				|| step.argumentIndex != index
				|| step.sourceArgumentIndex != expectedSourceIndex
				|| step.slotId != argumentSlotId(call.id, index)) {
				throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: call "${call.id}" has an invalid argument materialization at schedule index $index';
			}
		}
		final invocation = call.evaluationSchedule[call.evaluationSchedule.length - 1];
		if (invocation.kind != OcamlCallEvaluationStepKind.InvokeCallee
			|| invocation.argumentIndex != null
			|| invocation.sourceArgumentIndex != null
			|| invocation.slotId != null)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: call "${call.id}" has an invalid invocation step';
	}

	/** Rejects a corrupted standard Array call before syntax can consume it. */
	static function requireStandardArrayCall(call:OcamlCallDecision):Void {
		final target = call.standardArrayTarget;
		if (target == null)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: standard Array call "${call.id}" has no typed target operation';
		OcamlStandardArrayCallContract.require(target);
		final expectedField = OcamlStandardArrayCallContract.sourceFieldName(target.operation);
		if (call.calleeId != 'Array|Array::$expectedField'
			|| call.sourceModuleId != "Array"
			|| call.sourceTypeName != "Array"
			|| call.sourceFieldName != expectedField
			|| call.receiver != null
			|| call.arguments.length != 0
			|| call.resultKind != standardArrayCallResultKind(target.resultKind)
			|| call.result != null
			|| call.standardIMapTarget != null
			|| call.structuralIteratorTarget != null
			|| call.proofId != OcamlStandardArrayCallContract.PROOF_ID
			|| call.proofClaim != target.proofClaim
			|| call.reason.length == 0
			|| call.functionId.length == 0
			|| call.programRevision.length == 0
			|| call.bodyRevision.length == 0
			|| call.pipelineRevision.length == 0
			|| call.source.file.length == 0
			|| call.source.min < 0
			|| call.source.max < call.source.min
			|| call.profileEligibility.length != 2
			|| call.profileEligibility[0] != "metal"
			|| call.profileEligibility[1] != "portable") {
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: standard Array call "${call.id}" has incomplete or conflicting source, proof, profile, or revision facts';
		}
		final argumentCount = target.argumentSemanticTypeIds.length;
		if (call.evaluationSchedule.length != argumentCount + 2)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: standard Array call "${call.id}" has an invalid evaluation schedule';
		final receiver = call.evaluationSchedule[0];
		if (receiver.kind != OcamlCallEvaluationStepKind.MaterializeReceiver
			|| receiver.argumentIndex != null
			|| receiver.sourceArgumentIndex != null
			|| receiver.slotId != receiverSlotId(call.id)) {
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: standard Array call "${call.id}" has an invalid receiver materialization';
		}
		for (index in 0...argumentCount) {
			final step = call.evaluationSchedule[index + 1];
			if (step.kind != OcamlCallEvaluationStepKind.MaterializeArgument
				|| step.argumentIndex != index
				|| step.sourceArgumentIndex != index
				|| step.slotId != argumentSlotId(call.id, index)) {
				throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: standard Array call "${call.id}" has an invalid argument materialization at index $index';
			}
		}
		final invocation = call.evaluationSchedule[call.evaluationSchedule.length - 1];
		if (invocation.kind != OcamlCallEvaluationStepKind.InvokeCallee
			|| invocation.argumentIndex != null
			|| invocation.sourceArgumentIndex != null
			|| invocation.slotId != null) {
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: standard Array call "${call.id}" has an invalid invocation step';
		}
	}

	/** Converts the Array-specific result fact into the shared call result kind. */
	public static function standardArrayCallResultKind(resultKind:OcamlStandardArrayResultKind):OcamlCallResultKind {
		return switch (resultKind) {
			case Value: OcamlCallResultKind.Value;
			case EffectOnlyVoid: OcamlCallResultKind.EffectOnlyVoid;
			case _: throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: unsupported standard Array result kind "$resultKind"';
		}
	}

	/**
		Rejects a corrupted standard `IMap` call before syntax can consume it.

		This call kind owns its generic carrier and result facts inside the
		specialized target plan, so it deliberately has no ordinary callable
		declaration or closed primitive `OcamlCallValuePlan` records.
	**/
	static function requireStandardIMapCall(call:OcamlCallDecision):Void {
		final target = call.standardIMapTarget;
		if (target == null)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: standard IMap call "${call.id}" has no typed target operation';
		OcamlStandardIMapCallContract.require(target);
		final expectedField = OcamlStandardIMapCallContract.sourceFieldName(target.operation);
		if (call.calleeId != 'haxe.Constraints|haxe.IMap::$expectedField'
			|| call.sourceModuleId != "haxe.Constraints"
			|| call.sourceTypeName != "IMap"
			|| call.sourceFieldName != expectedField
			|| call.receiver != null
			|| call.arguments.length != 0
			|| call.result != null
			|| call.standardArrayTarget != null
			|| call.structuralIteratorTarget != null
			|| call.proofId != OcamlStandardIMapCallContract.PROOF_ID
			|| call.proofClaim != target.proofClaim
			|| call.reason.length == 0
			|| call.functionId.length == 0
			|| call.programRevision.length == 0
			|| call.bodyRevision.length == 0
			|| call.pipelineRevision.length == 0
			|| call.source.file.length == 0
			|| call.source.min < 0
			|| call.source.max < call.source.min
			|| call.profileEligibility.length != 2
			|| call.profileEligibility[0] != "metal"
			|| call.profileEligibility[1] != "portable") {
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: standard IMap call "${call.id}" has incomplete or conflicting source, proof, profile, or revision facts';
		}
		final effectOnly = target.resultSemanticTypeId == "Void";
		if ((effectOnly && call.resultKind != OcamlCallResultKind.EffectOnlyVoid)
			|| (!effectOnly && call.resultKind != OcamlCallResultKind.Value)) {
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: standard IMap call "${call.id}" disagrees with its typed result';
		}
		final argumentCount = target.argumentSemanticTypeIds.length;
		if (call.evaluationSchedule.length != argumentCount + 2)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: standard IMap call "${call.id}" has an invalid evaluation schedule';
		final receiver = call.evaluationSchedule[0];
		if (receiver.kind != OcamlCallEvaluationStepKind.MaterializeReceiver
			|| receiver.argumentIndex != null
			|| receiver.sourceArgumentIndex != null
			|| receiver.slotId != receiverSlotId(call.id)) {
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: standard IMap call "${call.id}" has an invalid receiver materialization';
		}
		for (index in 0...argumentCount) {
			final step = call.evaluationSchedule[index + 1];
			if (step.kind != OcamlCallEvaluationStepKind.MaterializeArgument
				|| step.argumentIndex != index
				|| step.sourceArgumentIndex != index
				|| step.slotId != argumentSlotId(call.id, index)) {
				throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: standard IMap call "${call.id}" has an invalid argument materialization at index $index';
			}
		}
		final invocation = call.evaluationSchedule[call.evaluationSchedule.length - 1];
		if (invocation.kind != OcamlCallEvaluationStepKind.InvokeCallee
			|| invocation.argumentIndex != null
			|| invocation.sourceArgumentIndex != null
			|| invocation.slotId != null) {
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: standard IMap call "${call.id}" has an invalid invocation step';
		}
	}

	/**
		Rejects a corrupted direct structural Iterator call before syntax runs.

		A structural Iterator is a Haxe value with zero-argument `hasNext` and
		`next` functions, regardless of the concrete class that produced it. The
		sealed target records which `HxIterator` operation implements the direct
		call, while the evaluation schedule guarantees that the receiver is
		evaluated exactly once.
	**/
	static function requireStructuralIteratorCall(call:OcamlCallDecision):Void {
		final target = call.structuralIteratorTarget;
		if (target == null)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: structural Iterator call "${call.id}" has no typed target operation';
		OcamlStructuralIteratorCallContract.require(target);
		final expectedField = OcamlStructuralIteratorCallContract.sourceFieldName(target.operation);
		if (call.calleeId != 'haxe.Iterator|Iterator::$expectedField'
			|| call.sourceModuleId != "haxe.Iterator"
			|| call.sourceTypeName != "Iterator"
			|| call.sourceFieldName != expectedField
			|| call.receiver != null
			|| call.arguments.length != 0
			|| call.resultKind != OcamlCallResultKind.Value
			|| call.result != null
			|| call.standardArrayTarget != null
			|| call.standardIMapTarget != null
			|| call.proofId != OcamlStructuralIteratorCallContract.PROOF_ID
			|| call.proofClaim != target.proofClaim
			|| call.reason.length == 0
			|| call.functionId.length == 0
			|| call.programRevision.length == 0
			|| call.bodyRevision.length == 0
			|| call.pipelineRevision.length == 0
			|| call.source.file.length == 0
			|| call.source.min < 0
			|| call.source.max < call.source.min
			|| call.profileEligibility.length != 2
			|| call.profileEligibility[0] != "metal"
			|| call.profileEligibility[1] != "portable") {
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: structural Iterator call "${call.id}" has incomplete or conflicting source, proof, profile, or revision facts';
		}
		if (call.evaluationSchedule.length != 2)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: structural Iterator call "${call.id}" has an invalid evaluation schedule';
		final receiver = call.evaluationSchedule[0];
		if (receiver.kind != OcamlCallEvaluationStepKind.MaterializeReceiver
			|| receiver.argumentIndex != null
			|| receiver.sourceArgumentIndex != null
			|| receiver.slotId != receiverSlotId(call.id)) {
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: structural Iterator call "${call.id}" has an invalid receiver materialization';
		}
		final invocation = call.evaluationSchedule[1];
		if (invocation.kind != OcamlCallEvaluationStepKind.InvokeCallee
			|| invocation.argumentIndex != null
			|| invocation.sourceArgumentIndex != null
			|| invocation.slotId != null) {
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: structural Iterator call "${call.id}" has an invalid invocation step';
		}
	}

	/**
		Rejects a corrupted final callable boundary before publication.

		A callable boundary records the parameter and result carriers that one
		function definition accepts. Ordinary methods use a declaration identity;
		a nested function literal instead uses its parent-scoped lexical identity.
		Both forms are validated here so syntax never has to infer the signature.
	**/
	public static function requireCallableBoundary(boundary:OcamlCallableBoundaryPlan):Void {
		if (boundary.kind != OcamlCallKind.DirectStaticHaxeMethod
			&& boundary.kind != OcamlCallKind.DirectInstanceHaxeMethod
			&& boundary.kind != OcamlCallKind.DirectHaxeConstructor
			&& boundary.kind != OcamlCallKind.TypedFunctionValue)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: callable boundary "${boundary.id}" has unsupported kind ${boundary.kind}';
		requireCallCommon(boundary.calleeId, boundary.sourceModuleId, boundary.sourceTypeName, boundary.sourceFieldName, boundary.kind, boundary.arguments,
			boundary.resultKind, boundary.result, boundary.profileEligibility, boundary.reason, boundary.proofId, boundary.proofClaim,
			boundary.programRevision, boundary.pipelineRevision, 'callable boundary "${boundary.id}"', boundary.receiver);
		if (boundary.receiver != null)
			requireCallValue(boundary.receiver, -2, 'callable boundary "${boundary.id}" receiver');
		if (!Lambda.foreach(boundary.arguments, value -> value.conversion == OcamlCallCarrierConversion.Identity))
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: callable boundary "${boundary.id}" arguments must use identity carrier records';
		if (boundary.functionId.length == 0 || boundary.bodyRevision.length == 0)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: callable boundary "${boundary.id}" has an empty function or body revision';
	}

	static function requireCallCommon(calleeId:String, sourceModuleId:String, sourceTypeName:String, sourceFieldName:String, kind:OcamlCallKind,
			arguments:Array<OcamlCallValuePlan>, resultKind:OcamlCallResultKind, result:Null<OcamlCallValuePlan>, profileEligibility:Array<String>,
			reason:String, proofId:String, proofClaim:String, programRevision:String, pipelineRevision:String, owner:String,
			?receiver:Null<OcamlCallValuePlan>):Void {
		if (calleeId.length == 0)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has an empty typed callee identity';
		switch (kind) {
			case DirectStaticHaxeMethod:
				if (receiver != null)
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner assigns a receiver to a static method';
				if (sourceModuleId.length == 0 || sourceTypeName.length == 0 || sourceFieldName.length == 0)
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has an incomplete Haxe declaration identity';
				if (proofId != DIRECT_STATIC_SIGNATURE_PROOF_ID)
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has a mismatched direct-static signature proof';
			case DirectInstanceHaxeMethod:
				if (receiver == null)
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has no sealed instance receiver';
				if (!isNominalInternalSide(receiver.inputSemanticTypeId, receiver.inputCarrierTypeId, receiver.inputRepresentationId)
					|| !isNominalInternalSide(receiver.outputSemanticTypeId, receiver.outputCarrierTypeId, receiver.outputRepresentationId)) {
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has an instance receiver outside the sealed nominal carrier family';
				}
				if (sourceModuleId.length == 0 || sourceTypeName.length == 0 || sourceFieldName.length == 0)
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has an incomplete Haxe declaration identity';
				if (proofId != DIRECT_INSTANCE_SIGNATURE_PROOF_ID)
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has a mismatched direct-instance signature proof';
			case DirectHaxeConstructor:
				if (receiver != null)
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner assigns a receiver to a constructor';
				if (sourceModuleId.length == 0 || sourceTypeName.length == 0 || sourceFieldName != "new")
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has an incomplete Haxe constructor identity';
				if (proofId != DIRECT_CONSTRUCTOR_SIGNATURE_PROOF_ID)
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has a mismatched direct-constructor signature proof';
				if (arguments.length != 1 || arguments[0].parameterOptional)
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner is outside the one-required-argument constructor slice';
				if (!isExactIntSide(arguments[0].inputSemanticTypeId, arguments[0].inputCarrierTypeId, arguments[0].inputRepresentationId)
					|| !isExactIntSide(arguments[0].outputSemanticTypeId, arguments[0].outputCarrierTypeId, arguments[0].outputRepresentationId)) {
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner is outside the first exact Int constructor-argument slice';
				}
				if (resultKind != OcamlCallResultKind.Value
					|| result == null
					|| !isNominalInternalSide(result.inputSemanticTypeId, result.inputCarrierTypeId, result.inputRepresentationId)
					|| !isNominalInternalSide(result.outputSemanticTypeId, result.outputCarrierTypeId, result.outputRepresentationId)) {
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has no sealed nominal constructor result';
				}
			case TypedFunctionValue:
				if (receiver != null)
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner assigns a receiver to a function value';
				if (sourceModuleId.length != 0 || sourceTypeName.length != 0 || sourceFieldName.length != 0)
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner assigns declaration fields to a first-class function value';
				if (proofId.indexOf(FUNCTION_VALUE_SIGNATURE_PROOF_ID_PREFIX) != 0)
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has a mismatched function-value signature proof';
			case _:
				throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has unsupported kind $kind';
		}
		for (index in 0...arguments.length)
			requireCallValue(arguments[index], index, '$owner argument $index');
		var optionalSeen = false;
		for (index in 0...arguments.length) {
			final argument = arguments[index];
			if (argument.parameterOptional) {
				if (optionalSeen || index != arguments.length - 1 || !isOptionalSemanticType(argument.outputSemanticTypeId))
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has an unsupported optional-parameter shape';
				optionalSeen = true;
			}
		}
		switch (resultKind) {
			case Value:
				if (result == null)
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has a value result kind without a value crossing';
				if (result.parameterOptional)
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner result cannot be an optional parameter';
				requireCallValue(result, -1, '$owner result');
			case EffectOnlyVoid:
				if (result != null)
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner effect-only Void result cannot carry a representation or conversion';
			case _:
				throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has unsupported result kind $resultKind';
		}
		if (profileEligibility.length != 2 || profileEligibility[0] != "metal" || profileEligibility[1] != "portable")
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has an unsupported profile inventory';
		if (reason.length == 0 || proofClaim.length == 0)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has an incomplete typed-call proof';
		if (programRevision.length == 0 || pipelineRevision.length == 0)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has an empty program or pipeline revision';
		if (kind == OcamlCallKind.TypedFunctionValue) {
			requireFunctionValueSignatureMatrix(arguments, resultKind, result, proofId, owner);
		}
	}

	/**
		Validates every computed callback against the same representation matrix.

		The occurrence has no program-wide declaration, so its sealed argument
		and result records are the complete boundary. Signature-specific branches
		would let validation drift each time another callback type is admitted.
	**/
	static function requireFunctionValueSignatureMatrix(arguments:Array<OcamlCallValuePlan>, resultKind:OcamlCallResultKind, result:Null<OcamlCallValuePlan>,
			proofId:String, owner:String):Void {
		for (argument in arguments) {
			if (!isAdmittedInternalSide(argument.inputSemanticTypeId, argument.inputCarrierTypeId, argument.inputRepresentationId)
				|| !isAdmittedInternalSide(argument.outputSemanticTypeId, argument.outputCarrierTypeId, argument.outputRepresentationId)) {
				throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner contains an argument outside the function-value signature matrix';
			}
		}
		if (resultKind == OcamlCallResultKind.Value
			&& (result == null
				|| (!isAdmittedInternalSide(result.inputSemanticTypeId, result.inputCarrierTypeId, result.inputRepresentationId)
					&& !isNominalInternalSide(result.inputSemanticTypeId, result.inputCarrierTypeId, result.inputRepresentationId))
				|| (!isAdmittedInternalSide(result.outputSemanticTypeId, result.outputCarrierTypeId, result.outputRepresentationId)
					&& !isNominalInternalSide(result.outputSemanticTypeId, result.outputCarrierTypeId, result.outputRepresentationId))
				|| !sameRepresentationSides(result)
				|| result.conversion != OcamlCallCarrierConversion.Identity)) {
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner contains a result outside the function-value signature matrix';
		}
		final expectedProofId = functionValueProofId(arguments, resultKind, result);
		if (proofId != expectedProofId)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner binds proof "$proofId" to the wrong canonical function-value signature; expected "$expectedProofId"';
	}

	/** Reconstructs the versioned proof identity from one sealed callback boundary. */
	public static function functionValueProofId(arguments:Array<OcamlCallValuePlan>, resultKind:OcamlCallResultKind, result:Null<OcamlCallValuePlan>):String {
		final parameterIds = arguments.map(argument -> (argument.parameterOptional ? "?" : "") + argument.outputSemanticTypeId);
		final resultId = switch (resultKind) {
			case Value:
				if (result == null)
					throw "reflaxe.ocaml [ocaml-call:invalid-plan]: cannot identify a value-returning function signature without a result";
				result.outputSemanticTypeId;
			case EffectOnlyVoid:
				if (result != null)
					throw "reflaxe.ocaml [ocaml-call:invalid-plan]: cannot identify an effect-only function signature with a result carrier";
				"Void";
			case _:
				throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: cannot identify unsupported function result kind "$resultKind"';
		}
		return FUNCTION_VALUE_SIGNATURE_PROOF_ID_PREFIX + '(${parameterIds.join(",")})->$resultId';
	}

	static function sameRepresentationSides(value:OcamlCallValuePlan):Bool {
		return value.inputSemanticTypeId == value.outputSemanticTypeId
			&& value.inputCarrierTypeId == value.outputCarrierTypeId
			&& value.inputRepresentationId == value.outputRepresentationId;
	}

	static function isExactIntSide(semanticTypeId:String, carrierTypeId:String, representationId:String):Bool {
		return semanticTypeId == "Int" && carrierTypeId == "int" && representationId == "representation:Int:internal-value";
	}

	static function isExactBoolSide(semanticTypeId:String, carrierTypeId:String, representationId:String):Bool {
		return semanticTypeId == "Bool" && carrierTypeId == "bool" && representationId == "representation:Bool:internal-value";
	}

	static function isExactNullIntSide(semanticTypeId:String, carrierTypeId:String, representationId:String):Bool {
		return semanticTypeId == "Null<Int>" && carrierTypeId == "Obj.t" && representationId == "representation:Null<Int>:internal-value";
	}

	static function isExactNullBoolSide(semanticTypeId:String, carrierTypeId:String, representationId:String):Bool {
		return semanticTypeId == "Null<Bool>"
			&& carrierTypeId == "Obj.t"
			&& representationId == "representation:Null<Bool>:internal-value";
	}

	static function isExactStringSide(semanticTypeId:String, carrierTypeId:String, representationId:String):Bool {
		return semanticTypeId == "String" && carrierTypeId == "string" && representationId == "representation:String:internal-value";
	}

	static function isExactDynamicSide(semanticTypeId:String, carrierTypeId:String, representationId:String):Bool {
		return semanticTypeId == "Dynamic" && carrierTypeId == "Obj.t" && representationId == "representation:Dynamic:internal-value";
	}

	/** Reports whether one closed non-Bool carrier can enter Dynamic via `Obj.repr`. */
	public static function isConcreteDynamicInputSide(semanticTypeId:String, carrierTypeId:String, representationId:String):Bool {
		return isExactIntSide(semanticTypeId, carrierTypeId, representationId)
			|| isExactStringSide(semanticTypeId, carrierTypeId, representationId)
			|| isNominalInternalSide(semanticTypeId, carrierTypeId, representationId);
	}

	static function isAdmittedInternalSide(semanticTypeId:String, carrierTypeId:String, representationId:String):Bool {
		return isExactIntSide(semanticTypeId, carrierTypeId, representationId)
			|| isExactBoolSide(semanticTypeId, carrierTypeId, representationId)
			|| isExactNullIntSide(semanticTypeId, carrierTypeId, representationId)
			|| isExactNullBoolSide(semanticTypeId, carrierTypeId, representationId)
			|| isExactStringSide(semanticTypeId, carrierTypeId, representationId)
			|| isExactDynamicSide(semanticTypeId, carrierTypeId, representationId);
	}

	static function isNullableSemanticType(semanticTypeId:String):Bool {
		return semanticTypeId == "Null<Int>" || semanticTypeId == "Null<Bool>";
	}

	static function isOptionalSemanticType(semanticTypeId:String):Bool {
		return isNullableSemanticType(semanticTypeId) || semanticTypeId == "String" || semanticTypeId == "Dynamic";
	}

	/** Recognizes the identity shape used by a sealed program-owned class record. */
	public static function isNominalInternalSide(semanticTypeId:String, carrierTypeId:String, representationId:String):Bool {
		return semanticTypeId.length > 0
			&& semanticTypeId.indexOf("<") < 0
			&& carrierTypeId.length > 0
			&& !isAdmittedInternalSide(semanticTypeId, carrierTypeId, representationId)
			&& representationId == 'representation:$semanticTypeId:internal-value';
	}

	/** Returns whether the typed source occurrence is the explicit null literal. */
	public static function isExplicitNullExpression(expression:TypedExpr):Bool {
		return switch (expression.expr) {
			case TConst(TNull): true;
			case _: false;
		}
	}

	/** Returns the stable plan-local carrier slot for one source argument. */
	public static function argumentSlotId(callId:String, argumentIndex:Int):String {
		if (callId.length == 0 || argumentIndex < 0)
			throw "reflaxe.ocaml [ocaml-call:invalid-plan]: cannot identify a call argument slot without a call identity and non-negative index";
		return "call-argument-slot:" + Sha256.encode(callId + "|" + argumentIndex).substr(0, 24);
	}

	/** Returns the stable plan-local carrier slot for a computed callee value. */
	public static function calleeSlotId(callId:String):String {
		if (callId.length == 0)
			throw "reflaxe.ocaml [ocaml-call:invalid-plan]: cannot identify a function-value slot without a call identity";
		return "call-callee-slot:" + Sha256.encode(callId).substr(0, 24);
	}

	/** Returns the stable plan-local carrier slot for one instance receiver. */
	public static function receiverSlotId(callId:String):String {
		if (callId.length == 0)
			throw "reflaxe.ocaml [ocaml-call:invalid-plan]: cannot identify an instance receiver slot without a call identity";
		return "call-receiver-slot:" + Sha256.encode(callId).substr(0, 24);
	}

	/** Builds the complete closed schedule for one admitted typed call. */
	public static function evaluationSchedule(callId:String, argumentCount:Int, ?omittedArgumentIndices:Array<Int>, materializeCallee:Bool = false,
			materializeReceiver:Bool = false):Array<OcamlCallEvaluationStep> {
		if (argumentCount < 0)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: cannot schedule unsupported typed-call arity $argumentCount';
		if (materializeCallee && materializeReceiver)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: call "$callId" cannot materialize both a function value and an instance receiver';
		final omitted = omittedArgumentIndices ?? [];
		final omittedByIndex:Map<Int, Bool> = [];
		for (index in omitted) {
			if (index < 0 || index >= argumentCount || omittedByIndex.exists(index))
				throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: call "$callId" has an invalid omitted argument index $index';
			omittedByIndex.set(index, true);
		}
		final schedule:Array<OcamlCallEvaluationStep> = [];
		if (materializeCallee) {
			schedule.push({
				kind: OcamlCallEvaluationStepKind.MaterializeCallee,
				argumentIndex: null,
				sourceArgumentIndex: null,
				slotId: calleeSlotId(callId)
			});
		}
		if (materializeReceiver) {
			schedule.push({
				kind: OcamlCallEvaluationStepKind.MaterializeReceiver,
				argumentIndex: null,
				sourceArgumentIndex: null,
				slotId: receiverSlotId(callId)
			});
		}
		var sourceArgumentIndex = 0;
		for (index in 0...argumentCount) {
			final isOmitted = omittedByIndex.exists(index);
			schedule.push({
				kind: isOmitted ? OcamlCallEvaluationStepKind.MaterializeOmittedArgument : OcamlCallEvaluationStepKind.MaterializeArgument,
				argumentIndex: index,
				sourceArgumentIndex: isOmitted ? null : sourceArgumentIndex++,
				slotId: argumentSlotId(callId, index)
			});
		}
		schedule.push({
			kind: OcamlCallEvaluationStepKind.InvokeCallee,
			argumentIndex: null,
			sourceArgumentIndex: null,
			slotId: null
		});
		return schedule;
	}

	static function copySource(source:OcamlLoweredSourceSpan):OcamlLoweredSourceSpan {
		return {file: source.file, min: source.min, max: source.max};
	}
}

/** One Haxe parameter admitted by the common represented-call signature matrix. */
private typedef OcamlAdmittedCallSignatureArgument = {
	final type:Type;
	final semanticTypeId:String;
	final optional:Bool;
}

/**
	The target-neutral callable shape selected before an occurrence is planned.

	The canonical ID contains semantic parameter/result facts only. Whether the
	function value came from a local or another call belongs to the occurrence
	identity because it changes evaluation, not the callable signature.
**/
private typedef OcamlAdmittedCallSignature = {
	final id:String;
	final arguments:Array<OcamlAdmittedCallSignatureArgument>;
	final resultKind:OcamlCallResultKind;
	final resultType:Null<Type>;
	final resultSemanticTypeId:Null<String>;
}

/**
	Selects the first closed typed-call kinds from final Haxe expressions.

	Only an ordinary, non-extern, non-generic static method whose arguments and
	result independently select admitted representations, or a local/call-produced
	function value using that same signature matrix, is admitted. Every other
	computed-call shape remains on the older syntax path until a later slice gives
	it an equally complete identity, conversion plan, evaluation schedule, and
	fail-closed validator.
**/
class OcamlCallPlanner {
	final representations:OcamlRepresentationRegistry;
	final binding:OcamlFunctionPlanBinding;
	final localRepresentations:Null<OcamlLocalRepresentationPlan>;
	final localIdentities:Null<LexicalLocalIdentityPlan>;

	public function new(representations:OcamlRepresentationRegistry, binding:OcamlFunctionPlanBinding, ?localRepresentations:OcamlLocalRepresentationPlan,
			?localIdentities:LexicalLocalIdentityPlan) {
		this.representations = representations;
		this.binding = binding;
		this.localRepresentations = localRepresentations;
		this.localIdentities = localIdentities;
	}

	/** Selects the callable boundary exported by this function, if admitted. */
	public function boundaryFor(data:ClassFuncData):Null<OcamlCallableBoundaryPlan> {
		final declaration = declarationFor(data.classType, data.field, data.isStatic, representations, binding.programRevision, binding.pipelineRevision);
		if (declaration == null)
			return null;
		var result = OcamlCallPlan.copyOptionalValue(declaration.result);
		var resultReason = "";
		if (data.expr != null && declaration.resultKind == OcamlCallResultKind.Value) {
			if (result == null)
				throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: callable "${declaration.calleeId}" has a value result kind without a value crossing';
			var resultExpression = straightLineResultExpression(data.expr);
			final returnExpressions = functionReturnExpressions(data.expr);
			var directionalReturnCount = 0;
			for (returnExpression in returnExpressions) {
				final returnValue = definitionResultValue(returnExpression, declaration.result, representations);
				if (returnValue == null) {
					throw 'reflaxe.ocaml [ocaml-call:unsupported-definition-result]: callable "${declaration.calleeId}" returns a value outside the sealed ${declaration.result.outputSemanticTypeId} result-conversion matrix';
				}
				if (returnValue.conversion != OcamlCallCarrierConversion.Identity)
					directionalReturnCount += 1;
			}
			if (directionalReturnCount > 0 && (resultExpression == null || returnExpressions.length != 1)) {
				final directResult = directRootResultExpression(data.expr);
				if (!supportsDirectionalResultControl(data.expr, directResult, returnExpressions, declaration.result, representations)) {
					throw 'reflaxe.ocaml [ocaml-call:result-control-unsealed]: callable "${declaration.calleeId}" requires $directionalReturnCount result conversion${directionalReturnCount == 1 ? "" : "s"} across early or nested return control; haxe_ocaml-w32h3 must seal those transfers before OCaml syntax';
				}
				resultExpression = directResult;
				if (directResult == null) {
					resultReason = ' Every path in its final typed body exits through sealed return control, so the declared ${result.outputSemanticTypeId} carrier remains the only callable result boundary.';
				}
			}
			if (resultExpression != null) {
				final plannedResult = definitionResultValue(resultExpression, declaration.result, representations);
				if (plannedResult == null)
					return null;
				result = plannedResult;
				resultReason = ' Its final straight-line ${result.inputSemanticTypeId} body value crosses into the exported ${result.outputSemanticTypeId} carrier via ${result.conversion}.';
			}
		}
		return {
			id: "callable-boundary:" + Sha256.encode(declaration.calleeId).substr(0, 24),
			calleeId: declaration.calleeId,
			sourceModuleId: declaration.sourceModuleId,
			sourceTypeName: declaration.sourceTypeName,
			sourceFieldName: declaration.sourceFieldName,
			kind: declaration.kind,
			receiver: OcamlCallPlan.copyOptionalValue(declaration.receiver),
			arguments: declaration.arguments.map(OcamlCallPlan.copyValue),
			resultKind: declaration.resultKind,
			result: result,
			profileEligibility: declaration.profileEligibility.copy(),
			reason: declaration.reason + resultReason,
			proofId: declaration.proofId,
			proofClaim: declaration.proofClaim,
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: binding.bodyRevision,
			pipelineRevision: binding.pipelineRevision
		};
	}

	/**
		Selects the independently typed boundary for one represented function literal.

		The function literal already has a stable lexical occurrence owned by its
		enclosing root function. Its result must use a carrier already owned by the
		existing first-class function-value matrix: exact Bool/Int/String, nullable
		Int/Bool, Dynamic, or one program-owned monomorphic class record. Dynamic
		already has one closed `Obj.t` carrier. A nominal result is admitted only when
		the representation registry supplies its exact record and layout proof; generic,
		inherited, interface, extern, and otherwise unrepresented classes remain
		deferred. Zero-argument literals use the same represented result proof with an
		empty argument list.
	**/
	public function boundaryForNestedRepresentedResult(tfunc:haxe.macro.Type.TFunc):Null<OcamlCallableBoundaryPlan> {
		final functionType:Type = switch (TypeTools.follow(tfunc.t)) {
			case TFun(_, _): tfunc.t;
			case _:
				TFun([
					for (argument in tfunc.args)
						{name: argument.v.name, opt: argument.value != null, t: argument.v.t}
				], tfunc.t);
		};
		final signature = selectAdmittedSignature(functionType, null, representations);
		if (signature == null || signature.resultKind != OcamlCallResultKind.Value)
			return null;
		final argumentRepresentations:Array<OcamlRepresentationDecision> = [];
		for (argument in signature.arguments) {
			final representation = representationForSemanticType(argument.semanticTypeId, representations);
			if (representation == null)
				return null;
			argumentRepresentations.push(representation);
		}
		final resultRepresentation = signature.resultType == null ? null : representationFor(signature.resultType, representations);
		if (resultRepresentation == null)
			return null;
		switch (resultRepresentation.semanticTypeId) {
			case "Int", "Bool", "String", "Null<Int>", "Null<Bool>", "Dynamic":
			case _:
				if (representations.monomorphicClassValue(resultRepresentation.semanticTypeId) == null)
					return null;
		}
		final proof = functionValueProof(signature);
		return {
			id: "nested-callable-boundary:" + Sha256.encode(binding.functionId).substr(0, 24),
			calleeId: binding.functionId,
			sourceModuleId: "",
			sourceTypeName: "",
			sourceFieldName: "",
			kind: OcamlCallKind.TypedFunctionValue,
			receiver: null,
			arguments: [
				for (index in 0...argumentRepresentations.length)
					identityValue(index, argumentRepresentations[index], signature.arguments[index].optional)
			],
			resultKind: OcamlCallResultKind.Value,
			result: identityValue(-1, resultRepresentation),
			profileEligibility: ["metal", "portable"],
			reason: 'The final typed function literal has a parent-scoped lexical identity, represented parameters, and one existing ${resultRepresentation.semanticTypeId} result carrier. Its nested return plan and generated closure consume this same boundary.',
			proofId: proof.id,
			proofClaim: proof.claim,
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: binding.bodyRevision,
			pipelineRevision: binding.pipelineRevision
		};
	}

	/**
		Selects the generated instance-producing boundary owned by one constructor body.

		The Haxe `new` function itself remains effect-only. This separate boundary
		describes the target `create` operation that allocates the sealed class
		layout, executes that exact body, and then returns the allocated instance.
	**/
	public function constructionBoundaryFor(data:ClassFuncData):Null<OcamlCallableBoundaryPlan> {
		if (data.field.name != "new" || data.isStatic)
			return null;
		final declaration = constructorDeclarationFor(data.classType, data.field, representations, binding.programRevision, binding.pipelineRevision);
		if (declaration == null)
			return null;
		return {
			id: "construction-boundary:" + Sha256.encode(declaration.calleeId).substr(0, 24),
			calleeId: declaration.calleeId,
			sourceModuleId: declaration.sourceModuleId,
			sourceTypeName: declaration.sourceTypeName,
			sourceFieldName: declaration.sourceFieldName,
			kind: declaration.kind,
			receiver: null,
			arguments: declaration.arguments.map(OcamlCallPlan.copyValue),
			resultKind: declaration.resultKind,
			result: OcamlCallPlan.copyOptionalValue(declaration.result),
			profileEligibility: declaration.profileEligibility.copy(),
			reason: declaration.reason +
			" This revision-bound definition proves which final Haxe constructor body the generated create operation executes before returning its allocation.",
			proofId: declaration.proofId,
			proofClaim: declaration.proofClaim,
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: binding.bodyRevision,
			pipelineRevision: binding.pipelineRevision
		};
	}

	/** Collects value-return expressions owned by this function, excluding nested callables. */
	static function functionReturnExpressions(body:TypedExpr):Array<TypedExpr> {
		final expressions:Array<TypedExpr> = [];
		function visit(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TReturn(value):
					if (value != null)
						expressions.push(value);
				case TFunction(_):
					// A nested function owns its own callable result.
				case _:
					TypedExprTools.iter(expression, visit);
			}
		}
		visit(body);
		return expressions;
	}

	/**
		Finds one result expression whose conversion does not require control flow.

		A root return, or the final return in an otherwise straight-line root block,
		can be converted around the complete generated body. Any earlier or nested
		return remains for the explicit control-effects model.
	**/
	static function straightLineResultExpression(body:TypedExpr):Null<TypedExpr> {
		return switch (body.expr) {
			case TMeta(_, child):
				straightLineResultExpression(child);
			case TReturn(value):
				value;
			case TBlock(expressions) if (expressions.length > 0):
				var hasEarlierReturn = false;
				for (index in 0...expressions.length - 1) {
					if (containsReturn(expressions[index])) {
						hasEarlierReturn = true;
						break;
					}
				}
				hasEarlierReturn ? null : directReturnValue(expressions[expressions.length - 1]);
			case _:
				null;
		};
	}

	/**
		Returns the direct root result even when an earlier nested return exists.

		This is not independently safe to lower. It is exposed only to the
		exact-nullable result-control check below, which requires every earlier
		return to preserve the already selected nullable carrier.
	**/
	static function directRootResultExpression(body:TypedExpr):Null<TypedExpr> {
		return switch (body.expr) {
			case TMeta(_, child):
				directRootResultExpression(child);
			case TReturn(value):
				value;
			case TBlock(expressions) if (expressions.length > 0):
				directReturnValue(expressions[expressions.length - 1]);
			case _:
				null;
		};
	}

	/** Unwraps metadata around one direct return without searching nested control flow. */
	static function directReturnValue(expression:TypedExpr):Null<TypedExpr> {
		return switch (expression.expr) {
			case TMeta(_, child): directReturnValue(child);
			case TReturn(value): value;
			case _: null;
		};
	}

	/** Reports whether this expression contains return control owned by this function. */
	static function containsReturn(expression:TypedExpr):Bool {
		return switch (expression.expr) {
			case TReturn(_):
				true;
			case TFunction(_):
				false;
			case _:
				var found = false;
				TypedExprTools.iter(expression, child -> {
					if (!found && containsReturn(child))
						found = true;
				});
				found;
		};
	}

	/** Selects the closed body-value to callable-carrier crossing, or rejects the pair. */
	static function definitionResultValue(expression:TypedExpr, boundaryValue:OcamlCallValuePlan,
			representations:OcamlRepresentationRegistry):Null<OcamlCallValuePlan> {
		final input = representationFor(expression.t, representations);
		final output = representationForSemanticType(boundaryValue.outputSemanticTypeId, representations);
		if (input == null || output == null)
			return null;
		if (input.semanticTypeId == output.semanticTypeId)
			return identityValue(-1, output);
		if (input.semanticTypeId == "Int" && output.semanticTypeId == "Null<Int>")
			return crossingValue(-1, input, output, OcamlCallCarrierConversion.BoxExactIntToNullableInt);
		if (input.semanticTypeId == "Null<Int>" && output.semanticTypeId == "Int")
			return crossingValue(-1, input, output, OcamlCallCarrierConversion.CheckedUnboxNullableInt);
		if (input.semanticTypeId == "Bool" && output.semanticTypeId == "Null<Bool>")
			return crossingValue(-1, input, output, OcamlCallCarrierConversion.BoxExactBoolToNullableBool);
		return null;
	}

	/**
		Admits directional result conversions only when control owns every
		non-direct crossing.

		Nullable output retains the existing box-or-preserve family. Exact `Int`
		output admits only one checked nullable direct result while every earlier
		return already produces exact `Int`. A `Null<Int>` body with no direct
		result is also admitted when the conservative control-flow facts prove that
		every path returns and every return uses the existing identity-or-box
		matrix. The control plan must still seal every occurrence; this check only
		keeps the callable boundary available for that independent owner.
	**/
	static function supportsDirectionalResultControl(body:TypedExpr, directResult:Null<TypedExpr>, returnExpressions:Array<TypedExpr>,
			boundaryValue:OcamlCallValuePlan, representations:OcamlRepresentationRegistry):Bool {
		if (directResult == null) {
			if (!OcamlControlFlowFacts.definitelyReturns(body)
				|| boundaryValue.outputSemanticTypeId != "Null<Int>"
				|| boundaryValue.outputCarrierTypeId != "Obj.t"
				|| returnExpressions.length == 0) {
				return false;
			}
			for (returnExpression in returnExpressions) {
				final crossing = definitionResultValue(returnExpression, boundaryValue, representations);
				if (crossing == null
					|| (crossing.conversion != OcamlCallCarrierConversion.Identity
						&& crossing.conversion != OcamlCallCarrierConversion.BoxExactIntToNullableInt)) {
					return false;
				}
			}
			return true;
		}
		final directCrossing = definitionResultValue(directResult, boundaryValue, representations);
		if (directCrossing == null)
			return false;
		final nullableOutput = boundaryValue.outputCarrierTypeId == "Obj.t"
			&& (boundaryValue.outputSemanticTypeId == "Null<Int>" || boundaryValue.outputSemanticTypeId == "Null<Bool>");
		final checkedIntOutput = boundaryValue.outputSemanticTypeId == "Int"
			&& boundaryValue.outputCarrierTypeId == "int"
			&& directCrossing.conversion == OcamlCallCarrierConversion.CheckedUnboxNullableInt;
		if (!nullableOutput && !checkedIntOutput)
			return false;
		final nullableConversion = boundaryValue.outputSemanticTypeId == "Null<Int>" ? OcamlCallCarrierConversion.BoxExactIntToNullableInt : OcamlCallCarrierConversion.BoxExactBoolToNullableBool;
		if (nullableOutput
			&& directCrossing.conversion != OcamlCallCarrierConversion.Identity
			&& directCrossing.conversion != nullableConversion) {
			return false;
		}
		var foundDirect = false;
		for (returnExpression in returnExpressions) {
			final crossing = definitionResultValue(returnExpression, boundaryValue, representations);
			if (crossing == null)
				return false;
			if (returnExpression == directResult) {
				foundDirect = true;
				if (checkedIntOutput && crossing.conversion != OcamlCallCarrierConversion.CheckedUnboxNullableInt)
					return false;
			} else if (checkedIntOutput && crossing.conversion != OcamlCallCarrierConversion.Identity) {
				return false;
			}
			if (nullableOutput
				&& crossing.conversion != OcamlCallCarrierConversion.Identity
				&& crossing.conversion != nullableConversion) {
				return false;
			}
		}
		return foundDirect;
	}

	/** Plans every admitted call occurrence in one exact final function body. */
	public function plan(expression:TypedExpr):OcamlCallPlan {
		final decisions:Array<OcamlCallDecision> = [];
		function visit(current:TypedExpr):Void {
			final decision = decisionFor(current);
			if (decision != null)
				decisions.push(decision);
			TypedExprTools.iter(current, visit);
		}
		visit(expression);
		return new OcamlCallPlan(decisions);
	}

	function decisionFor(expression:TypedExpr):Null<OcamlCallDecision> {
		return switch (expression.expr) {
			case TNew(classRef, parameters, arguments):
				final classType = classRef.get();
				final constructor = classType.constructor == null ? null : classType.constructor.get();
				final declaration = parameters.length == 0
					&& constructor != null ? constructorDeclarationFor(classType, constructor, representations, binding.programRevision,
						binding.pipelineRevision) : null;
				final plannedArguments = declaration == null ? null : callArgumentValues(arguments, declaration.arguments, representations);
				if (declaration == null
					|| plannedArguments == null
					|| !sameResultExpressionType(expression.t, declaration.resultKind, declaration.result, representations)) {
					null;
				} else {
					final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
					final id = "call:" + Sha256.encode([
						binding.functionId,
						binding.programRevision,
						binding.bodyRevision,
						binding.pipelineRevision,
						OcamlCallPlan.sourceKey(source),
						declaration.calleeId
					].join("|")).substr(0, 24);
					{
						id: id,
						source: source,
						calleeId: declaration.calleeId,
						sourceModuleId: declaration.sourceModuleId,
						sourceTypeName: declaration.sourceTypeName,
						sourceFieldName: declaration.sourceFieldName,
						kind: declaration.kind,
						receiver: null,
						arguments: plannedArguments,
						resultKind: declaration.resultKind,
						result: OcamlCallPlan.copyOptionalValue(declaration.result),
						evaluationSchedule: OcamlCallPlan.evaluationSchedule(id, plannedArguments.length),
						profileEligibility: ["metal", "portable"],
						reason: constructorCallReason(plannedArguments, declaration.result),
						proofId: declaration.proofId,
						proofClaim: declaration.proofClaim,
						functionId: binding.functionId,
						programRevision: binding.programRevision,
						bodyRevision: binding.bodyRevision,
						pipelineRevision: binding.pipelineRevision
					};
				}
			case TCall({expr: TField(_, FStatic(classRef, fieldRef))}, arguments):
				final classType = classRef.get();
				final field = fieldRef.get();
				final declaration = declarationFor(classType, field, true, representations, binding.programRevision, binding.pipelineRevision);
				final plannedArguments = declaration == null ? null : callArgumentValues(arguments, declaration.arguments, representations);
				if (declaration == null
					|| plannedArguments == null
					|| !sameResultExpressionType(expression.t, declaration.resultKind, declaration.result, representations)) {
					null;
				} else {
					final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
					final id = "call:" + Sha256.encode([
						binding.functionId,
						binding.programRevision,
						binding.bodyRevision,
						binding.pipelineRevision,
						OcamlCallPlan.sourceKey(source),
						declaration.calleeId
					].join("|")).substr(0, 24);
					{
						id: id,
						source: source,
						calleeId: declaration.calleeId,
						sourceModuleId: declaration.sourceModuleId,
						sourceTypeName: declaration.sourceTypeName,
						sourceFieldName: declaration.sourceFieldName,
						kind: declaration.kind,
						receiver: null,
						arguments: plannedArguments,
						resultKind: declaration.resultKind,
						result: OcamlCallPlan.copyOptionalValue(declaration.result),
						evaluationSchedule: OcamlCallPlan.evaluationSchedule(id, plannedArguments.length, omittedArgumentIndices(plannedArguments)),
						profileEligibility: ["metal", "portable"],
						reason: callReason(plannedArguments, declaration.resultKind, declaration.result),
						proofId: declaration.proofId,
						proofClaim: declaration.proofClaim,
						functionId: binding.functionId,
						programRevision: binding.programRevision,
						bodyRevision: binding.bodyRevision,
						pipelineRevision: binding.pipelineRevision
					};
				}
			case TCall({expr: TField(receiverExpression, FInstance(classRef, parameters, fieldRef))}, arguments):
				final classType = classRef.get();
				final field = fieldRef.get();
				final standardArrayTarget = OcamlStandardArrayCallContract.select(classType, parameters, field, receiverExpression, arguments, expression.t);
				if (standardArrayTarget != null)
					return standardArrayCallDecision(expression, classType, field, standardArrayTarget);
				if (OcamlStandardIMapCallContract.isIMapClass(classType))
					return null;
				final standardIMapTarget = OcamlStandardIMapCallContract.select(classType, parameters, field, receiverExpression, arguments, expression.t);
				if (standardIMapTarget != null)
					return standardIMapCallDecision(expression, classType, field, standardIMapTarget);
				final declaration = parameters.length == 0 ? declarationFor(classType, field, false, representations, binding.programRevision,
					binding.pipelineRevision) : null;
				final receiver = declaration == null ? null : instanceReceiverValue(receiverExpression, declaration);
				final plannedArguments = declaration == null ? null : callArgumentValues(arguments, declaration.arguments, representations);
				if (declaration == null
					|| receiver == null
					|| plannedArguments == null
					|| !sameResultExpressionType(expression.t, declaration.resultKind, declaration.result, representations)) {
					null;
				} else {
					final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
					final id = "call:" + Sha256.encode([
						binding.functionId,
						binding.programRevision,
						binding.bodyRevision,
						binding.pipelineRevision,
						OcamlCallPlan.sourceKey(source),
						declaration.calleeId
					].join("|")).substr(0, 24);
					{
						id: id,
						source: source,
						calleeId: declaration.calleeId,
						sourceModuleId: declaration.sourceModuleId,
						sourceTypeName: declaration.sourceTypeName,
						sourceFieldName: declaration.sourceFieldName,
						kind: declaration.kind,
						receiver: receiver,
						arguments: plannedArguments,
						resultKind: declaration.resultKind,
						result: OcamlCallPlan.copyOptionalValue(declaration.result),
						evaluationSchedule: OcamlCallPlan.evaluationSchedule(id, plannedArguments.length, omittedArgumentIndices(plannedArguments), false,
							true),
						profileEligibility: ["metal", "portable"],
						reason: instanceCallReason(receiver, plannedArguments, declaration.resultKind, declaration.result),
						proofId: declaration.proofId,
						proofClaim: declaration.proofClaim,
						functionId: binding.functionId,
						programRevision: binding.programRevision,
						bodyRevision: binding.bodyRevision,
						pipelineRevision: binding.pipelineRevision
					};
				}
			case TCall({expr: TField(receiverExpression, FAnon(fieldRef))}, arguments):
				final field = fieldRef.get();
				final target = OcamlStructuralIteratorCallContract.select(receiverExpression, field, arguments, expression.t);
				target == null ? null : structuralIteratorCallDecision(expression, field, target);
			case TCall(callee, arguments):
				final signature = functionValueSignature(callee, arguments, expression.t, representations);
				final plannedArguments = signature == null ? null : functionValueArguments(signature, arguments, representations);
				final plannedResult = signature == null ? null : functionValueResult(signature, representations);
				if (signature == null
					|| plannedArguments == null
					|| (signature.resultKind == OcamlCallResultKind.Value && plannedResult == null)
					|| (signature.resultKind == OcamlCallResultKind.EffectOnlyVoid && plannedResult != null)) {
					null;
				} else {
					final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
					final selectedCalleeId = functionValueCalleeId(callee, binding, signature.id);
					final id = "call:" + Sha256.encode([
						binding.functionId,
						binding.programRevision,
						binding.bodyRevision,
						binding.pipelineRevision,
						OcamlCallPlan.sourceKey(source),
						selectedCalleeId
					].join("|")).substr(0, 24);
					final proof = functionValueProof(signature);
					{
						id: id,
						source: source,
						calleeId: selectedCalleeId,
						sourceModuleId: "",
						sourceTypeName: "",
						sourceFieldName: "",
						kind: OcamlCallKind.TypedFunctionValue,
						receiver: null,
						arguments: plannedArguments,
						resultKind: signature.resultKind,
						result: plannedResult,
						evaluationSchedule: OcamlCallPlan.evaluationSchedule(id, plannedArguments.length, omittedArgumentIndices(plannedArguments), true),
						profileEligibility: ["metal", "portable"],
						reason: proof.reason,
						proofId: proof.id,
						proofClaim: proof.claim,
						functionId: binding.functionId,
						programRevision: binding.programRevision,
						bodyRevision: binding.bodyRevision,
						pipelineRevision: binding.pipelineRevision
					};
				}
			case _:
				null;
		}
	}

	function standardArrayCallDecision(expression:TypedExpr, classType:ClassType, field:ClassField, target:OcamlStandardArrayCallTarget):OcamlCallDecision {
		OcamlStandardArrayCallContract.require(target);
		final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
		final selectedCalleeId = calleeId(classType, field);
		final id = "call:" + Sha256.encode([
			binding.functionId,
			binding.programRevision,
			binding.bodyRevision,
			binding.pipelineRevision,
			OcamlCallPlan.sourceKey(source),
			selectedCalleeId,
			OcamlStandardArrayCallContract.fingerprint(target)
		].join("|")).substr(0, 24);
		return {
			id: id,
			source: source,
			calleeId: selectedCalleeId,
			sourceModuleId: classType.module,
			sourceTypeName: classType.name,
			sourceFieldName: field.name,
			kind: OcamlCallKind.StandardArrayMethod,
			receiver: null,
			arguments: [],
			resultKind: OcamlCallPlan.standardArrayCallResultKind(target.resultKind),
			result: null,
			evaluationSchedule: OcamlCallPlan.evaluationSchedule(id, target.argumentSemanticTypeIds.length, [], false, true),
			profileEligibility: ["metal", "portable"],
			reason: 'The final typed Haxe expression calls standard ${target.receiverSemanticTypeId}.${field.name}. Its sealed target selects ${target.runtimeModule}.${target.runtimeFunction} before syntax while preserving receiver-first and source-order argument evaluation.',
			proofId: target.proofId,
			proofClaim: target.proofClaim,
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: binding.bodyRevision,
			pipelineRevision: binding.pipelineRevision,
			standardArrayTarget: OcamlStandardArrayCallContract.copy(target)
		};
	}

	function structuralIteratorCallDecision(expression:TypedExpr, field:ClassField, target:OcamlStructuralIteratorCallTarget):OcamlCallDecision {
		OcamlStructuralIteratorCallContract.require(target);
		final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
		final selectedCalleeId = 'haxe.Iterator|Iterator::${field.name}';
		final id = "call:" + Sha256.encode([
			binding.functionId,
			binding.programRevision,
			binding.bodyRevision,
			binding.pipelineRevision,
			OcamlCallPlan.sourceKey(source),
			selectedCalleeId,
			OcamlStructuralIteratorCallContract.fingerprint(target)
		].join("|")).substr(0, 24);
		return {
			id: id,
			source: source,
			calleeId: selectedCalleeId,
			sourceModuleId: "haxe.Iterator",
			sourceTypeName: "Iterator",
			sourceFieldName: field.name,
			kind: OcamlCallKind.StructuralIteratorMethod,
			receiver: null,
			arguments: [],
			resultKind: OcamlCallResultKind.Value,
			result: null,
			evaluationSchedule: OcamlCallPlan.evaluationSchedule(id, 0, [], false, true),
			profileEligibility: ["metal", "portable"],
			reason: 'The final typed Haxe expression calls structural Iterator.${field.name}. Its sealed target selects ${target.receiverCarrierTypeId} and ${target.runtimeModule}.${target.runtimeFunction} before syntax while preserving receiver-first evaluation.',
			proofId: target.proofId,
			proofClaim: target.proofClaim,
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: binding.bodyRevision,
			pipelineRevision: binding.pipelineRevision,
			structuralIteratorTarget: OcamlStructuralIteratorCallContract.copy(target)
		};
	}

	function standardIMapCallDecision(expression:TypedExpr, classType:ClassType, field:ClassField, target:OcamlStandardIMapCallTarget):OcamlCallDecision {
		OcamlStandardIMapCallContract.require(target);
		final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
		final selectedCalleeId = calleeId(classType, field);
		final id = "call:" + Sha256.encode([
			binding.functionId,
			binding.programRevision,
			binding.bodyRevision,
			binding.pipelineRevision,
			OcamlCallPlan.sourceKey(source),
			selectedCalleeId,
			OcamlStandardIMapCallContract.fingerprint(target)
		].join("|")).substr(0, 24);
		return {
			id: id,
			source: source,
			calleeId: selectedCalleeId,
			sourceModuleId: classType.module,
			sourceTypeName: classType.name,
			sourceFieldName: field.name,
			kind: OcamlCallKind.StandardIMapMethod,
			receiver: null,
			arguments: [],
			resultKind: target.resultSemanticTypeId == "Void" ? OcamlCallResultKind.EffectOnlyVoid : OcamlCallResultKind.Value,
			result: null,
			evaluationSchedule: OcamlCallPlan.evaluationSchedule(id, target.argumentSemanticTypeIds.length, [], false, true),
			profileEligibility: ["metal", "portable"],
			reason: 'The final typed Haxe expression calls standard ${target.receiverSemanticTypeId}.${field.name}. Its sealed target operation selects ${target.receiverCarrierId}, ${target.runtimeModule}.${target.runtimeFunction}, and ${target.resultForm} before syntax while preserving receiver-first and source-order argument evaluation.',
			proofId: target.proofId,
			proofClaim: target.proofClaim,
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: binding.bodyRevision,
			pipelineRevision: binding.pipelineRevision,
			standardIMapTarget: OcamlStandardIMapCallContract.copy(target)
		};
	}

	/**
		Returns whether one callee and argument list fit a sealed function-value
		family.

		The check is intentionally shape-only so planning and the builder's
		fail-closed guard agree without sharing mutable compiler state. Instance
		methods and arbitrary field expressions stay with their existing owners.
	**/
	public static function isAdmittedFunctionValueCall(callee:TypedExpr, arguments:Array<TypedExpr>, resultType:Type,
			?representations:OcamlRepresentationRegistry):Bool {
		return functionValueSignature(callee, arguments, resultType, representations) != null;
	}

	/**
		Returns the canonical admitted signature for one computed function call.

		The ID depends only on semantic parameter/result types and optionality.
		Local versus call-produced form is deliberately excluded here and retained
		by `functionValueCalleeId`, so equivalent callback signatures compare equal
		while different source occurrences cannot collide.
	**/
	public static function functionValueSignatureId(callee:TypedExpr, arguments:Array<TypedExpr>, resultType:Type):Null<String> {
		final signature = functionValueSignature(callee, arguments, resultType);
		return signature == null ? null : signature.id;
	}

	/** Rebuilds the typed signature needed to authenticate one stored call decision. */
	public static function functionValueSignatureIdForDecision(callee:TypedExpr, arguments:Array<TypedExpr>, resultType:Type,
			result:Null<OcamlCallValuePlan>):Null<String> {
		final expectedNominalResult = result != null
			&& OcamlCallPlan.isNominalInternalSide(result.outputSemanticTypeId, result.outputCarrierTypeId,
				result.outputRepresentationId) ? result.outputSemanticTypeId : null;
		final signature = functionValueSignature(callee, arguments, resultType, null, expectedNominalResult);
		return signature == null ? null : signature.id;
	}

	static function functionValueSignature(callee:TypedExpr, arguments:Array<TypedExpr>, resultType:Type, ?representations:OcamlRepresentationRegistry,
			?expectedNominalResult:String):Null<OcamlAdmittedCallSignature> {
		final calleeForm = functionValueCalleeForm(callee);
		if (calleeForm == null)
			return null;
		final signature = selectAdmittedSignature(callee.t, calleeForm, representations, expectedNominalResult);
		if (signature == null || !functionValueArgumentsMatch(signature, arguments))
			return null;
		return switch (signature.resultKind) {
			case Value: final actualResult = semanticTypeIdWithExpectedNominal(resultType, representations,
					expectedNominalResult); signature.resultSemanticTypeId != null && actualResult == signature.resultSemanticTypeId ? signature : null;
			case EffectOnlyVoid:
				isExactVoid(resultType) ? signature : null;
			case _:
				null;
		}
	}

	static function functionValueCalleeForm(callee:TypedExpr):Null<String> {
		return switch (callee.expr) {
			case TLocal(_): "local";
			case TCall(_, _): "call-result";
			case _: null;
		}
	}

	static function functionValueArgumentsMatch(signature:OcamlAdmittedCallSignature, arguments:Array<TypedExpr>):Bool {
		final omittedTrailingOptional = arguments.length + 1 == signature.arguments.length
			&& signature.arguments.length > 0
			&& signature.arguments[signature.arguments.length - 1].optional;
		if (arguments.length != signature.arguments.length && !omittedTrailingOptional)
			return false;
		for (index in 0...arguments.length) {
			final expected = signature.arguments[index];
			final actualSemanticType = semanticTypeId(arguments[index].t);
			// The later call-value planner already owns concrete-to-Dynamic boxing.
			// Admit the same primitive matrix here, so computed functions cannot
			// bypass the sealed call before those conversions are selected.
			if (actualSemanticType == expected.semanticTypeId
				|| (actualSemanticType == "Int" && expected.semanticTypeId == "Null<Int>")
				|| (actualSemanticType == "Null<Int>" && expected.semanticTypeId == "Int")
				|| (actualSemanticType == "Bool" && expected.semanticTypeId == "Null<Bool>")
				|| ((actualSemanticType == "Bool" || actualSemanticType == "Int" || actualSemanticType == "String")
					&& expected.semanticTypeId == "Dynamic")
				|| (expected.optional
					&& (expected.semanticTypeId == "String" || expected.semanticTypeId == "Dynamic")
					&& OcamlCallPlan.isExplicitNullExpression(arguments[index]))) {
				continue;
			}
			return false;
		}
		return true;
	}

	/**
		Builds the stable identity for a computed function used at one call site.

		The sealed caller/body identity and producer occurrence distinguish each
		admitted use without depending on Haxe's process-local variable numbers,
		rendered target names, or object addresses.
	**/
	public static function functionValueCalleeId(callee:TypedExpr, binding:OcamlFunctionPlanBinding, signatureId:String):String {
		if (signatureId.length == 0)
			throw "reflaxe.ocaml [ocaml-call:invalid-plan]: cannot identify a function value without its canonical signature";
		final source = OcamlLoweredOrigin.sourceSpan(callee.pos);
		final form = switch (callee.expr) {
			case TLocal(_): "local-function-value";
			case TCall(_, _): "call-result";
			case _: throw "reflaxe.ocaml [ocaml-call:invalid-plan]: unsupported function-value callee shape reached identity construction";
		}
		return "function-value:" + Sha256.encode([
			binding.functionId,
			binding.programRevision,
			binding.bodyRevision,
			binding.pipelineRevision,
			form,
			OcamlCallPlan.sourceKey(source),
			signatureId
		].join("|")).substr(0, 32);
	}

	static function functionValueArguments(signature:OcamlAdmittedCallSignature, arguments:Array<TypedExpr>,
			representations:OcamlRepresentationRegistry):Null<Array<OcamlCallValuePlan>> {
		final boundaryValues:Array<OcamlCallValuePlan> = [];
		for (index in 0...signature.arguments.length) {
			final argument = signature.arguments[index];
			final representation = representationForSemanticType(argument.semanticTypeId, representations);
			if (representation == null)
				return null;
			boundaryValues.push(identityValue(index, representation, argument.optional));
		}
		return callArgumentValues(arguments, boundaryValues, representations);
	}

	static function functionValueResult(signature:OcamlAdmittedCallSignature, representations:OcamlRepresentationRegistry):Null<OcamlCallValuePlan> {
		if (signature.resultKind == OcamlCallResultKind.EffectOnlyVoid)
			return null;
		final semanticType = signature.resultSemanticTypeId;
		if (semanticType == null)
			return null;
		final representation = representationForSemanticType(semanticType, representations);
		return representation == null ? null : identityValue(-1, representation);
	}

	static function functionValueProof(signature:OcamlAdmittedCallSignature):{id:String, reason:String, claim:String} {
		final resultDescription = signature.resultKind == OcamlCallResultKind.EffectOnlyVoid ? "effect-only Void" : signature.resultSemanticTypeId;
		return {
			id: OcamlCallPlan.FUNCTION_VALUE_SIGNATURE_PROOF_ID_PREFIX + signature.id,
			reason: 'The typed Haxe expression invokes one local or call-produced function value with canonical signature ${signature.id}. The sealed schedule binds the callee first, materializes each supplied or omitted argument in parameter order, invokes the function once, and preserves its $resultDescription result contract.',
			claim: "The followed Haxe function type selects every parameter and result from the closed internal representation matrix. Every call occurrence must materialize its computed callee before arguments, distinguish supplied and omitted values before syntax, and apply only the recorded carrier conversions."
		};
	}

	static function callArgumentValues(arguments:Array<TypedExpr>, boundaryValues:Array<OcamlCallValuePlan>,
			representations:OcamlRepresentationRegistry):Null<Array<OcamlCallValuePlan>> {
		final omittedTrailingOptional = arguments.length + 1 == boundaryValues.length
			&& boundaryValues.length > 0
			&& boundaryValues[boundaryValues.length - 1].parameterOptional;
		if (arguments.length != boundaryValues.length && !omittedTrailingOptional)
			return null;
		final planned:Array<OcamlCallValuePlan> = [];
		for (index in 0...arguments.length) {
			final boundary = boundaryValues[index];
			final output = representationForSemanticType(boundary.outputSemanticTypeId, representations);
			if (output == null)
				return null;
			if (boundary.parameterOptional
				&& output.semanticTypeId == "String"
				&& OcamlCallPlan.isExplicitNullExpression(arguments[index])) {
				planned.push(crossingValue(index, output, output, OcamlCallCarrierConversion.MaterializeExplicitNullString, true));
				continue;
			}
			if (boundary.parameterOptional
				&& output.semanticTypeId == "Dynamic"
				&& OcamlCallPlan.isExplicitNullExpression(arguments[index])) {
				planned.push(crossingValue(index, output, output, OcamlCallCarrierConversion.MaterializeExplicitNullDynamic, true));
				continue;
			}
			final input = representationFor(arguments[index].t, representations);
			if (input == null)
				return null;
			if (input.semanticTypeId == output.semanticTypeId) {
				if (output.semanticTypeId == "Null<Int>") {
					planned.push(crossingValue(index, input, output, OcamlCallCarrierConversion.PreserveNullableIntCarrier, boundary.parameterOptional));
				} else if (output.semanticTypeId == "Null<Bool>") {
					planned.push(crossingValue(index, input, output, OcamlCallCarrierConversion.PreserveNullableBoolCarrier, boundary.parameterOptional));
				} else if (output.semanticTypeId == "Dynamic") {
					planned.push(crossingValue(index, input, output, OcamlCallCarrierConversion.PreserveDynamicCarrier, boundary.parameterOptional));
				} else {
					if (boundary.inputRepresentationId != input.id || boundary.outputRepresentationId != output.id)
						return null;
					final identity = OcamlCallPlan.copyValue(boundary);
					planned.push(identity);
				}
			} else if (input.semanticTypeId == "Int" && output.semanticTypeId == "Null<Int>") {
				planned.push(crossingValue(index, input, output, OcamlCallCarrierConversion.BoxExactIntToNullableInt, boundary.parameterOptional));
			} else if (input.semanticTypeId == "Null<Int>" && output.semanticTypeId == "Int" && !boundary.parameterOptional) {
				planned.push(crossingValue(index, input, output, OcamlCallCarrierConversion.CheckedUnboxNullableInt));
			} else if (input.semanticTypeId == "Bool" && output.semanticTypeId == "Null<Bool>") {
				planned.push(crossingValue(index, input, output, OcamlCallCarrierConversion.BoxExactBoolToNullableBool, boundary.parameterOptional));
			} else if (input.semanticTypeId == "Bool" && output.semanticTypeId == "Dynamic") {
				planned.push(crossingValue(index, input, output, OcamlCallCarrierConversion.BoxExactBoolToDynamic, boundary.parameterOptional));
			} else if (output.semanticTypeId == "Dynamic"
				&& OcamlCallPlan.isConcreteDynamicInputSide(input.semanticTypeId, input.carrierTypeId, input.id)) {
				planned.push(crossingValue(index, input, output, OcamlCallCarrierConversion.BoxConcreteToDynamic, boundary.parameterOptional));
			} else {
				return null;
			}
		}
		if (omittedTrailingOptional) {
			final boundary = boundaryValues[boundaryValues.length - 1];
			final representation = representationForSemanticType(boundary.outputSemanticTypeId, representations);
			if (representation == null)
				return null;
			final conversion = switch (boundary.outputSemanticTypeId) {
				case "Null<Int>": OcamlCallCarrierConversion.MaterializeOmittedNullableInt;
				case "Null<Bool>": OcamlCallCarrierConversion.MaterializeOmittedNullableBool;
				case "String": OcamlCallCarrierConversion.MaterializeOmittedString;
				case "Dynamic": OcamlCallCarrierConversion.MaterializeOmittedDynamic;
				case _: return null;
			}
			planned.push(crossingValue(boundary.index, representation, representation, conversion, true));
		}
		return planned;
	}

	static function omittedArgumentIndices(arguments:Array<OcamlCallValuePlan>):Array<Int> {
		return [
			for (argument in arguments)
				if (OcamlCallPlan.isOmittedConversion(argument.conversion)) argument.index
		];
	}

	static function sameResultExpressionType(type:Type, resultKind:OcamlCallResultKind, result:Null<OcamlCallValuePlan>,
			representations:OcamlRepresentationRegistry):Bool {
		return switch (resultKind) {
			case Value: final representation = representationFor(type,
					representations); result != null && representation != null && representation.semanticTypeId == result.outputSemanticTypeId;
			case EffectOnlyVoid: result == null && isExactVoid(type);
			case _:
				false;
		}
	}

	function instanceReceiverValue(expression:TypedExpr, declaration:OcamlCallableDeclarationPlan):Null<OcamlCallValuePlan> {
		final boundary = declaration.receiver;
		if (boundary == null)
			return null;
		final input = representationFor(expression.t, representations);
		if (input == null
			|| input.id != boundary.inputRepresentationId
			|| input.semanticTypeId != boundary.inputSemanticTypeId
			|| input.carrierTypeId != boundary.inputCarrierTypeId) {
			return null;
		}
		final unwrapped = unwrapTransparent(expression);
		final exactProducer = switch (unwrapped.expr) {
			case TNew(classRef, parameters, _): parameters.length == 0 && representations.monomorphicClassForType(unwrapped.t) != null;
			case TCall({expr: TField(_, FStatic(classRef, fieldRef))}, arguments):
				final producer = declarationFor(classRef.get(), fieldRef.get(), true, representations, binding.programRevision, binding.pipelineRevision);
				producer != null
				&& producer.result != null
				&& arguments.length == producer.arguments.filter(argument -> !OcamlCallPlan.isOmittedConversion(argument.conversion)).length
				&& producer.result.outputRepresentationId == boundary.inputRepresentationId;
			case TLocal(local):
				final reference = localRepresentations == null
					|| localIdentities == null ? null : localRepresentations.referenceFor(localIdentities.requireHostId(local.id).id);
				reference != null
				&& reference.domain == OcamlRepresentationDomain.InternalValue
				&& reference.representationId == boundary.inputRepresentationId
				&& reference.semanticTypeId == boundary.inputSemanticTypeId;
			case _:
				false;
		}
		return exactProducer ? OcamlCallPlan.copyValue(boundary) : null;
	}

	static function unwrapTransparent(expression:TypedExpr):TypedExpr {
		return switch (expression.expr) {
			case TParenthesis(child), TMeta(_, child), TCast(child, null):
				unwrapTransparent(child);
			case _:
				expression;
		}
	}

	static function instanceCallReason(receiver:OcamlCallValuePlan, arguments:Array<OcamlCallValuePlan>, resultKind:OcamlCallResultKind,
			result:Null<OcamlCallValuePlan>):String {
		return
			'The typed Haxe expression resolves to one ordinary instance method on exact ${receiver.outputSemanticTypeId}. Its sealed schedule materializes that ${receiver.outputCarrierTypeId} receiver once before every source-order argument, then invokes the method with already evaluated values. '
			+ callReason(arguments, resultKind, result);
	}

	static function constructorCallReason(arguments:Array<OcamlCallValuePlan>, result:Null<OcamlCallValuePlan>):String {
		if (result == null)
			throw "reflaxe.ocaml [ocaml-call:invalid-plan]: a constructor call has no nominal result crossing";
		final conversions = arguments.map(argument -> '${argument.inputSemanticTypeId} -> ${argument.outputSemanticTypeId} via ${argument.conversion}');
		return
			'The typed Haxe expression constructs one exact ${result.outputSemanticTypeId} value. Its sealed schedule materializes required arguments [${conversions.join(", ")}] before the generated create boundary allocates the nominal ${result.outputCarrierTypeId} carrier, executes the revision-bound constructor body, and returns that allocation.';
	}

	static function callReason(arguments:Array<OcamlCallValuePlan>, resultKind:OcamlCallResultKind, result:Null<OcamlCallValuePlan>):String {
		final conversions = arguments.map(argument ->
			OcamlCallPlan.isOmittedConversion(argument.conversion) ? 'omitted optional ${argument.outputSemanticTypeId} via ${argument.conversion}' : '${argument.inputSemanticTypeId} -> ${argument.outputSemanticTypeId} via ${argument.conversion}');
		final resultDescription = switch (resultKind) {
			case Value:
				if (result == null)
					throw "reflaxe.ocaml [ocaml-call:invalid-plan]: a value-result call has no value crossing";
				'its exact ${result.outputSemanticTypeId} result carrier is preserved';
			case EffectOnlyVoid:
				"its effect-only Void result produces no Haxe value or representation";
			case _:
				throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: unsupported call result kind $resultKind';
		}
		return
			'The typed Haxe expression resolves to one ordinary static method. Its sealed argument crossings are [${conversions.join(", ")}], and $resultDescription.';
	}

	/** Selects one program-wide callable declaration before module syntax starts. */
	public static function declarationFor(classType:ClassType, field:ClassField, isStatic:Bool, representations:OcamlRepresentationRegistry,
			programRevision:String, pipelineRevision:String):Null<OcamlCallableDeclarationPlan> {
		if (!ordinaryOwner(classType) || field.name == "new" || field.isExtern || classType.params.length > 0 || field.params.length > 0
			|| field.overloads.get().length > 0 || !ordinaryMethod(field)) {
			return null;
		}
		final signature = admittedSignature(field, representations);
		if (signature == null)
			return null;
		final receiverRepresentation = isStatic ? null : representations.monomorphicClassValue(classSemanticTypeId(classType));
		if (!isStatic && receiverRepresentation == null)
			return null;
		final argumentRepresentations:Array<OcamlRepresentationDecision> = [];
		for (argument in signature.arguments) {
			final representation = representationForSemanticType(argument.semanticTypeId, representations);
			if (representation == null)
				return null;
			argumentRepresentations.push(representation);
		}
		final resultRepresentation = signature.resultType == null ? null : representationFor(signature.resultType, representations);
		if (signature.resultKind == OcamlCallResultKind.Value && resultRepresentation == null)
			return null;
		final selectedCalleeId = calleeId(classType, field);
		final semanticSignature = argumentRepresentations.map(representation -> representation.semanticTypeId).join(", ");
		final resultDescription = signature.resultKind == OcamlCallResultKind.EffectOnlyVoid ? "effect-only Void" : resultRepresentation.semanticTypeId;
		return {
			id: "callable-declaration:" + Sha256.encode(selectedCalleeId).substr(0, 24),
			calleeId: selectedCalleeId,
			sourceModuleId: classType.module,
			sourceTypeName: classType.name,
			sourceFieldName: field.name,
			kind: isStatic ? OcamlCallKind.DirectStaticHaxeMethod : OcamlCallKind.DirectInstanceHaxeMethod,
			receiver: receiverRepresentation == null ? null : identityValue(-2, receiverRepresentation),
			arguments: [
				for (index in 0...argumentRepresentations.length)
					identityValue(index, argumentRepresentations[index], signature.arguments[index].optional)
			],
			resultKind: signature.resultKind,
			result: resultRepresentation == null ? null : identityValue(-1, resultRepresentation),
			profileEligibility: ["metal", "portable"],
			reason: isStatic ? 'An ordinary static Haxe method with arguments [$semanticSignature] and result $resultDescription independently selects one sealed internal carrier for each represented boundary value. Effect-only Void owns no result carrier. At most one trailing Null<Int>, Null<Bool>, exact String, or Dynamic parameter may be optional.' : 'An ordinary instance method on exact ${receiverRepresentation.semanticTypeId} uses the sealed ${receiverRepresentation.carrierTypeId} nominal receiver plus arguments [$semanticSignature] and result $resultDescription.',
			proofId: isStatic ? OcamlCallPlan.DIRECT_STATIC_SIGNATURE_PROOF_ID : OcamlCallPlan.DIRECT_INSTANCE_SIGNATURE_PROOF_ID,
			proofClaim: isStatic ? "The closed direct-static signature matrix independently selects each declared argument representation and either a represented result or explicit effect-only Void. Every call occurrence must match that result shape and those callable carriers, then materialize its source arguments in index order before invocation." : "The complete typed program selects one exact monomorphic receiver carrier and a closed method signature. Every admitted occurrence must preserve that carrier, materialize the receiver once before all source-order arguments, and invoke only the matching sealed instance definition.",
			programRevision: programRevision,
			pipelineRevision: pipelineRevision
		};
	}

	/** Selects the first exact instance-producing constructor declaration. */
	public static function constructorDeclarationFor(classType:ClassType, field:ClassField, representations:OcamlRepresentationRegistry,
			programRevision:String, pipelineRevision:String):Null<OcamlCallableDeclarationPlan> {
		if (!ordinaryOwner(classType) || field.name != "new" || field.isExtern || classType.params.length > 0 || field.params.length > 0
			|| field.overloads.get().length > 0 || !ordinaryMethod(field)) {
			return null;
		}
		final signature = admittedSignature(field, representations);
		if (signature == null
			|| signature.resultKind != OcamlCallResultKind.EffectOnlyVoid
			|| signature.arguments.length != 1
			|| signature.arguments[0].optional) {
			return null;
		}
		final resultRepresentation = representations.monomorphicClassValue(classSemanticTypeId(classType));
		final argumentRepresentation = representationForSemanticType(signature.arguments[0].semanticTypeId, representations);
		if (resultRepresentation == null || argumentRepresentation == null || argumentRepresentation.semanticTypeId != "Int")
			return null;
		final selectedCalleeId = calleeId(classType, field);
		return {
			id: "construction-declaration:" + Sha256.encode(selectedCalleeId).substr(0, 24),
			calleeId: selectedCalleeId,
			sourceModuleId: classType.module,
			sourceTypeName: classType.name,
			sourceFieldName: field.name,
			kind: OcamlCallKind.DirectHaxeConstructor,
			receiver: null,
			arguments: [identityValue(0, argumentRepresentation)],
			resultKind: OcamlCallResultKind.Value,
			result: identityValue(-1, resultRepresentation),
			profileEligibility: ["metal", "portable"],
			reason: 'An exact whole-program-monomorphic ${resultRepresentation.semanticTypeId} constructor takes one required Int carrier. The generated create boundary owns record allocation, execution of the sealed Haxe constructor body, and the exact ${resultRepresentation.carrierTypeId} instance result.',
			proofId: OcamlCallPlan.DIRECT_CONSTRUCTOR_SIGNATURE_PROOF_ID,
			proofClaim: "The complete typed program selects one exact monomorphic class layout and one ordinary one-argument constructor. Every admitted construction must preserve the declared argument carrier, execute the exact sealed constructor body once, and return the same nominal allocation without target-side signature recovery.",
			programRevision: programRevision,
			pipelineRevision: pipelineRevision
		};
	}

	static function admittedSignature(field:ClassField, representations:OcamlRepresentationRegistry):Null<OcamlAdmittedCallSignature> {
		return selectAdmittedSignature(field.type, null, representations);
	}

	/**
		Selects one canonical callable signature over already-sealed representations.

		Haxe 4.3.7 preserves the optional flag on call-produced function typedefs
		but exposes optional primitive, String, and Dynamic parameters through
		different exact or core `Null` shapes.
		Local method values retain the nullable parameter type. This selector
		normalizes both forms to one semantic signature while refusing exact
		optional locals that do not have that observed typed-API shape.
	**/
	static function selectAdmittedSignature(type:Type, calleeForm:Null<String>, ?representations:OcamlRepresentationRegistry,
			?expectedNominalResult:String):Null<OcamlAdmittedCallSignature> {
		return switch (TypeTools.follow(type)) {
			case TFun(arguments, result) if (semanticTypeIdWithExpectedNominal(result, representations, expectedNominalResult) != null
				|| isExactVoid(result)):
				var optionalCount = 0;
				var valid = true;
				final selectedArguments:Array<OcamlAdmittedCallSignatureArgument> = [];
				for (index in 0...arguments.length) {
					final argument = arguments[index];
					final semanticType = if (argument.opt && OcamlRepresentationRegistry.isExactNullDynamic(argument.t)) {
						"Dynamic";
					} else if (argument.opt && OcamlRepresentationRegistry.isExactNullString(argument.t)) {
						"String";
					} else if (argument.opt && calleeForm == "call-result" && OcamlRepresentationRegistry.isExactInt(argument.t)) {
						"Null<Int>";
					} else if (argument.opt && calleeForm == "call-result" && OcamlRepresentationRegistry.isExactBool(argument.t)) {
						"Null<Bool>";
					} else if (argument.opt
						&& OcamlRepresentationRegistry.isExactString(argument.t)
						&& (calleeForm == null || calleeForm == "call-result")) {
						"String";
					} else {
						semanticTypeId(argument.t);
					}
					if (semanticType == null) {
						valid = false;
						break;
					}
					if (argument.opt) {
						optionalCount += 1;
						if (optionalCount > 1
							|| index != arguments.length - 1
							|| (semanticType != "Null<Int>" && semanticType != "Null<Bool>" && semanticType != "String" && semanticType != "Dynamic")) {
							valid = false;
							break;
						}
					}
					selectedArguments.push({
						type: argument.t,
						semanticTypeId: semanticType,
						optional: argument.opt
					});
				}
				if (!valid) {
					null;
				} else {
					final resultKind = isExactVoid(result) ? OcamlCallResultKind.EffectOnlyVoid : OcamlCallResultKind.Value;
					final resultSemanticTypeId = resultKind == OcamlCallResultKind.Value ? semanticTypeIdWithExpectedNominal(result, representations,
						expectedNominalResult) : null;
					final parameterIds = selectedArguments.map(argument -> (argument.optional ? "?" : "") + argument.semanticTypeId);
					final resultId = resultKind == OcamlCallResultKind.EffectOnlyVoid ? "Void" : resultSemanticTypeId;
					{
						id: '(${parameterIds.join(",")})->$resultId',
						arguments: selectedArguments,
						resultKind: resultKind,
						resultType: resultKind == OcamlCallResultKind.EffectOnlyVoid ? null : result,
						resultSemanticTypeId: resultSemanticTypeId
					};
				}
			case _:
				null;
		}
	}

	/**
		Selects the representation identity used by the closed call matrix.

		Haxe's direct `String` and core `Null<String>` types share the same
		nullable string carrier. Keeping one semantic identity lets a value that
		remains typed as `Null<String>` after a source-level null check cross an
		ordinary Haxe String call boundary without target-side recovery.
	**/
	static function semanticTypeId(type:Type):Null<String> {
		if (OcamlRepresentationRegistry.isExactInt(type))
			return "Int";
		if (OcamlRepresentationRegistry.isExactBool(type))
			return "Bool";
		if (OcamlRepresentationRegistry.isExactNullInt(type))
			return "Null<Int>";
		if (OcamlRepresentationRegistry.isExactNullBool(type))
			return "Null<Bool>";
		if (OcamlRepresentationRegistry.isExactString(type) || OcamlRepresentationRegistry.isExactNullString(type))
			return "String";
		if (OcamlRepresentationRegistry.isExactDynamic(type))
			return "Dynamic";
		return null;
	}

	static function semanticTypeIdWithRegistry(type:Type, representations:Null<OcamlRepresentationRegistry>):Null<String> {
		final primitive = semanticTypeId(type);
		if (primitive != null || representations == null)
			return primitive;
		final layout = representations.monomorphicClassForType(type);
		return layout == null ? null : layout.semanticTypeId;
	}

	/**
		Authenticates a nominal result while replaying a stored decision.

		Planning still requires the live representation registry. Replay receives the
		already-sealed semantic class name and accepts it only when the current typed
		result names that same non-generic class. This lets call lookup verify the
		original occurrence without turning every class-shaped function into an
		admitted callback.
	**/
	static function semanticTypeIdWithExpectedNominal(type:Type, representations:Null<OcamlRepresentationRegistry>,
			expectedNominalResult:Null<String>):Null<String> {
		final selected = semanticTypeIdWithRegistry(type, representations);
		if (selected != null)
			return selected;
		if (expectedNominalResult == null)
			return null;
		final observed = OcamlRepresentationRegistry.monomorphicClassSemanticTypeId(type);
		return observed == expectedNominalResult ? observed : null;
	}

	static function classSemanticTypeId(classType:ClassType):String {
		return (classType.pack ?? []).concat([classType.name]).join(".");
	}

	/** Returns whether a type is the exact built-in `Void` result. */
	public static function isExactVoid(type:Type):Bool {
		return switch (TypeTools.follow(type)) {
			case TAbstract(abstractRef, _): final abstractType = abstractRef.get(); abstractType.pack.length == 0 && abstractType.name == "Void";
			case _:
				false;
		}
	}

	static function representationFor(type:Type, representations:OcamlRepresentationRegistry):Null<OcamlRepresentationDecision> {
		final semanticType = semanticTypeIdWithRegistry(type, representations);
		return semanticType == null ? null : representationForSemanticType(semanticType, representations);
	}

	static function representationForSemanticType(semanticType:String, representations:OcamlRepresentationRegistry):Null<OcamlRepresentationDecision> {
		return switch (semanticType) {
			case "Int": representations.selectExactInt(OcamlRepresentationDomain.InternalValue);
			case "Bool": representations.selectExactBool(OcamlRepresentationDomain.InternalValue);
			case "Null<Int>": representations.selectExactNullInt(OcamlRepresentationDomain.InternalValue);
			case "Null<Bool>": representations.selectExactNullBool(OcamlRepresentationDomain.InternalValue);
			case "String": representations.selectExactString(OcamlRepresentationDomain.InternalValue);
			case "Dynamic": representations.selectExactDynamic(OcamlRepresentationDomain.InternalValue);
			case _: representations.monomorphicClassValue(semanticType);
		}
	}

	static function ordinaryMethod(field:ClassField):Bool {
		return switch (field.kind) {
			case FMethod(MethNormal): true;
			case _: false;
		}
	}

	static function ordinaryOwner(classType:ClassType):Bool {
		if (classType.isExtern || classType.isInterface)
			return false;
		return switch (classType.kind) {
			case KNormal: true;
			case _: false;
		}
	}

	public static function calleeId(classType:ClassType, field:ClassField):String {
		final packagePath = classType.pack.length == 0 ? "" : classType.pack.join(".") + ".";
		return classType.module + "|" + packagePath + classType.name + "::" + field.name;
	}

	static function identityValue(index:Int, representation:OcamlRepresentationDecision, parameterOptional:Bool = false):OcamlCallValuePlan {
		return {
			index: index,
			parameterOptional: parameterOptional,
			inputSemanticTypeId: representation.semanticTypeId,
			inputCarrierTypeId: representation.carrierTypeId,
			inputRepresentationId: representation.id,
			outputSemanticTypeId: representation.semanticTypeId,
			outputCarrierTypeId: representation.carrierTypeId,
			outputRepresentationId: representation.id,
			conversion: OcamlCallCarrierConversion.Identity,
			proofId: "identity-call-carrier-v1",
			proofClaim: "The typed value already uses the callable boundary representation, so syntax preserves its carrier without a target conversion."
		};
	}

	static function crossingValue(index:Int, input:OcamlRepresentationDecision, output:OcamlRepresentationDecision, conversion:OcamlCallCarrierConversion,
			parameterOptional:Bool = false):OcamlCallValuePlan {
		final proof = switch (conversion) {
			case PreserveNullableIntCarrier: {
					id: "nullable-int-call-carrier-preserve-v1",
					claim: "The source value already produces the selected exact Null<Int> Obj.t carrier, so the boundary preserves it without another box."
				};
			case BoxExactIntToNullableInt: {
					id: "nullable-int-call-box-v1",
					claim: "The source value produces exact Int in OCaml int; one Obj.repr operation stores that value in the selected exact Null<Int> Obj.t boundary carrier."
				};
			case CheckedUnboxNullableInt: {
					id: "nullable-int-call-checked-unbox-v1",
					claim: "The typed value produces exact Null<Int> in its Obj.t carrier after Haxe control flow excluded null; one checked runtime unwrap rejects a missing value and produces the required exact Int boundary value."
				};
			case PreserveNullableBoolCarrier: {
					id: "nullable-bool-call-carrier-preserve-v1",
					claim: "The source value already produces the selected exact Null<Bool> Obj.t carrier, so the boundary preserves it without another box."
				};
			case PreserveDynamicCarrier: {
					id: "dynamic-call-carrier-preserve-v1",
					claim: "The source value already produces the selected Dynamic Obj.t carrier, so the call boundary preserves its null, primitive, or reference-bearing payload without another box."
				};
			case BoxConcreteToDynamic: {
					id: "dynamic-call-box-concrete-v1",
					claim: "The source value produces one admitted non-Bool concrete carrier; one Obj.repr operation preserves that value or reference identity in the selected Dynamic Obj.t boundary carrier."
				};
			case BoxExactBoolToDynamic: {
					id: "dynamic-call-box-bool-v1",
					claim: "The source value produces exact Bool in OCaml bool; the runtime's distinguishable Bool box preserves true and false without colliding with immediate Int values in Dynamic."
				};
			case BoxExactBoolToNullableBool: {
					id: "nullable-bool-call-box-v1",
					claim: "The source value produces exact Bool in OCaml bool; one Obj.repr operation stores that value in the selected exact Null<Bool> Obj.t boundary carrier."
				};
			case MaterializeOmittedNullableInt: {
					id: "omitted-nullable-int-call-materialization-v1",
					claim: "The Haxe call omits one trailing optional Null<Int> parameter, so the sealed schedule materializes the selected null Obj.t carrier without evaluating a source expression."
				};
			case MaterializeOmittedNullableBool: {
					id: "omitted-nullable-bool-call-materialization-v1",
					claim: "The Haxe call omits one trailing optional Null<Bool> parameter, so the sealed schedule materializes the selected null Obj.t carrier without evaluating a source expression."
				};
			case MaterializeOmittedString: {
					id: "omitted-string-call-materialization-v1",
					claim: "The Haxe call omits one trailing optional String parameter, so the sealed schedule materializes the selected Haxe String null sentinel without evaluating a source expression."
				};
			case MaterializeOmittedDynamic: {
					id: "omitted-dynamic-call-materialization-v1",
					claim: "The Haxe call omits one trailing optional Dynamic parameter, so the sealed schedule materializes Dynamic's existing null Obj.t carrier without evaluating a source expression."
				};
			case MaterializeExplicitNullString: {
					id: "explicit-null-string-call-materialization-v1",
					claim: "The Haxe call explicitly supplies the null literal to one trailing optional String parameter, so the sealed supplied-argument step materializes the selected Haxe String null sentinel."
				};
			case MaterializeExplicitNullDynamic: {
					id: "explicit-null-dynamic-call-materialization-v1",
					claim: "The Haxe call explicitly supplies the null literal to one trailing optional Dynamic parameter, so the sealed supplied-argument step materializes Dynamic's existing null Obj.t carrier."
				};
			case Identity:
				throw "reflaxe.ocaml [ocaml-call:invalid-plan]: a directional call crossing cannot use the identity helper";
		}
		return {
			index: index,
			parameterOptional: parameterOptional,
			inputSemanticTypeId: input.semanticTypeId,
			inputCarrierTypeId: input.carrierTypeId,
			inputRepresentationId: input.id,
			outputSemanticTypeId: output.semanticTypeId,
			outputCarrierTypeId: output.carrierTypeId,
			outputRepresentationId: output.id,
			conversion: conversion,
			proofId: proof.id,
			proofClaim: proof.claim
		};
	}
}
#end
