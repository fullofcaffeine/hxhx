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

	This first boundary deliberately admits one ordinary static method with one
	exact `Int` parameter and an exact `Int` result. Later call families extend
	the closed planner rather than teaching the syntax builder new call rules.
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
	final evaluationSchedule:Array<String>;
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
			decision.evaluationSchedule.join(","),
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
			evaluationSchedule: decision.evaluationSchedule.copy(),
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

	/** Returns whether two call-boundary values describe the same sealed crossing. */
	public static function sameValue(left:OcamlCallValuePlan, right:OcamlCallValuePlan):Bool {
		return left.index == right.index
			&& left.semanticTypeId == right.semanticTypeId
			&& left.carrierTypeId == right.carrierTypeId
			&& left.representationId == right.representationId
			&& left.conversion == right.conversion;
	}

	/** Rejects a corrupted value record outside the first closed call family. */
	public static function requireFirstFamilyValue(value:OcamlCallValuePlan, expectedIndex:Int, owner:String):Void {
		if (value.index != expectedIndex
			|| value.semanticTypeId != "Int"
			|| value.carrierTypeId != "int"
			|| value.representationId != "representation:Int:internal-value"
			|| value.conversion != OcamlCallCarrierConversion.Identity) {
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner must select exact Int -> int through the internal-value representation and identity conversion';
		}
	}

	/** Rejects a corrupted program-wide declaration before it enters the catalog. */
	public static function requireFirstFamilyDeclaration(declaration:OcamlCallableDeclarationPlan):Void {
		requireFirstFamilyCommon(declaration.calleeId, declaration.sourceModuleId, declaration.sourceTypeName, declaration.sourceFieldName, declaration.kind,
			declaration.arguments, declaration.result, declaration.profileEligibility, declaration.reason, declaration.proofId, declaration.proofClaim,
			declaration.programRevision, declaration.pipelineRevision, 'callable declaration "${declaration.id}"');
	}

	/** Rejects a corrupted call occurrence before syntax can consume it. */
	public static function requireFirstFamilyCall(call:OcamlCallDecision):Void {
		requireFirstFamilyCommon(call.calleeId, call.sourceModuleId, call.sourceTypeName, call.sourceFieldName, call.kind, call.arguments, call.result,
			call.profileEligibility, call.reason, call.proofId, call.proofClaim, call.programRevision, call.pipelineRevision, 'call "${call.id}"');
		if (call.functionId.length == 0 || call.bodyRevision.length == 0)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: call "${call.id}" has an empty caller or body revision';
		if (call.source.file.length == 0 || call.source.min < 0 || call.source.max < call.source.min)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: call "${call.id}" has an invalid source occurrence';
		if (call.evaluationSchedule.length != 2
			|| call.evaluationSchedule[0] != "evaluate-argument:0"
			|| call.evaluationSchedule[1] != "invoke-callee") {
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: call "${call.id}" has an invalid evaluation schedule';
		}
	}

	/** Rejects a corrupted final callable boundary before publication. */
	public static function requireFirstFamilyBoundary(boundary:OcamlCallableBoundaryPlan):Void {
		requireFirstFamilyCommon(boundary.calleeId, boundary.sourceModuleId, boundary.sourceTypeName, boundary.sourceFieldName, boundary.kind,
			boundary.arguments, boundary.result, boundary.profileEligibility, boundary.reason, boundary.proofId, boundary.proofClaim,
			boundary.programRevision, boundary.pipelineRevision, 'callable boundary "${boundary.id}"');
		if (boundary.functionId.length == 0 || boundary.bodyRevision.length == 0)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: callable boundary "${boundary.id}" has an empty function or body revision';
	}

	static function requireFirstFamilyCommon(calleeId:String, sourceModuleId:String, sourceTypeName:String, sourceFieldName:String, kind:OcamlCallKind,
			arguments:Array<OcamlCallValuePlan>, result:OcamlCallValuePlan, profileEligibility:Array<String>, reason:String, proofId:String,
			proofClaim:String, programRevision:String, pipelineRevision:String, owner:String):Void {
		if (calleeId.length == 0 || sourceModuleId.length == 0 || sourceTypeName.length == 0 || sourceFieldName.length == 0)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has an incomplete Haxe callee identity';
		if (kind != OcamlCallKind.DirectStaticHaxeMethod)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has unsupported kind $kind';
		if (arguments.length != 1)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has ${arguments.length} arguments instead of the admitted arity 1';
		requireFirstFamilyValue(arguments[0], 0, '$owner argument');
		requireFirstFamilyValue(result, -1, '$owner result');
		if (profileEligibility.length != 2 || profileEligibility[0] != "metal" || profileEligibility[1] != "portable")
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has an unsupported profile inventory';
		if (reason.length == 0 || proofId != "direct-one-int-static-call-v1" || proofClaim.length == 0)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has an incomplete first-family proof';
		if (programRevision.length == 0 || pipelineRevision.length == 0)
			throw 'reflaxe.ocaml [ocaml-call:invalid-plan]: $owner has an empty program or pipeline revision';
	}

	static function copySource(source:OcamlLoweredSourceSpan):OcamlLoweredSourceSpan {
		return {file: source.file, min: source.min, max: source.max};
	}
}

