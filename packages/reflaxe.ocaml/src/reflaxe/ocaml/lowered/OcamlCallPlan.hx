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
}

/** How one represented value crosses an admitted call boundary. */
enum abstract OcamlCallCarrierConversion(String) from String to String {
	final Identity = "identity";
	final PreserveNullableIntCarrier = "preserve-nullable-int-carrier";
	final BoxExactIntToNullableInt = "box-exact-int-to-nullable-int";
}

/** The only runtime actions admitted in a direct-call evaluation schedule. */
enum abstract OcamlCallEvaluationStepKind(String) from String to String {
	final MaterializeArgument = "materialize-argument";
	final InvokeCallee = "invoke-callee";
}

/**
	One typed source-order step that must complete before the call can run.

	A materialization step owns one source argument index and one stable
	plan-local carrier slot. The final invocation step deliberately owns neither.
**/
typedef OcamlCallEvaluationStep = {
	final kind:OcamlCallEvaluationStepKind;
	final argumentIndex:Null<Int>;
	final slotId:Null<String>;
}

/**
	One directional argument or result crossing fixed by the typed call contract.

	Arguments flow from the source-expression representation into the callable
	boundary. Results flow from the callable boundary into the call-expression
	representation. Declaration and final-boundary values use identical input and
	output representations because they describe the function's carrier itself.
**/
typedef OcamlCallValuePlan = {
	final index:Int;
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
	final result:OcamlCallValuePlan;
	final profileEligibility:Array<String>;
	final reason:String;
	final proofId:String;
	final proofClaim:String;
	final programRevision:String;
	final pipelineRevision:String;
}

