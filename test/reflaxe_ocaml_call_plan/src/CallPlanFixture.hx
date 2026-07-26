import haxe.macro.Context;
import haxe.macro.Expr;
import reflaxe.ocaml.OcamlCompiler;
import reflaxe.ocaml.lowered.OcamlCallPlan;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallCarrierConversion;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallDecision;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallEvaluationStep;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallEvaluationStepKind;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallKind;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallValuePlan;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallableBoundaryPlan;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallableDeclarationPlan;
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

	static function value(index:Int):OcamlCallValuePlan {
		return {
			index: index,
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

	static function nullableValue(index:Int):OcamlCallValuePlan {
		return {
			index: index,
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

	static function boolValue(index:Int):OcamlCallValuePlan {
		return {
			index: index,
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

	static function nullableArgument(index:Int, conversion:OcamlCallCarrierConversion):OcamlCallValuePlan {
		return switch (conversion) {
			case PreserveNullableIntCarrier:
				{
					index: index,
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
			arguments: [value(0)],
			result: value(-1),
			profileEligibility: ["metal", "portable"],
			reason: "fixture",
			proofId: "direct-one-int-static-call-v1",
			proofClaim: "fixture",
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
			arguments: [value(0), value(1)],
			result: value(-1),
			profileEligibility: ["metal", "portable"],
			reason: "fixture",
			proofId: "direct-two-int-static-call-v1",
			proofClaim: "fixture",
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
			arguments: [nullableValue(0)],
			result: nullableValue(-1),
			profileEligibility: ["metal", "portable"],
			reason: "fixture",
			proofId: "direct-one-nullable-int-static-call-v1",
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
			arguments: [boolValue(0)],
			result: boolValue(-1),
			profileEligibility: ["metal", "portable"],
			reason: "fixture",
			proofId: "direct-one-bool-static-call-v1",
			proofClaim: "fixture",
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
			arguments: [value(0)],
			result: value(-1),
			evaluationSchedule: OcamlCallPlan.evaluationSchedule(CALL_ID, 1),
			profileEligibility: ["metal", "portable"],
			reason: "fixture",
			proofId: "direct-one-int-static-call-v1",
			proofClaim: "fixture",
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
			arguments: [value(0), value(1)],
			result: value(-1),
			evaluationSchedule: OcamlCallPlan.evaluationSchedule(TWO_CALL_ID, 2),
			profileEligibility: ["metal", "portable"],
			reason: "fixture",
			proofId: "direct-two-int-static-call-v1",
			proofClaim: "fixture",
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
			arguments: [nullableArgument(0, conversion)],
			result: nullableValue(-1),
			evaluationSchedule: OcamlCallPlan.evaluationSchedule(id, 1),
			profileEligibility: ["metal", "portable"],
			reason: "fixture",
			proofId: "direct-one-nullable-int-static-call-v1",
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
			arguments: [boolValue(0)],
			result: boolValue(-1),
			evaluationSchedule: OcamlCallPlan.evaluationSchedule(BOOL_CALL_ID, 1),
			profileEligibility: ["metal", "portable"],
			reason: "fixture",
			proofId: "direct-one-bool-static-call-v1",
			proofClaim: "fixture",
			functionId: caller.functionId,
			programRevision: caller.programRevision,
			bodyRevision: caller.bodyRevision,
			pipelineRevision: caller.pipelineRevision
		};
	}

	static function copyCall(source:OcamlCallDecision, ?calleeId:String, ?kind:OcamlCallKind, ?arguments:Array<OcamlCallValuePlan>,
			?result:OcamlCallValuePlan, ?bodyRevision:String, ?evaluationSchedule:Array<OcamlCallEvaluationStep>):OcamlCallDecision {
		return {
			id: source.id,
			source: {file: source.source.file, min: source.source.min, max: source.source.max},
			calleeId: calleeId ?? source.calleeId,
			sourceModuleId: source.sourceModuleId,
			sourceTypeName: source.sourceTypeName,
			sourceFieldName: source.sourceFieldName,
			kind: kind ?? source.kind,
			arguments: arguments ?? source.arguments.map(OcamlCallPlan.copyValue),
			result: result ?? OcamlCallPlan.copyValue(source.result),
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
			arguments: [value(0)],
			result: value(-1),
			profileEligibility: ["metal", "portable"],
			reason: "fixture",
			proofId: "direct-one-int-static-call-v1",
			proofClaim: "fixture",
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
			arguments: [value(0), value(1)],
			result: value(-1),
			profileEligibility: ["metal", "portable"],
			reason: "fixture",
			proofId: "direct-two-int-static-call-v1",
			proofClaim: "fixture",
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
			arguments: [nullableValue(0)],
			result: nullableValue(-1),
			profileEligibility: ["metal", "portable"],
			reason: "fixture",
			proofId: "direct-one-nullable-int-static-call-v1",
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
			arguments: [boolValue(0)],
			result: boolValue(-1),
			profileEligibility: ["metal", "portable"],
			reason: "fixture",
			proofId: "direct-one-bool-static-call-v1",
			proofClaim: "fixture",
			functionId: callee.functionId,
			programRevision: callee.programRevision,
			bodyRevision: callee.bodyRevision,
			pipelineRevision: callee.pipelineRevision
		};
	}

	static function seal(registry:OcamlFunctionPlanRegistry, owner:OcamlFunctionPlanBinding, calls:OcamlCallPlan,
			callable:Null<OcamlCallableBoundaryPlan>):Void {
		registry.sealFunction(owner, OcamlLocalStoragePlanner.planExpressions([]), new OcamlLocalRepresentationPlan([]), calls, callable);
	}

	static function expectThrows(code:String, operation:Void->Void):Void {
		var message:Null<String> = null;
		try {
			operation();
		} catch (error:Dynamic) {
			message = Std.string(error);
		}
		if (message == null || message.indexOf(code) < 0)
			Context.error('Expected failure containing "$code", received ${message == null ? "no failure" : message}.', Context.currentPos());
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
		final caller = binding("Main|Main::main", "body:caller");
		final callee = binding("Arithmetic|Arithmetic::increment", "body:callee");
		final selectedCall = call(caller);
		final registry = new OcamlFunctionPlanRegistry();
		registry.beginProgram(PROGRAM_REVISION);
		registry.registerCallableDeclaration(declaration());
		registry.requireCallableDeclaration(selectedCall);
		seal(registry, caller, new OcamlCallPlan([selectedCall]), null);
		seal(registry, callee, new OcamlCallPlan([]), boundary(callee));
		registry.validateCallGraph();

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
				slotId: OcamlCallPlan.argumentSlotId(CALL_ID, 1)
			},
			invocation
		]);
		expectThrows("invalid-plan", () -> registry.requireCallableDeclaration(outOfRangeSchedule));
		final wrongSlotSchedule = copyCall(selectedCall, null, null, null, null, null, [
			{
				kind: OcamlCallEvaluationStepKind.MaterializeArgument,
				argumentIndex: 0,
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

		final wrongSemanticType = copyCall(selectedCall, null, null, [
			{
				index: 0,
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
		Reflect.setField(wrongBoolFamilyProof, "proofId", "direct-one-int-static-call-v1");
		expectThrows("invalid-plan", () -> boolRegistry.requireCallableDeclaration(wrongBoolFamilyProof));

		final conflictingBoolBoundary = boolBoundary(boolCallee);
		Reflect.setField(conflictingBoolBoundary.result, "outputRepresentationId", "representation:Int:internal-value");
		final conflictingBoolRegistry = new OcamlFunctionPlanRegistry();
		conflictingBoolRegistry.beginProgram(PROGRAM_REVISION);
		conflictingBoolRegistry.registerCallableDeclaration(boolDeclaration());
		expectThrows("invalid-plan", () -> seal(conflictingBoolRegistry, boolCallee, new OcamlCallPlan([]), conflictingBoolBoundary));

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
