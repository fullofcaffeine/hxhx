package reflaxe.ocaml.lowered;

#if (macro || reflaxe_runtime)
import haxe.crypto.Sha256;
import haxe.macro.Type;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypeTools;
import reflaxe.data.ClassFuncData;
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureContract;
import reflaxe.ocaml.lowered.OcamlAnonymousStructureModel.OcamlAnonymousStructureDecision;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallCarrierConversion;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallKind;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallResultKind;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallValuePlan;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallPlanner;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallableBoundaryPlan;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;

/** How the compiler proved a function's completed result without admitting new calls. */
enum abstract OcamlFunctionResultBoundarySource(String) from String to String {
	final CallableBoundary = "callable-boundary";
	final StaticInlineExactIntDeclaration = "static-inline-exact-int-declaration";
	final NonGenericInstanceExactIntDeclaration = "non-generic-instance-exact-int-declaration";
	final NonGenericInstanceExactStringDeclaration = "non-generic-instance-exact-string-declaration";
	final NonGenericInstanceEffectOnlyVoidDeclaration = "non-generic-instance-effect-only-void-declaration";
	final StaticNullableAnonymousDeclaration = "static-nullable-anonymous-declaration";
}

/** Exact anonymous-object decision reused by one result-only function boundary. */
typedef OcamlFunctionResultAnonymousStructureProof = {
	final semanticTypeId:String;
	final structureId:String;
	final structureRevision:String;
	final structureProofId:String;
	final representationId:String;
	final representationRevision:String;
}

/**
	The represented value recovered when one generated function finishes.

	A function result boundary answers only this question: after the function body
	finishes normally or exits through a nested `return`, which Haxe value and OCaml
	carrier does the function produce? It does not authorize calls, parameters, or a
	receiver. Those broader facts remain owned by `OcamlCallableBoundaryPlan`.

	The record contains plain strings and copied carrier facts, so reports can retain
	it without keeping Haxe compiler objects alive across requests.
**/
typedef OcamlFunctionResultBoundaryPlan = {
	final id:String;
	final source:OcamlFunctionResultBoundarySource;
	final callableBoundaryId:Null<String>;
	final sourceModuleId:String;
	final sourceTypeName:String;
	final sourceFieldName:String;
	final resultKind:OcamlCallResultKind;
	final result:Null<OcamlCallValuePlan>;
	final anonymousStructure:Null<OcamlFunctionResultAnonymousStructureProof>;
	final profileEligibility:Array<String>;
	final reason:String;
	final proofId:String;
	final proofClaim:String;
	final functionId:String;
	final programRevision:String;
	final bodyRevision:String;
	final pipelineRevision:String;
}

/** Builds and validates result-only function boundaries before target syntax. */
class OcamlFunctionResultBoundary {
	public static inline final MODEL = "typed-ocaml-function-result-boundary-v2";
	public static inline final CALLABLE_RESULT_PROOF_ID = "callable-function-result-boundary-v1";
	public static inline final STATIC_INLINE_EXACT_INT_PROOF_ID = "static-inline-exact-int-function-result-v1";
	public static inline final NON_GENERIC_INSTANCE_EXACT_INT_PROOF_ID = "non-generic-instance-exact-int-function-result-v1";
	public static inline final NON_GENERIC_INSTANCE_EXACT_STRING_PROOF_ID = "non-generic-instance-exact-string-function-result-v1";
	public static inline final NON_GENERIC_INSTANCE_EFFECT_ONLY_VOID_PROOF_ID = "non-generic-instance-effect-only-void-function-result-v1";
	public static inline final STATIC_NULLABLE_ANONYMOUS_PROOF_ID = "static-nullable-anonymous-function-result-v1";

