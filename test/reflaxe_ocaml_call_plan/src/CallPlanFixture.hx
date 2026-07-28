import haxe.macro.Context;
import haxe.macro.Expr;
import reflaxe.ocaml.OcamlCompiler;
import reflaxe.ocaml.lowered.OcamlCallPlan;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallCarrierConversion;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallDecision;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallEvaluationStep;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallEvaluationStepKind;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallKind;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallPlanner;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallResultKind;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallValuePlan;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallableBoundaryPlan;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallableDeclarationPlan;
import reflaxe.ocaml.lowered.OcamlBytesProducerPlan;
import reflaxe.ocaml.lowered.OcamlControlPlan;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlFunctionPlanRegistry;
import reflaxe.ocaml.lowered.OcamlLocalRepresentationPlan;
import reflaxe.ocaml.lowered.OcamlLocalStoragePlanner;

/**
	Checks typed-call registry invariants and the pre-write lifecycle boundary.

	The executable portable fixture covers real Haxe typing and runtime behavior;
	this fixture deliberately corrupts model records so missing, duplicate, stale,
	and conflicting plans are proven to fail closed. It also gives Reflaxe a
	sentinel output and proves incomplete whole-program facts are rejected before
	that file can be written.
**/
@:access(reflaxe.ocaml.OcamlCompiler)
class CallPlanFixture {
	static var expectedFailureIndex = 0;

	static inline final PROGRAM_REVISION = "program:call-plan-fixture";
	static inline final CALLEE_ID = "Arithmetic|Arithmetic::increment";
	static inline final CALL_ID = "call:fixture";
	static inline final TWO_CALLEE_ID = "Arithmetic|Arithmetic::add";
	static inline final TWO_CALL_ID = "call:two-argument-fixture";
	static inline final NULLABLE_CALLEE_ID = "NullableCalls|NullableCalls::identity";
	static inline final NULLABLE_PRESERVE_CALL_ID = "call:nullable-preserve-fixture";
	static inline final NULLABLE_BOX_CALL_ID = "call:nullable-box-fixture";
	static inline final BOOL_CALLEE_ID = "BoolCalls|BoolCalls::negate";
	static inline final BOOL_CALL_ID = "call:bool-fixture";
	static inline final NULLABLE_BOOL_CALLEE_ID = "BoolCalls|BoolCalls::identityNullable";
	static inline final NULLABLE_BOOL_PRESERVE_CALL_ID = "call:nullable-bool-preserve-fixture";
	static inline final NULLABLE_BOOL_BOX_CALL_ID = "call:nullable-bool-box-fixture";
	static inline final MIXED_CALLEE_ID = "MixedCalls|MixedCalls::choose";
	static inline final MIXED_PRESERVE_CALL_ID = "call:mixed-preserve-fixture";
	static inline final MIXED_BOX_CALL_ID = "call:mixed-box-fixture";
	static inline final ZERO_CALLEE_ID = "ZeroArgCalls|ZeroArgCalls::exactCount";
	static inline final ZERO_CALL_ID = "call:zero-argument-fixture";
	static inline final OPTIONAL_CALLEE_ID = "OptionalCalls|OptionalCalls::optionalInt";
	static inline final OPTIONAL_OMITTED_CALL_ID = "call:optional-omitted-fixture";
	static inline final OPTIONAL_SUPPLIED_CALL_ID = "call:optional-supplied-fixture";
	static inline final VOID_CALLEE_ID = "VoidCalls|VoidCalls::withArguments";
	static inline final VOID_CALL_ID = "call:void-fixture";
	static inline final FUNCTION_VALUE_CALLEE_ID = "function-value:fixture";
	static inline final FUNCTION_VALUE_CALL_ID = "call:function-value-fixture";
	static inline final OPTIONAL_STRING_FUNCTION_VALUE_CALLEE_ID = "function-value:optional-string-fixture";
	static inline final OPTIONAL_STRING_FUNCTION_VALUE_CALL_ID = "call:optional-string-function-value-fixture";
	static inline final CONSTRUCTOR_CALLEE_ID = "Counter|Counter::new";
	static inline final CONSTRUCTOR_CALL_ID = "call:constructor-fixture";

	static function value(index:Int):OcamlCallValuePlan {
		return {
			index: index,
			parameterOptional: false,
			inputSemanticTypeId: "Int",
			inputCarrierTypeId: "int",
			inputRepresentationId: "representation:Int:internal-value",
			outputSemanticTypeId: "Int",
			outputCarrierTypeId: "int",
			outputRepresentationId: "representation:Int:internal-value",
			conversion: OcamlCallCarrierConversion.Identity,
			proofId: "identity-call-carrier-v1",
			proofClaim: "fixture identity"
		};
	}

	static function nominalCounterValue(index:Int):OcamlCallValuePlan {
		return {
			index: index,
			parameterOptional: false,
			inputSemanticTypeId: "Counter",
			inputCarrierTypeId: "counter_t",
			inputRepresentationId: "representation:Counter:internal-value",
			outputSemanticTypeId: "Counter",
			outputCarrierTypeId: "counter_t",
			outputRepresentationId: "representation:Counter:internal-value",
			conversion: OcamlCallCarrierConversion.Identity,
			proofId: "identity-call-carrier-v1",
			proofClaim: "fixture exact nominal Counter carrier"
		};
	}

	static function nullableValue(index:Int):OcamlCallValuePlan {
		return {
			index: index,
			parameterOptional: false,
			inputSemanticTypeId: "Null<Int>",
			inputCarrierTypeId: "Obj.t",
			inputRepresentationId: "representation:Null<Int>:internal-value",
			outputSemanticTypeId: "Null<Int>",
			outputCarrierTypeId: "Obj.t",
			outputRepresentationId: "representation:Null<Int>:internal-value",
			conversion: OcamlCallCarrierConversion.Identity,
			proofId: "identity-call-carrier-v1",
			proofClaim: "fixture nullable identity"
		};
	}

	static function optionalNullableValue(index:Int):OcamlCallValuePlan {
		final selected = nullableValue(index);
		return {
			index: selected.index,
			parameterOptional: true,
			inputSemanticTypeId: selected.inputSemanticTypeId,
			inputCarrierTypeId: selected.inputCarrierTypeId,
			inputRepresentationId: selected.inputRepresentationId,
			outputSemanticTypeId: selected.outputSemanticTypeId,
			outputCarrierTypeId: selected.outputCarrierTypeId,
			outputRepresentationId: selected.outputRepresentationId,
			conversion: selected.conversion,
			proofId: selected.proofId,
			proofClaim: selected.proofClaim
		};
	}

	static function omittedOptionalNullableValue(index:Int):OcamlCallValuePlan {
		final selected = optionalNullableValue(index);
		return {
			index: selected.index,
			parameterOptional: true,
			inputSemanticTypeId: selected.inputSemanticTypeId,
			inputCarrierTypeId: selected.inputCarrierTypeId,
			inputRepresentationId: selected.inputRepresentationId,
			outputSemanticTypeId: selected.outputSemanticTypeId,
			outputCarrierTypeId: selected.outputCarrierTypeId,
			outputRepresentationId: selected.outputRepresentationId,
			conversion: OcamlCallCarrierConversion.MaterializeOmittedNullableInt,
			proofId: "omitted-nullable-int-call-materialization-v1",
			proofClaim: "fixture omitted optional Null<Int>"
		};
	}

	static function suppliedOptionalNullableValue(index:Int):OcamlCallValuePlan {
		final selected = nullableArgument(index, OcamlCallCarrierConversion.PreserveNullableIntCarrier);
		return {
			index: selected.index,
			parameterOptional: true,
			inputSemanticTypeId: selected.inputSemanticTypeId,
			inputCarrierTypeId: selected.inputCarrierTypeId,
			inputRepresentationId: selected.inputRepresentationId,
			outputSemanticTypeId: selected.outputSemanticTypeId,
			outputCarrierTypeId: selected.outputCarrierTypeId,
			outputRepresentationId: selected.outputRepresentationId,
			conversion: selected.conversion,
			proofId: selected.proofId,
			proofClaim: selected.proofClaim
		};
	}

	static function boolValue(index:Int):OcamlCallValuePlan {
		return {
			index: index,
			parameterOptional: false,
			inputSemanticTypeId: "Bool",
			inputCarrierTypeId: "bool",
			inputRepresentationId: "representation:Bool:internal-value",
			outputSemanticTypeId: "Bool",
			outputCarrierTypeId: "bool",
			outputRepresentationId: "representation:Bool:internal-value",
			conversion: OcamlCallCarrierConversion.Identity,
			proofId: "identity-call-carrier-v1",
			proofClaim: "fixture Bool identity"
		};
	}

	static function stringValue(index:Int):OcamlCallValuePlan {
		return {
			index: index,
			parameterOptional: false,
			inputSemanticTypeId: "String",
			inputCarrierTypeId: "string",
			inputRepresentationId: "representation:String:internal-value",
			outputSemanticTypeId: "String",
			outputCarrierTypeId: "string",
			outputRepresentationId: "representation:String:internal-value",
			conversion: OcamlCallCarrierConversion.Identity,
			proofId: "identity-call-carrier-v1",
			proofClaim: "fixture String identity"
		};
	}

	static function optionalStringValue(index:Int, omitted:Bool = false):OcamlCallValuePlan {
		final selected = stringValue(index);
		return {
			index: selected.index,
			parameterOptional: true,
			inputSemanticTypeId: selected.inputSemanticTypeId,
			inputCarrierTypeId: selected.inputCarrierTypeId,
			inputRepresentationId: selected.inputRepresentationId,
			outputSemanticTypeId: selected.outputSemanticTypeId,
			outputCarrierTypeId: selected.outputCarrierTypeId,
			outputRepresentationId: selected.outputRepresentationId,
			conversion: omitted ? OcamlCallCarrierConversion.MaterializeOmittedString : selected.conversion,
			proofId: omitted ? "omitted-string-call-materialization-v1" : selected.proofId,
			proofClaim: omitted ? "fixture omitted optional String" : selected.proofClaim
		};
	}

	static function explicitNullStringValue(index:Int):OcamlCallValuePlan {
		final selected = optionalStringValue(index);
		return {
			index: selected.index,
			parameterOptional: true,
			inputSemanticTypeId: selected.inputSemanticTypeId,
			inputCarrierTypeId: selected.inputCarrierTypeId,
			inputRepresentationId: selected.inputRepresentationId,
			outputSemanticTypeId: selected.outputSemanticTypeId,
			outputCarrierTypeId: selected.outputCarrierTypeId,
			outputRepresentationId: selected.outputRepresentationId,
			conversion: OcamlCallCarrierConversion.MaterializeExplicitNullString,
			proofId: "explicit-null-string-call-materialization-v1",
			proofClaim: "fixture explicitly supplied null String"
		};
	}

	static function nullableArgument(index:Int, conversion:OcamlCallCarrierConversion):OcamlCallValuePlan {
		return switch (conversion) {
			case PreserveNullableIntCarrier:
				{
					index: index,
					parameterOptional: false,
					inputSemanticTypeId: "Null<Int>",
					inputCarrierTypeId: "Obj.t",
					inputRepresentationId: "representation:Null<Int>:internal-value",
					outputSemanticTypeId: "Null<Int>",
					outputCarrierTypeId: "Obj.t",
					outputRepresentationId: "representation:Null<Int>:internal-value",
					conversion: conversion,
					proofId: "nullable-int-call-carrier-preserve-v1",
					proofClaim: "fixture nullable preserve"
				};
			case BoxExactIntToNullableInt:
				{
					index: index,
					parameterOptional: false,
					inputSemanticTypeId: "Int",
					inputCarrierTypeId: "int",
					inputRepresentationId: "representation:Int:internal-value",
					outputSemanticTypeId: "Null<Int>",
					outputCarrierTypeId: "Obj.t",
					outputRepresentationId: "representation:Null<Int>:internal-value",
					conversion: conversion,
					proofId: "nullable-int-call-box-v1",
					proofClaim: "fixture nullable box"
				};
			case Identity:
				throw "fixture nullable occurrence must select preserve or box";
			case PreserveNullableBoolCarrier, BoxExactBoolToNullableBool, MaterializeOmittedNullableInt, MaterializeOmittedNullableBool,
				MaterializeOmittedString, MaterializeExplicitNullString:
				throw "fixture nullable Int occurrence received a nullable Bool conversion";
		};
	}

	static function nullableBoolValue(index:Int):OcamlCallValuePlan {
		return {
			index: index,
			parameterOptional: false,
			inputSemanticTypeId: "Null<Bool>",
			inputCarrierTypeId: "Obj.t",
			inputRepresentationId: "representation:Null<Bool>:internal-value",
			outputSemanticTypeId: "Null<Bool>",
			outputCarrierTypeId: "Obj.t",
			outputRepresentationId: "representation:Null<Bool>:internal-value",
			conversion: OcamlCallCarrierConversion.Identity,
			proofId: "identity-call-carrier-v1",
			proofClaim: "fixture nullable Bool identity"
		};
	}

