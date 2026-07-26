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
	final PreserveNullableBoolCarrier = "preserve-nullable-bool-carrier";
	final BoxExactBoolToNullableBool = "box-exact-bool-to-nullable-bool";
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

	This boundary deliberately admits ordinary static methods whose required
	arguments and result independently use the closed exact `Int`, `Bool`,
	`Null<Int>`, or `Null<Bool>` representation matrix. The argument vector may
	be empty; OCaml's synthetic unit parameter is added mechanically at the
	syntax boundary and is not represented as a Haxe argument. Later call kinds
	extend the planner rather than teaching the syntax builder new rules.
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
	span and exact typed callee shape, but it cannot add, replace, or infer a
	decision. The callee check matters because Haxe can assign the same source
	span to a nested call and its enclosing call. A source-only lookup could
	therefore apply a zero-argument plan to a different call that has arguments.
	Plan-to-plan span collisions are also rejected during construction.
**/
class OcamlCallPlan {
	public static inline final DIRECT_STATIC_SIGNATURE_PROOF_ID = "direct-static-representation-signature-v1";

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
			case TCall({expr: TField(_, FStatic(classRef, fieldRef))}, arguments): arguments.length == decision.arguments.length && OcamlCallPlanner.calleeId(classRef.get(),
					fieldRef.get()) == decision.calleeId;
			case _:
				false;
		}
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
			&& decision.result.inputSemanticTypeId == "Null<Bool>"
			&& decision.result.inputCarrierTypeId == "Obj.t"
			&& decision.result.outputSemanticTypeId == "Null<Bool>"
			&& decision.result.outputCarrierTypeId == "Obj.t"
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
						&& !isExactBoolSide(value.inputSemanticTypeId, value.inputCarrierTypeId, value.inputRepresentationId)
						&& !isExactNullIntSide(value.inputSemanticTypeId, value.inputCarrierTypeId, value.inputRepresentationId)
						&& !isExactNullBoolSide(value.inputSemanticTypeId, value.inputCarrierTypeId, value.inputRepresentationId))
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
			case _:
				throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has unsupported conversion "${value.conversion}"';
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
		if (result.conversion != OcamlCallCarrierConversion.Identity)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner must preserve its exact declared result carrier';
		if (!requiresIdentityBoundary) {
			for (argument in arguments) {
				if (isNullableSemanticType(argument.outputSemanticTypeId) && argument.conversion == OcamlCallCarrierConversion.Identity) {
					throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner must explicitly preserve an existing ${argument.outputSemanticTypeId} carrier or box its exact primitive';
				}
			}
		}
		if (reason.length == 0 || proofId != DIRECT_STATIC_SIGNATURE_PROOF_ID || proofClaim.length == 0)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has an incomplete or mismatched direct-static signature proof';
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

	static function isNullableSemanticType(semanticTypeId:String):Bool {
		return semanticTypeId == "Null<Int>" || semanticTypeId == "Null<Bool>";
	}

	/** Returns the stable plan-local carrier slot for one source argument. */
	public static function argumentSlotId(callId:String, argumentIndex:Int):String {
		if (callId.length == 0 || argumentIndex < 0)
			throw "reflaxe.ocaml [ocaml-call:invalid-plan]: cannot identify a call argument slot without a call identity and non-negative index";
		return "call-argument-slot:" + Sha256.encode(callId + "|" + argumentIndex).substr(0, 24);
	}

	/** Builds the complete closed schedule for one admitted direct call. */
	public static function evaluationSchedule(callId:String, argumentCount:Int):Array<OcamlCallEvaluationStep> {
		if (argumentCount < 0)
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

	static function copySource(source:OcamlLoweredSourceSpan):OcamlLoweredSourceSpan {
		return {file: source.file, min: source.min, max: source.max};
	}
}