	/**
		Selects one result boundary without expanding the callable ABI.

		Existing admitted callables reuse their result. Declaration-only paths admit
		the existing static inline exact-`Int` tracer, one exact core-`Null` anonymous
		result backed by a direct object literal, plus exact `Int`, `String`, and
		payloadless `Void` results for concrete non-generic instance methods. These
		rules deliberately ignore receiver and parameter ABI; they prove only how the
		already-emitted method finishes.
	**/
	public static function select(data:ClassFuncData, callable:Null<OcamlCallableBoundaryPlan>, representations:OcamlRepresentationRegistry,
			binding:OcamlFunctionPlanBinding, anonymousStructures:OcamlAnonymousStructurePlan):Null<OcamlFunctionResultBoundaryPlan> {
		if (callable != null
			&& (callable.kind == OcamlCallKind.DirectStaticHaxeMethod
				|| callable.kind == OcamlCallKind.DirectInstanceHaxeMethod
				|| callable.kind == OcamlCallKind.TypedFunctionValue)) {
			return fromCallable(callable);
		}
		if (data.expr == null || data.field.isExtern || data.classType.isExtern || data.classType.isInterface || data.classType.params.length > 0
			|| data.field.params.length > 0 || data.field.overloads.get().length > 0) {
			return null;
		}
		switch (data.classType.kind) {
			case KNormal, KAbstractImpl(_):
			case _:
				return null;
		}
		final followedResult = switch (TypeTools.follow(data.field.type)) {
			case TFun(_, result): result;
			case _: null;
		};
		if (followedResult == null)
			return null;
		final exactIntResult = OcamlRepresentationRegistry.isExactInt(followedResult);
		final exactStringResult = OcamlRepresentationRegistry.isExactString(followedResult);
		final effectOnlyVoidResult = OcamlCallPlanner.isExactVoid(followedResult);
		final anonymousSemanticTypeId = nullableAnonymousSemanticTypeId(followedResult);

		var source:OcamlFunctionResultBoundarySource;
		var reason:String;
		var proofId:String;
		var proofClaim:String;
		var semanticTypeId:String;
		var resultKind = OcamlCallResultKind.Value;
		var anonymousStructure:Null<OcamlFunctionResultAnonymousStructureProof> = null;
		if (data.isStatic) {
			if (exactIntResult) {
				final matchesStaticTracer = switch (data.field.kind) {
					case FMethod(MethInline):
						switch (TypeTools.follow(data.field.type)) {
							case TFun(arguments, _): arguments.length == 1 && !arguments[0].opt && OcamlRepresentationRegistry.isExactInt(arguments[0].t);
							case _: false;
						}
					case _: false;
				};
				if (!matchesStaticTracer)
					return null;
				source = OcamlFunctionResultBoundarySource.StaticInlineExactIntDeclaration;
				reason = "The final typed declaration is a static inline function with one required exact Int input, an exact Int result, and function-owned return control. The compiler may therefore recover those returns as Int without claiming that the parameter or call sites use a newly admitted ABI.";
				proofId = STATIC_INLINE_EXACT_INT_PROOF_ID;
				proofClaim = "The followed declaration result and the program representation registry independently select Int -> int. This result-only record authorizes function completion and private return recovery, but no receiver, parameter, or call occurrence.";
				semanticTypeId = "Int";
			} else {
				switch (data.field.kind) {
					case FMethod(MethNormal):
					case _:
						return null;
				}
				if (anonymousSemanticTypeId == null)
					return null;
				final literal = directCompletedObjectLiteral(data.expr);
				if (literal == null || !anonymousStructures.hasLiteral(literal))
					return null;
				final literalPlan = anonymousStructures.requireLiteral(literal, representations);
				final structure = literalPlan.structure;
				if (structure.semanticTypeId != anonymousSemanticTypeId)
					return null;
				anonymousStructure = anonymousProof(structure);
				source = OcamlFunctionResultBoundarySource.StaticNullableAnonymousDeclaration;
				reason = "The final typed declaration is a concrete non-generic static function whose normal completed result is one directly constructed anonymous object. Nested typed null returns may preserve that exact runtime-container carrier without admitting parameters, calls, fields, casts, or other anonymous-value sources.";
				proofId = STATIC_NULLABLE_ANONYMOUS_PROOF_ID;
				proofClaim = "The anonymous-structure planner already fixed the direct result literal's shape, mutable HxAnon container, reference identity, shared aliases, runtime null sentinel, and representation revision. This result-only boundary reuses that exact decision; it does not infer a shape from the declared type or authorize another anonymous crossing.";
				semanticTypeId = structure.semanticTypeId;
			}
		} else {
			switch (data.field.kind) {
				case FMethod(MethNormal):
				case _:
					return null;
			}
			if (effectOnlyVoidResult) {
				source = OcamlFunctionResultBoundarySource.NonGenericInstanceEffectOnlyVoidDeclaration;
				reason = "The final typed declaration is a concrete non-generic instance method with a Void result. The compiler may complete its function-owned payloadless returns without deciding how a receiver, parameter, override, or call site is represented.";
				proofId = NON_GENERIC_INSTANCE_EFFECT_ONLY_VOID_PROOF_ID;
				proofClaim = "The followed instance-method result is exact Haxe Void, which carries no value. This result-only record authorizes function completion through the payloadless return signal, but no receiver, parameter, dispatch, or call occurrence.";
				semanticTypeId = "Void";
				resultKind = OcamlCallResultKind.EffectOnlyVoid;
			} else if (exactIntResult) {
				source = OcamlFunctionResultBoundarySource.NonGenericInstanceExactIntDeclaration;
				reason = "The final typed declaration is a concrete non-generic instance method with an exact Int result. The compiler may recover its function-owned returns as Int without deciding how a receiver, parameter, override, or call site is represented.";
				proofId = NON_GENERIC_INSTANCE_EXACT_INT_PROOF_ID;
				proofClaim = "The followed instance-method result and the program representation registry independently select Int -> int. This result-only record authorizes function completion and private return recovery, but no receiver, parameter, dispatch, or call occurrence.";
				semanticTypeId = "Int";
			} else if (exactStringResult) {
				source = OcamlFunctionResultBoundarySource.NonGenericInstanceExactStringDeclaration;
				reason = "The final typed declaration is a concrete non-generic instance method with an exact String result. The compiler may recover its function-owned returns as String without deciding how a receiver, parameter, override, or call site is represented.";
				proofId = NON_GENERIC_INSTANCE_EXACT_STRING_PROOF_ID;
				proofClaim = "The followed instance-method result and the program representation registry independently select String -> string. This result-only record authorizes function completion and private return recovery, but no receiver, parameter, dispatch, or call occurrence.";
				semanticTypeId = "String";
			} else {
				return null;
			}
		}
		final result:Null<OcamlCallValuePlan> = if (resultKind == OcamlCallResultKind.EffectOnlyVoid) {
			null;
		} else {
			final representation = if (anonymousStructure != null) {
				representations.require(anonymousStructure.representationId, binding.programRevision);
			} else if (semanticTypeId == "Int") {
				representations.selectExactInt(OcamlRepresentationDomain.InternalValue);
			} else {
				representations.selectExactString(OcamlRepresentationDomain.InternalValue);
			};
			{
				index: -1,
				parameterOptional: false,
				inputSemanticTypeId: representation.semanticTypeId,
				inputCarrierTypeId: representation.carrierTypeId,
				inputRepresentationId: representation.id,
				outputSemanticTypeId: representation.semanticTypeId,
				outputCarrierTypeId: representation.carrierTypeId,
				outputRepresentationId: representation.id,
				conversion: OcamlCallCarrierConversion.Identity,
				proofId: "identity-call-carrier-v1",
				proofClaim: 'The final typed function result already uses the exact $semanticTypeId internal carrier, so function completion preserves that carrier without conversion.'
			};
		};
		final selected:OcamlFunctionResultBoundaryPlan = {
			id: "function-result-boundary:" + Sha256.encode(binding.functionId).substr(0, 24),
			source: source,
			callableBoundaryId: null,
			sourceModuleId: data.classType.module,
			sourceTypeName: data.classType.name,
			sourceFieldName: data.field.name,
			resultKind: resultKind,
			result: result,
			anonymousStructure: anonymousStructure,
			profileEligibility: ["metal", "portable"],
			reason: reason,
			proofId: proofId,
			proofClaim: proofClaim,
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: binding.bodyRevision,
			pipelineRevision: binding.pipelineRevision
		};
		require(selected);
		return selected;
	}