	static function nullableBoolArgument(index:Int, conversion:OcamlCallCarrierConversion):OcamlCallValuePlan {
		return switch (conversion) {
			case PreserveNullableBoolCarrier:
				{
					index: index,
					parameterOptional: false,
					inputSemanticTypeId: "Null<Bool>",
					inputCarrierTypeId: "Obj.t",
					inputRepresentationId: "representation:Null<Bool>:internal-value",
					outputSemanticTypeId: "Null<Bool>",
					outputCarrierTypeId: "Obj.t",
					outputRepresentationId: "representation:Null<Bool>:internal-value",
					conversion: conversion,
					proofId: "nullable-bool-call-carrier-preserve-v1",
					proofClaim: "fixture nullable Bool preserve"
				};
			case BoxExactBoolToNullableBool:
				{
					index: index,
					parameterOptional: false,
					inputSemanticTypeId: "Bool",
					inputCarrierTypeId: "bool",
					inputRepresentationId: "representation:Bool:internal-value",
					outputSemanticTypeId: "Null<Bool>",
					outputCarrierTypeId: "Obj.t",
					outputRepresentationId: "representation:Null<Bool>:internal-value",
					conversion: conversion,
					proofId: "nullable-bool-call-box-v1",
					proofClaim: "fixture nullable Bool box"
				};
			case Identity:
				throw "fixture nullable Bool occurrence must select preserve or box";
			case PreserveNullableIntCarrier, BoxExactIntToNullableInt, MaterializeOmittedNullableInt, MaterializeOmittedNullableBool,
				MaterializeOmittedString, MaterializeExplicitNullString:
				throw "fixture nullable Bool occurrence received a nullable Int conversion";
		};
	}

	static function declaration():OcamlCallableDeclarationPlan {
		return {
			id: "callable-declaration:fixture",
			calleeId: CALLEE_ID,
			sourceModuleId: "Arithmetic",
			sourceTypeName: "Arithmetic",
			sourceFieldName: "increment",
			kind: OcamlCallKind.DirectStaticHaxeMethod,
			receiver: null,
			arguments: [value(0)],
			resultKind: OcamlCallResultKind.Value,
			result: value(-1),
			profileEligibility: ["metal", "portable"],
			reason: "fixture",
			proofId: OcamlCallPlan.DIRECT_STATIC_SIGNATURE_PROOF_ID,
			proofClaim: "fixture",
			programRevision: PROGRAM_REVISION,
			pipelineRevision: OcamlFunctionPlanRegistry.PIPELINE_REVISION
		};
	}

	static function constructorDeclaration():OcamlCallableDeclarationPlan {
		return {
			id: "construction-declaration:fixture",
			calleeId: CONSTRUCTOR_CALLEE_ID,
			sourceModuleId: "Counter",
			sourceTypeName: "Counter",
			sourceFieldName: "new",
			kind: OcamlCallKind.DirectHaxeConstructor,
			receiver: null,
			arguments: [value(0)],
			resultKind: OcamlCallResultKind.Value,
			result: nominalCounterValue(-1),
			profileEligibility: ["metal", "portable"],
			reason: "fixture exact one-argument construction",
			proofId: OcamlCallPlan.DIRECT_CONSTRUCTOR_SIGNATURE_PROOF_ID,
			proofClaim: "fixture exact one-argument construction",
			programRevision: PROGRAM_REVISION,
			pipelineRevision: OcamlFunctionPlanRegistry.PIPELINE_REVISION
		};
	}

	static function twoArgumentDeclaration():OcamlCallableDeclarationPlan {
		return {
			id: "callable-declaration:two-argument-fixture",
			calleeId: TWO_CALLEE_ID,
			sourceModuleId: "Arithmetic",
			sourceTypeName: "Arithmetic",
			sourceFieldName: "add",
			kind: OcamlCallKind.DirectStaticHaxeMethod,
			receiver: null,
			arguments: [value(0), value(1)],
			resultKind: OcamlCallResultKind.Value,
			result: value(-1),
			profileEligibility: ["metal", "portable"],
			reason: "fixture",
			proofId: OcamlCallPlan.DIRECT_STATIC_SIGNATURE_PROOF_ID,
			proofClaim: "fixture",
			programRevision: PROGRAM_REVISION,
			pipelineRevision: OcamlFunctionPlanRegistry.PIPELINE_REVISION
		};
	}

	static function zeroArgumentDeclaration():OcamlCallableDeclarationPlan {
		return {
			id: "callable-declaration:zero-argument-fixture",
			calleeId: ZERO_CALLEE_ID,
			sourceModuleId: "ZeroArgCalls",
			sourceTypeName: "ZeroArgCalls",
			sourceFieldName: "exactCount",
			kind: OcamlCallKind.DirectStaticHaxeMethod,
			receiver: null,
			arguments: [],
			resultKind: OcamlCallResultKind.Value,
			result: value(-1),
			profileEligibility: ["metal", "portable"],
			reason: "fixture zero-argument signature",
			proofId: OcamlCallPlan.DIRECT_STATIC_SIGNATURE_PROOF_ID,
			proofClaim: "fixture zero-argument signature",
			programRevision: PROGRAM_REVISION,
			pipelineRevision: OcamlFunctionPlanRegistry.PIPELINE_REVISION
		};
	}

	static function nullableDeclaration():OcamlCallableDeclarationPlan {
		return {
			id: "callable-declaration:nullable-fixture",
			calleeId: NULLABLE_CALLEE_ID,
			sourceModuleId: "NullableCalls",
			sourceTypeName: "NullableCalls",
			sourceFieldName: "identity",
			kind: OcamlCallKind.DirectStaticHaxeMethod,
			receiver: null,
			arguments: [nullableValue(0)],
			resultKind: OcamlCallResultKind.Value,
			result: nullableValue(-1),
			profileEligibility: ["metal", "portable"],
			reason: "fixture",
			proofId: OcamlCallPlan.DIRECT_STATIC_SIGNATURE_PROOF_ID,
			proofClaim: "fixture",
			programRevision: PROGRAM_REVISION,
			pipelineRevision: OcamlFunctionPlanRegistry.PIPELINE_REVISION
		};
	}

	static function boolDeclaration():OcamlCallableDeclarationPlan {
		return {
			id: "callable-declaration:bool-fixture",
			calleeId: BOOL_CALLEE_ID,
			sourceModuleId: "BoolCalls",
			sourceTypeName: "BoolCalls",
			sourceFieldName: "negate",
			kind: OcamlCallKind.DirectStaticHaxeMethod,
			receiver: null,
			arguments: [boolValue(0)],
			resultKind: OcamlCallResultKind.Value,
			result: boolValue(-1),
			profileEligibility: ["metal", "portable"],
			reason: "fixture",
			proofId: OcamlCallPlan.DIRECT_STATIC_SIGNATURE_PROOF_ID,
			proofClaim: "fixture",
			programRevision: PROGRAM_REVISION,
			pipelineRevision: OcamlFunctionPlanRegistry.PIPELINE_REVISION
		};
	}

	static function nullableBoolDeclaration():OcamlCallableDeclarationPlan {
		return {
			id: "callable-declaration:nullable-bool-fixture",
			calleeId: NULLABLE_BOOL_CALLEE_ID,
			sourceModuleId: "BoolCalls",
			sourceTypeName: "BoolCalls",
			sourceFieldName: "identityNullable",
			kind: OcamlCallKind.DirectStaticHaxeMethod,
			receiver: null,
			arguments: [nullableBoolValue(0)],
			resultKind: OcamlCallResultKind.Value,
			result: nullableBoolValue(-1),
			profileEligibility: ["metal", "portable"],
			reason: "fixture",
			proofId: OcamlCallPlan.DIRECT_STATIC_SIGNATURE_PROOF_ID,
			proofClaim: "fixture",
			programRevision: PROGRAM_REVISION,
			pipelineRevision: OcamlFunctionPlanRegistry.PIPELINE_REVISION
		};
	}

	static function mixedDeclaration():OcamlCallableDeclarationPlan {
		return {
			id: "callable-declaration:mixed-fixture",
			calleeId: MIXED_CALLEE_ID,
			sourceModuleId: "MixedCalls",
			sourceTypeName: "MixedCalls",
			sourceFieldName: "choose",
			kind: OcamlCallKind.DirectStaticHaxeMethod,
			receiver: null,
			arguments: [value(0), nullableBoolValue(1), boolValue(2), nullableValue(3)],
			resultKind: OcamlCallResultKind.Value,
			result: nullableValue(-1),
			profileEligibility: ["metal", "portable"],
			reason: "fixture mixed signature",
			proofId: OcamlCallPlan.DIRECT_STATIC_SIGNATURE_PROOF_ID,
			proofClaim: "fixture mixed signature",
			programRevision: PROGRAM_REVISION,
			pipelineRevision: OcamlFunctionPlanRegistry.PIPELINE_REVISION
		};
	}

	static function optionalDeclaration():OcamlCallableDeclarationPlan {
		return {
			id: "callable-declaration:optional-fixture",
			calleeId: OPTIONAL_CALLEE_ID,
			sourceModuleId: "OptionalCalls",
			sourceTypeName: "OptionalCalls",
			sourceFieldName: "optionalInt",
			kind: OcamlCallKind.DirectStaticHaxeMethod,
			receiver: null,
			arguments: [optionalNullableValue(0)],
			resultKind: OcamlCallResultKind.Value,
			result: value(-1),
			profileEligibility: ["metal", "portable"],
			reason: "fixture optional signature",
			proofId: OcamlCallPlan.DIRECT_STATIC_SIGNATURE_PROOF_ID,
			proofClaim: "fixture optional signature",
			programRevision: PROGRAM_REVISION,
			pipelineRevision: OcamlFunctionPlanRegistry.PIPELINE_REVISION
		};
	}

	static function voidDeclaration():OcamlCallableDeclarationPlan {
		return {
			id: "callable-declaration:void-fixture",
			calleeId: VOID_CALLEE_ID,
			sourceModuleId: "VoidCalls",
			sourceTypeName: "VoidCalls",
			sourceFieldName: "withArguments",
			kind: OcamlCallKind.DirectStaticHaxeMethod,
			receiver: null,
			arguments: [value(0), boolValue(1), stringValue(2)],
			resultKind: OcamlCallResultKind.EffectOnlyVoid,
			result: null,
			profileEligibility: ["metal", "portable"],
			reason: "fixture effect-only Void signature",
			proofId: OcamlCallPlan.DIRECT_STATIC_SIGNATURE_PROOF_ID,
			proofClaim: "fixture effect-only Void signature",
			programRevision: PROGRAM_REVISION,
			pipelineRevision: OcamlFunctionPlanRegistry.PIPELINE_REVISION
		};
	}

	static function binding(functionId:String, bodyRevision:String):OcamlFunctionPlanBinding {
		return {
			functionId: functionId,
			programRevision: PROGRAM_REVISION,
			bodyRevision: bodyRevision,
			pipelineRevision: OcamlFunctionPlanRegistry.PIPELINE_REVISION
		};
	}

	static function call(caller:OcamlFunctionPlanBinding):OcamlCallDecision {
		return {
			id: CALL_ID,
			source: {file: "CallPlanFixture.hx", min: 0, max: 1},
			calleeId: CALLEE_ID,
			sourceModuleId: "Arithmetic",
			sourceTypeName: "Arithmetic",
			sourceFieldName: "increment",
			kind: OcamlCallKind.DirectStaticHaxeMethod,
			receiver: null,
			arguments: [value(0)],
			resultKind: OcamlCallResultKind.Value,
			result: value(-1),
			evaluationSchedule: OcamlCallPlan.evaluationSchedule(CALL_ID, 1),
			profileEligibility: ["metal", "portable"],
			reason: "fixture",
			proofId: OcamlCallPlan.DIRECT_STATIC_SIGNATURE_PROOF_ID,
			proofClaim: "fixture",
			functionId: caller.functionId,
			programRevision: caller.programRevision,
			bodyRevision: caller.bodyRevision,
			pipelineRevision: caller.pipelineRevision
		};
	}

