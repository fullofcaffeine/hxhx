import haxe.macro.Context;
import haxe.macro.Expr;
import reflaxe.ocaml.OcamlCompiler;
import reflaxe.ocaml.lowered.OcamlCallPlan;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallCarrierConversion;
import reflaxe.ocaml.lowered.OcamlCallPlan.OcamlCallDecision;
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

	static function value(index:Int):OcamlCallValuePlan {
		return {
			index: index,
			semanticTypeId: "Int",
			carrierTypeId: "int",
			representationId: "representation:Int:internal-value",
			conversion: OcamlCallCarrierConversion.Identity
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
			id: "call:fixture",
			source: {file: "CallPlanFixture.hx", min: 0, max: 1},
			calleeId: CALLEE_ID,
			sourceModuleId: "Arithmetic",
			sourceTypeName: "Arithmetic",
			sourceFieldName: "increment",
			kind: OcamlCallKind.DirectStaticHaxeMethod,
			arguments: [value(0)],
			result: value(-1),
			evaluationSchedule: ["evaluate-argument:0", "invoke-callee"],
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

	static function copyCall(source:OcamlCallDecision, ?calleeId:String, ?kind:OcamlCallKind, ?arguments:Array<OcamlCallValuePlan>,
			?result:OcamlCallValuePlan, ?bodyRevision:String):OcamlCallDecision {
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
			evaluationSchedule: source.evaluationSchedule.copy(),
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

		expectThrows("duplicate-declaration", () -> registry.registerCallableDeclaration(declaration()));
		expectThrows("duplicate-function-seal", () -> seal(registry, caller, new OcamlCallPlan([]), null));

		final wrongCallee = copyCall(selectedCall, "Missing|Missing::increment");
		expectThrows("missing-declaration", () -> registry.requireCallableDeclaration(wrongCallee));

		final wrongKind = copyCall(selectedCall, null, cast "dynamic-call");
		expectThrows("invalid-plan", () -> registry.requireCallableDeclaration(wrongKind));

		final wrongArity = copyCall(selectedCall, null, null, [value(0), value(1)]);
		expectThrows("invalid-plan", () -> registry.requireCallableDeclaration(wrongArity));

		final wrongSemanticType = copyCall(selectedCall, null, null, [
			{
				index: 0,
				semanticTypeId: "Float",
				carrierTypeId: "int",
				representationId: "representation:Int:internal-value",
				conversion: OcamlCallCarrierConversion.Identity
			}
		]);
		expectThrows("invalid-plan", () -> registry.requireCallableDeclaration(wrongSemanticType));

		final wrongCarrier = copyCall(selectedCall, null, null, [
			{
				index: 0,
				semanticTypeId: "Int",
				carrierTypeId: "Obj.t",
				representationId: "representation:Int:internal-value",
				conversion: OcamlCallCarrierConversion.Identity
			}
		]);
		expectThrows("invalid-plan", () -> registry.requireCallableDeclaration(wrongCarrier));

		final wrongConversion = copyCall(selectedCall, null, null, [
			{
				index: 0,
				semanticTypeId: "Int",
				carrierTypeId: "int",
				representationId: "representation:Int:internal-value",
				conversion: cast "box"
			}
		]);
		expectThrows("invalid-plan", () -> registry.requireCallableDeclaration(wrongConversion));

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