	/**
		Drops a declaration-only candidate unless control planning actually used it.

		The selector runs before control planning so the planner can validate an
		early return. Keeping the record afterward requires at least one admitted
		return decision; an ordinary straight-line helper therefore gains no new
		report or generated-function boundary merely because its type also matches.
	**/
	public static function retainAfterControlPlanning(boundary:Null<OcamlFunctionResultBoundaryPlan>,
			hasAdmittedReturn:Bool):Null<OcamlFunctionResultBoundaryPlan> {
		if (boundary != null && boundary.source != OcamlFunctionResultBoundarySource.CallableBoundary && !hasAdmittedReturn)
			return null;
		return boundary;
	}

	/** Copies the result part of an already admitted callable without changing it. */
	public static function fromCallable(callable:OcamlCallableBoundaryPlan):OcamlFunctionResultBoundaryPlan {
		final selected:OcamlFunctionResultBoundaryPlan = {
			id: "function-result-boundary:" + Sha256.encode(callable.functionId).substr(0, 24),
			source: OcamlFunctionResultBoundarySource.CallableBoundary,
			callableBoundaryId: callable.id,
			sourceModuleId: callable.sourceModuleId,
			sourceTypeName: callable.sourceTypeName,
			sourceFieldName: callable.sourceFieldName,
			resultKind: callable.resultKind,
			result: OcamlCallPlan.copyOptionalValue(callable.result),
			anonymousStructure: null,
			profileEligibility: callable.profileEligibility.copy(),
			reason: "The admitted callable already fixes this function's completed result. Control lowering reuses that result and does not create a second conversion decision.",
			proofId: CALLABLE_RESULT_PROOF_ID,
			proofClaim: "The result kind, carrier conversion, function identity, body revision, program revision, and pipeline revision are copied from one validated callable boundary and must remain equal to it.",
			functionId: callable.functionId,
			programRevision: callable.programRevision,
			bodyRevision: callable.bodyRevision,
			pipelineRevision: callable.pipelineRevision
		};
		require(selected);
		return selected;
	}