	static function constructorCall(caller:OcamlFunctionPlanBinding):OcamlCallDecision {
		return {
			id: CONSTRUCTOR_CALL_ID,
			source: {file: "CallPlanFixture.hx", min: 50, max: 51},
			calleeId: CONSTRUCTOR_CALLEE_ID,
			sourceModuleId: "Counter",
			sourceTypeName: "Counter",
			sourceFieldName: "new",
			kind: OcamlCallKind.DirectHaxeConstructor,
			receiver: null,
			arguments: [value(0)],
			resultKind: OcamlCallResultKind.Value,
			result: nominalCounterValue(-1),
			evaluationSchedule: OcamlCallPlan.evaluationSchedule(CONSTRUCTOR_CALL_ID, 1),
			profileEligibility: ["metal", "portable"],
			reason: "fixture exact one-argument construction occurrence",
			proofId: OcamlCallPlan.DIRECT_CONSTRUCTOR_SIGNATURE_PROOF_ID,
			proofClaim: "fixture exact one-argument construction occurrence",
			functionId: caller.functionId,
			programRevision: caller.programRevision,
			bodyRevision: caller.bodyRevision,
			pipelineRevision: caller.pipelineRevision
		};
	}

	static function functionValueCall(caller:OcamlFunctionPlanBinding):OcamlCallDecision {
		return {
			id: FUNCTION_VALUE_CALL_ID,
			source: {file: "CallPlanFixture.hx", min: 30, max: 31},
			calleeId: FUNCTION_VALUE_CALLEE_ID,
			sourceModuleId: "",
			sourceTypeName: "",
			sourceFieldName: "",
			kind: OcamlCallKind.TypedFunctionValue,
			receiver: null,
			arguments: [value(0)],
			resultKind: OcamlCallResultKind.Value,
			result: value(-1),
			evaluationSchedule: OcamlCallPlan.evaluationSchedule(FUNCTION_VALUE_CALL_ID, 1, [], true),
			profileEligibility: ["metal", "portable"],
			reason: "fixture exact Int function-value call",
			proofId: OcamlCallPlan.FUNCTION_VALUE_SIGNATURE_PROOF_ID_PREFIX + "(Int)->Int",
			proofClaim: "fixture exact Int function-value signature",
			functionId: caller.functionId,
			programRevision: caller.programRevision,
			bodyRevision: caller.bodyRevision,
			pipelineRevision: caller.pipelineRevision
		};
	}

	static function optionalStringFunctionValueCall(caller:OcamlFunctionPlanBinding, arguments:Array<OcamlCallValuePlan>,
			?omittedArgumentIndices:Array<Int>):OcamlCallDecision {
		return {
			id: OPTIONAL_STRING_FUNCTION_VALUE_CALL_ID,
			source: {file: "CallPlanFixture.hx", min: 32, max: 33},
			calleeId: OPTIONAL_STRING_FUNCTION_VALUE_CALLEE_ID,
			sourceModuleId: "",
			sourceTypeName: "",
			sourceFieldName: "",
			kind: OcamlCallKind.TypedFunctionValue,
			receiver: null,
			arguments: arguments,
			resultKind: OcamlCallResultKind.Value,
			result: stringValue(-1),
			evaluationSchedule: OcamlCallPlan.evaluationSchedule(OPTIONAL_STRING_FUNCTION_VALUE_CALL_ID, arguments.length, omittedArgumentIndices ?? [], true),
			profileEligibility: ["metal", "portable"],
			reason: "fixture trailing optional String function-value call",
			proofId: OcamlCallPlan.functionValueProofId(arguments, OcamlCallResultKind.Value, stringValue(-1)),
			proofClaim: "fixture trailing optional String function-value signature",
			functionId: caller.functionId,
			programRevision: caller.programRevision,
			bodyRevision: caller.bodyRevision,
			pipelineRevision: caller.pipelineRevision
		};
	}

	static function matrixFunctionValueCall(caller:OcamlFunctionPlanBinding, id:String, sourceMin:Int, arguments:Array<OcamlCallValuePlan>,
			resultKind:OcamlCallResultKind, result:Null<OcamlCallValuePlan>):OcamlCallDecision {
		final omittedArgumentIndices = [
			for (index in 0...arguments.length)
				if (OcamlCallPlan.isOmittedConversion(arguments[index].conversion)) index
		];
		return {
			id: id,
			source: {file: "CallPlanFixture.hx", min: sourceMin, max: sourceMin + 1},
			calleeId: "function-value:matrix:" + id,
			sourceModuleId: "",
			sourceTypeName: "",
			sourceFieldName: "",
			kind: OcamlCallKind.TypedFunctionValue,
			receiver: null,
			arguments: arguments,
			resultKind: resultKind,
			result: result,
			evaluationSchedule: OcamlCallPlan.evaluationSchedule(id, arguments.length, omittedArgumentIndices, true),
			profileEligibility: ["metal", "portable"],
			reason: "fixture represented function-value signature matrix",
			proofId: OcamlCallPlan.functionValueProofId(arguments, resultKind, result),
			proofClaim: "fixture represented function-value signature matrix",
			functionId: caller.functionId,
			programRevision: caller.programRevision,
			bodyRevision: caller.bodyRevision,
			pipelineRevision: caller.pipelineRevision
		};
	}

	static function twoArgumentCall(caller:OcamlFunctionPlanBinding):OcamlCallDecision {
		return {
			id: TWO_CALL_ID,
			source: {file: "CallPlanFixture.hx", min: 2, max: 3},
			calleeId: TWO_CALLEE_ID,
			sourceModuleId: "Arithmetic",
			sourceTypeName: "Arithmetic",
			sourceFieldName: "add",
			kind: OcamlCallKind.DirectStaticHaxeMethod,
			receiver: null,
			arguments: [value(0), value(1)],
			resultKind: OcamlCallResultKind.Value,
			result: value(-1),
			evaluationSchedule: OcamlCallPlan.evaluationSchedule(TWO_CALL_ID, 2),
			profileEligibility: ["metal", "portable"],
			reason: "fixture",
			proofId: OcamlCallPlan.DIRECT_STATIC_SIGNATURE_PROOF_ID,
			proofClaim: "fixture",
			functionId: caller.functionId,
			programRevision: caller.programRevision,
			bodyRevision: caller.bodyRevision,
			pipelineRevision: caller.pipelineRevision
		};
	}

	static function zeroArgumentCall(caller:OcamlFunctionPlanBinding):OcamlCallDecision {
		return {
			id: ZERO_CALL_ID,
			source: {file: "CallPlanFixture.hx", min: 18, max: 19},
			calleeId: ZERO_CALLEE_ID,
			sourceModuleId: "ZeroArgCalls",
			sourceTypeName: "ZeroArgCalls",
			sourceFieldName: "exactCount",
			kind: OcamlCallKind.DirectStaticHaxeMethod,
			receiver: null,
			arguments: [],
			resultKind: OcamlCallResultKind.Value,
			result: value(-1),
			evaluationSchedule: OcamlCallPlan.evaluationSchedule(ZERO_CALL_ID, 0),
			profileEligibility: ["metal", "portable"],
			reason: "fixture zero-argument signature",
			proofId: OcamlCallPlan.DIRECT_STATIC_SIGNATURE_PROOF_ID,
			proofClaim: "fixture zero-argument signature",
			functionId: caller.functionId,
			programRevision: caller.programRevision,
			bodyRevision: caller.bodyRevision,
			pipelineRevision: caller.pipelineRevision
		};
	}

	static function nullableCall(caller:OcamlFunctionPlanBinding, id:String, sourceMin:Int, conversion:OcamlCallCarrierConversion):OcamlCallDecision {
		return {
			id: id,
			source: {file: "CallPlanFixture.hx", min: sourceMin, max: sourceMin + 1},
			calleeId: NULLABLE_CALLEE_ID,
			sourceModuleId: "NullableCalls",
			sourceTypeName: "NullableCalls",
			sourceFieldName: "identity",
			kind: OcamlCallKind.DirectStaticHaxeMethod,
			receiver: null,
			arguments: [nullableArgument(0, conversion)],
			resultKind: OcamlCallResultKind.Value,
			result: nullableValue(-1),
			evaluationSchedule: OcamlCallPlan.evaluationSchedule(id, 1),
			profileEligibility: ["metal", "portable"],
			reason: "fixture",
			proofId: OcamlCallPlan.DIRECT_STATIC_SIGNATURE_PROOF_ID,
			proofClaim: "fixture",
			functionId: caller.functionId,
			programRevision: caller.programRevision,
			bodyRevision: caller.bodyRevision,
			pipelineRevision: caller.pipelineRevision
		};
	}

	static function boolCall(caller:OcamlFunctionPlanBinding):OcamlCallDecision {
		return {
			id: BOOL_CALL_ID,
			source: {file: "CallPlanFixture.hx", min: 8, max: 9},
			calleeId: BOOL_CALLEE_ID,
			sourceModuleId: "BoolCalls",
			sourceTypeName: "BoolCalls",
			sourceFieldName: "negate",
			kind: OcamlCallKind.DirectStaticHaxeMethod,
			receiver: null,
			arguments: [boolValue(0)],
			resultKind: OcamlCallResultKind.Value,
			result: boolValue(-1),
			evaluationSchedule: OcamlCallPlan.evaluationSchedule(BOOL_CALL_ID, 1),
			profileEligibility: ["metal", "portable"],
			reason: "fixture",
			proofId: OcamlCallPlan.DIRECT_STATIC_SIGNATURE_PROOF_ID,
			proofClaim: "fixture",
			functionId: caller.functionId,
			programRevision: caller.programRevision,
			bodyRevision: caller.bodyRevision,
			pipelineRevision: caller.pipelineRevision
		};
	}

	static function nullableBoolCall(caller:OcamlFunctionPlanBinding, id:String, sourceMin:Int, conversion:OcamlCallCarrierConversion):OcamlCallDecision {
		return {
			id: id,
			source: {file: "CallPlanFixture.hx", min: sourceMin, max: sourceMin + 1},
			calleeId: NULLABLE_BOOL_CALLEE_ID,
			sourceModuleId: "BoolCalls",
			sourceTypeName: "BoolCalls",
			sourceFieldName: "identityNullable",
			kind: OcamlCallKind.DirectStaticHaxeMethod,
			receiver: null,
			arguments: [nullableBoolArgument(0, conversion)],
			resultKind: OcamlCallResultKind.Value,
			result: nullableBoolValue(-1),
			evaluationSchedule: OcamlCallPlan.evaluationSchedule(id, 1),
			profileEligibility: ["metal", "portable"],
			reason: "fixture",
			proofId: OcamlCallPlan.DIRECT_STATIC_SIGNATURE_PROOF_ID,
			proofClaim: "fixture",
			functionId: caller.functionId,
			programRevision: caller.programRevision,
			bodyRevision: caller.bodyRevision,
			pipelineRevision: caller.pipelineRevision
		};
	}

	static function mixedCall(caller:OcamlFunctionPlanBinding, id:String, sourceMin:Int, boolConversion:OcamlCallCarrierConversion,
			intConversion:OcamlCallCarrierConversion):OcamlCallDecision {
		return {
			id: id,
			source: {file: "CallPlanFixture.hx", min: sourceMin, max: sourceMin + 1},
			calleeId: MIXED_CALLEE_ID,
			sourceModuleId: "MixedCalls",
			sourceTypeName: "MixedCalls",
			sourceFieldName: "choose",
			kind: OcamlCallKind.DirectStaticHaxeMethod,
			receiver: null,
			arguments: [
				value(0),
				nullableBoolArgument(1, boolConversion),
				boolValue(2),
				nullableArgument(3, intConversion)
			],
			resultKind: OcamlCallResultKind.Value,
			result: nullableValue(-1),
			evaluationSchedule: OcamlCallPlan.evaluationSchedule(id, 4),
			profileEligibility: ["metal", "portable"],
			reason: "fixture mixed signature",
			proofId: OcamlCallPlan.DIRECT_STATIC_SIGNATURE_PROOF_ID,
			proofClaim: "fixture mixed signature",
			functionId: caller.functionId,
			programRevision: caller.programRevision,
			bodyRevision: caller.bodyRevision,
			pipelineRevision: caller.pipelineRevision
		};
	}

	static function optionalCall(caller:OcamlFunctionPlanBinding, omitted:Bool):OcamlCallDecision {
		final id = omitted ? OPTIONAL_OMITTED_CALL_ID : OPTIONAL_SUPPLIED_CALL_ID;
		return {
			id: id,
			source: {file: "CallPlanFixture.hx", min: omitted ? 20 : 22, max: omitted ? 21 : 23},
			calleeId: OPTIONAL_CALLEE_ID,
			sourceModuleId: "OptionalCalls",
			sourceTypeName: "OptionalCalls",
			sourceFieldName: "optionalInt",
			kind: OcamlCallKind.DirectStaticHaxeMethod,
			receiver: null,
			arguments: [omitted ? omittedOptionalNullableValue(0) : suppliedOptionalNullableValue(0)],
			resultKind: OcamlCallResultKind.Value,
			result: value(-1),
			evaluationSchedule: OcamlCallPlan.evaluationSchedule(id, 1, omitted ? [0] : []),
			profileEligibility: ["metal", "portable"],
			reason: "fixture optional call",
			proofId: OcamlCallPlan.DIRECT_STATIC_SIGNATURE_PROOF_ID,
			proofClaim: "fixture optional call",
			functionId: caller.functionId,
			programRevision: caller.programRevision,
			bodyRevision: caller.bodyRevision,
			pipelineRevision: caller.pipelineRevision
		};
	}

