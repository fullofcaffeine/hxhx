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
import reflaxe.ocaml.lowered.OcamlEnumDynamicCarrier.OcamlEnumDynamicCarrierIdentity;
import reflaxe.ocaml.lowered.OcamlLoweredOrigin.OcamlLoweredSourceSpan;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationDomain;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationAliasingPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationBoxingPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationIdentityPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationImplicitDefaultPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationNullPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationStorageMutationPolicy;
import reflaxe.ocaml.lowered.OcamlRepresentationModel.OcamlRepresentationValueMutationPolicy;

/** How the compiler proved a function's completed result without admitting new calls. */
enum abstract OcamlFunctionResultBoundarySource(String) from String to String {
	final CallableBoundary = "callable-boundary";
	final StaticInlineExactIntDeclaration = "static-inline-exact-int-declaration";
	final NonGenericInstanceExactIntDeclaration = "non-generic-instance-exact-int-declaration";
	final NonGenericInstanceExactStringDeclaration = "non-generic-instance-exact-string-declaration";
	final NonGenericInstanceEffectOnlyVoidDeclaration = "non-generic-instance-effect-only-void-declaration";
	final NonGenericInstanceNullableEnumDeclaration = "non-generic-instance-nullable-enum-declaration";
	final NonGenericStaticNullableEnumDeclaration = "non-generic-static-nullable-enum-declaration";
	final NonGenericStaticAllReturnNullableBoolDeclaration = "non-generic-static-all-return-nullable-bool-declaration";
	final NestedNullableEnumCallable = "nested-nullable-enum-callable";
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

/** Exact enum identity and source value used by one nullable-enum result crossing. */
typedef OcamlFunctionResultNullableEnumProof = {
	final semanticTypeId:String;
	final nullableSemanticTypeId:String;
	final carrierTypeId:String;
	final source:OcamlLoweredSourceSpan;
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
	final nullableEnum:Null<OcamlFunctionResultNullableEnumProof>;
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
	public static inline final MODEL = "typed-ocaml-function-result-boundary-v5";
	public static inline final CALLABLE_RESULT_PROOF_ID = "callable-function-result-boundary-v1";
	public static inline final STATIC_INLINE_EXACT_INT_PROOF_ID = "static-inline-exact-int-function-result-v1";
	public static inline final NON_GENERIC_INSTANCE_EXACT_INT_PROOF_ID = "non-generic-instance-exact-int-function-result-v1";
	public static inline final NON_GENERIC_INSTANCE_EXACT_STRING_PROOF_ID = "non-generic-instance-exact-string-function-result-v1";
	public static inline final NON_GENERIC_INSTANCE_EFFECT_ONLY_VOID_PROOF_ID = "non-generic-instance-effect-only-void-function-result-v1";
	public static inline final NON_GENERIC_INSTANCE_NULLABLE_ENUM_PROOF_ID = "non-generic-instance-nullable-enum-function-result-v1";
	public static inline final NON_GENERIC_STATIC_NULLABLE_ENUM_PROOF_ID = "non-generic-static-nullable-enum-function-result-v1";
	public static inline final NON_GENERIC_STATIC_ALL_RETURN_NULLABLE_BOOL_PROOF_ID = "non-generic-static-all-return-nullable-bool-function-result-v1";
	public static inline final NESTED_NULLABLE_ENUM_PROOF_ID = "nested-nullable-enum-function-result-v1";
	public static inline final STATIC_NULLABLE_ANONYMOUS_PROOF_ID = "static-nullable-anonymous-function-result-v1";

	/**
		Selects one result boundary without expanding the callable ABI.

		Existing admitted callables reuse their result. Declaration-only paths admit
		the existing static inline exact-`Int` tracer, one exact core-`Null` anonymous
		result backed by a direct object literal, exact nullable-enum results from a
		proven final value, plus exact `Int`, `String`, and payloadless `Void` results
		for concrete non-generic instance methods. These rules deliberately ignore
		receiver and parameter ABI. They prove only how the emitted method finishes.
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
		final nullableBoolResult = OcamlRepresentationRegistry.isExactNullBool(followedResult);
		final completedNullableBool = nullableBoolResult ? directCompletedValue(data.expr) : null;
		final anonymousSemanticTypeId = nullableAnonymousSemanticTypeId(followedResult);
		final nullableEnumIdentity = nullableEnumIdentity(followedResult);

		var source:OcamlFunctionResultBoundarySource;
		var reason:String;
		var proofId:String;
		var proofClaim:String;
		var semanticTypeId:String;
		var resultKind = OcamlCallResultKind.Value;
		var anonymousStructure:Null<OcamlFunctionResultAnonymousStructureProof> = null;
		var nullableEnum:Null<OcamlFunctionResultNullableEnumProof> = null;
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
			} else if (completedNullableBool != null
				&& OcamlRepresentationRegistry.isExactBool(completedNullableBool.t)
				&& OcamlControlFlowFacts.definitelyReturns(data.expr)) {
				switch (data.field.kind) {
					case FMethod(MethNormal):
					case _:
						return null;
				}
				source = OcamlFunctionResultBoundarySource.NonGenericStaticAllReturnNullableBoolDeclaration;
				reason = "The concrete non-generic static function declares Null<Bool>, and every path in its final typed body exits through function-owned return control. The result-only boundary can therefore recover the selected Obj.t carrier without deciding how its parameters or call sites are represented.";
				proofId = NON_GENERIC_STATIC_ALL_RETURN_NULLABLE_BOOL_PROOF_ID;
				proofClaim = "The declared core Null<Bool> result selects the existing Obj.t carrier, the final normal-completion value is exact Bool, and control-flow facts prove every other path returns. The completion value and each return occurrence must independently enter the nullable carrier. This proof authorizes no parameter or call ABI.";
				semanticTypeId = "Null<Bool>";
			} else if (nullableEnumIdentity != null) {
				switch (data.field.kind) {
					case FMethod(MethNormal):
					case _:
						return null;
				}
				final completedEnum = completedExactEnumValue(data.expr, nullableEnumIdentity.semanticTypeId);
				if (completedEnum == null)
					return null;
				nullableEnum = nullableEnumProof(nullableEnumIdentity, completedEnum);
				source = OcamlFunctionResultBoundarySource.NonGenericStaticNullableEnumDeclaration;
				reason = "The concrete non-generic static function declares Null<Enum>, and the final typed value on its normal completion path has that exact enum identity. The function boundary stores the normal value in Obj.t before it enters the nullable result carrier.";
				proofId = NON_GENERIC_STATIC_NULLABLE_ENUM_PROOF_ID;
				proofClaim = "The declared core Null<Enum> result and final typed normal-completion value agree on one ordinary Haxe enum identity. Obj.repr preserves that native variant while typed null returns use the same Obj.t carrier. This result-only proof does not authorize parameters, calls, fields, constructors, or other enum values.";
				semanticTypeId = nullableEnum.nullableSemanticTypeId;
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
			} else if (nullableEnumIdentity != null) {
				final completedEnum = directCompletedEnumValue(data.expr);
				final completedIdentity = completedEnum == null ? null : OcamlEnumDynamicCarrier.fromDirectValue(completedEnum);
				if (completedIdentity == null || completedIdentity.semanticTypeId != nullableEnumIdentity.semanticTypeId)
					return null;
				nullableEnum = nullableEnumProof(nullableEnumIdentity, completedEnum);
				source = OcamlFunctionResultBoundarySource.NonGenericInstanceNullableEnumDeclaration;
				reason = "The concrete non-generic instance method declares Null<Enum> and its normal completion directly constructs that exact enum. The function boundary stores the native OCaml variant in Obj.t before it enters the nullable result carrier.";
				proofId = NON_GENERIC_INSTANCE_NULLABLE_ENUM_PROOF_ID;
				proofClaim = "The final typed declaration and direct constructor agree on one ordinary Haxe enum identity. Obj.repr preserves that native variant for both normal completion and admitted early returns. The static nullable-enum type retains the enum identity, so this boundary does not create a Dynamic value or admit enum-valued calls, fields, locals, or unrelated constructors.";
				semanticTypeId = nullableEnum.nullableSemanticTypeId;
			} else {
				return null;
			}
		}
		final result:Null<OcamlCallValuePlan> = if (resultKind == OcamlCallResultKind.EffectOnlyVoid) {
			null;
		} else {
			if (nullableEnum != null) {
				nullableEnumResultValue(nullableEnum, representations);
			} else if (semanticTypeId == "Null<Bool>") {
				final input = representations.selectExactBool(OcamlRepresentationDomain.InternalValue);
				final output = representations.selectExactNullBool(OcamlRepresentationDomain.InternalValue);
				{
					index: -1,
					parameterOptional: false,
					inputSemanticTypeId: input.semanticTypeId,
					inputCarrierTypeId: input.carrierTypeId,
					inputRepresentationId: input.id,
					outputSemanticTypeId: output.semanticTypeId,
					outputCarrierTypeId: output.carrierTypeId,
					outputRepresentationId: output.id,
					conversion: OcamlCallCarrierConversion.BoxExactBoolToNullableBool,
					proofId: "nullable-bool-call-box-v1",
					proofClaim: "The exact Bool normal-completion value is boxed once into the declared Null<Bool> Obj.t carrier."
				};
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
			}
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
			nullableEnum: nullableEnum,
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
		Selects the first result-changing boundary for a nested function literal.

		This narrow slice accepts a zero-argument helper declared as `Null<Enum>`
		when its normal completion has that exact enum type. The callable still
		exports the nullable `Obj.t` carrier. Only the helper body crosses from the
		native OCaml enum variant into that carrier. Early returns are accepted later
		only when the control planner proves each `null` or enum path separately.
	**/
	public static function selectNestedNullableEnumCallable(tfunc:haxe.macro.Type.TFunc, representations:OcamlRepresentationRegistry,
			binding:OcamlFunctionPlanBinding):Null<OcamlCallableBoundaryPlan> {
		if (tfunc.args.length != 0)
			return null;
		final resultType = switch (TypeTools.follow(tfunc.t)) {
			case TFun(_, result): result;
			case _: tfunc.t;
		};
		final identity = nullableEnumIdentity(resultType);
		if (identity == null)
			return null;
		final completed = completedExactEnumValue(tfunc.expr, identity.semanticTypeId);
		if (completed == null)
			return null;
		final proof = nullableEnumProof(identity, completed);
		final result = nullableEnumResultValue(proof, representations);
		final signatureId = '()->${proof.nullableSemanticTypeId}';
		return {
			id: "nested-callable-boundary:" + Sha256.encode(binding.functionId).substr(0, 24),
			calleeId: binding.functionId,
			sourceModuleId: "",
			sourceTypeName: "",
			sourceFieldName: "",
			kind: OcamlCallKind.TypedFunctionValue,
			receiver: null,
			arguments: [],
			resultKind: OcamlCallResultKind.Value,
			result: result,
			profileEligibility: ["metal", "portable"],
			reason: "The zero-argument nested helper declares one exact nullable-enum result. Its native enum completion enters Obj.t once, while sealed early returns preserve the same nullable carrier.",
			proofId: OcamlCallPlan.FUNCTION_VALUE_SIGNATURE_PROOF_ID_PREFIX + signatureId,
			proofClaim: "The final typed function literal, its declared core Null<Enum> result, and its normal enum completion agree on one enum identity. This boundary changes only the function result carrier and does not admit enum parameters, fields, or unrelated calls.",
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: binding.bodyRevision,
			pipelineRevision: binding.pipelineRevision
		};
	}

	/** Registers both sides of one exact enum-to-nullable result crossing. */
	static function nullableEnumResultValue(proof:OcamlFunctionResultNullableEnumProof, representations:OcamlRepresentationRegistry):OcamlCallValuePlan {
		final inputRepresentation = representations.register({
			semanticTypeId: proof.semanticTypeId,
			domain: OcamlRepresentationDomain.InternalValue,
			carrierTypeId: proof.carrierTypeId,
			nullPolicy: OcamlRepresentationNullPolicy.NonNull,
			identityPolicy: OcamlRepresentationIdentityPolicy.PrimitiveValue,
			aliasingPolicy: OcamlRepresentationAliasingPolicy.NoValueAlias,
			storageMutationPolicy: OcamlRepresentationStorageMutationPolicy.ImmutableBinding,
			valueMutationPolicy: OcamlRepresentationValueMutationPolicy.ImmutableValue,
			boxingPolicy: OcamlRepresentationBoxingPolicy.DirectUnboxed,
			implicitDefaultPolicy: OcamlRepresentationImplicitDefaultPolicy.NotAdmitted,
			reason: "One exact ordinary Haxe enum value completes a sealed nullable-enum function result as its native OCaml variant.",
			proof: {
				id: "exact-enum-function-result-input-v1",
				claim: "The final typed expression has the exact enum identity before syntax generation."
			},
			profileEligibility: ["metal", "portable"]
		});
		final outputRepresentation = representations.register({
			semanticTypeId: proof.nullableSemanticTypeId,
			domain: OcamlRepresentationDomain.InternalValue,
			carrierTypeId: "Obj.t",
			nullPolicy: OcamlRepresentationNullPolicy.RuntimeSentinel,
			identityPolicy: OcamlRepresentationIdentityPolicy.PrimitiveValue,
			aliasingPolicy: OcamlRepresentationAliasingPolicy.NoValueAlias,
			storageMutationPolicy: OcamlRepresentationStorageMutationPolicy.ImmutableBinding,
			valueMutationPolicy: OcamlRepresentationValueMutationPolicy.ImmutableValue,
			boxingPolicy: OcamlRepresentationBoxingPolicy.DirectRuntimeContainer,
			implicitDefaultPolicy: OcamlRepresentationImplicitDefaultPolicy.NotAdmitted,
			reason: "The exact nullable enum result uses Obj.t so it can preserve either the Haxe null sentinel or the native enum variant.",
			proof: {
				id: "nullable-enum-function-result-output-v1",
				claim: "The declared core Null<Enum> type and final exact enum value fix both the nullable carrier and its enum identity."
			},
			profileEligibility: ["metal", "portable"]
		});
		return {
			index: -1,
			parameterOptional: false,
			inputSemanticTypeId: proof.semanticTypeId,
			inputCarrierTypeId: proof.carrierTypeId,
			inputRepresentationId: inputRepresentation.id,
			outputSemanticTypeId: proof.nullableSemanticTypeId,
			outputCarrierTypeId: "Obj.t",
			outputRepresentationId: outputRepresentation.id,
			conversion: OcamlCallCarrierConversion.BoxExactEnumToNullableEnum,
			proofId: "nullable-enum-function-result-box-v1",
			proofClaim: "The exact native enum variant enters its declared nullable result through one Obj.repr operation. Its static Null<Enum> type keeps the exact enum identity without a Dynamic runtime-name box."
		};
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
			nullableEnum: null,
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

	/**
		Binds a nested nullable-enum body conversion to its callable result.

		The callable tells callers that the helper returns `Null<Enum>` in `Obj.t`.
		This result record adds the missing body-side fact: normal completion starts
		as the native enum variant and must enter `Obj.t` before the helper returns.
	**/
	public static function fromNestedNullableEnum(callable:OcamlCallableBoundaryPlan, tfunc:haxe.macro.Type.TFunc):OcamlFunctionResultBoundaryPlan {
		if (callable.kind != OcamlCallKind.TypedFunctionValue
			|| callable.resultKind != OcamlCallResultKind.Value
			|| callable.result == null
			|| !OcamlCallPlan.isExactEnumToNullableResult(callable.result)) {
			throw 'reflaxe.ocaml [ocaml-function-result:invalid-plan]: nested nullable-enum result requires one exact enum-to-nullable callable result';
		}
		final resultType = switch (TypeTools.follow(tfunc.t)) {
			case TFun(_, result): result;
			case _: tfunc.t;
		};
		final identity = nullableEnumIdentity(resultType);
		final completed = identity == null ? null : completedExactEnumValue(tfunc.expr, identity.semanticTypeId);
		if (identity == null || completed == null)
			throw 'reflaxe.ocaml [ocaml-function-result:invalid-plan]: nested nullable-enum callable lost its declared type or normal enum completion';
		final proof = nullableEnumProof(identity, completed);
		final selected:OcamlFunctionResultBoundaryPlan = {
			id: "function-result-boundary:" + Sha256.encode(callable.functionId).substr(0, 24),
			source: OcamlFunctionResultBoundarySource.NestedNullableEnumCallable,
			callableBoundaryId: callable.id,
			sourceModuleId: "",
			sourceTypeName: "",
			sourceFieldName: "",
			resultKind: callable.resultKind,
			result: OcamlCallPlan.copyOptionalValue(callable.result),
			anonymousStructure: null,
			nullableEnum: proof,
			profileEligibility: callable.profileEligibility.copy(),
			reason: "The nested helper callable exports one exact Null<Enum> Obj.t result. This body boundary proves that its normal native enum value enters that carrier before the function returns.",
			proofId: NESTED_NULLABLE_ENUM_PROOF_ID,
			proofClaim: "The nested callable result, declared Null<Enum> type, normal completion value, function identity, body revision, program revision, and pipeline revision agree on one exact enum-to-nullable crossing.",
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
			nullableEnum: copyNullableEnumProof(boundary.nullableEnum),
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
					|| boundary.nullableEnum != null
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
			case NonGenericInstanceNullableEnumDeclaration:
				requireDeclarationNullableEnum(boundary, false);
			case NonGenericStaticNullableEnumDeclaration:
				requireDeclarationNullableEnum(boundary, true);
			case NonGenericStaticAllReturnNullableBoolDeclaration:
				requireDeclarationNullableBool(boundary);
			case NestedNullableEnumCallable:
				requireNestedNullableEnum(boundary);
			case StaticNullableAnonymousDeclaration:
				requireDeclarationAnonymous(boundary);
		}
	}

	/** Rejects a nested result record that lost its callable or enum identity. */
	static function requireNestedNullableEnum(boundary:OcamlFunctionResultBoundaryPlan):Void {
		final result = boundary.result;
		final proof = boundary.nullableEnum;
		final expectedCallableBoundaryId = "nested-callable-boundary:" + Sha256.encode(boundary.functionId).substr(0, 24);
		if (boundary.callableBoundaryId != expectedCallableBoundaryId
			|| boundary.anonymousStructure != null
			|| boundary.sourceModuleId.length != 0
			|| boundary.sourceTypeName.length != 0
			|| boundary.sourceFieldName.length != 0
			|| boundary.functionId.indexOf("|nested-function|") < 0
			|| boundary.resultKind != OcamlCallResultKind.Value
			|| result == null
			|| proof == null
			|| proof.semanticTypeId.length == 0
			|| proof.nullableSemanticTypeId != 'Null<${proof.semanticTypeId}>'
			|| proof.carrierTypeId != '${OcamlEnumDynamicCarrier.CARRIER_MODEL}:${proof.semanticTypeId}'
			|| result.inputSemanticTypeId != proof.semanticTypeId
			|| result.inputCarrierTypeId != proof.carrierTypeId
			|| result.outputSemanticTypeId != proof.nullableSemanticTypeId
			|| result.outputCarrierTypeId != "Obj.t"
			|| !OcamlCallPlan.isExactEnumToNullableResult(result)
			|| boundary.proofId != NESTED_NULLABLE_ENUM_PROOF_ID) {
			throw 'reflaxe.ocaml [ocaml-function-result:invalid-plan]: nested result boundary "${boundary.id}" exceeds the exact nullable-enum callable slice';
		}
	}

	/** Checks that an instance `Void` declaration owns no value or callable facts. */
	static function requireDeclarationEffectOnlyVoid(boundary:OcamlFunctionResultBoundaryPlan):Void {
		if (boundary.callableBoundaryId != null
			|| boundary.anonymousStructure != null
			|| boundary.nullableEnum != null
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
			|| boundary.nullableEnum != null
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

	/** Rejects a result-only nullable Boolean boundary that widened into call authority. */
	static function requireDeclarationNullableBool(boundary:OcamlFunctionResultBoundaryPlan):Void {
		final result = boundary.result;
		if (boundary.callableBoundaryId != null
			|| boundary.anonymousStructure != null
			|| boundary.nullableEnum != null
			|| boundary.sourceModuleId.length == 0
			|| boundary.sourceTypeName.length == 0
			|| boundary.sourceFieldName.length == 0
			|| boundary.functionId.indexOf("|static|function|") < 0
			|| boundary.resultKind != OcamlCallResultKind.Value
			|| result == null
			|| result.inputSemanticTypeId != "Bool"
			|| result.inputCarrierTypeId != "bool"
			|| result.inputRepresentationId != "representation:Bool:internal-value"
			|| result.outputSemanticTypeId != "Null<Bool>"
			|| result.outputCarrierTypeId != "Obj.t"
			|| result.outputRepresentationId != "representation:Null<Bool>:internal-value"
			|| result.conversion != OcamlCallCarrierConversion.BoxExactBoolToNullableBool
			|| result.proofId != "nullable-bool-call-box-v1"
			|| boundary.proofId != NON_GENERIC_STATIC_ALL_RETURN_NULLABLE_BOOL_PROOF_ID) {
			throw 'reflaxe.ocaml [ocaml-function-result:invalid-plan]: declaration-derived result boundary "${boundary.id}" exceeds the non-generic static all-return Null<Bool> slice';
		}
	}

	/** Rejects a nullable-enum result whose exact enum identity proof was changed. */
	static function requireDeclarationNullableEnum(boundary:OcamlFunctionResultBoundaryPlan, isStatic:Bool):Void {
		final result = boundary.result;
		final proof = boundary.nullableEnum;
		if (boundary.callableBoundaryId != null
			|| boundary.anonymousStructure != null
			|| boundary.sourceModuleId.length == 0
			|| boundary.sourceTypeName.length == 0
			|| boundary.sourceFieldName.length == 0
			|| boundary.functionId.indexOf(isStatic ? "|static|function|" : "|instance|function|") < 0
			|| boundary.resultKind != OcamlCallResultKind.Value
			|| result == null
			|| proof == null
			|| proof.semanticTypeId.length == 0
			|| proof.nullableSemanticTypeId != 'Null<${proof.semanticTypeId}>'
			|| proof.carrierTypeId != '${OcamlEnumDynamicCarrier.CARRIER_MODEL}:${proof.semanticTypeId}'
			|| proof.source.file.length == 0
			|| proof.source.min < 0
			|| proof.source.max < proof.source.min
			|| result.inputSemanticTypeId != proof.semanticTypeId
			|| result.inputCarrierTypeId != proof.carrierTypeId
			|| result.outputSemanticTypeId != proof.nullableSemanticTypeId
			|| result.outputCarrierTypeId != "Obj.t"
			|| result.conversion != OcamlCallCarrierConversion.BoxExactEnumToNullableEnum
			|| boundary.proofId != (isStatic ? NON_GENERIC_STATIC_NULLABLE_ENUM_PROOF_ID : NON_GENERIC_INSTANCE_NULLABLE_ENUM_PROOF_ID)) {
			throw 'reflaxe.ocaml [ocaml-function-result:invalid-plan]: declaration-derived result boundary "${boundary.id}" exceeds the nullable-enum ${isStatic ? "static-function" : "instance-method"} slice';
		}
	}

	/** Checks the exact anonymous structure reused by a result-only static function. */
	static function requireDeclarationAnonymous(boundary:OcamlFunctionResultBoundaryPlan):Void {
		final result = boundary.result;
		final structure = boundary.anonymousStructure;
		if (boundary.callableBoundaryId != null
			|| boundary.nullableEnum != null
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

	/** Returns the value from the final direct return that completes a function body. */
	static function directCompletedValue(body:TypedExpr):Null<TypedExpr> {
		final unwrappedBody = unwrapTransparent(body);
		final completed = switch (unwrappedBody.expr) {
			case TBlock(expressions) if (expressions.length > 0): unwrapTransparent(expressions[expressions.length - 1]);
			case _: unwrappedBody;
		};
		return switch (completed.expr) {
			case TReturn(value) if (value != null): unwrapTransparent(value);
			case _: null;
		};
	}

	/** Finds only the direct enum constructor that completes the function body. */
	static function directCompletedEnumValue(body:TypedExpr):Null<TypedExpr> {
		final unwrappedBody = unwrapTransparent(body);
		final completed = switch (unwrappedBody.expr) {
			case TBlock(expressions) if (expressions.length > 0): unwrapTransparent(expressions[expressions.length - 1]);
			case _: unwrappedBody;
		};
		return switch (completed.expr) {
			case TReturn(value) if (value != null):
				final unwrappedValue = unwrapTransparent(value);
				OcamlEnumDynamicCarrier.fromDirectValue(unwrappedValue) == null ? null : unwrappedValue;
			case _: null;
		};
	}

	/**
		Finds the final typed value on one normal completion path.

		This accepts an exact enum-producing call or local only when Haxe assigned the
		final expression that enum type. It does not prove any call ABI. The caller
		uses the value only to seal this function's declared nullable result carrier.
	**/
	static function completedExactEnumValue(body:TypedExpr, semanticTypeId:String):Null<TypedExpr> {
		final unwrappedBody = unwrapTransparent(body);
		final completed = switch (unwrappedBody.expr) {
			case TBlock(expressions) if (expressions.length > 0): unwrapTransparent(expressions[expressions.length - 1]);
			case _: unwrappedBody;
		};
		return switch (completed.expr) {
			case TReturn(value) if (value != null): final unwrappedValue = unwrapTransparent(value); final identity = OcamlEnumDynamicCarrier.fromType(unwrappedValue.t); identity != null && identity.semanticTypeId == semanticTypeId ? unwrappedValue : null;
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

	/** Returns the inner ordinary enum only for the direct core Null<Enum> form. */
	static function nullableEnumIdentity(type:Type):Null<OcamlEnumDynamicCarrierIdentity> {
		return switch (type) {
			case TAbstract(abstractRef, [inner]): final abstractType = abstractRef.get(); abstractType.pack.length == 0 && abstractType.name == "Null" ? OcamlEnumDynamicCarrier.fromType(inner) : null;
			case _: null;
		};
	}

	/** Copies one exact enum identity and its normal-completion source into the result proof. */
	static function nullableEnumProof(identity:OcamlEnumDynamicCarrierIdentity, completed:TypedExpr):OcamlFunctionResultNullableEnumProof {
		return {
			semanticTypeId: identity.semanticTypeId,
			nullableSemanticTypeId: 'Null<${identity.semanticTypeId}>',
			carrierTypeId: identity.carrierTypeId,
			source: OcamlLoweredOrigin.sourceSpan(completed.pos)
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

	static function copyNullableEnumProof(proof:Null<OcamlFunctionResultNullableEnumProof>):Null<OcamlFunctionResultNullableEnumProof> {
		return proof == null ? null : {
			semanticTypeId: proof.semanticTypeId,
			nullableSemanticTypeId: proof.nullableSemanticTypeId,
			carrierTypeId: proof.carrierTypeId,
			source: {
				file: proof.source.file,
				min: proof.source.min,
				max: proof.source.max
			}
		};
	}

	/** Requires a callable-derived result record to remain identical to its owner. */
	public static function requireCallableMatch(boundary:OcamlFunctionResultBoundaryPlan, callable:OcamlCallableBoundaryPlan):Void {
		require(boundary);
		if ((boundary.source != OcamlFunctionResultBoundarySource.CallableBoundary
			&& boundary.source != OcamlFunctionResultBoundarySource.NestedNullableEnumCallable)
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