/**
	Selects the first closed typed-call kind from final Haxe expressions.

	Only an ordinary, non-extern, non-generic static method whose required
	arguments and result independently select exact `Int`, `Bool`,
	`Null<Int>`, or `Null<Bool>` representations is admitted. Everything else is
	left explicitly unmigrated for a later call-kind or representation slice.
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
			case TCall({expr: TField(_, FStatic(classRef, fieldRef))}, arguments):
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
			final input = representationFor(arguments[index].t, representations);
			final output = representationForSemanticType(boundary.outputSemanticTypeId, representations);
			if (input == null || output == null)
				return null;
			if (input.semanticTypeId == output.semanticTypeId) {
				if (output.semanticTypeId == "Null<Int>") {
					planned.push(crossingValue(index, input, output, OcamlCallCarrierConversion.PreserveNullableIntCarrier));
				} else if (output.semanticTypeId == "Null<Bool>") {
					planned.push(crossingValue(index, input, output, OcamlCallCarrierConversion.PreserveNullableBoolCarrier));
				} else {
					if (boundary.inputRepresentationId != input.id || boundary.outputRepresentationId != output.id)
						return null;
					final identity = OcamlCallPlan.copyValue(boundary);
					planned.push(identity);
				}
			} else if (input.semanticTypeId == "Int" && output.semanticTypeId == "Null<Int>") {
				planned.push(crossingValue(index, input, output, OcamlCallCarrierConversion.BoxExactIntToNullableInt));
			} else if (input.semanticTypeId == "Bool" && output.semanticTypeId == "Null<Bool>") {
				planned.push(crossingValue(index, input, output, OcamlCallCarrierConversion.BoxExactBoolToNullableBool));
			} else {
				return null;
			}
		}
		return planned;
	}

	static function sameResultExpressionType(type:Type, result:OcamlCallValuePlan):Bool {
		return semanticTypeId(type) == result.outputSemanticTypeId;
	}

	static function callReason(arguments:Array<OcamlCallValuePlan>, result:OcamlCallValuePlan):String {
		final conversions = arguments.map(argument -> '${argument.inputSemanticTypeId} -> ${argument.outputSemanticTypeId} via ${argument.conversion}');
		return
			'The typed Haxe expression resolves to one ordinary static method. Its sealed argument crossings are [${conversions.join(", ")}], and its exact ${result.outputSemanticTypeId} result carrier is preserved.';
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
		for (argumentType in signature.argumentTypes) {
			final representation = representationFor(argumentType, representations);
			if (representation == null)
				return null;
			argumentRepresentations.push(representation);
		}
		final resultRepresentation = representationFor(signature.resultType, representations);
		if (resultRepresentation == null)
			return null;
		final selectedCalleeId = calleeId(classType, field);
		final semanticSignature = argumentRepresentations.map(representation -> representation.semanticTypeId).join(", ");
		return {
			id: "callable-declaration:" + Sha256.encode(selectedCalleeId).substr(0, 24),
			calleeId: selectedCalleeId,
			sourceModuleId: classType.module,
			sourceTypeName: classType.name,
			sourceFieldName: field.name,
			kind: OcamlCallKind.DirectStaticHaxeMethod,
			arguments: [
				for (index in 0...argumentRepresentations.length)
					identityValue(index, argumentRepresentations[index])
			],
			result: identityValue(-1, resultRepresentation),
			profileEligibility: ["metal", "portable"],
			reason: 'An ordinary static Haxe method with required arguments [$semanticSignature] and result ${resultRepresentation.semanticTypeId} independently selects one sealed internal carrier for each boundary value.',
			proofId: OcamlCallPlan.DIRECT_STATIC_SIGNATURE_PROOF_ID,
			proofClaim: "The closed direct-static signature matrix independently selects each declared argument and result representation. Every call occurrence must match those callable carriers and materialize its source arguments in index order before invocation.",
			programRevision: programRevision,
			pipelineRevision: pipelineRevision
		};
	}

	static function admittedSignature(field:ClassField):Null<{argumentTypes:Array<Type>, resultType:Type}> {
		return switch (TypeTools.follow(field.type)) {
			case TFun(arguments, result)
				if (Lambda.foreach(arguments, argument -> !argument.opt && semanticTypeId(argument.t) != null)
					&& semanticTypeId(result) != null):
				{argumentTypes: arguments.map(argument -> argument.t), resultType: result};
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
		return null;
	}

	static function representationFor(type:Type, representations:OcamlRepresentationRegistry):Null<OcamlRepresentationDecision> {
		final semanticType = semanticTypeId(type);
		return semanticType == null ? null : representationForSemanticType(semanticType, representations);
	}

	static function representationForSemanticType(semanticType:String, representations:OcamlRepresentationRegistry):Null<OcamlRepresentationDecision> {
		return switch (semanticType) {
			case "Int": representations.selectExactInt(OcamlRepresentationDomain.InternalValue);
			case "Bool": representations.selectExactBool(OcamlRepresentationDomain.InternalValue);
			case "Null<Int>": representations.selectExactNullInt(OcamlRepresentationDomain.InternalValue);
			case "Null<Bool>": representations.selectExactNullBool(OcamlRepresentationDomain.InternalValue);
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
			case PreserveNullableBoolCarrier: {
					id: "nullable-bool-call-carrier-preserve-v1",
					claim: "The source argument already produces the selected exact Null<Bool> Obj.t carrier, so the call preserves it without another box."
				};
			case BoxExactBoolToNullableBool: {
					id: "nullable-bool-call-box-v1",
					claim: "The source argument produces exact Bool in OCaml bool; one Obj.repr operation stores that value in the selected exact Null<Bool> Obj.t parameter carrier."
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