	static function voidCall(caller:OcamlFunctionPlanBinding):OcamlCallDecision {
		return {
			id: VOID_CALL_ID,
			source: {file: "CallPlanFixture.hx", min: 24, max: 25},
			calleeId: VOID_CALLEE_ID,
			sourceModuleId: "VoidCalls",
			sourceTypeName: "VoidCalls",
			sourceFieldName: "withArguments",
			kind: OcamlCallKind.DirectStaticHaxeMethod,
			receiver: null,
			arguments: [value(0), boolValue(1), stringValue(2)],
			resultKind: OcamlCallResultKind.EffectOnlyVoid,
			result: null,
			evaluationSchedule: OcamlCallPlan.evaluationSchedule(VOID_CALL_ID, 3),
			profileEligibility: ["metal", "portable"],
			reason: "fixture effect-only Void call",
			proofId: OcamlCallPlan.DIRECT_STATIC_SIGNATURE_PROOF_ID,
			proofClaim: "fixture effect-only Void call",
			functionId: caller.functionId,
			programRevision: caller.programRevision,
			bodyRevision: caller.bodyRevision,
			pipelineRevision: caller.pipelineRevision
		};
	}

	static function copyCall(source:OcamlCallDecision, ?calleeId:String, ?kind:OcamlCallKind, ?arguments:Array<OcamlCallValuePlan>,
			?result:OcamlCallValuePlan, ?bodyRevision:String, ?evaluationSchedule:Array<OcamlCallEvaluationStep>,
			?resultKind:OcamlCallResultKind):OcamlCallDecision {
		return {
			id: source.id,
			source: {file: source.source.file, min: source.source.min, max: source.source.max},
			calleeId: calleeId ?? source.calleeId,
			sourceModuleId: source.sourceModuleId,
			sourceTypeName: source.sourceTypeName,
			sourceFieldName: source.sourceFieldName,
			kind: kind ?? source.kind,
			receiver: null,
			arguments: arguments ?? source.arguments.map(OcamlCallPlan.copyValue),
			resultKind: resultKind ?? source.resultKind,
			result: result ?? OcamlCallPlan.copyOptionalValue(source.result),
			evaluationSchedule: (evaluationSchedule ?? source.evaluationSchedule).map(OcamlCallPlan.copyEvaluationStep),
			profileEligibility: source.profileEligibility.copy(),
			reason: source.reason,
			proofId: source.proofId,
			proofClaim: source.proofClaim,
			functionId: source.functionId,
			programRevision: source.programRevision,
			bodyRevision: bodyRevision ?? source.bodyRevision,
			pipelineRevision: source.pipelineRevision
		};
	}

	static function boundary(callee:OcamlFunctionPlanBinding):OcamlCallableBoundaryPlan {
		return {
			id: "callable-boundary:fixture",
			calleeId: CALLEE_ID,
			sourceModuleId: "Arithmetic",
			sourceTypeName: "Arithmetic",
			sourceFieldName: "increment",
			kind: OcamlCallKind.DirectStaticHaxeMethod,
			receiver: null,
			arguments: [value(0)],
			resultKind: OcamlCallResultKind.Value,
			result: value(-1),
			profileEligibility: ["metal", "portable"],
			reason: "fixture",
			proofId: OcamlCallPlan.DIRECT_STATIC_SIGNATURE_PROOF_ID,
			proofClaim: "fixture",
			functionId: callee.functionId,
			programRevision: callee.programRevision,
			bodyRevision: callee.bodyRevision,
			pipelineRevision: callee.pipelineRevision
		};
	}

	static function constructorBoundary(callee:OcamlFunctionPlanBinding):OcamlCallableBoundaryPlan {
		return {
			id: "construction-boundary:fixture",
			calleeId: CONSTRUCTOR_CALLEE_ID,
			sourceModuleId: "Counter",
			sourceTypeName: "Counter",
			sourceFieldName: "new",
			kind: OcamlCallKind.DirectHaxeConstructor,
			receiver: null,
			arguments: [value(0)],
			resultKind: OcamlCallResultKind.Value,
			result: nominalCounterValue(-1),
			profileEligibility: ["metal", "portable"],
			reason: "fixture allocation, exact constructor body, and nominal instance result",
			proofId: OcamlCallPlan.DIRECT_CONSTRUCTOR_SIGNATURE_PROOF_ID,
			proofClaim: "fixture allocation, exact constructor body, and nominal instance result",
			functionId: callee.functionId,
			programRevision: callee.programRevision,
			bodyRevision: callee.bodyRevision,
			pipelineRevision: callee.pipelineRevision
		};
	}

	static function twoArgumentBoundary(callee:OcamlFunctionPlanBinding):OcamlCallableBoundaryPlan {
		return {
			id: "callable-boundary:two-argument-fixture",
			calleeId: TWO_CALLEE_ID,
			sourceModuleId: "Arithmetic",
			sourceTypeName: "Arithmetic",
			sourceFieldName: "add",
			kind: OcamlCallKind.DirectStaticHaxeMethod,
			receiver: null,
			arguments: [value(0), value(1)],
			resultKind: OcamlCallResultKind.Value,
			result: value(-1),
			profileEligibility: ["metal", "portable"],
			reason: "fixture",
			proofId: OcamlCallPlan.DIRECT_STATIC_SIGNATURE_PROOF_ID,
			proofClaim: "fixture",
			functionId: callee.functionId,
			programRevision: callee.programRevision,
			bodyRevision: callee.bodyRevision,
			pipelineRevision: callee.pipelineRevision
		};
	}

	static function zeroArgumentBoundary(callee:OcamlFunctionPlanBinding):OcamlCallableBoundaryPlan {
		return {
			id: "callable-boundary:zero-argument-fixture",
			calleeId: ZERO_CALLEE_ID,
			sourceModuleId: "ZeroArgCalls",
			sourceTypeName: "ZeroArgCalls",
			sourceFieldName: "exactCount",
			kind: OcamlCallKind.DirectStaticHaxeMethod,
			receiver: null,
			arguments: [],
			resultKind: OcamlCallResultKind.Value,
			result: value(-1),
			profileEligibility: ["metal", "portable"],
			reason: "fixture zero-argument signature",
			proofId: OcamlCallPlan.DIRECT_STATIC_SIGNATURE_PROOF_ID,
			proofClaim: "fixture zero-argument signature",
			functionId: callee.functionId,
			programRevision: callee.programRevision,
			bodyRevision: callee.bodyRevision,
			pipelineRevision: callee.pipelineRevision
		};
	}

	static function nullableBoundary(callee:OcamlFunctionPlanBinding):OcamlCallableBoundaryPlan {
		return {
			id: "callable-boundary:nullable-fixture",
			calleeId: NULLABLE_CALLEE_ID,
			sourceModuleId: "NullableCalls",
			sourceTypeName: "NullableCalls",
			sourceFieldName: "identity",
			kind: OcamlCallKind.DirectStaticHaxeMethod,
			receiver: null,
			arguments: [nullableValue(0)],
			resultKind: OcamlCallResultKind.Value,
			result: nullableValue(-1),
			profileEligibility: ["metal", "portable"],
			reason: "fixture",
			proofId: OcamlCallPlan.DIRECT_STATIC_SIGNATURE_PROOF_ID,
			proofClaim: "fixture",
			functionId: callee.functionId,
			programRevision: callee.programRevision,
			bodyRevision: callee.bodyRevision,
			pipelineRevision: callee.pipelineRevision
		};
	}

	static function boolBoundary(callee:OcamlFunctionPlanBinding):OcamlCallableBoundaryPlan {
		return {
			id: "callable-boundary:bool-fixture",
			calleeId: BOOL_CALLEE_ID,
			sourceModuleId: "BoolCalls",
			sourceTypeName: "BoolCalls",
			sourceFieldName: "negate",
			kind: OcamlCallKind.DirectStaticHaxeMethod,
			receiver: null,
			arguments: [boolValue(0)],
			resultKind: OcamlCallResultKind.Value,
			result: boolValue(-1),
			profileEligibility: ["metal", "portable"],
			reason: "fixture",
			proofId: OcamlCallPlan.DIRECT_STATIC_SIGNATURE_PROOF_ID,
			proofClaim: "fixture",
			functionId: callee.functionId,
			programRevision: callee.programRevision,
			bodyRevision: callee.bodyRevision,
			pipelineRevision: callee.pipelineRevision
		};
	}

	static function nullableBoolBoundary(callee:OcamlFunctionPlanBinding, ?result:OcamlCallValuePlan):OcamlCallableBoundaryPlan {
		return {
			id: "callable-boundary:nullable-bool-fixture",
			calleeId: NULLABLE_BOOL_CALLEE_ID,
			sourceModuleId: "BoolCalls",
			sourceTypeName: "BoolCalls",
			sourceFieldName: "identityNullable",
			kind: OcamlCallKind.DirectStaticHaxeMethod,
			receiver: null,
			arguments: [nullableBoolValue(0)],
			resultKind: OcamlCallResultKind.Value,
			result: result ?? nullableBoolValue(-1),
			profileEligibility: ["metal", "portable"],
			reason: "fixture",
			proofId: OcamlCallPlan.DIRECT_STATIC_SIGNATURE_PROOF_ID,
			proofClaim: "fixture",
			functionId: callee.functionId,
			programRevision: callee.programRevision,
			bodyRevision: callee.bodyRevision,
			pipelineRevision: callee.pipelineRevision
		};
	}

	static function mixedBoundary(callee:OcamlFunctionPlanBinding):OcamlCallableBoundaryPlan {
		return {
			id: "callable-boundary:mixed-fixture",
			calleeId: MIXED_CALLEE_ID,
			sourceModuleId: "MixedCalls",
			sourceTypeName: "MixedCalls",
			sourceFieldName: "choose",
			kind: OcamlCallKind.DirectStaticHaxeMethod,
			receiver: null,
			arguments: [value(0), nullableBoolValue(1), boolValue(2), nullableValue(3)],
			resultKind: OcamlCallResultKind.Value,
			result: nullableValue(-1),
			profileEligibility: ["metal", "portable"],
			reason: "fixture mixed signature",
			proofId: OcamlCallPlan.DIRECT_STATIC_SIGNATURE_PROOF_ID,
			proofClaim: "fixture mixed signature",
			functionId: callee.functionId,
			programRevision: callee.programRevision,
			bodyRevision: callee.bodyRevision,
			pipelineRevision: callee.pipelineRevision
		};
	}

	static function optionalBoundary(callee:OcamlFunctionPlanBinding):OcamlCallableBoundaryPlan {
		return {
			id: "callable-boundary:optional-fixture",
			calleeId: OPTIONAL_CALLEE_ID,
			sourceModuleId: "OptionalCalls",
			sourceTypeName: "OptionalCalls",
			sourceFieldName: "optionalInt",
			kind: OcamlCallKind.DirectStaticHaxeMethod,
			receiver: null,
			arguments: [optionalNullableValue(0)],
			resultKind: OcamlCallResultKind.Value,
			result: value(-1),
			profileEligibility: ["metal", "portable"],
			reason: "fixture optional signature",
			proofId: OcamlCallPlan.DIRECT_STATIC_SIGNATURE_PROOF_ID,
			proofClaim: "fixture optional signature",
			functionId: callee.functionId,
			programRevision: callee.programRevision,
			bodyRevision: callee.bodyRevision,
			pipelineRevision: callee.pipelineRevision
		};
	}

	static function voidBoundary(callee:OcamlFunctionPlanBinding):OcamlCallableBoundaryPlan {
		return {
			id: "callable-boundary:void-fixture",
			calleeId: VOID_CALLEE_ID,
			sourceModuleId: "VoidCalls",
			sourceTypeName: "VoidCalls",
			sourceFieldName: "withArguments",
			kind: OcamlCallKind.DirectStaticHaxeMethod,
			receiver: null,
			arguments: [value(0), boolValue(1), stringValue(2)],
			resultKind: OcamlCallResultKind.EffectOnlyVoid,
			result: null,
			profileEligibility: ["metal", "portable"],
			reason: "fixture effect-only Void signature",
			proofId: OcamlCallPlan.DIRECT_STATIC_SIGNATURE_PROOF_ID,
			proofClaim: "fixture effect-only Void signature",
			functionId: callee.functionId,
			programRevision: callee.programRevision,
			bodyRevision: callee.bodyRevision,
			pipelineRevision: callee.pipelineRevision
		};
	}

