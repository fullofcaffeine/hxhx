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
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDecision;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;

/** The source-language dispatch selected before OCaml syntax is constructed. */
enum abstract OcamlCallKind(String) from String to String {
	final DirectStaticHaxeMethod = "direct-static-haxe-method";
	final TypedFunctionValue = "typed-function-value";
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
	final PreserveNullableBoolCarrier = "preserve-nullable-bool-carrier";
	final BoxExactBoolToNullableBool = "box-exact-bool-to-nullable-bool";
	final MaterializeOmittedNullableInt = "materialize-omitted-nullable-int";
	final MaterializeOmittedNullableBool = "materialize-omitted-nullable-bool";
	final MaterializeOmittedString = "materialize-omitted-string";
	final MaterializeExplicitNullString = "materialize-explicit-null-string";
}

/** The only runtime actions admitted in a sealed typed-call schedule. */
enum abstract OcamlCallEvaluationStepKind(String) from String to String {
	final MaterializeCallee = "materialize-callee";
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
	`Null<Bool>`, or `String` representation matrix. A result either uses the
	same represented matrix or explicitly records effect-only Haxe `Void`, which
	has no carrier. The argument vector may be empty; OCaml's synthetic unit
	parameter is added mechanically at the syntax boundary and is not represented
	as a Haxe argument. Later call kinds extend the planner rather than teaching
	the syntax builder new rules.
**/
typedef OcamlCallableBoundaryPlan = {
	final id:String;
	final calleeId:String;
	final sourceModuleId:String;
	final sourceTypeName:String;
	final sourceFieldName:String;
	final kind:OcamlCallKind;
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
}

/**
	Immutable call inventory for one final function body.

	The syntax builder can resolve an admitted occurrence by its normalized source
	span and exact typed callee shape, but it cannot add, replace, or infer a
	decision. The callee check matters because Haxe can assign the same source
	span to a nested call and its enclosing call. A source-only lookup could
	therefore apply a zero-argument plan to a different call that has arguments.
	Plan-to-plan span collisions are also rejected during construction.
**/
class OcamlCallPlan {
	public static inline final DIRECT_STATIC_SIGNATURE_PROOF_ID = "direct-static-representation-signature-v3";
	public static inline final FUNCTION_VALUE_SIGNATURE_PROOF_ID = "typed-function-value-signature-v1";
	public static inline final FUNCTION_VALUE_OPTIONAL_STRING_SIGNATURE_PROOF_ID = "typed-function-value-optional-string-signature-v1";

	final ordered:Array<OcamlCallDecision>;
	final bySourceKey:Map<String, OcamlCallDecision> = [];

	public final revision:String;

	public function new(decisions:Array<OcamlCallDecision>) {
		ordered = decisions.map(copyDecision);
		ordered.sort((left, right) -> Reflect.compare(left.id, right.id));
		for (decision in ordered) {
			final key = sourceKey(decision.source);
			if (bySourceKey.exists(key))
				throw 'reflaxe.ocaml [ocaml-call:duplicate-source-occurrence]: more than one admitted call uses source occurrence "$key"';
			bySourceKey.set(key, decision);
		}
		revision = "sha256:" + Sha256.encode(ordered.map(decisionFingerprint).join("\n"));
	}

	/** Returns one admitted call by its exact final-body source occurrence. */
	public function decisionFor(expression:TypedExpr):Null<OcamlCallDecision> {
		final decision = bySourceKey.get(sourceKey(OcamlLoweredOrigin.sourceSpan(expression.pos)));
		return decision == null || !matchesTypedOccurrence(decision, expression) ? null : copyDecision(decision);
	}

