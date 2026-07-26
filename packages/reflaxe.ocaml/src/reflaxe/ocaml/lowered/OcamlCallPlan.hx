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

/** One argument or result shape fixed by the typed call contract. */
typedef OcamlCallValuePlan = {
	final index:Int;
	final semanticTypeId:String;
	final carrierTypeId:String;
	final representationId:String;
	final conversion:OcamlCallCarrierConversion;
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

	This boundary deliberately admits only ordinary static methods with one or
	two exact `Int` parameters and an exact `Int` result. Later call families
	extend the closed planner rather than teaching the syntax builder new rules.
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
			value.semanticTypeId,
			value.carrierTypeId,
			value.representationId,
			(value.conversion : String)
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
			semanticTypeId: value.semanticTypeId,
			carrierTypeId: value.carrierTypeId,
			representationId: value.representationId,
			conversion: value.conversion
		};
	}

	public static function copyEvaluationStep(step:OcamlCallEvaluationStep):OcamlCallEvaluationStep {
		return {
			kind: step.kind,
			argumentIndex: step.argumentIndex,
			slotId: step.slotId
		};
	}

	/** Returns whether two call-boundary values describe the same sealed crossing. */
	public static function sameValue(left:OcamlCallValuePlan, right:OcamlCallValuePlan):Bool {
		return left.index == right.index
			&& left.semanticTypeId == right.semanticTypeId
			&& left.carrierTypeId == right.carrierTypeId
			&& left.representationId == right.representationId
			&& left.conversion == right.conversion;
	}

	/** Rejects a corrupted value record outside the closed direct-static family. */
	public static function requireDirectStaticIntValue(value:OcamlCallValuePlan, expectedIndex:Int, owner:String):Void {
		if (value.index != expectedIndex
			|| value.semanticTypeId != "Int"
			|| value.carrierTypeId != "int"
			|| value.representationId != "representation:Int:internal-value"
			|| value.conversion != OcamlCallCarrierConversion.Identity) {
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner must select exact Int -> int through the internal-value representation and identity conversion';
		}
	}

	/** Rejects a corrupted program-wide declaration before it enters the catalog. */
	public static function requireDirectStaticIntDeclaration(declaration:OcamlCallableDeclarationPlan):Void {
		requireDirectStaticIntCommon(declaration.calleeId, declaration.sourceModuleId, declaration.sourceTypeName, declaration.sourceFieldName,
			declaration.kind, declaration.arguments, declaration.result, declaration.profileEligibility, declaration.reason, declaration.proofId,
			declaration.proofClaim, declaration.programRevision, declaration.pipelineRevision, 'callable declaration "${declaration.id}"');
	}

	/** Rejects a corrupted call occurrence before syntax can consume it. */
	public static function requireDirectStaticIntCall(call:OcamlCallDecision):Void {
		requireDirectStaticIntCommon(call.calleeId, call.sourceModuleId, call.sourceTypeName, call.sourceFieldName, call.kind, call.arguments, call.result,
			call.profileEligibility, call.reason, call.proofId, call.proofClaim, call.programRevision, call.pipelineRevision, 'call "${call.id}"');
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
	public static function requireDirectStaticIntBoundary(boundary:OcamlCallableBoundaryPlan):Void {
		requireDirectStaticIntCommon(boundary.calleeId, boundary.sourceModuleId, boundary.sourceTypeName, boundary.sourceFieldName, boundary.kind,
			boundary.arguments, boundary.result, boundary.profileEligibility, boundary.reason, boundary.proofId, boundary.proofClaim,
			boundary.programRevision, boundary.pipelineRevision, 'callable boundary "${boundary.id}"');
		if (boundary.functionId.length == 0 || boundary.bodyRevision.length == 0)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: callable boundary "${boundary.id}" has an empty function or body revision';
	}

	static function requireDirectStaticIntCommon(calleeId:String, sourceModuleId:String, sourceTypeName:String, sourceFieldName:String, kind:OcamlCallKind,
			arguments:Array<OcamlCallValuePlan>, result:OcamlCallValuePlan, profileEligibility:Array<String>, reason:String, proofId:String,
			proofClaim:String, programRevision:String, pipelineRevision:String, owner:String):Void {
		if (calleeId.length == 0 || sourceModuleId.length == 0 || sourceTypeName.length == 0 || sourceFieldName.length == 0)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has an incomplete Haxe callee identity';
		if (kind != OcamlCallKind.DirectStaticHaxeMethod)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has unsupported kind $kind';
		if (arguments.length < 1 || arguments.length > 2)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has ${arguments.length} arguments outside the admitted arities 1 and 2';
		for (index in 0...arguments.length)
			requireDirectStaticIntValue(arguments[index], index, '$owner argument $index');
		requireDirectStaticIntValue(result, -1, '$owner result');
		if (profileEligibility.length != 2 || profileEligibility[0] != "metal" || profileEligibility[1] != "portable")
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has an unsupported profile inventory';
		if (reason.length == 0 || proofId != proofIdForArity(arguments.length) || proofClaim.length == 0)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has an incomplete direct-static Int proof';
		if (programRevision.length == 0 || pipelineRevision.length == 0)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has an empty program or pipeline revision';
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
				if (declaration == null
					|| !Lambda.foreach(arguments, argument -> OcamlRepresentationRegistry.isExactInt(argument.t))
					|| !OcamlRepresentationRegistry.isExactInt(expression.t)) {
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
						arguments: declaration.arguments.map(OcamlCallPlan.copyValue),
						result: OcamlCallPlan.copyValue(declaration.result),
						evaluationSchedule: OcamlCallPlan.evaluationSchedule(id, arguments.length),
						profileEligibility: ["metal", "portable"],
						reason: 'The typed Haxe expression resolves to one ordinary static method with ${arguments.length} exact Int argument${arguments.length == 1 ? "" : "s"} and exact Int result.',
						proofId: OcamlCallPlan.proofIdForArity(arguments.length),
						proofClaim: "Each selected exact Int representation is an identity crossing for one direct Haxe static call. Materializing every source argument in index order before invocation preserves Haxe evaluation order without relying on OCaml application order.",
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

	/** Selects one program-wide callable declaration before module syntax starts. */
	public static function declarationFor(classType:ClassType, field:ClassField, representations:OcamlRepresentationRegistry, programRevision:String,
			pipelineRevision:String):Null<OcamlCallableDeclarationPlan> {
		if (!ordinaryOwner(classType) || field.isExtern || classType.params.length > 0 || field.params.length > 0 || field.overloads.get().length > 0
			|| !ordinaryMethod(field)) {
			return null;
		}
		final signature = exactIntSignature(field);
		if (signature == null)
			return null;
		final representation = representations.selectExactInt(OcamlRepresentationDomain.InternalValue);
		final selectedCalleeId = calleeId(classType, field);
		return {
			id: "callable-declaration:" + Sha256.encode(selectedCalleeId).substr(0, 24),
			calleeId: selectedCalleeId,
			sourceModuleId: classType.module,
			sourceTypeName: classType.name,
			sourceFieldName: field.name,
			kind: OcamlCallKind.DirectStaticHaxeMethod,
			arguments: [for (index in 0...signature.arguments.length) valuePlan(index, representation)],
			result: valuePlan(-1, representation),
			profileEligibility: ["metal", "portable"],
			reason: 'An ordinary static Haxe method with ${signature.arguments.length} exact Int argument${signature.arguments.length == 1 ? "" : "s"} and exact Int result uses the direct internal int carrier at both definition and call boundaries.',
			proofId: OcamlCallPlan.proofIdForArity(signature.arguments.length),
			proofClaim: "Each selected exact Int representation is an identity crossing for one direct Haxe static call. Materializing every source argument in index order before invocation preserves Haxe evaluation order without relying on OCaml application order.",
			programRevision: programRevision,
			pipelineRevision: pipelineRevision
		};
	}

	static function exactIntSignature(field:ClassField):Null<{arguments:Array<Type>, result:Type}> {
		return switch (TypeTools.follow(field.type)) {
			case TFun(arguments, result)
				if (arguments.length >= 1
					&& arguments.length <= 2
					&& Lambda.foreach(arguments, argument -> !argument.opt && OcamlRepresentationRegistry.isExactInt(argument.t))
					&& OcamlRepresentationRegistry.isExactInt(result)):
				{arguments: arguments.map(argument -> argument.t), result: result};
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

	static function valuePlan(index:Int, representation:OcamlRepresentationDecision):OcamlCallValuePlan {
		return {
			index: index,
			semanticTypeId: representation.semanticTypeId,
			carrierTypeId: representation.carrierTypeId,
			representationId: representation.id,
			conversion: OcamlCallCarrierConversion.Identity
		};
	}
}
#end