	static function seal(registry:OcamlFunctionPlanRegistry, owner:OcamlFunctionPlanBinding, calls:OcamlCallPlan, callable:Null<OcamlCallableBoundaryPlan>,
			?construction:Null<OcamlCallableBoundaryPlan>):Void {
		registry.sealFunction(owner, OcamlLocalStoragePlanner.planExpressions([]), new OcamlLocalRepresentationPlan([]), new OcamlBytesProducerPlan([]),
			calls, OcamlControlPlan.notAdmitted(owner), callable, construction);
	}

	static function expectThrows(code:String, operation:Void->Void):Void {
		expectedFailureIndex += 1;
		var message:Null<String> = null;
		try {
			operation();
		} catch (error:Dynamic) {
			message = Std.string(error);
		}
		if (message == null || message.indexOf(code) < 0)
			Context.error('Expected failure $expectedFailureIndex containing "$code", received ${message == null ? "no failure" : message}.',
				Context.currentPos());
	}

	/**
		Proves that whole-program validation runs before Reflaxe writes files.

		The compiler is given an extra output file, then its target-owned call
		registry is deliberately left without the callee's final boundary. The
		expected validation error must occur before that sentinel file exists.
	**/
	static function expectPreWriteValidation(caller:OcamlFunctionPlanBinding, selectedCall:OcamlCallDecision):Void {
		final outputDirectory = ".tmp/reflaxe-ocaml-call-plan-prewrite";
		final sentinel = outputDirectory + "/must-not-exist.ml";
		if (sys.FileSystem.exists(sentinel))
			sys.FileSystem.deleteFile(sentinel);
		if (sys.FileSystem.exists(outputDirectory))
			sys.FileSystem.deleteDirectory(outputDirectory);

		final compiler = new OcamlCompiler();
		compiler.functionPlanRegistry.beginProgram(PROGRAM_REVISION);
		compiler.functionPlanRegistry.registerCallableDeclaration(declaration());
		seal(compiler.functionPlanRegistry, caller, new OcamlCallPlan([selectedCall]), null);
		compiler.setOutputDir(outputDirectory);
		compiler.setExtraFile("must-not-exist.ml", "must not be written");

		expectThrows("missing-callable", () -> compiler.generateFiles());
		if (sys.FileSystem.exists(sentinel))
			Context.error("Whole-program call validation ran after Reflaxe wrote the sentinel output file.", Context.currentPos());
		if (sys.FileSystem.exists(outputDirectory))
			sys.FileSystem.deleteDirectory(outputDirectory);
	}