	/** Returns a detached copy suitable for a sealed plan or report. */
	public static function copy(boundary:OcamlFunctionResultBoundaryPlan):OcamlFunctionResultBoundaryPlan {
		return {
			id: boundary.id,
			source: boundary.source,
			callableBoundaryId: boundary.callableBoundaryId,
			sourceModuleId: boundary.sourceModuleId,
			sourceTypeName: boundary.sourceTypeName,
			sourceFieldName: boundary.sourceFieldName,
			resultKind: boundary.resultKind,
			result: OcamlCallPlan.copyOptionalValue(boundary.result),
			anonymousStructure: copyAnonymousProof(boundary.anonymousStructure),
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

	/** Rejects incomplete, stale, or broadened result-only records. */
	public static function require(boundary:OcamlFunctionResultBoundaryPlan):Void {
		if (boundary.id != "function-result-boundary:" + Sha256.encode(boundary.functionId).substr(0, 24)
			|| boundary.functionId.length == 0
			|| boundary.programRevision.length == 0
			|| boundary.bodyRevision.length == 0
			|| boundary.pipelineRevision.length == 0
			|| boundary.reason.length == 0
			|| boundary.proofClaim.length == 0
			|| boundary.profileEligibility.length != 2
			|| boundary.profileEligibility[0] != "metal"
			|| boundary.profileEligibility[1] != "portable") {
			throw 'reflaxe.ocaml [ocaml-function-result:invalid-plan]: result boundary "${boundary.id}" has incomplete identity, revision, proof, or profile facts';
		}
		switch (boundary.resultKind) {
			case Value:
				if (boundary.result == null)
					throw 'reflaxe.ocaml [ocaml-function-result:invalid-plan]: value result boundary "${boundary.id}" has no carrier';
				OcamlCallPlan.requireCallValue(boundary.result, -1, 'function result boundary "${boundary.id}"');
			case EffectOnlyVoid:
				if (boundary.result != null)
					throw 'reflaxe.ocaml [ocaml-function-result:invalid-plan]: effect-only result boundary "${boundary.id}" carries a value';
			case _:
				throw 'reflaxe.ocaml [ocaml-function-result:invalid-plan]: result boundary "${boundary.id}" has unsupported kind ${boundary.resultKind}';
		}
		switch (boundary.source) {
			case CallableBoundary:
				if (boundary.callableBoundaryId == null
					|| boundary.callableBoundaryId.length == 0
					|| boundary.anonymousStructure != null
					|| boundary.proofId != CALLABLE_RESULT_PROOF_ID)
					throw 'reflaxe.ocaml [ocaml-function-result:invalid-plan]: callable-derived result boundary "${boundary.id}" has no callable owner';
			case StaticInlineExactIntDeclaration:
				requireDeclarationExactValue(boundary, STATIC_INLINE_EXACT_INT_PROOF_ID, "|static|function|", "static inline", "Int", "int");
			case NonGenericInstanceExactIntDeclaration:
				requireDeclarationExactValue(boundary, NON_GENERIC_INSTANCE_EXACT_INT_PROOF_ID, "|instance|function|", "non-generic instance", "Int", "int");
			case NonGenericInstanceExactStringDeclaration:
				requireDeclarationExactValue(boundary, NON_GENERIC_INSTANCE_EXACT_STRING_PROOF_ID, "|instance|function|", "non-generic instance", "String",
					"string");
			case NonGenericInstanceEffectOnlyVoidDeclaration:
				requireDeclarationEffectOnlyVoid(boundary);
			case StaticNullableAnonymousDeclaration:
				requireDeclarationAnonymous(boundary);
		}
	}

	/** Checks that an instance `Void` declaration owns no value or callable facts. */
	static function requireDeclarationEffectOnlyVoid(boundary:OcamlFunctionResultBoundaryPlan):Void {
		if (boundary.callableBoundaryId != null
			|| boundary.anonymousStructure != null
			|| boundary.sourceModuleId.length == 0
			|| boundary.sourceTypeName.length == 0
			|| boundary.sourceFieldName.length == 0
			|| boundary.functionId.indexOf("|instance|function|") < 0
			|| boundary.resultKind != OcamlCallResultKind.EffectOnlyVoid
			|| boundary.result != null
			|| boundary.proofId != NON_GENERIC_INSTANCE_EFFECT_ONLY_VOID_PROOF_ID) {
			throw 'reflaxe.ocaml [ocaml-function-result:invalid-plan]: declaration-derived result boundary "${boundary.id}" exceeds the non-generic instance effect-only Void slice';
		}
	}

	/**
		Checks one exact declaration result without mistaking it for call authority.

		The function identity must also name the declaration mode selected by the
		source record. This catches a report that relabels an instance method as the
		static tracer (or vice versa) while leaving the carrier bytes unchanged.
	**/
	static function requireDeclarationExactValue(boundary:OcamlFunctionResultBoundaryPlan, expectedProofId:String, functionMode:String, label:String,
			semanticTypeId:String, carrierTypeId:String):Void {
		final result = boundary.result;
		final representationId = 'representation:$semanticTypeId:internal-value';
		if (boundary.callableBoundaryId != null
			|| boundary.anonymousStructure != null
			|| boundary.sourceModuleId.length == 0
			|| boundary.sourceTypeName.length == 0
			|| boundary.sourceFieldName.length == 0
			|| boundary.functionId.indexOf(functionMode) < 0
			|| boundary.resultKind != OcamlCallResultKind.Value
			|| result == null
			|| result.inputSemanticTypeId != semanticTypeId
			|| result.inputCarrierTypeId != carrierTypeId
			|| result.inputRepresentationId != representationId
			|| result.outputSemanticTypeId != semanticTypeId
			|| result.outputCarrierTypeId != carrierTypeId
			|| result.outputRepresentationId != representationId
			|| result.conversion != OcamlCallCarrierConversion.Identity
			|| boundary.proofId != expectedProofId) {
			throw 'reflaxe.ocaml [ocaml-function-result:invalid-plan]: declaration-derived result boundary "${boundary.id}" exceeds the $label exact-$semanticTypeId slice';
		}
	}

	/** Checks the exact anonymous structure reused by a result-only static function. */
	static function requireDeclarationAnonymous(boundary:OcamlFunctionResultBoundaryPlan):Void {
		final result = boundary.result;
		final structure = boundary.anonymousStructure;
		if (boundary.callableBoundaryId != null
			|| boundary.sourceModuleId.length == 0
			|| boundary.sourceTypeName.length == 0
			|| boundary.sourceFieldName.length == 0
			|| boundary.functionId.indexOf("|static|function|") < 0
			|| boundary.resultKind != OcamlCallResultKind.Value
			|| result == null
			|| structure == null
			|| !StringTools.startsWith(structure.semanticTypeId, "anonymous{")
			|| !StringTools.endsWith(structure.semanticTypeId, "}")
			|| structure.structureId != OcamlAnonymousStructureContract.structureId(structure.semanticTypeId)
			|| !StringTools.startsWith(structure.structureRevision, "sha256:")
			|| structure.structureProofId != OcamlAnonymousStructureContract.PROOF_ID
			|| structure.representationId != 'representation:${structure.semanticTypeId}:internal-value'
			|| !StringTools.startsWith(structure.representationRevision, "sha256:")
			|| result.inputSemanticTypeId != structure.semanticTypeId
			|| result.inputCarrierTypeId != "Obj.t"
			|| result.inputRepresentationId != structure.representationId
			|| result.outputSemanticTypeId != structure.semanticTypeId
			|| result.outputCarrierTypeId != "Obj.t"
			|| result.outputRepresentationId != structure.representationId
			|| result.conversion != OcamlCallCarrierConversion.Identity
			|| boundary.proofId != STATIC_NULLABLE_ANONYMOUS_PROOF_ID) {
			throw 'reflaxe.ocaml [ocaml-function-result:invalid-plan]: declaration-derived result boundary "${boundary.id}" exceeds the static nullable anonymous-object slice';
		}
	}

	/** Finds only the direct object literal that completes the function body. */
	static function directCompletedObjectLiteral(body:TypedExpr):Null<TypedExpr> {
		final unwrappedBody = unwrapTransparent(body);
		final completed = switch (unwrappedBody.expr) {
			case TBlock(expressions) if (expressions.length > 0): unwrapTransparent(expressions[expressions.length - 1]);
			case _: unwrappedBody;
		};
		return switch (completed.expr) {
			case TReturn(value) if (value != null):
				final unwrappedValue = unwrapTransparent(value);
				switch (unwrappedValue.expr) {
					case TObjectDecl(_): unwrappedValue;
					case _: null;
				}
			case _: null;
		};
	}

	static function unwrapTransparent(expression:TypedExpr):TypedExpr {
		return switch (expression.expr) {
			case TMeta(_, child), TParenthesis(child): unwrapTransparent(child);
			case _: expression;
		};
	}

	/** Returns the shape only for the direct core `Null<anonymous object>` form. */
	static function nullableAnonymousSemanticTypeId(type:Type):Null<String> {
		return switch (type) {
			case TAbstract(abstractRef, [inner]): final abstractType = abstractRef.get(); abstractType.pack.length == 0 && abstractType.name == "Null" ? OcamlAnonymousStructurePlan.semanticTypeIdForType(inner) : null;
			case _:
				null;
		};
	}

	static function anonymousProof(structure:OcamlAnonymousStructureDecision):OcamlFunctionResultAnonymousStructureProof {
		OcamlAnonymousStructureContract.requireStructure(structure);
		return {
			semanticTypeId: structure.semanticTypeId,
			structureId: structure.id,
			structureRevision: structure.revision,
			structureProofId: structure.proofId,
			representationId: structure.representationId,
			representationRevision: structure.representationRevision
		};
	}

	static function copyAnonymousProof(proof:Null<OcamlFunctionResultAnonymousStructureProof>):Null<OcamlFunctionResultAnonymousStructureProof> {
		return proof == null ? null : {
			semanticTypeId: proof.semanticTypeId,
			structureId: proof.structureId,
			structureRevision: proof.structureRevision,
			structureProofId: proof.structureProofId,
			representationId: proof.representationId,
			representationRevision: proof.representationRevision
		};
	}

	/** Requires a callable-derived result record to remain identical to its owner. */
	public static function requireCallableMatch(boundary:OcamlFunctionResultBoundaryPlan, callable:OcamlCallableBoundaryPlan):Void {
		require(boundary);
		if (boundary.source != OcamlFunctionResultBoundarySource.CallableBoundary
			|| boundary.callableBoundaryId != callable.id
			|| boundary.functionId != callable.functionId
			|| boundary.programRevision != callable.programRevision
			|| boundary.bodyRevision != callable.bodyRevision
			|| boundary.pipelineRevision != callable.pipelineRevision
			|| boundary.resultKind != callable.resultKind
			|| !sameOptionalValue(boundary.result, callable.result)) {
			throw 'reflaxe.ocaml [ocaml-function-result:callable-mismatch]: result boundary "${boundary.id}" disagrees with callable boundary "${callable.id}"';
		}
	}

	static function sameOptionalValue(left:Null<OcamlCallValuePlan>, right:Null<OcamlCallValuePlan>):Bool {
		if (left == null || right == null)
			return left == null && right == null;
		return OcamlCallPlan.sameValue(left, right);
	}
}
#end