	static function matchesTypedOccurrence(decision:OcamlCallDecision, expression:TypedExpr):Bool {
		return switch (expression.expr) {
			case TCall({expr: TField(_, FStatic(classRef, fieldRef))}, arguments): arguments.length == suppliedArgumentCount(decision.arguments) && OcamlCallPlanner.calleeId(classRef.get(),
					fieldRef.get()) == decision.calleeId;
			case TCall(callee, arguments) if (decision.kind == OcamlCallKind.TypedFunctionValue): final binding:OcamlFunctionPlanBinding = {
					functionId: decision.functionId,
					programRevision: decision.programRevision,
					bodyRevision: decision.bodyRevision,
					pipelineRevision: decision.pipelineRevision
				}; final signatureId = OcamlCallPlanner.functionValueSignatureId(callee, arguments,
					expression.t); signatureId != null && OcamlCallPlanner.functionValueCalleeId(callee, binding, signatureId) == decision.calleeId;
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

	/** Returns whether a crossing materializes an omitted source argument. */
	public static function isOmittedConversion(conversion:OcamlCallCarrierConversion):Bool {
		return conversion == OcamlCallCarrierConversion.MaterializeOmittedNullableInt
			|| conversion == OcamlCallCarrierConversion.MaterializeOmittedNullableBool
			|| conversion == OcamlCallCarrierConversion.MaterializeOmittedString;
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

	public static function sourceKey(source:OcamlLoweredSourceSpan):String {
		return source.file + ":" + source.min + ":" + source.max;
	}

	static function decisionFingerprint(decision:OcamlCallDecision):String {
		return [
			decision.id,
			decision.calleeId,
			(decision.kind : String),
			decision.arguments.map(valueFingerprint).join(","),
			resultFingerprint(decision.resultKind, decision.result),
			decision.evaluationSchedule.map(evaluationStepFingerprint).join(","),
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
			pipelineRevision: decision.pipelineRevision
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
						&& !isExactStringSide(value.inputSemanticTypeId, value.inputCarrierTypeId, value.inputRepresentationId))
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
			case PreserveNullableBoolCarrier:
				if (!sameRepresentationSides(value)
					|| !isExactNullBoolSide(value.inputSemanticTypeId, value.inputCarrierTypeId, value.inputRepresentationId)
					|| value.proofId != "nullable-bool-call-carrier-preserve-v1") {
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner must preserve one exact Null<Bool> Obj.t carrier';
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
			case MaterializeExplicitNullString:
				if (!value.parameterOptional
					|| !sameRepresentationSides(value)
					|| !isExactStringSide(value.inputSemanticTypeId, value.inputCarrierTypeId, value.inputRepresentationId)
					|| value.proofId != "explicit-null-string-call-materialization-v1") {
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner must materialize one explicitly supplied null String carrier';
				}
			case _:
				throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has unsupported conversion "${value.conversion}"';
		}
	}

	/** Rejects a corrupted program-wide declaration before it enters the catalog. */
	public static function requireCallableDeclarationPlan(declaration:OcamlCallableDeclarationPlan):Void {
		if (declaration.kind != OcamlCallKind.DirectStaticHaxeMethod)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: callable declaration "${declaration.id}" cannot describe a computed function value';
		requireCallCommon(declaration.calleeId, declaration.sourceModuleId, declaration.sourceTypeName, declaration.sourceFieldName, declaration.kind,
			declaration.arguments, declaration.resultKind, declaration.result, declaration.profileEligibility, declaration.reason, declaration.proofId,
			declaration.proofClaim, declaration.programRevision, declaration.pipelineRevision, 'callable declaration "${declaration.id}"');
		if (!Lambda.foreach(declaration.arguments, value -> value.conversion == OcamlCallCarrierConversion.Identity)
			|| (declaration.result != null && declaration.result.conversion != OcamlCallCarrierConversion.Identity)) {
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: callable declaration "${declaration.id}" must use identity carrier records';
		}
	}

	/** Rejects a corrupted call occurrence before syntax can consume it. */
	public static function requireCall(call:OcamlCallDecision):Void {
		requireCallCommon(call.calleeId, call.sourceModuleId, call.sourceTypeName, call.sourceFieldName, call.kind, call.arguments, call.resultKind,
			call.result, call.profileEligibility, call.reason, call.proofId, call.proofClaim, call.programRevision, call.pipelineRevision, 'call "${call.id}"');
		if (call.result != null && call.result.conversion != OcamlCallCarrierConversion.Identity)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: call "${call.id}" must preserve its exact declared result carrier';
		for (argument in call.arguments) {
			if (isNullableSemanticType(argument.outputSemanticTypeId) && argument.conversion == OcamlCallCarrierConversion.Identity) {
				throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: call "${call.id}" must explicitly preserve an existing ${argument.outputSemanticTypeId} carrier or box its exact primitive';
			}
		}
		if (call.functionId.length == 0 || call.bodyRevision.length == 0)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: call "${call.id}" has an empty caller or body revision';
		if (call.source.file.length == 0 || call.source.min < 0 || call.source.max < call.source.min)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: call "${call.id}" has an invalid source occurrence';
		final hasMaterializedCallee = call.kind == OcamlCallKind.TypedFunctionValue;
		final scheduleOffset = hasMaterializedCallee ? 1 : 0;
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

	/** Rejects a corrupted final callable boundary before publication. */
	public static function requireCallableBoundary(boundary:OcamlCallableBoundaryPlan):Void {
		if (boundary.kind != OcamlCallKind.DirectStaticHaxeMethod)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: callable boundary "${boundary.id}" cannot describe a computed function value';
		requireCallCommon(boundary.calleeId, boundary.sourceModuleId, boundary.sourceTypeName, boundary.sourceFieldName, boundary.kind, boundary.arguments,
			boundary.resultKind, boundary.result, boundary.profileEligibility, boundary.reason, boundary.proofId, boundary.proofClaim,
			boundary.programRevision, boundary.pipelineRevision, 'callable boundary "${boundary.id}"');
		if (!Lambda.foreach(boundary.arguments, value -> value.conversion == OcamlCallCarrierConversion.Identity))
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: callable boundary "${boundary.id}" arguments must use identity carrier records';
		if (boundary.functionId.length == 0 || boundary.bodyRevision.length == 0)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: callable boundary "${boundary.id}" has an empty function or body revision';
	}

	static function requireCallCommon(calleeId:String, sourceModuleId:String, sourceTypeName:String, sourceFieldName:String, kind:OcamlCallKind,
			arguments:Array<OcamlCallValuePlan>, resultKind:OcamlCallResultKind, result:Null<OcamlCallValuePlan>, profileEligibility:Array<String>,
			reason:String, proofId:String, proofClaim:String, programRevision:String, pipelineRevision:String, owner:String):Void {
		if (calleeId.length == 0)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has an empty typed callee identity';
		switch (kind) {
			case DirectStaticHaxeMethod:
				if (sourceModuleId.length == 0 || sourceTypeName.length == 0 || sourceFieldName.length == 0)
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has an incomplete Haxe declaration identity';
				if (proofId != DIRECT_STATIC_SIGNATURE_PROOF_ID)
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has a mismatched direct-static signature proof';
			case TypedFunctionValue:
				if (sourceModuleId.length != 0 || sourceTypeName.length != 0 || sourceFieldName.length != 0)
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner assigns declaration fields to a first-class function value';
				if (proofId != FUNCTION_VALUE_SIGNATURE_PROOF_ID && proofId != FUNCTION_VALUE_OPTIONAL_STRING_SIGNATURE_PROOF_ID)
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
			switch (proofId) {
				case FUNCTION_VALUE_SIGNATURE_PROOF_ID:
					requireExactIntFunctionValueSignature(arguments, resultKind, result, owner);
				case FUNCTION_VALUE_OPTIONAL_STRING_SIGNATURE_PROOF_ID:
					requireOptionalStringFunctionValueSignature(arguments, resultKind, result, owner);
				case _:
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has a mismatched function-value signature proof';
			}
		}
	}

	static function requireExactIntFunctionValueSignature(arguments:Array<OcamlCallValuePlan>, resultKind:OcamlCallResultKind,
			result:Null<OcamlCallValuePlan>, owner:String):Void {
		if (arguments.length != 1
			|| arguments[0].parameterOptional
			|| !isExactIntSide(arguments[0].inputSemanticTypeId, arguments[0].inputCarrierTypeId, arguments[0].inputRepresentationId)
			|| !sameRepresentationSides(arguments[0])
			|| arguments[0].conversion != OcamlCallCarrierConversion.Identity
			|| resultKind != OcamlCallResultKind.Value
			|| result == null
			|| !isExactIntSide(result.inputSemanticTypeId, result.inputCarrierTypeId, result.inputRepresentationId)
			|| !sameRepresentationSides(result)
			|| result.conversion != OcamlCallCarrierConversion.Identity) {
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner is outside the one-argument exact Int function-value signature';
		}
	}

	static function requireOptionalStringFunctionValueSignature(arguments:Array<OcamlCallValuePlan>, resultKind:OcamlCallResultKind,
			result:Null<OcamlCallValuePlan>, owner:String):Void {
		if ((arguments.length != 1 && arguments.length != 2)
			|| !arguments[arguments.length - 1].parameterOptional
			|| (arguments.length == 2 && arguments[0].parameterOptional)
			|| resultKind != OcamlCallResultKind.Value
			|| result == null
			|| !isExactStringSide(result.inputSemanticTypeId, result.inputCarrierTypeId, result.inputRepresentationId)
			|| !sameRepresentationSides(result)
			|| result.conversion != OcamlCallCarrierConversion.Identity) {
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner is outside the trailing optional String function-value signature';
		}
		for (index in 0...arguments.length) {
			final argument = arguments[index];
			if (!isExactStringSide(argument.inputSemanticTypeId, argument.inputCarrierTypeId, argument.inputRepresentationId)
				|| !sameRepresentationSides(argument)
				|| (index < arguments.length - 1 && argument.conversion != OcamlCallCarrierConversion.Identity)
				|| (index == arguments.length - 1
					&& argument.conversion != OcamlCallCarrierConversion.Identity
					&& argument.conversion != OcamlCallCarrierConversion.MaterializeOmittedString
					&& argument.conversion != OcamlCallCarrierConversion.MaterializeExplicitNullString)) {
				throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner is outside the trailing optional String function-value signature';
			}
		}
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

	static function isNullableSemanticType(semanticTypeId:String):Bool {
		return semanticTypeId == "Null<Int>" || semanticTypeId == "Null<Bool>";
	}

	static function isOptionalSemanticType(semanticTypeId:String):Bool {
		return isNullableSemanticType(semanticTypeId) || semanticTypeId == "String";
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

	/** Builds the complete closed schedule for one admitted typed call. */
	public static function evaluationSchedule(callId:String, argumentCount:Int, ?omittedArgumentIndices:Array<Int>,
			materializeCallee:Bool = false):Array<OcamlCallEvaluationStep> {
		if (argumentCount < 0)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: cannot schedule unsupported typed-call arity $argumentCount';
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

/**
	Selects the first closed typed-call kinds from final Haxe expressions.

	Only an ordinary, non-extern, non-generic static method whose arguments and
	result independently select admitted representations, or one explicitly
	listed function-value signature, is admitted. Function values currently
	include exact `Int -> Int` locals/call results and local functions with one
	trailing optional String. Every other computed-call shape remains on the
	older syntax path until a later slice gives it an equally complete identity,
	conversion plan, evaluation schedule, and fail-closed validator.
**/
class OcamlCallPlanner {
	final representations:OcamlRepresentationRegistry;
	final binding:OcamlFunctionPlanBinding;

	public function new(representations:OcamlRepresentationRegistry, binding:OcamlFunctionPlanBinding) {
		this.representations = representations;
		this.binding = binding;
	}

	/** Selects the callable boundary exported by this function, if admitted. */
	public function boundaryFor(data:ClassFuncData):Null<OcamlCallableBoundaryPlan> {
		if (!data.isStatic)
			return null;
		final declaration = declarationFor(data.classType, data.field, representations, binding.programRevision, binding.pipelineRevision);
		if (declaration == null)
			return null;
		var result = OcamlCallPlan.copyOptionalValue(declaration.result);
		var resultReason = "";
		if (data.expr != null && declaration.resultKind == OcamlCallResultKind.Value) {
			if (result == null)
				throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: callable "${declaration.calleeId}" has a value result kind without a value crossing';
			final resultExpression = straightLineResultExpression(data.expr);
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
				throw 'reflaxe.ocaml [ocaml-call:result-control-unsealed]: callable "${declaration.calleeId}" requires $directionalReturnCount result conversion${directionalReturnCount == 1 ? "" : "s"} across early or nested return control; haxe_ocaml-w32h3 must seal those transfers before OCaml syntax';
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
		if (input.semanticTypeId == "Bool" && output.semanticTypeId == "Null<Bool>")
			return crossingValue(-1, input, output, OcamlCallCarrierConversion.BoxExactBoolToNullableBool);
		return null;
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
			case TCall({expr: TField(_, FStatic(classRef, fieldRef))}, arguments):
				final classType = classRef.get();
				final field = fieldRef.get();
				final declaration = declarationFor(classType, field, representations, binding.programRevision, binding.pipelineRevision);
				final plannedArguments = declaration == null ? null : callArgumentValues(arguments, declaration.arguments, representations);
				if (declaration == null
					|| plannedArguments == null
					|| !sameResultExpressionType(expression.t, declaration.resultKind, declaration.result)) {
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
			case TCall(callee, arguments):
				final signatureId = functionValueSignatureId(callee, arguments, expression.t);
				final plannedArguments = signatureId == null ? null : functionValueArguments(signatureId, arguments, representations);
				final plannedResult = signatureId == null ? null : functionValueResult(signatureId, representations);
				if (signatureId == null || plannedArguments == null || plannedResult == null) {
					null;
				} else {
					final source = OcamlLoweredOrigin.sourceSpan(expression.pos);
					final selectedCalleeId = functionValueCalleeId(callee, binding, signatureId);
					final id = "call:" + Sha256.encode([
						binding.functionId,
						binding.programRevision,
						binding.bodyRevision,
						binding.pipelineRevision,
						OcamlCallPlan.sourceKey(source),
						selectedCalleeId
					].join("|")).substr(0, 24);
					final proof = functionValueProof(signatureId);
					{
						id: id,
						source: source,
						calleeId: selectedCalleeId,
						sourceModuleId: "",
						sourceTypeName: "",
						sourceFieldName: "",
						kind: OcamlCallKind.TypedFunctionValue,
						arguments: plannedArguments,
						resultKind: OcamlCallResultKind.Value,
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

	/**
		Returns whether one callee and argument list fit a sealed function-value
		family.

		The check is intentionally shape-only so planning and the builder's
		fail-closed guard agree without sharing mutable compiler state. Instance
		methods and arbitrary field expressions stay with their existing owners.
	**/
	public static function isAdmittedFunctionValueCall(callee:TypedExpr, arguments:Array<TypedExpr>, resultType:Type):Bool {
		return functionValueSignatureId(callee, arguments, resultType) != null;
	}

	/**
		Returns the canonical admitted signature for one computed function call.

		Exact `Int -> Int` and the admitted optional-String signatures accept
		local and call-produced callees. The callee form remains part of the
		stable identity so those occurrences cannot collide. Haxe's typed API
		preserves the optional flag but follows a call-produced function typedef
		to an exact `String` parameter; local method values retain `Null<String>`.
		Both shapes therefore require the optional flag, while the exact
		parameter carrier remains form-specific.
	**/
	public static function functionValueSignatureId(callee:TypedExpr, arguments:Array<TypedExpr>, resultType:Type):Null<String> {
		final calleeForm = switch (callee.expr) {
			case TLocal(_): "local";
			case TCall(_, _): "call-result";
			case _: return null;
		}
		return switch (TypeTools.follow(callee.t)) {
			case TFun(parameters, result)
				if (calleeForm != null
					&& parameters.length == 1
					&& !parameters[0].opt
					&& arguments.length == 1
					&& OcamlRepresentationRegistry.isExactInt(parameters[0].t)
					&& OcamlRepresentationRegistry.isExactInt(arguments[0].t)
					&& OcamlRepresentationRegistry.isExactInt(result)
					&& OcamlRepresentationRegistry.isExactInt(resultType)):
				"(Int)->Int";
			case TFun(parameters, result)
				if (calleeForm != null
					&& parameters.length == 1
					&& parameters[0].opt
					&& arguments.length <= 1
					&& isAdmittedOptionalStringParameter(parameters[0].t, calleeForm)
					&& suppliedStrings(arguments)
					&& OcamlRepresentationRegistry.isExactString(result)
					&& OcamlRepresentationRegistry.isExactString(resultType)):
				"(?String)->String";
			case TFun(parameters, result)
				if (calleeForm != null
					&& parameters.length == 2
					&& !parameters[0].opt
					&& parameters[1].opt
					&& arguments.length >= 1
					&& arguments.length <= 2
					&& OcamlRepresentationRegistry.isExactString(parameters[0].t)
					&& isAdmittedOptionalStringParameter(parameters[1].t, calleeForm)
					&& suppliedStrings(arguments)
					&& OcamlRepresentationRegistry.isExactString(result)
					&& OcamlRepresentationRegistry.isExactString(resultType)):
				"(String,?String)->String";
			case _:
				null;
		}
	}

	static function isAdmittedOptionalStringParameter(type:Type, calleeForm:String):Bool {
		return OcamlRepresentationRegistry.isExactNullString(type)
			|| (calleeForm == "call-result" && OcamlRepresentationRegistry.isExactString(type));
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

	static function suppliedStrings(arguments:Array<TypedExpr>):Bool {
		for (argument in arguments) {
			if (!OcamlRepresentationRegistry.isExactString(argument.t) && !OcamlCallPlan.isExplicitNullExpression(argument))
				return false;
		}
		return true;
	}

	static function functionValueArguments(signatureId:String, arguments:Array<TypedExpr>,
			representations:OcamlRepresentationRegistry):Null<Array<OcamlCallValuePlan>> {
		return switch (signatureId) {
			case "(Int)->Int":
				final representation = representations.selectExactInt(OcamlRepresentationDomain.InternalValue);
				[identityValue(0, representation)];
			case "(?String)->String":
				final representation = representations.selectExactString(OcamlRepresentationDomain.InternalValue);
				callArgumentValues(arguments, [identityValue(0, representation, true)], representations);
			case "(String,?String)->String":
				final representation = representations.selectExactString(OcamlRepresentationDomain.InternalValue);
				callArgumentValues(arguments, [identityValue(0, representation), identityValue(1, representation, true)], representations);
			case _:
				null;
		}
	}

	static function functionValueResult(signatureId:String, representations:OcamlRepresentationRegistry):Null<OcamlCallValuePlan> {
		return switch (signatureId) {
			case "(Int)->Int": identityValue(-1, representations.selectExactInt(OcamlRepresentationDomain.InternalValue));
			case "(?String)->String", "(String,?String)->String":
				identityValue(-1, representations.selectExactString(OcamlRepresentationDomain.InternalValue));
			case _:
				null;
		}
	}

	static function functionValueProof(signatureId:String):{id:String, reason:String, claim:String} {
		return switch (signatureId) {
			case "(Int)->Int": {
					id: OcamlCallPlan.FUNCTION_VALUE_SIGNATURE_PROOF_ID,
					reason: "The typed Haxe expression invokes one already-created Int -> Int function value. The sealed schedule evaluates and binds the callee first, evaluates and binds the exact Int argument second, then invokes the bound function and preserves its exact Int result.",
					claim: "The followed Haxe function type selects one required exact Int parameter and an exact Int result. Its call occurrence must materialize the computed callee before the source argument, without target-side signature inference or carrier conversion."
				};
			case "(?String)->String", "(String,?String)->String": {
					id: OcamlCallPlan.FUNCTION_VALUE_OPTIONAL_STRING_SIGNATURE_PROOF_ID,
					reason: "The typed Haxe expression invokes one local or call-produced function value with one trailing optional String parameter. The sealed schedule binds the callee first, evaluates each supplied String in source order, materializes an omitted String without source evaluation, then invokes the function and preserves its exact String result.",
					claim: "The followed Haxe function type selects exact String carriers and one trailing optional String. Every call occurrence must distinguish supplied, explicitly null, and omitted values before syntax, using the existing String null-sentinel conversion where required."
				};
			case _:
				throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: unsupported function-value signature "$signatureId" reached proof construction';
		}
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
			final input = representationFor(arguments[index].t, representations);
			if (input == null)
				return null;
			if (input.semanticTypeId == output.semanticTypeId) {
				if (output.semanticTypeId == "Null<Int>") {
					planned.push(crossingValue(index, input, output, OcamlCallCarrierConversion.PreserveNullableIntCarrier, boundary.parameterOptional));
				} else if (output.semanticTypeId == "Null<Bool>") {
					planned.push(crossingValue(index, input, output, OcamlCallCarrierConversion.PreserveNullableBoolCarrier, boundary.parameterOptional));
				} else {
					if (boundary.inputRepresentationId != input.id || boundary.outputRepresentationId != output.id)
						return null;
					final identity = OcamlCallPlan.copyValue(boundary);
					planned.push(identity);
				}
			} else if (input.semanticTypeId == "Int" && output.semanticTypeId == "Null<Int>") {
				planned.push(crossingValue(index, input, output, OcamlCallCarrierConversion.BoxExactIntToNullableInt, boundary.parameterOptional));
			} else if (input.semanticTypeId == "Bool" && output.semanticTypeId == "Null<Bool>") {
				planned.push(crossingValue(index, input, output, OcamlCallCarrierConversion.BoxExactBoolToNullableBool, boundary.parameterOptional));
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

	static function sameResultExpressionType(type:Type, resultKind:OcamlCallResultKind, result:Null<OcamlCallValuePlan>):Bool {
		return switch (resultKind) {
			case Value: result != null && semanticTypeId(type) == result.outputSemanticTypeId;
			case EffectOnlyVoid: result == null && isExactVoid(type);
			case _:
				false;
		}
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
	public static function declarationFor(classType:ClassType, field:ClassField, representations:OcamlRepresentationRegistry, programRevision:String,
			pipelineRevision:String):Null<OcamlCallableDeclarationPlan> {
		if (!ordinaryOwner(classType) || field.isExtern || classType.params.length > 0 || field.params.length > 0 || field.overloads.get().length > 0
			|| !ordinaryMethod(field)) {
			return null;
		}
		final signature = admittedSignature(field);
		if (signature == null)
			return null;
		final argumentRepresentations:Array<OcamlRepresentationDecision> = [];
		for (argument in signature.arguments) {
			final representation = representationForArgument(argument.type, argument.optional, representations);
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
			kind: OcamlCallKind.DirectStaticHaxeMethod,
			arguments: [
				for (index in 0...argumentRepresentations.length)
					identityValue(index, argumentRepresentations[index], signature.arguments[index].optional)
			],
			resultKind: signature.resultKind,
			result: resultRepresentation == null ? null : identityValue(-1, resultRepresentation),
			profileEligibility: ["metal", "portable"],
			reason: 'An ordinary static Haxe method with arguments [$semanticSignature] and result $resultDescription independently selects one sealed internal carrier for each represented boundary value. Effect-only Void owns no result carrier. At most one trailing Null<Int>, Null<Bool>, or exact String parameter may be optional.',
			proofId: OcamlCallPlan.DIRECT_STATIC_SIGNATURE_PROOF_ID,
			proofClaim: "The closed direct-static signature matrix independently selects each declared argument representation and either a represented result or explicit effect-only Void. Every call occurrence must match that result shape and those callable carriers, then materialize its source arguments in index order before invocation.",
			programRevision: programRevision,
			pipelineRevision: pipelineRevision
		};
	}

	static function admittedSignature(field:ClassField):Null<{
		arguments:Array<{type:Type, optional:Bool}>,
		resultKind:OcamlCallResultKind,
		resultType:Null<Type>
	}> {
		return switch (TypeTools.follow(field.type)) {
			case TFun(arguments, result) if (semanticTypeId(result) != null || isExactVoid(result)):
				var optionalCount = 0;
				var valid = true;
				for (index in 0...arguments.length) {
					final argument = arguments[index];
					final semanticType = semanticTypeId(argument.t) ?? (argument.opt
						&& OcamlRepresentationRegistry.isExactNullString(argument.t) ? "String" : null);
					if (semanticType == null) {
						valid = false;
						break;
					}
					if (argument.opt) {
						optionalCount += 1;
						if (optionalCount > 1
							|| index != arguments.length - 1
							|| (semanticType != "Null<Int>" && semanticType != "Null<Bool>" && semanticType != "String")) {
							valid = false;
							break;
						}
					}
				}
				valid ? {
					arguments: arguments.map(argument -> {
						type: argument.t,
						optional: argument.opt
					}),
					resultKind: isExactVoid(result) ? OcamlCallResultKind.EffectOnlyVoid : OcamlCallResultKind.Value,
					resultType: isExactVoid(result) ? null : result
				} : null;
			case _:
				null;
		}
	}

	static function semanticTypeId(type:Type):Null<String> {
		if (OcamlRepresentationRegistry.isExactInt(type))
			return "Int";
		if (OcamlRepresentationRegistry.isExactBool(type))
			return "Bool";
		if (OcamlRepresentationRegistry.isExactNullInt(type))
			return "Null<Int>";
		if (OcamlRepresentationRegistry.isExactNullBool(type))
			return "Null<Bool>";
		if (OcamlRepresentationRegistry.isExactString(type))
			return "String";
		return null;
	}

	/** Returns whether a type is the exact built-in `Void` result. */
	static function isExactVoid(type:Type):Bool {
		return switch (TypeTools.follow(type)) {
			case TAbstract(abstractRef, _): final abstractType = abstractRef.get(); abstractType.pack.length == 0 && abstractType.name == "Void";
			case _:
				false;
		}
	}

	static function representationFor(type:Type, representations:OcamlRepresentationRegistry):Null<OcamlRepresentationDecision> {
		final semanticType = semanticTypeId(type);
		return semanticType == null ? null : representationForSemanticType(semanticType, representations);
	}

	static function representationForArgument(type:Type, optional:Bool, representations:OcamlRepresentationRegistry):Null<OcamlRepresentationDecision> {
		if (optional && OcamlRepresentationRegistry.isExactNullString(type))
			return representations.selectExactString(OcamlRepresentationDomain.InternalValue);
		return representationFor(type, representations);
	}

	static function representationForSemanticType(semanticType:String, representations:OcamlRepresentationRegistry):Null<OcamlRepresentationDecision> {
		return switch (semanticType) {
			case "Int": representations.selectExactInt(OcamlRepresentationDomain.InternalValue);
			case "Bool": representations.selectExactBool(OcamlRepresentationDomain.InternalValue);
			case "Null<Int>": representations.selectExactNullInt(OcamlRepresentationDomain.InternalValue);
			case "Null<Bool>": representations.selectExactNullBool(OcamlRepresentationDomain.InternalValue);
			case "String": representations.selectExactString(OcamlRepresentationDomain.InternalValue);
			case _: null;
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
			case PreserveNullableBoolCarrier: {
					id: "nullable-bool-call-carrier-preserve-v1",
					claim: "The source value already produces the selected exact Null<Bool> Obj.t carrier, so the boundary preserves it without another box."
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
			case MaterializeExplicitNullString: {
					id: "explicit-null-string-call-materialization-v1",
					claim: "The Haxe call explicitly supplies the null literal to one trailing optional String parameter, so the sealed supplied-argument step materializes the selected Haxe String null sentinel."
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