	public static macro function run():Expr {
		final stringArgument = stringValue(0);
		OcamlCallPlan.requireCallValue(stringArgument, 0, "exact String fixture");
		final wrongStringCarrier = OcamlCallPlan.copyValue(stringArgument);
		Reflect.setField(wrongStringCarrier, "outputCarrierTypeId", "Obj.t");
		expectThrows("invalid identity crossing", () -> OcamlCallPlan.requireCallValue(wrongStringCarrier, 0, "wrong String carrier fixture"));
		final wrongStringRepresentation = OcamlCallPlan.copyValue(stringArgument);
		Reflect.setField(wrongStringRepresentation, "inputRepresentationId", "representation:String:mutable-local-storage");
		expectThrows("invalid identity crossing", () -> OcamlCallPlan.requireCallValue(wrongStringRepresentation, 0, "wrong String representation fixture"));
		final missingStringProof = OcamlCallPlan.copyValue(stringArgument);
		Reflect.setField(missingStringProof, "proofId", "");
		expectThrows("invalid index or empty conversion proof", () -> OcamlCallPlan.requireCallValue(missingStringProof, 0, "missing String proof fixture"));

		final caller = binding("Main|Main::main", "body:caller");
		final callee = binding("Arithmetic|Arithmetic::increment", "body:callee");
		final localBlock = Context.typeExpr(macro {
			final localIdentityValue = 1;
			localIdentityValue;
		});
		final localValue = switch (localBlock.expr) {
			case TBlock(expressions): expressions[expressions.length - 1];
			case _: Context.error("Expected the function-value identity fixture to type as a block.", Context.currentPos());
		}
		final callValue = Context.typeExpr(macro Std.string(1));
		final sharedIdentityPosition = Context.currentPos();
		final localAtSharedPosition = {
			expr: localValue.expr,
			pos: sharedIdentityPosition,
			t: localValue.t
		};
		final callAtSharedPosition = {
			expr: callValue.expr,
			pos: sharedIdentityPosition,
			t: callValue.t
		};
		final localIdentity = OcamlCallPlanner.functionValueCalleeId(localAtSharedPosition, caller, "(?String)->String");
		final callResultIdentity = OcamlCallPlanner.functionValueCalleeId(callAtSharedPosition, caller, "(?String)->String");
		if (localIdentity == callResultIdentity)
			Context.error("Local and call-produced function values shared one callee identity.", Context.currentPos());

		final selectedFunctionValueCall = functionValueCall(caller);
		OcamlCallPlan.requireCall(selectedFunctionValueCall);
		final functionValueRegistry = new OcamlFunctionPlanRegistry();
		functionValueRegistry.beginProgram(PROGRAM_REVISION);
		seal(functionValueRegistry, caller, new OcamlCallPlan([selectedFunctionValueCall]), null);
		functionValueRegistry.validateCallGraph();
		expectThrows("does not own a program-wide callable declaration", () -> functionValueRegistry.requireCallableDeclaration(selectedFunctionValueCall));

		final missingCalleeMaterialization = copyCall(selectedFunctionValueCall, null, null, null, null, null,
			selectedFunctionValueCall.evaluationSchedule.slice(1));
		expectThrows("invalid evaluation schedule", () -> OcamlCallPlan.requireCall(missingCalleeMaterialization));
		final wrongCalleeSlot = copyCall(selectedFunctionValueCall);
		Reflect.setField(wrongCalleeSlot.evaluationSchedule[0], "slotId", "call-callee-slot:wrong");
		expectThrows("invalid callee materialization", () -> OcamlCallPlan.requireCall(wrongCalleeSlot));
		final declarationOwnedFunctionValue = copyCall(selectedFunctionValueCall);
		Reflect.setField(declarationOwnedFunctionValue, "sourceModuleId", "Main");
		expectThrows("assigns declaration fields", () -> OcamlCallPlan.requireCall(declarationOwnedFunctionValue));
		final wrongFunctionValueProof = copyCall(selectedFunctionValueCall);
		Reflect.setField(wrongFunctionValueProof, "proofId", OcamlCallPlan.DIRECT_STATIC_SIGNATURE_PROOF_ID);
		expectThrows("mismatched function-value signature proof", () -> OcamlCallPlan.requireCall(wrongFunctionValueProof));
		final wrongFunctionValueArgument = copyCall(selectedFunctionValueCall, null, null, [boolValue(0)]);
		expectThrows("wrong canonical function-value signature", () -> OcamlCallPlan.requireCall(wrongFunctionValueArgument));

		final omittedOptionalStringFunctionValueCall = optionalStringFunctionValueCall(caller, [optionalStringValue(0, true)], [0]);
		OcamlCallPlan.requireCall(omittedOptionalStringFunctionValueCall);
		final suppliedOptionalStringFunctionValueCall = optionalStringFunctionValueCall(caller, [optionalStringValue(0)]);
		OcamlCallPlan.requireCall(suppliedOptionalStringFunctionValueCall);
		final explicitNullOptionalStringFunctionValueCall = optionalStringFunctionValueCall(caller, [explicitNullStringValue(0)]);
		OcamlCallPlan.requireCall(explicitNullOptionalStringFunctionValueCall);
		final requiredThenOmittedStringFunctionValueCall = optionalStringFunctionValueCall(caller, [stringValue(0), optionalStringValue(1, true)], [1]);
		OcamlCallPlan.requireCall(requiredThenOmittedStringFunctionValueCall);
		final requiredThenSuppliedStringFunctionValueCall = optionalStringFunctionValueCall(caller, [stringValue(0), optionalStringValue(1)]);
		OcamlCallPlan.requireCall(requiredThenSuppliedStringFunctionValueCall);
		final mixedMatrixFunctionValueCall = matrixFunctionValueCall(caller, "call:function-value-mixed-matrix-fixture", 34, [boolValue(0), value(1)],
			OcamlCallResultKind.Value, stringValue(-1));
		OcamlCallPlan.requireCall(mixedMatrixFunctionValueCall);
		final zeroMatrixFunctionValueCall = matrixFunctionValueCall(caller, "call:function-value-zero-matrix-fixture", 36, [], OcamlCallResultKind.Value,
			boolValue(-1));
		OcamlCallPlan.requireCall(zeroMatrixFunctionValueCall);
		final nullableMatrixFunctionValueCall = matrixFunctionValueCall(caller, "call:function-value-nullable-matrix-fixture", 38,
			[nullableArgument(0, OcamlCallCarrierConversion.BoxExactIntToNullableInt)], OcamlCallResultKind.Value, nullableValue(-1));
		OcamlCallPlan.requireCall(nullableMatrixFunctionValueCall);
		final optionalNullableMatrixFunctionValueCall = matrixFunctionValueCall(caller, "call:function-value-optional-matrix-fixture", 40,
			[omittedOptionalNullableValue(0)], OcamlCallResultKind.Value, value(-1));
		OcamlCallPlan.requireCall(optionalNullableMatrixFunctionValueCall);
		final effectMatrixFunctionValueCall = matrixFunctionValueCall(caller, "call:function-value-effect-matrix-fixture", 42, [stringValue(0)],
			OcamlCallResultKind.EffectOnlyVoid, null);
		OcamlCallPlan.requireCall(effectMatrixFunctionValueCall);

		final wrongOptionalStringProof = copyCall(omittedOptionalStringFunctionValueCall);
		Reflect.setField(wrongOptionalStringProof, "proofId", OcamlCallPlan.DIRECT_STATIC_SIGNATURE_PROOF_ID);
		expectThrows("mismatched function-value signature proof", () -> OcamlCallPlan.requireCall(wrongOptionalStringProof));
		final requiredTrailingString = copyCall(requiredThenSuppliedStringFunctionValueCall, null, null, [stringValue(0), stringValue(1)]);
		expectThrows("wrong canonical function-value signature", () -> OcamlCallPlan.requireCall(requiredTrailingString));
		final optionalBoolArgument = boolValue(0);
		Reflect.setField(optionalBoolArgument, "parameterOptional", true);
		final optionalBoolClaimingStringProof = copyCall(suppliedOptionalStringFunctionValueCall, null, null, [optionalBoolArgument]);
		expectThrows("unsupported optional-parameter shape", () -> OcamlCallPlan.requireCall(optionalBoolClaimingStringProof));
		final wrongOptionalStringCarrier = copyCall(suppliedOptionalStringFunctionValueCall);
		Reflect.setField(wrongOptionalStringCarrier.arguments[0], "outputCarrierTypeId", "Obj.t");
		expectThrows("invalid identity crossing", () -> OcamlCallPlan.requireCall(wrongOptionalStringCarrier));
		final omittedStringWithSourceEvaluation = copyCall(omittedOptionalStringFunctionValueCall);
		Reflect.setField(omittedStringWithSourceEvaluation.evaluationSchedule[1], "sourceArgumentIndex", 0);
		expectThrows("invalid argument materialization", () -> OcamlCallPlan.requireCall(omittedStringWithSourceEvaluation));
		final wrongMixedMatrixProof = copyCall(mixedMatrixFunctionValueCall);
		Reflect.setField(wrongMixedMatrixProof, "proofId", OcamlCallPlan.FUNCTION_VALUE_SIGNATURE_PROOF_ID_PREFIX + "(Int,Int)->String");
		expectThrows("wrong canonical function-value signature", () -> OcamlCallPlan.requireCall(wrongMixedMatrixProof));
		final effectWithValueResult = copyCall(effectMatrixFunctionValueCall);
		Reflect.setField(effectWithValueResult, "resultKind", OcamlCallResultKind.Value);
		expectThrows("value result kind without a value crossing", () -> OcamlCallPlan.requireCall(effectWithValueResult));

		final selectedCall = call(caller);
		final registry = new OcamlFunctionPlanRegistry();
		registry.beginProgram(PROGRAM_REVISION);
		registry.registerCallableDeclaration(declaration());
		registry.requireCallableDeclaration(selectedCall);
		seal(registry, caller, new OcamlCallPlan([selectedCall]), null);
		seal(registry, callee, new OcamlCallPlan([]), boundary(callee));
		registry.validateCallGraph();

		final constructorCaller = binding("Main|Main::construct", "body:constructor-caller");
		final constructorDefinition = binding(CONSTRUCTOR_CALLEE_ID, "body:constructor-definition");
		final selectedConstructorCall = constructorCall(constructorCaller);
		final constructorRegistry = new OcamlFunctionPlanRegistry();
		constructorRegistry.beginProgram(PROGRAM_REVISION);
		if (constructorRegistry.hasConstructorDeclaration(CONSTRUCTOR_CALLEE_ID))
			Context.error("The constructor hard-cut guard reported an unregistered constructor.", Context.currentPos());
		constructorRegistry.registerCallableDeclaration(constructorDeclaration());
		if (!constructorRegistry.hasConstructorDeclaration(CONSTRUCTOR_CALLEE_ID))
			Context.error("The constructor hard-cut guard did not expose the registered constructor.", Context.currentPos());
		if (registry.hasConstructorDeclaration(CALLEE_ID))
			Context.error("The constructor hard-cut guard incorrectly selected an ordinary method.", Context.currentPos());
		constructorRegistry.requireCallableDeclaration(selectedConstructorCall);
		seal(constructorRegistry, constructorCaller, new OcamlCallPlan([selectedConstructorCall]), null);
		seal(constructorRegistry, constructorDefinition, new OcamlCallPlan([]), null, constructorBoundary(constructorDefinition));
		constructorRegistry.validateCallGraph();

		final primitiveConstructorResult = OcamlCallPlan.copyDeclaration(constructorDeclaration());
		Reflect.setField(primitiveConstructorResult, "result", value(-1));
		expectThrows("no sealed nominal constructor result", () -> OcamlCallPlan.requireCallableDeclarationPlan(primitiveConstructorResult));
		final optionalConstructorArgument = OcamlCallPlan.copyDeclaration(constructorDeclaration());
		Reflect.setField(optionalConstructorArgument.arguments[0], "parameterOptional", true);
		expectThrows("one-required-argument constructor slice", () -> OcamlCallPlan.requireCallableDeclarationPlan(optionalConstructorArgument));
		final boolConstructorArgument = OcamlCallPlan.copyDeclaration(constructorDeclaration());
		Reflect.setField(boolConstructorArgument, "arguments", [boolValue(0)]);
		expectThrows("first exact Int constructor-argument slice", () -> OcamlCallPlan.requireCallableDeclarationPlan(boolConstructorArgument));
		final wrongConstructorProof = OcamlCallPlan.copyDeclaration(constructorDeclaration());
		Reflect.setField(wrongConstructorProof, "proofId", OcamlCallPlan.DIRECT_STATIC_SIGNATURE_PROOF_ID);
		expectThrows("mismatched direct-constructor signature proof", () -> OcamlCallPlan.requireCallableDeclarationPlan(wrongConstructorProof));
		final reorderedConstructorSchedule = copyCall(selectedConstructorCall);
		reorderedConstructorSchedule.evaluationSchedule.reverse();
		expectThrows("invalid argument materialization", () -> constructorRegistry.requireCallableDeclaration(reorderedConstructorSchedule));
		final staleConstructorBoundary = constructorBoundary(constructorDefinition);
		Reflect.setField(staleConstructorBoundary, "bodyRevision", "body:stale-constructor-definition");
		final staleConstructorRegistry = new OcamlFunctionPlanRegistry();
		staleConstructorRegistry.beginProgram(PROGRAM_REVISION);
		staleConstructorRegistry.registerCallableDeclaration(constructorDeclaration());
		expectThrows("stale-callable-binding",
			() -> seal(staleConstructorRegistry, constructorDefinition, new OcamlCallPlan([]), null, staleConstructorBoundary));
		final missingConstructorBoundaryRegistry = new OcamlFunctionPlanRegistry();
		missingConstructorBoundaryRegistry.beginProgram(PROGRAM_REVISION);
		missingConstructorBoundaryRegistry.registerCallableDeclaration(constructorDeclaration());
		seal(missingConstructorBoundaryRegistry, constructorCaller, new OcamlCallPlan([selectedConstructorCall]), null);
		expectThrows("missing-callable", () -> missingConstructorBoundaryRegistry.validateCallGraph());

		final twoArgumentCallee = binding("Arithmetic|Arithmetic::add", "body:two-argument-callee");
		final selectedTwoArgumentCall = twoArgumentCall(caller);
		final twoArgumentRegistry = new OcamlFunctionPlanRegistry();
		twoArgumentRegistry.beginProgram(PROGRAM_REVISION);
		twoArgumentRegistry.registerCallableDeclaration(twoArgumentDeclaration());
		twoArgumentRegistry.requireCallableDeclaration(selectedTwoArgumentCall);
		seal(twoArgumentRegistry, caller, new OcamlCallPlan([selectedTwoArgumentCall]), null);
		seal(twoArgumentRegistry, twoArgumentCallee, new OcamlCallPlan([]), twoArgumentBoundary(twoArgumentCallee));
		twoArgumentRegistry.validateCallGraph();

		final nullableCaller = binding("Main|Main::nullableCalls", "body:nullable-caller");
		final nullableCallee = binding("NullableCalls|NullableCalls::identity", "body:nullable-callee");
		final preserveNullableCall = nullableCall(nullableCaller, NULLABLE_PRESERVE_CALL_ID, 4, OcamlCallCarrierConversion.PreserveNullableIntCarrier);
		final boxNullableCall = nullableCall(nullableCaller, NULLABLE_BOX_CALL_ID, 6, OcamlCallCarrierConversion.BoxExactIntToNullableInt);
		final nullableRegistry = new OcamlFunctionPlanRegistry();
		nullableRegistry.beginProgram(PROGRAM_REVISION);
		nullableRegistry.registerCallableDeclaration(nullableDeclaration());
		nullableRegistry.requireCallableDeclaration(preserveNullableCall);
		nullableRegistry.requireCallableDeclaration(boxNullableCall);
		seal(nullableRegistry, nullableCaller, new OcamlCallPlan([preserveNullableCall, boxNullableCall]), null);
		seal(nullableRegistry, nullableCallee, new OcamlCallPlan([]), nullableBoundary(nullableCallee));
		nullableRegistry.validateCallGraph();

		final boolCaller = binding("Main|Main::boolCall", "body:bool-caller");
		final boolCallee = binding("BoolCalls|BoolCalls::negate", "body:bool-callee");
		final selectedBoolCall = boolCall(boolCaller);
		final boolRegistry = new OcamlFunctionPlanRegistry();
		boolRegistry.beginProgram(PROGRAM_REVISION);
		boolRegistry.registerCallableDeclaration(boolDeclaration());
		boolRegistry.requireCallableDeclaration(selectedBoolCall);
		seal(boolRegistry, boolCaller, new OcamlCallPlan([selectedBoolCall]), null);
		seal(boolRegistry, boolCallee, new OcamlCallPlan([]), boolBoundary(boolCallee));
		boolRegistry.validateCallGraph();

		final nullableBoolCaller = binding("Main|Main::nullableBoolCalls", "body:nullable-bool-caller");
		final nullableBoolCallee = binding("BoolCalls|BoolCalls::identityNullable", "body:nullable-bool-callee");
		final preserveNullableBoolCall = nullableBoolCall(nullableBoolCaller, NULLABLE_BOOL_PRESERVE_CALL_ID, 10,
			OcamlCallCarrierConversion.PreserveNullableBoolCarrier);
		final boxNullableBoolCall = nullableBoolCall(nullableBoolCaller, NULLABLE_BOOL_BOX_CALL_ID, 12, OcamlCallCarrierConversion.BoxExactBoolToNullableBool);
		final nullableBoolRegistry = new OcamlFunctionPlanRegistry();
		nullableBoolRegistry.beginProgram(PROGRAM_REVISION);
		nullableBoolRegistry.registerCallableDeclaration(nullableBoolDeclaration());
		nullableBoolRegistry.requireCallableDeclaration(preserveNullableBoolCall);
		nullableBoolRegistry.requireCallableDeclaration(boxNullableBoolCall);
		seal(nullableBoolRegistry, nullableBoolCaller, new OcamlCallPlan([preserveNullableBoolCall, boxNullableBoolCall]), null);
		final boxedDefinitionResult = nullableBoolArgument(-1, OcamlCallCarrierConversion.BoxExactBoolToNullableBool);
		seal(nullableBoolRegistry, nullableBoolCallee, new OcamlCallPlan([]), nullableBoolBoundary(nullableBoolCallee, boxedDefinitionResult));
		nullableBoolRegistry.validateCallGraph();

		final mixedCaller = binding("Main|Main::mixedCalls", "body:mixed-caller");
		final mixedCallee = binding("MixedCalls|MixedCalls::choose", "body:mixed-callee");
		final preserveMixedCall = mixedCall(mixedCaller, MIXED_PRESERVE_CALL_ID, 14, OcamlCallCarrierConversion.PreserveNullableBoolCarrier,
			OcamlCallCarrierConversion.PreserveNullableIntCarrier);
		final boxMixedCall = mixedCall(mixedCaller, MIXED_BOX_CALL_ID, 16, OcamlCallCarrierConversion.BoxExactBoolToNullableBool,
			OcamlCallCarrierConversion.BoxExactIntToNullableInt);
		final mixedRegistry = new OcamlFunctionPlanRegistry();
		mixedRegistry.beginProgram(PROGRAM_REVISION);
		mixedRegistry.registerCallableDeclaration(mixedDeclaration());
		mixedRegistry.requireCallableDeclaration(preserveMixedCall);
		mixedRegistry.requireCallableDeclaration(boxMixedCall);
		seal(mixedRegistry, mixedCaller, new OcamlCallPlan([preserveMixedCall, boxMixedCall]), null);
		seal(mixedRegistry, mixedCallee, new OcamlCallPlan([]), mixedBoundary(mixedCallee));
		mixedRegistry.validateCallGraph();
		final mixedSchedule = preserveMixedCall.evaluationSchedule;
		final reorderedMixedArguments = copyCall(preserveMixedCall, null, null, null, null, null, [
			mixedSchedule[0],
			mixedSchedule[2],
			mixedSchedule[1],
			mixedSchedule[3],
			mixedSchedule[4]
		]);
		expectThrows("invalid-plan", () -> mixedRegistry.requireCallableDeclaration(reorderedMixedArguments));

		final zeroCaller = binding("Main|Main::zeroArgumentCalls", "body:zero-argument-caller");
		final zeroCallee = binding("ZeroArgCalls|ZeroArgCalls::exactCount", "body:zero-argument-callee");
		final selectedZeroArgumentCall = zeroArgumentCall(zeroCaller);
		final zeroArgumentRegistry = new OcamlFunctionPlanRegistry();
		zeroArgumentRegistry.beginProgram(PROGRAM_REVISION);
		zeroArgumentRegistry.registerCallableDeclaration(zeroArgumentDeclaration());
		zeroArgumentRegistry.requireCallableDeclaration(selectedZeroArgumentCall);
		seal(zeroArgumentRegistry, zeroCaller, new OcamlCallPlan([selectedZeroArgumentCall]), null);
		seal(zeroArgumentRegistry, zeroCallee, new OcamlCallPlan([]), zeroArgumentBoundary(zeroCallee));
		zeroArgumentRegistry.validateCallGraph();
		final zeroSchedule = selectedZeroArgumentCall.evaluationSchedule;
		if (zeroSchedule.length != 1
			|| zeroSchedule[0].kind != OcamlCallEvaluationStepKind.InvokeCallee
			|| zeroSchedule[0].argumentIndex != null
			|| zeroSchedule[0].sourceArgumentIndex != null
			|| zeroSchedule[0].slotId != null) {
			Context.error("The zero-argument call schedule must contain only one invocation step.", Context.currentPos());
		}
		expectThrows("invalid-plan", () -> OcamlCallPlan.evaluationSchedule(ZERO_CALL_ID, -1));
		final zeroMissingInvocation = copyCall(selectedZeroArgumentCall, null, null, null, null, null, []);
		expectThrows("invalid-plan", () -> zeroArgumentRegistry.requireCallableDeclaration(zeroMissingInvocation));
		final zeroUnexpectedMaterialization = copyCall(selectedZeroArgumentCall, null, null, null, null, null, [
			{
				kind: OcamlCallEvaluationStepKind.MaterializeArgument,
				argumentIndex: 0,
				sourceArgumentIndex: 0,
				slotId: OcamlCallPlan.argumentSlotId(ZERO_CALL_ID, 0)
			},
			zeroSchedule[0]
		]);
		expectThrows("invalid-plan", () -> zeroArgumentRegistry.requireCallableDeclaration(zeroUnexpectedMaterialization));

		final optionalCaller = binding("Main|Main::optionalCalls", "body:optional-caller");
		final optionalCallee = binding("OptionalCalls|OptionalCalls::optionalInt", "body:optional-callee");
		final omittedOptionalCall = optionalCall(optionalCaller, true);
		final suppliedOptionalCall = optionalCall(optionalCaller, false);
		final optionalRegistry = new OcamlFunctionPlanRegistry();
		optionalRegistry.beginProgram(PROGRAM_REVISION);
		if (optionalRegistry.hasCallableDeclaration(OPTIONAL_CALLEE_ID))
			Context.error("The optional declaration guard reported an unregistered callable.", Context.currentPos());
		if (optionalRegistry.hasOptionalCallableDeclaration(OPTIONAL_CALLEE_ID))
			Context.error("The optional hard-cut guard reported an unregistered callable.", Context.currentPos());
		optionalRegistry.registerCallableDeclaration(optionalDeclaration());
		if (!optionalRegistry.hasCallableDeclaration(OPTIONAL_CALLEE_ID))
			Context.error("The optional declaration guard did not expose the registered callable.", Context.currentPos());
		if (!optionalRegistry.hasOptionalCallableDeclaration(OPTIONAL_CALLEE_ID))
			Context.error("The optional hard-cut guard did not expose the registered optional callable.", Context.currentPos());
		if (registry.hasOptionalCallableDeclaration(CALLEE_ID))
			Context.error("The optional hard-cut guard incorrectly selected a required-argument callable.", Context.currentPos());
		optionalRegistry.requireCallableDeclaration(omittedOptionalCall);
		optionalRegistry.requireCallableDeclaration(suppliedOptionalCall);
		seal(optionalRegistry, optionalCaller, new OcamlCallPlan([omittedOptionalCall, suppliedOptionalCall]), null);
		seal(optionalRegistry, optionalCallee, new OcamlCallPlan([]), optionalBoundary(optionalCallee));
		optionalRegistry.validateCallGraph();

		final omittedSchedule = omittedOptionalCall.evaluationSchedule;
		if (omittedSchedule.length != 2
			|| omittedSchedule[0].kind != OcamlCallEvaluationStepKind.MaterializeOmittedArgument
			|| omittedSchedule[0].argumentIndex != 0
			|| omittedSchedule[0].sourceArgumentIndex != null
			|| omittedSchedule[0].slotId != OcamlCallPlan.argumentSlotId(OPTIONAL_OMITTED_CALL_ID, 0)
			|| omittedSchedule[1].kind != OcamlCallEvaluationStepKind.InvokeCallee
			|| omittedSchedule[1].sourceArgumentIndex != null) {
			Context.error("The omitted optional call did not retain one source-free carrier materialization before invocation.", Context.currentPos());
		}
		final suppliedSchedule = suppliedOptionalCall.evaluationSchedule;
		if (suppliedSchedule[0].kind != OcamlCallEvaluationStepKind.MaterializeArgument || suppliedSchedule[0].sourceArgumentIndex != 0) {
			Context.error("The supplied optional call did not retain source argument zero.", Context.currentPos());
		}
		expectThrows("invalid-plan", () -> OcamlCallPlan.evaluationSchedule(OPTIONAL_OMITTED_CALL_ID, 1, [1]));
		expectThrows("invalid-plan", () -> OcamlCallPlan.evaluationSchedule(OPTIONAL_OMITTED_CALL_ID, 1, [0, 0]));

		final omittedWithoutOptional = OcamlCallPlan.copyValue(omittedOptionalCall.arguments[0]);
		Reflect.setField(omittedWithoutOptional, "parameterOptional", false);
		expectThrows("invalid-plan", () -> optionalRegistry.requireCallableDeclaration(copyCall(omittedOptionalCall, null, null, [omittedWithoutOptional])));

		final omittedWithSourceStep = copyCall(omittedOptionalCall, null, null, null, null, null, [
			{
				kind: OcamlCallEvaluationStepKind.MaterializeArgument,
				argumentIndex: 0,
				sourceArgumentIndex: 0,
				slotId: OcamlCallPlan.argumentSlotId(OPTIONAL_OMITTED_CALL_ID, 0)
			},
			omittedSchedule[1]
		]);
		expectThrows("invalid-plan", () -> optionalRegistry.requireCallableDeclaration(omittedWithSourceStep));

		final suppliedWithoutSourceStep = copyCall(suppliedOptionalCall, null, null, null, null, null, [
			{
				kind: OcamlCallEvaluationStepKind.MaterializeArgument,
				argumentIndex: 0,
				sourceArgumentIndex: null,
				slotId: OcamlCallPlan.argumentSlotId(OPTIONAL_SUPPLIED_CALL_ID, 0)
			},
			suppliedSchedule[1]
		]);
		expectThrows("invalid-plan", () -> optionalRegistry.requireCallableDeclaration(suppliedWithoutSourceStep));

		final nonTrailingOptionalDeclaration = OcamlCallPlan.copyDeclaration(optionalDeclaration());
		Reflect.setField(nonTrailingOptionalDeclaration, "arguments", [optionalNullableValue(0), value(1)]);
		expectThrows("invalid-plan", () -> OcamlCallPlan.requireCallableDeclarationPlan(nonTrailingOptionalDeclaration));

		final optionalStringDeclaration = OcamlCallPlan.copyDeclaration(optionalDeclaration());
		Reflect.setField(optionalStringDeclaration, "arguments", [optionalStringValue(0)]);
		Reflect.setField(optionalStringDeclaration, "result", stringValue(-1));
		OcamlCallPlan.requireCallableDeclarationPlan(optionalStringDeclaration);
		final omittedOptionalString = copyCall(omittedOptionalCall, null, null, [optionalStringValue(0, true)], stringValue(-1));
		OcamlCallPlan.requireCall(omittedOptionalString);
		final explicitNullOptionalString = copyCall(suppliedOptionalCall, null, null, [explicitNullStringValue(0)], stringValue(-1));
		OcamlCallPlan.requireCall(explicitNullOptionalString);
		final optionalStringBoundary = optionalBoundary(optionalCallee);
		Reflect.setField(optionalStringBoundary, "arguments", [optionalStringValue(0)]);
		Reflect.setField(optionalStringBoundary, "result", stringValue(-1));
		OcamlCallPlan.requireCallableBoundary(optionalStringBoundary);

		final omittedStringWithWrongProof = OcamlCallPlan.copyValue(optionalStringValue(0, true));
		Reflect.setField(omittedStringWithWrongProof, "proofId", "omitted-nullable-int-call-materialization-v1");
		expectThrows("invalid-plan", () -> OcamlCallPlan.requireCallValue(omittedStringWithWrongProof, 0, "fixture omitted optional String"));
		final explicitNullStringWithWrongProof = OcamlCallPlan.copyValue(explicitNullStringValue(0));
		Reflect.setField(explicitNullStringWithWrongProof, "proofId", "identity-call-carrier-v1");
		expectThrows("invalid-plan", () -> OcamlCallPlan.requireCallValue(explicitNullStringWithWrongProof, 0, "fixture explicit null String"));
		final nonTrailingOptionalStringDeclaration = OcamlCallPlan.copyDeclaration(optionalStringDeclaration);
		Reflect.setField(nonTrailingOptionalStringDeclaration, "arguments", [optionalStringValue(0), value(1)]);
		expectThrows("invalid-plan", () -> OcamlCallPlan.requireCallableDeclarationPlan(nonTrailingOptionalStringDeclaration));

		final voidCaller = binding("Main|Main::voidCalls", "body:void-caller");
		final voidCallee = binding(VOID_CALLEE_ID, "body:void-callee");
		final selectedVoidCall = voidCall(voidCaller);
		final voidRegistry = new OcamlFunctionPlanRegistry();
		voidRegistry.beginProgram(PROGRAM_REVISION);
		voidRegistry.registerCallableDeclaration(voidDeclaration());
		if (!voidRegistry.hasEffectOnlyCallableDeclaration(VOID_CALLEE_ID))
			Context.error("The Void hard-cut guard did not expose the admitted effect-only callable.", Context.currentPos());
		if (registry.hasEffectOnlyCallableDeclaration(CALLEE_ID))
			Context.error("The Void hard-cut guard incorrectly selected a value-returning callable.", Context.currentPos());
		voidRegistry.requireCallableDeclaration(selectedVoidCall);
		seal(voidRegistry, voidCaller, new OcamlCallPlan([selectedVoidCall]), null);
		seal(voidRegistry, voidCallee, new OcamlCallPlan([]), voidBoundary(voidCallee));
		voidRegistry.validateCallGraph();

		final valueKindWithoutValue = OcamlCallPlan.copyDeclaration(voidDeclaration());
		Reflect.setField(valueKindWithoutValue, "resultKind", OcamlCallResultKind.Value);
		expectThrows("invalid-plan", () -> OcamlCallPlan.requireCallableDeclarationPlan(valueKindWithoutValue));
		final effectKindWithValue = OcamlCallPlan.copyDeclaration(voidDeclaration());
		Reflect.setField(effectKindWithValue, "result", value(-1));
		expectThrows("invalid-plan", () -> OcamlCallPlan.requireCallableDeclarationPlan(effectKindWithValue));
		final valueReturningVoidCall = copyCall(selectedVoidCall, null, null, null, value(-1), null, null, OcamlCallResultKind.Value);
		expectThrows("declaration-mismatch", () -> voidRegistry.requireCallableDeclaration(valueReturningVoidCall));
		final valueReturningVoidBoundary = voidBoundary(voidCallee);
		Reflect.setField(valueReturningVoidBoundary, "resultKind", OcamlCallResultKind.Value);
		Reflect.setField(valueReturningVoidBoundary, "result", value(-1));
		final mismatchedVoidBoundaryRegistry = new OcamlFunctionPlanRegistry();
		mismatchedVoidBoundaryRegistry.beginProgram(PROGRAM_REVISION);
		mismatchedVoidBoundaryRegistry.registerCallableDeclaration(voidDeclaration());
		expectThrows("boundary-declaration-mismatch",
			() -> seal(mismatchedVoidBoundaryRegistry, voidCallee, new OcamlCallPlan([]), valueReturningVoidBoundary));

		expectThrows("duplicate-declaration", () -> registry.registerCallableDeclaration(declaration()));
		expectThrows("duplicate-function-seal", () -> seal(registry, caller, new OcamlCallPlan([]), null));

		final wrongCallee = copyCall(selectedCall, "Missing|Missing::increment");
		expectThrows("missing-declaration", () -> registry.requireCallableDeclaration(wrongCallee));

		final wrongKind = copyCall(selectedCall, null, cast "dynamic-call");
		expectThrows("invalid-plan", () -> registry.requireCallableDeclaration(wrongKind));

		final wrongArity = copyCall(selectedCall, null, null, [value(0), value(1), value(2)]);
		expectThrows("invalid-plan", () -> registry.requireCallableDeclaration(wrongArity));

		final materialization = selectedCall.evaluationSchedule[0];
		final invocation = selectedCall.evaluationSchedule[1];
		final missingMaterialization = copyCall(selectedCall, null, null, null, null, null, [invocation]);
		expectThrows("invalid-plan", () -> registry.requireCallableDeclaration(missingMaterialization));
		final reorderedSchedule = copyCall(selectedCall, null, null, null, null, null, [invocation, materialization]);
		expectThrows("invalid-plan", () -> registry.requireCallableDeclaration(reorderedSchedule));
		final repeatedMaterialization = copyCall(selectedCall, null, null, null, null, null, [materialization, materialization]);
		expectThrows("invalid-plan", () -> registry.requireCallableDeclaration(repeatedMaterialization));
		final outOfRangeSchedule = copyCall(selectedCall, null, null, null, null, null, [
			{
				kind: OcamlCallEvaluationStepKind.MaterializeArgument,
				argumentIndex: 1,
				sourceArgumentIndex: 1,
				slotId: OcamlCallPlan.argumentSlotId(CALL_ID, 1)
			},
			invocation
		]);
		expectThrows("invalid-plan", () -> registry.requireCallableDeclaration(outOfRangeSchedule));
		final wrongSlotSchedule = copyCall(selectedCall, null, null, null, null, null, [
			{
				kind: OcamlCallEvaluationStepKind.MaterializeArgument,
				argumentIndex: 0,
				sourceArgumentIndex: 0,
				slotId: "call-argument-slot:wrong"
			},
			invocation
		]);
		expectThrows("invalid-plan", () -> registry.requireCallableDeclaration(wrongSlotSchedule));

		final twoSchedule = selectedTwoArgumentCall.evaluationSchedule;
		final reorderedArguments = copyCall(selectedTwoArgumentCall, null, null, null, null, null, [twoSchedule[1], twoSchedule[0], twoSchedule[2]]);
		expectThrows("invalid-plan", () -> twoArgumentRegistry.requireCallableDeclaration(reorderedArguments));
		final repeatedFirstArgument = copyCall(selectedTwoArgumentCall, null, null, null, null, null, [twoSchedule[0], twoSchedule[0], twoSchedule[2]]);
		expectThrows("invalid-plan", () -> twoArgumentRegistry.requireCallableDeclaration(repeatedFirstArgument));
		final skippedFirstArgument = copyCall(selectedTwoArgumentCall, null, null, null, null, null, [twoSchedule[1], twoSchedule[2]]);
		expectThrows("invalid-plan", () -> twoArgumentRegistry.requireCallableDeclaration(skippedFirstArgument));

		final missingRequiredArgument = copyCall(selectedCall, null, null, [], null, null, OcamlCallPlan.evaluationSchedule(CALL_ID, 0));
		expectThrows("declaration-mismatch", () -> registry.requireCallableDeclaration(missingRequiredArgument));

		final wrongSemanticType = copyCall(selectedCall, null, null, [
			{
				index: 0,
				parameterOptional: false,
				inputSemanticTypeId: "Float",
				inputCarrierTypeId: "int",
				inputRepresentationId: "representation:Int:internal-value",
				outputSemanticTypeId: "Int",
				outputCarrierTypeId: "int",
				outputRepresentationId: "representation:Int:internal-value",
				conversion: OcamlCallCarrierConversion.Identity,
				proofId: "identity-call-carrier-v1",
				proofClaim: "fixture"
			}
		]);
		expectThrows("invalid-plan", () -> registry.requireCallableDeclaration(wrongSemanticType));

		final wrongCarrier = copyCall(selectedCall, null, null, [
			{
				index: 0,
				parameterOptional: false,
				inputSemanticTypeId: "Int",
				inputCarrierTypeId: "Obj.t",
				inputRepresentationId: "representation:Int:internal-value",
				outputSemanticTypeId: "Int",
				outputCarrierTypeId: "Obj.t",
				outputRepresentationId: "representation:Int:internal-value",
				conversion: OcamlCallCarrierConversion.Identity,
				proofId: "identity-call-carrier-v1",
				proofClaim: "fixture"
			}
		]);
		expectThrows("invalid-plan", () -> registry.requireCallableDeclaration(wrongCarrier));

		final wrongConversion = copyCall(selectedCall, null, null, [
			{
				index: 0,
				parameterOptional: false,
				inputSemanticTypeId: "Int",
				inputCarrierTypeId: "int",
				inputRepresentationId: "representation:Int:internal-value",
				outputSemanticTypeId: "Int",
				outputCarrierTypeId: "int",
				outputRepresentationId: "representation:Int:internal-value",
				conversion: cast "box",
				proofId: "identity-call-carrier-v1",
				proofClaim: "fixture"
			}
		]);
		expectThrows("invalid-plan", () -> registry.requireCallableDeclaration(wrongConversion));

		final missingNullableConversionValue = OcamlCallPlan.copyValue(boxNullableCall.arguments[0]);
		Reflect.setField(missingNullableConversionValue, "conversion", "");
		final missingNullableConversion = copyCall(boxNullableCall, null, null, [missingNullableConversionValue]);
		expectThrows("invalid-plan", () -> nullableRegistry.requireCallableDeclaration(missingNullableConversion));

		final ambiguousNullableIdentity = copyCall(preserveNullableCall, null, null, [nullableValue(0)]);
		expectThrows("invalid-plan", () -> nullableRegistry.requireCallableDeclaration(ambiguousNullableIdentity));

		final wrongNullableProofValue = OcamlCallPlan.copyValue(boxNullableCall.arguments[0]);
		Reflect.setField(wrongNullableProofValue, "proofId", "wrong-proof");
		final wrongNullableProof = copyCall(boxNullableCall, null, null, [wrongNullableProofValue]);
		expectThrows("invalid-plan", () -> nullableRegistry.requireCallableDeclaration(wrongNullableProof));

		final doubleBoxValue = OcamlCallPlan.copyValue(boxNullableCall.arguments[0]);
		Reflect.setField(doubleBoxValue, "inputSemanticTypeId", "Null<Int>");
		Reflect.setField(doubleBoxValue, "inputCarrierTypeId", "Obj.t");
		Reflect.setField(doubleBoxValue, "inputRepresentationId", "representation:Null<Int>:internal-value");
		final doubleBoxCall = copyCall(boxNullableCall, null, null, [doubleBoxValue]);
		expectThrows("invalid-plan", () -> nullableRegistry.requireCallableDeclaration(doubleBoxCall));

		final wrongNullableDirectionValue = OcamlCallPlan.copyValue(preserveNullableCall.arguments[0]);
		Reflect.setField(wrongNullableDirectionValue, "outputSemanticTypeId", "Int");
		Reflect.setField(wrongNullableDirectionValue, "outputCarrierTypeId", "int");
		Reflect.setField(wrongNullableDirectionValue, "outputRepresentationId", "representation:Int:internal-value");
		final wrongNullableDirection = copyCall(preserveNullableCall, null, null, [wrongNullableDirectionValue]);
		expectThrows("invalid-plan", () -> nullableRegistry.requireCallableDeclaration(wrongNullableDirection));

		final conflictingNullableBoundary = nullableBoundary(nullableCallee);
		Reflect.setField(conflictingNullableBoundary.arguments[0], "outputCarrierTypeId", "int");
		final conflictingNullableRegistry = new OcamlFunctionPlanRegistry();
		conflictingNullableRegistry.beginProgram(PROGRAM_REVISION);
		conflictingNullableRegistry.registerCallableDeclaration(nullableDeclaration());
		expectThrows("invalid-plan", () -> seal(conflictingNullableRegistry, nullableCallee, new OcamlCallPlan([]), conflictingNullableBoundary));

		final wrongBoolCarrierValue = OcamlCallPlan.copyValue(selectedBoolCall.arguments[0]);
		Reflect.setField(wrongBoolCarrierValue, "inputCarrierTypeId", "int");
		Reflect.setField(wrongBoolCarrierValue, "outputCarrierTypeId", "int");
		final wrongBoolCarrier = copyCall(selectedBoolCall, null, null, [wrongBoolCarrierValue]);
		expectThrows("invalid-plan", () -> boolRegistry.requireCallableDeclaration(wrongBoolCarrier));

		final wrongBoolProofValue = OcamlCallPlan.copyValue(selectedBoolCall.arguments[0]);
		Reflect.setField(wrongBoolProofValue, "proofId", "wrong-proof");
		final wrongBoolProof = copyCall(selectedBoolCall, null, null, [wrongBoolProofValue]);
		expectThrows("invalid-plan", () -> boolRegistry.requireCallableDeclaration(wrongBoolProof));

		final wrongBoolFamilyProof = copyCall(selectedBoolCall);
		Reflect.setField(wrongBoolFamilyProof, "proofId", "wrong-signature-proof");
		expectThrows("invalid-plan", () -> boolRegistry.requireCallableDeclaration(wrongBoolFamilyProof));

		final conflictingBoolBoundary = boolBoundary(boolCallee);
		Reflect.setField(conflictingBoolBoundary.result, "outputRepresentationId", "representation:Int:internal-value");
		final conflictingBoolRegistry = new OcamlFunctionPlanRegistry();
		conflictingBoolRegistry.beginProgram(PROGRAM_REVISION);
		conflictingBoolRegistry.registerCallableDeclaration(boolDeclaration());
		expectThrows("invalid-plan", () -> seal(conflictingBoolRegistry, boolCallee, new OcamlCallPlan([]), conflictingBoolBoundary));

		final ambiguousNullableBoolIdentity = copyCall(preserveNullableBoolCall, null, null, [nullableBoolValue(0)]);
		expectThrows("invalid-plan", () -> nullableBoolRegistry.requireCallableDeclaration(ambiguousNullableBoolIdentity));

		final wrongNullableBoolProofValue = OcamlCallPlan.copyValue(boxNullableBoolCall.arguments[0]);
		Reflect.setField(wrongNullableBoolProofValue, "proofId", "wrong-proof");
		final wrongNullableBoolProof = copyCall(boxNullableBoolCall, null, null, [wrongNullableBoolProofValue]);
		expectThrows("invalid-plan", () -> nullableBoolRegistry.requireCallableDeclaration(wrongNullableBoolProof));

		final doubleBoolBoxValue = OcamlCallPlan.copyValue(boxNullableBoolCall.arguments[0]);
		Reflect.setField(doubleBoolBoxValue, "inputSemanticTypeId", "Null<Bool>");
		Reflect.setField(doubleBoolBoxValue, "inputCarrierTypeId", "Obj.t");
		Reflect.setField(doubleBoolBoxValue, "inputRepresentationId", "representation:Null<Bool>:internal-value");
		final doubleBoolBoxCall = copyCall(boxNullableBoolCall, null, null, [doubleBoolBoxValue]);
		expectThrows("invalid-plan", () -> nullableBoolRegistry.requireCallableDeclaration(doubleBoolBoxCall));

		final wrongNullableBoolDirectionValue = OcamlCallPlan.copyValue(preserveNullableBoolCall.arguments[0]);
		Reflect.setField(wrongNullableBoolDirectionValue, "outputSemanticTypeId", "Bool");
		Reflect.setField(wrongNullableBoolDirectionValue, "outputCarrierTypeId", "bool");
		Reflect.setField(wrongNullableBoolDirectionValue, "outputRepresentationId", "representation:Bool:internal-value");
		final wrongNullableBoolDirection = copyCall(preserveNullableBoolCall, null, null, [wrongNullableBoolDirectionValue]);
		expectThrows("invalid-plan", () -> nullableBoolRegistry.requireCallableDeclaration(wrongNullableBoolDirection));

		final conflictingNullableBoolBoundary = nullableBoolBoundary(nullableBoolCallee);
		Reflect.setField(conflictingNullableBoolBoundary.arguments[0], "outputCarrierTypeId", "bool");
		final conflictingNullableBoolRegistry = new OcamlFunctionPlanRegistry();
		conflictingNullableBoolRegistry.beginProgram(PROGRAM_REVISION);
		conflictingNullableBoolRegistry.registerCallableDeclaration(nullableBoolDeclaration());
		expectThrows("invalid-plan", () -> seal(conflictingNullableBoolRegistry, nullableBoolCallee, new OcamlCallPlan([]), conflictingNullableBoolBoundary));

		final wrongMixedArgument = copyCall(preserveMixedCall, null, null, [
			boolValue(0),
			nullableBoolArgument(1, OcamlCallCarrierConversion.PreserveNullableBoolCarrier),
			boolValue(2),
			nullableArgument(3, OcamlCallCarrierConversion.PreserveNullableIntCarrier)
		]);
		expectThrows("declaration-argument-mismatch", () -> mixedRegistry.requireCallableDeclaration(wrongMixedArgument));

		final wrongMixedResult = copyCall(preserveMixedCall, null, null, null, boolValue(-1));
		expectThrows("declaration-mismatch", () -> mixedRegistry.requireCallableDeclaration(wrongMixedResult));

		final conflictingMixedBoundary = mixedBoundary(mixedCallee);
		Reflect.setField(conflictingMixedBoundary.arguments[0], "outputCarrierTypeId", "bool");
		final conflictingMixedRegistry = new OcamlFunctionPlanRegistry();
		conflictingMixedRegistry.beginProgram(PROGRAM_REVISION);
		conflictingMixedRegistry.registerCallableDeclaration(mixedDeclaration());
		expectThrows("invalid-plan", () -> seal(conflictingMixedRegistry, mixedCallee, new OcamlCallPlan([]), conflictingMixedBoundary));

		final staleCaller = copyCall(selectedCall, null, null, null, null, "body:stale");
		final staleCallerRegistry = new OcamlFunctionPlanRegistry();
		staleCallerRegistry.beginProgram(PROGRAM_REVISION);
		staleCallerRegistry.registerCallableDeclaration(declaration());
		expectThrows("stale-caller-binding", () -> seal(staleCallerRegistry, caller, new OcamlCallPlan([staleCaller]), null));

		final missingBoundaryRegistry = new OcamlFunctionPlanRegistry();
		missingBoundaryRegistry.beginProgram(PROGRAM_REVISION);
		missingBoundaryRegistry.registerCallableDeclaration(declaration());
		seal(missingBoundaryRegistry, caller, new OcamlCallPlan([selectedCall]), null);
		expectThrows("missing-callable", () -> missingBoundaryRegistry.validateCallGraph());
		expectPreWriteValidation(caller, selectedCall);

		Sys.println("REFLAXE_OCAML_CALL_PLAN_FIXTURE:PASS");
		return macro null;
	}
}