/**
	Selects the first closed typed-call family from final Haxe expressions.

	Only an ordinary, non-extern, non-generic static method with one required
	exact `Int` parameter and exact `Int` result is admitted. Everything else is
	left explicitly unmigrated for a later call-family slice.
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
			case TCall({expr: TField(_, FStatic(classRef, fieldRef))}, arguments) if (arguments.length == 1):
				final classType = classRef.get();
				final field = fieldRef.get();
				final declaration = declarationFor(classType, field, representations, binding.programRevision, binding.pipelineRevision);
				if (declaration == null
					|| !OcamlRepresentationRegistry.isExactInt(arguments[0].t)
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
						evaluationSchedule: ["evaluate-argument:0", "invoke-callee"],
						profileEligibility: ["metal", "portable"],
						reason: "The typed Haxe expression resolves to one ordinary static method with one exact Int argument and exact Int result.",
						proofId: "direct-one-int-static-call-v1",
						proofClaim: "The selected exact Int representation is an identity crossing for one direct Haxe static call. With one source argument, evaluating that argument before invocation preserves the complete argument order without relying on OCaml's multi-argument evaluation order.",
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
			|| !ordinaryMethod(field) || exactOneIntSignature(field) == null) {
			return null;
		}
		final representation = representations.selectExactInt(OcamlRepresentationDomain.InternalValue);
		final selectedCalleeId = calleeId(classType, field);
		return {
			id: "callable-declaration:" + Sha256.encode(selectedCalleeId).substr(0, 24),
			calleeId: selectedCalleeId,
			sourceModuleId: classType.module,
			sourceTypeName: classType.name,
			sourceFieldName: field.name,
			kind: OcamlCallKind.DirectStaticHaxeMethod,
			arguments: [valuePlan(0, representation)],
			result: valuePlan(-1, representation),
			profileEligibility: ["metal", "portable"],
			reason: "An ordinary static Haxe method with one exact Int argument and exact Int result uses the direct internal int carrier at both definition and call boundaries.",
			proofId: "direct-one-int-static-call-v1",
			proofClaim: "The selected exact Int representation is an identity crossing for one direct Haxe static call. With one source argument, evaluating that argument before invocation preserves the complete argument order without relying on OCaml's multi-argument evaluation order.",
			programRevision: programRevision,
			pipelineRevision: pipelineRevision
		};
	}

	static function exactOneIntSignature(field:ClassField):Null<{argument:Type, result:Type}> {
		return switch (TypeTools.follow(field.type)) {
			case TFun([argument], result)
				if (!argument.opt && OcamlRepresentationRegistry.isExactInt(argument.t) && OcamlRepresentationRegistry.isExactInt(result)):
				{argument: argument.t, result: result};
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