/**
	The callable shape exported by one exact final Haxe function body.

	This boundary deliberately admits ordinary static methods in the closed exact
	`Int` and `Null<Int>` families. Later call families extend the planner rather
	than teaching the syntax builder new rules.
**/
typedef OcamlCallableBoundaryPlan = {
	final id:String;
	final calleeId:String;
	final sourceModuleId:String;
	final sourceTypeName:String;
	final sourceFieldName:String;
	final kind:OcamlCallKind;
	final arguments:Array<OcamlCallValuePlan>;
	final result:OcamlCallValuePlan;
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
	final result:OcamlCallValuePlan;
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
	span, but it cannot add, replace, or infer a decision. A span collision is
	rejected during planning because an ambiguous lookup would otherwise invite a
	fallback semantic choice during emission.
**/
class OcamlCallPlan {
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
		return decision == null ? null : copyDecision(decision);
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
			valueFingerprint(decision.result),
			decision.evaluationSchedule.map(evaluationStepFingerprint).join(","),
			decision.functionId,
			decision.programRevision,
			decision.bodyRevision,
			decision.pipelineRevision
		].join("|");
	}

	static function valueFingerprint(value:OcamlCallValuePlan):String {
		return [
			Std.string(value.index),
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
			result: copyValue(decision.result),
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
			result: copyValue(boundary.result),
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
			result: copyValue(declaration.result),
			profileEligibility: declaration.profileEligibility.copy(),
			reason: declaration.reason,
			proofId: declaration.proofId,
			proofClaim: declaration.proofClaim,
			programRevision: declaration.programRevision,
			pipelineRevision: declaration.pipelineRevision
		};
	}

	public static function copyValue(value:OcamlCallValuePlan):OcamlCallValuePlan {
		return {
			index: value.index,
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
			slotId: step.slotId
		};
	}

	/** Returns whether two values describe the same complete sealed crossing. */
	public static function sameValue(left:OcamlCallValuePlan, right:OcamlCallValuePlan):Bool {
		return left.index == right.index
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
		a result, the call's input is the value produced by the function.
	**/
	public static function sameCallableBoundary(callValue:OcamlCallValuePlan, boundaryValue:OcamlCallValuePlan, isResult:Bool):Bool {
		return callValue.index == boundaryValue.index
			&& (isResult ? (callValue.inputSemanticTypeId == boundaryValue.inputSemanticTypeId
				&& callValue.inputCarrierTypeId == boundaryValue.inputCarrierTypeId
				&& callValue.inputRepresentationId == boundaryValue.inputRepresentationId) : (callValue.outputSemanticTypeId == boundaryValue.outputSemanticTypeId
					&& callValue.outputCarrierTypeId == boundaryValue.outputCarrierTypeId
					&& callValue.outputRepresentationId == boundaryValue.outputRepresentationId));
	}

	/** Rejects a corrupted value outside the closed direct-static families. */
	public static function requireDirectStaticValue(value:OcamlCallValuePlan, expectedIndex:Int, owner:String):Void {
		if (value.index != expectedIndex || value.proofId.length == 0 || value.proofClaim.length == 0)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has an invalid index or empty conversion proof';
		switch (value.conversion) {
			case Identity:
				if (!sameRepresentationSides(value)
					|| (!isExactIntSide(value.inputSemanticTypeId, value.inputCarrierTypeId, value.inputRepresentationId)
						&& !isExactNullIntSide(value.inputSemanticTypeId, value.inputCarrierTypeId, value.inputRepresentationId))
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
		}
	}

	/** Rejects a corrupted program-wide declaration before it enters the catalog. */
	public static function requireDirectStaticDeclaration(declaration:OcamlCallableDeclarationPlan):Void {
		requireDirectStaticCommon(declaration.calleeId, declaration.sourceModuleId, declaration.sourceTypeName, declaration.sourceFieldName, declaration.kind,
			declaration.arguments, declaration.result, declaration.profileEligibility, declaration.reason, declaration.proofId, declaration.proofClaim,
			declaration.programRevision, declaration.pipelineRevision, 'callable declaration "${declaration.id}"', true);
	}

	/** Rejects a corrupted call occurrence before syntax can consume it. */
	public static function requireDirectStaticCall(call:OcamlCallDecision):Void {
		requireDirectStaticCommon(call.calleeId, call.sourceModuleId, call.sourceTypeName, call.sourceFieldName, call.kind, call.arguments, call.result,
			call.profileEligibility, call.reason, call.proofId, call.proofClaim, call.programRevision, call.pipelineRevision, 'call "${call.id}"', false);
		if (call.functionId.length == 0 || call.bodyRevision.length == 0)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: call "${call.id}" has an empty caller or body revision';
		if (call.source.file.length == 0 || call.source.min < 0 || call.source.max < call.source.min)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: call "${call.id}" has an invalid source occurrence';
		if (call.evaluationSchedule.length != call.arguments.length + 1)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: call "${call.id}" has an invalid evaluation schedule';
		for (index in 0...call.arguments.length) {
			final step = call.evaluationSchedule[index];
			if (step.kind != OcamlCallEvaluationStepKind.MaterializeArgument
				|| step.argumentIndex != index
				|| step.slotId != argumentSlotId(call.id, index)) {
				throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: call "${call.id}" has an invalid argument materialization at schedule index $index';
			}
		}
		final invocation = call.evaluationSchedule[call.evaluationSchedule.length - 1];
		if (invocation.kind != OcamlCallEvaluationStepKind.InvokeCallee || invocation.argumentIndex != null || invocation.slotId != null)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: call "${call.id}" has an invalid invocation step';
	}

	/** Rejects a corrupted final callable boundary before publication. */
	public static function requireDirectStaticBoundary(boundary:OcamlCallableBoundaryPlan):Void {
		requireDirectStaticCommon(boundary.calleeId, boundary.sourceModuleId, boundary.sourceTypeName, boundary.sourceFieldName, boundary.kind,
			boundary.arguments, boundary.result, boundary.profileEligibility, boundary.reason, boundary.proofId, boundary.proofClaim,
			boundary.programRevision, boundary.pipelineRevision, 'callable boundary "${boundary.id}"', true);
		if (boundary.functionId.length == 0 || boundary.bodyRevision.length == 0)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: callable boundary "${boundary.id}" has an empty function or body revision';
	}

	static function requireDirectStaticCommon(calleeId:String, sourceModuleId:String, sourceTypeName:String, sourceFieldName:String, kind:OcamlCallKind,
			arguments:Array<OcamlCallValuePlan>, result:OcamlCallValuePlan, profileEligibility:Array<String>, reason:String, proofId:String,
			proofClaim:String, programRevision:String, pipelineRevision:String, owner:String, requiresIdentityBoundary:Bool):Void {
		if (calleeId.length == 0 || sourceModuleId.length == 0 || sourceTypeName.length == 0 || sourceFieldName.length == 0)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has an incomplete Haxe callee identity';
		if (kind != OcamlCallKind.DirectStaticHaxeMethod)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has unsupported kind $kind';
		if (arguments.length < 1 || arguments.length > 2)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has ${arguments.length} arguments outside the admitted arities 1 and 2';
		for (index in 0...arguments.length)
			requireDirectStaticValue(arguments[index], index, '$owner argument $index');
		requireDirectStaticValue(result, -1, '$owner result');
		if (requiresIdentityBoundary
			&& (!Lambda.foreach(arguments, value -> value.conversion == OcamlCallCarrierConversion.Identity)
				|| result.conversion != OcamlCallCarrierConversion.Identity)) {
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner describes a callable boundary and must use identity carrier records';
		}
		if (profileEligibility.length != 2 || profileEligibility[0] != "metal" || profileEligibility[1] != "portable")
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has an unsupported profile inventory';
		final expectedProofId = familyProofId(arguments, result);
		if (reason.length == 0 || proofId != expectedProofId || proofClaim.length == 0)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has an incomplete or mismatched direct-static family proof';
		if (!requiresIdentityBoundary
			&& expectedProofId == "direct-one-nullable-int-static-call-v1"
			&& arguments[0].conversion == OcamlCallCarrierConversion.Identity) {
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner must explicitly preserve an existing Null<Int> carrier or box one exact Int';
		}
		if (programRevision.length == 0 || pipelineRevision.length == 0)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has an empty program or pipeline revision';
	}

	static function sameRepresentationSides(value:OcamlCallValuePlan):Bool {
		return value.inputSemanticTypeId == value.outputSemanticTypeId
			&& value.inputCarrierTypeId == value.outputCarrierTypeId
			&& value.inputRepresentationId == value.outputRepresentationId;
	}

	static function isExactIntSide(semanticTypeId:String, carrierTypeId:String, representationId:String):Bool {
		return semanticTypeId == "Int" && carrierTypeId == "int" && representationId == "representation:Int:internal-value";
	}

	static function isExactNullIntSide(semanticTypeId:String, carrierTypeId:String, representationId:String):Bool {
		return semanticTypeId == "Null<Int>" && carrierTypeId == "Obj.t" && representationId == "representation:Null<Int>:internal-value";
	}

	static function familyProofId(arguments:Array<OcamlCallValuePlan>, result:OcamlCallValuePlan):String {
		final exactIntFamily = Lambda.foreach(arguments,
			value -> isExactIntSide(value.inputSemanticTypeId, value.inputCarrierTypeId, value.inputRepresentationId)
				&& isExactIntSide(value.outputSemanticTypeId, value.outputCarrierTypeId, value.outputRepresentationId)
				&& value.conversion == OcamlCallCarrierConversion.Identity)
			&& isExactIntSide(result.inputSemanticTypeId, result.inputCarrierTypeId, result.inputRepresentationId)
			&& isExactIntSide(result.outputSemanticTypeId, result.outputCarrierTypeId, result.outputRepresentationId)
			&& result.conversion == OcamlCallCarrierConversion.Identity;
		if (exactIntFamily)
			return proofIdForArity(arguments.length);
		final nullableIntFamily = arguments.length == 1
			&& isExactNullIntSide(arguments[0].outputSemanticTypeId, arguments[0].outputCarrierTypeId, arguments[0].outputRepresentationId)
			&& (arguments[0].conversion == OcamlCallCarrierConversion.PreserveNullableIntCarrier
				|| arguments[0].conversion == OcamlCallCarrierConversion.BoxExactIntToNullableInt
				|| arguments[0].conversion == OcamlCallCarrierConversion.Identity)
			&& isExactNullIntSide(result.inputSemanticTypeId, result.inputCarrierTypeId, result.inputRepresentationId)
			&& isExactNullIntSide(result.outputSemanticTypeId, result.outputCarrierTypeId, result.outputRepresentationId)
			&& result.conversion == OcamlCallCarrierConversion.Identity;
		if (nullableIntFamily)
			return "direct-one-nullable-int-static-call-v1";
		throw "reflaxe.ocaml [ocaml-call:invalid-plan]: no admitted direct-static family matches the sealed value crossings";
	}

	/** Returns the stable plan-local carrier slot for one source argument. */
	public static function argumentSlotId(callId:String, argumentIndex:Int):String {
		if (callId.length == 0 || argumentIndex < 0)
			throw "reflaxe.ocaml [ocaml-call:invalid-plan]: cannot identify a call argument slot without a call identity and non-negative index";
		return "call-argument-slot:" + Sha256.encode(callId + "|" + argumentIndex).substr(0, 24);
	}

	/** Builds the complete closed schedule for one admitted direct call. */
	public static function evaluationSchedule(callId:String, argumentCount:Int):Array<OcamlCallEvaluationStep> {
		if (argumentCount < 1 || argumentCount > 2)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: cannot schedule unsupported direct-call arity $argumentCount';
		final schedule:Array<OcamlCallEvaluationStep> = [
			for (index in 0...argumentCount)
				{
					kind: OcamlCallEvaluationStepKind.MaterializeArgument,
					argumentIndex: index,
					slotId: argumentSlotId(callId, index)
				}
		];
		schedule.push({
			kind: OcamlCallEvaluationStepKind.InvokeCallee,
			argumentIndex: null,
			slotId: null
		});
		return schedule;
	}

	/** Returns the proof contract for one admitted direct-static Int arity. */
	public static function proofIdForArity(arity:Int):String {
		return switch (arity) {
			case 1: "direct-one-int-static-call-v1";
			case 2: "direct-two-int-static-call-v1";
			case _: throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: no direct-static Int proof exists for arity $arity';
		}
	}

	static function copySource(source:OcamlLoweredSourceSpan):OcamlLoweredSourceSpan {
		return {file: source.file, min: source.min, max: source.max};
	}
}

/**
	Selects the first closed typed-call family from final Haxe expressions.

	Only an ordinary, non-extern, non-generic static method with one or two
	required exact `Int` parameters and exact `Int` result is admitted.
	Everything else is left explicitly unmigrated for a later call-family slice.
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
		return {
			id: "callable-boundary:" + Sha256.encode(declaration.calleeId).substr(0, 24),
			calleeId: declaration.calleeId,
			sourceModuleId: declaration.sourceModuleId,
			sourceTypeName: declaration.sourceTypeName,
			sourceFieldName: declaration.sourceFieldName,
			kind: declaration.kind,
			arguments: declaration.arguments.map(OcamlCallPlan.copyValue),
			result: OcamlCallPlan.copyValue(declaration.result),
			profileEligibility: declaration.profileEligibility.copy(),
			reason: declaration.reason,
			proofId: declaration.proofId,
			proofClaim: declaration.proofClaim,
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: binding.bodyRevision,
			pipelineRevision: binding.pipelineRevision
		};
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
			case TCall({expr: TField(_, FStatic(classRef, fieldRef))}, arguments) if (arguments.length >= 1 && arguments.length <= 2):
				final classType = classRef.get();
				final field = fieldRef.get();
				final declaration = declarationFor(classType, field, representations, binding.programRevision, binding.pipelineRevision);
				final plannedArguments = declaration == null ? null : callArgumentValues(arguments, declaration.arguments, representations);
				if (declaration == null || plannedArguments == null || !sameResultExpressionType(expression.t, declaration.result)) {
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
						result: OcamlCallPlan.copyValue(declaration.result),
						evaluationSchedule: OcamlCallPlan.evaluationSchedule(id, arguments.length),
						profileEligibility: ["metal", "portable"],
						reason: callReason(plannedArguments, declaration.result),
						proofId: declaration.proofId,
						proofClaim: declaration.proofClaim,
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

	static function callArgumentValues(arguments:Array<TypedExpr>, boundaryValues:Array<OcamlCallValuePlan>,
			representations:OcamlRepresentationRegistry):Null<Array<OcamlCallValuePlan>> {
		if (arguments.length != boundaryValues.length)
			return null;
		final planned:Array<OcamlCallValuePlan> = [];
		for (index in 0...arguments.length) {
			final boundary = boundaryValues[index];
			if (boundary.outputSemanticTypeId == "Int") {
				if (!OcamlRepresentationRegistry.isExactInt(arguments[index].t))
					return null;
				planned.push(OcamlCallPlan.copyValue(boundary));
			} else if (boundary.outputSemanticTypeId == "Null<Int>") {
				final input = if (OcamlRepresentationRegistry.isExactNullInt(arguments[index].t)) {
					representations.selectExactNullInt(OcamlRepresentationDomain.InternalValue);
				} else if (OcamlRepresentationRegistry.isExactInt(arguments[index].t)) {
					representations.selectExactInt(OcamlRepresentationDomain.InternalValue);
				} else {
					return null;
				}
				final output = representations.selectExactNullInt(OcamlRepresentationDomain.InternalValue);
				final conversion = input.semanticTypeId == "Int" ? OcamlCallCarrierConversion.BoxExactIntToNullableInt : OcamlCallCarrierConversion.PreserveNullableIntCarrier;
				planned.push(crossingValue(index, input, output, conversion));
			} else {
				return null;
			}
		}
		return planned;
	}

	static function sameResultExpressionType(type:Type, result:OcamlCallValuePlan):Bool {
		return switch (result.outputSemanticTypeId) {
			case "Int": OcamlRepresentationRegistry.isExactInt(type);
			case "Null<Int>": OcamlRepresentationRegistry.isExactNullInt(type);
			case _: false;
		}
	}

	static function callReason(arguments:Array<OcamlCallValuePlan>, result:OcamlCallValuePlan):String {
		if (result.outputSemanticTypeId == "Int")
			return
				'The typed Haxe expression resolves to one ordinary static method with ${arguments.length} exact Int identity argument${arguments.length == 1 ? "" : "s"} and exact Int result.';
		return switch (arguments[0].conversion) {
			case PreserveNullableIntCarrier:
				"The typed Haxe expression passes an existing exact Null<Int> carrier into one ordinary static Null<Int> method and preserves its nullable result.";
			case BoxExactIntToNullableInt:
				"The typed Haxe expression passes one exact Int into an ordinary static Null<Int> method, so the argument is boxed once before invocation and the nullable result carrier is preserved.";
			case Identity:
				"The typed Haxe expression resolves to one ordinary static Null<Int> method with an identity boundary.";
		}
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
		final representation = switch (signature.family) {
			case "exact-int": representations.selectExactInt(OcamlRepresentationDomain.InternalValue);
			case "exact-null-int": representations.selectExactNullInt(OcamlRepresentationDomain.InternalValue);
			case _: return null;
		}
		final selectedCalleeId = calleeId(classType, field);
		final proofId = signature.family == "exact-int" ? OcamlCallPlan.proofIdForArity(signature.argumentCount) : "direct-one-nullable-int-static-call-v1";
		final proofClaim = signature.family == "exact-int" ? "Each selected exact Int representation is an identity crossing for one direct Haxe static call. Materializing every source argument in index order before invocation preserves Haxe evaluation order without relying on OCaml application order." : "The callable accepts and returns the sealed exact Null<Int> Obj.t carrier. Each caller must either preserve that carrier or box one exact Int before invocation, and the nullable result remains in the same carrier.";
		return {
			id: "callable-declaration:" + Sha256.encode(selectedCalleeId).substr(0, 24),
			calleeId: selectedCalleeId,
			sourceModuleId: classType.module,
			sourceTypeName: classType.name,
			sourceFieldName: field.name,
			kind: OcamlCallKind.DirectStaticHaxeMethod,
			arguments: [for (index in 0...signature.argumentCount) identityValue(index, representation)],
			result: identityValue(-1, representation),
			profileEligibility: ["metal", "portable"],
			reason: signature.family == "exact-int" ? 'An ordinary static Haxe method with ${signature.argumentCount} exact Int argument${signature.argumentCount == 1 ? "" : "s"} and exact Int result uses the direct internal int carrier at both definition and call boundaries.' : "An ordinary static Haxe method with one exact Null<Int> parameter and result uses the sealed internal Obj.t carrier at its definition boundary.",
			proofId: proofId,
			proofClaim: proofClaim,
			programRevision: programRevision,
			pipelineRevision: pipelineRevision
		};
	}

	static function admittedSignature(field:ClassField):Null<{family:String, argumentCount:Int}> {
		return switch (TypeTools.follow(field.type)) {
			case TFun(arguments, result)
				if (arguments.length >= 1
					&& arguments.length <= 2
					&& Lambda.foreach(arguments, argument -> !argument.opt && OcamlRepresentationRegistry.isExactInt(argument.t))
					&& OcamlRepresentationRegistry.isExactInt(result)):
				{family: "exact-int", argumentCount: arguments.length};
			case TFun(arguments, result)
				if (arguments.length == 1
					&& !arguments[0].opt
					&& OcamlRepresentationRegistry.isExactNullInt(arguments[0].t)
					&& OcamlRepresentationRegistry.isExactNullInt(result)):
				{family: "exact-null-int", argumentCount: 1};
			case _:
				null;
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

	static function identityValue(index:Int, representation:OcamlRepresentationDecision):OcamlCallValuePlan {
		return {
			index: index,
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

	static function crossingValue(index:Int, input:OcamlRepresentationDecision, output:OcamlRepresentationDecision,
			conversion:OcamlCallCarrierConversion):OcamlCallValuePlan {
		final proof = switch (conversion) {
			case PreserveNullableIntCarrier: {
					id: "nullable-int-call-carrier-preserve-v1",
					claim: "The source argument already produces the selected exact Null<Int> Obj.t carrier, so the call preserves it without another box."
				};
			case BoxExactIntToNullableInt: {
					id: "nullable-int-call-box-v1",
					claim: "The source argument produces exact Int in OCaml int; one Obj.repr operation stores that value in the selected exact Null<Int> Obj.t parameter carrier."
				};
			case Identity:
				throw "reflaxe.ocaml [ocaml-call:invalid-plan]: a directional call crossing cannot use the identity helper";
		}
		return {
			index: index,
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
