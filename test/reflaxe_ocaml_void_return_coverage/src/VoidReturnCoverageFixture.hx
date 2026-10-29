import haxe.macro.Expr;
import reflaxe.ocaml.lowered.OcamlControlAdmission.OcamlControlAdmissionContract;
import reflaxe.ocaml.lowered.OcamlControlAdmission.OcamlControlAdmissionFamily;
import reflaxe.ocaml.lowered.OcamlControlAdmission.OcamlControlAdmissionSnapshot;
import reflaxe.ocaml.lowered.OcamlControlPlan;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlDecision;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlEffect;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlRuntimeTagPolicy;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlTargetKind;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlTargetMechanism;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlTransferKind;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlFunctionResultBoundary.OcamlFunctionResultBoundaryPlan;
import reflaxe.ocaml.lowered.OcamlLoweringReportWriter;

/**
	Checks how the lowering-report writer accounts for early `return;` in a `Void` function.

	Why: the report writer refuses to publish a function whose control admission
	says "this body has N admitted returns" unless each of those returns is
	explained. A value-returning function explains them with a separate
	function-result record. A `Void` function has no result value, so each
	payloadless `return;` must explain itself: it must be a complete
	"runtime Void return signal" decision owned by that exact function.

	What this fixture proves, without compiling a whole program:
	- one valid payloadless return covers its function's admitted return family;
	- a missing, foreign, or surplus return still fails the coverage check;
	- a corrupted payloadless record is rejected before it can count as coverage.

	How: it builds plain control decisions and admission snapshots with the same
	public constructors the planner uses, then calls the writer's coverage step.
**/
@:access(reflaxe.ocaml.lowered.OcamlLoweringReportWriter)
class VoidReturnCoverageFixture {
	static inline final FUNCTION_ID = "fixture.Main|Main|static|function|stop|0";
	static inline final OTHER_FUNCTION_ID = "fixture.Main|Main|static|function|other|0";
	static inline final MISSING_COVERAGE = "admits return transfers without a function result boundary";
	static inline final INVALID_PLAN = "ocaml-control:invalid-plan";

	static function binding(functionId:String):OcamlFunctionPlanBinding {
		return {
			functionId: functionId,
			programRevision: "program:void-coverage-fixture",
			bodyRevision: "body:void-coverage-fixture",
			pipelineRevision: "typed-ocaml-function-plan-v33"
		};
	}

	/** Creates an admission whose return family admits `returns` payloadless returns. */
	static function admission(functionId:String, returns:Int):OcamlControlAdmissionSnapshot {
		return OcamlControlAdmissionContract.create(binding(functionId), [
			OcamlControlAdmissionContract.family(OcamlControlAdmissionFamily.Return, returns, returns, true, []),
			OcamlControlAdmissionContract.family(OcamlControlAdmissionFamily.Loop, 0, 0, false, []),
			OcamlControlAdmissionContract.family(OcamlControlAdmissionFamily.Throw, 0, 0, false, [])
		], []);
	}

	/**
		Returns a payloadless return decision owned by `functionId`.

		Without `change`, the decision is valid. Each `change` field replaces one
		sealed fact so a test can corrupt exactly one part of the record.
	**/
	static function voidReturn(id:String, ?functionId:String, ?change:VoidReturnChange):OcamlControlDecision {
		final owner = functionId ?? FUNCTION_ID;
		final edit:VoidReturnChange = change ?? {};
		return {
			id: id,
			source: {file: "test/fixture/Main.hx", min: 10, max: 17},
			kind: OcamlControlTransferKind.Return,
			effect: edit.effect ?? OcamlControlEffect.ExitFunction,
			targetKind: OcamlControlTargetKind.Function,
			targetId: edit.targetId ?? owner,
			payload: null,
			runtimeTags: [],
			runtimeTagPolicy: OcamlControlRuntimeTagPolicy.NoRuntimeTags,
			mechanism: edit.mechanism ?? OcamlControlTargetMechanism.RuntimeVoidReturnSignal,
			runtimeCapabilityId: edit.runtimeCapabilityId ?? OcamlControlPlan.VOID_RETURN_SIGNAL_CAPABILITY_ID,
			profileEligibility: ["metal", "portable"],
			reason: "fixture payloadless return exits its owning Void function",
			proofId: edit.proofId ?? OcamlControlPlan.EFFECT_ONLY_VOID_RETURN_PROOF_ID,
			proofClaim: "fixture effect-only Void early-return crossing",
			functionId: owner,
			programRevision: "program:void-coverage-fixture",
			bodyRevision: edit.bodyRevision ?? "body:void-coverage-fixture",
			pipelineRevision: "typed-ocaml-function-plan-v33"
		};
	}

	static function check(admissions:Array<OcamlControlAdmissionSnapshot>, controls:Array<OcamlControlDecision>):Void {
		final noFunctionResults:Map<String, OcamlFunctionResultBoundaryPlan> = [];
		OcamlLoweringReportWriter.requireReturnCoverage(admissions, controls, noFunctionResults);
	}

	static function expectRejected(label:String, marker:String, admissions:Array<OcamlControlAdmissionSnapshot>, controls:Array<OcamlControlDecision>):Void {
		var message:Null<String> = null;
		try {
			check(admissions, controls);
		} catch (error:String) {
			message = error;
		}
		if (message == null)
			throw 'Void return coverage accepted $label';
		if (message.indexOf(marker) < 0)
			throw 'Void return coverage rejected $label for the wrong reason: $message';
	}

	public static macro function run():Expr {
		final oneReturn = [admission(FUNCTION_ID, 1)];

		// Valid: one sealed payloadless return explains the one admitted return.
		check(oneReturn, [voidReturn("control:return:void")]);
		check([admission(FUNCTION_ID, 2)], [voidReturn("control:return:void:a"), voidReturn("control:return:void:b")]);

		// Missing coverage: the admission still names returns that no decision explains.
		expectRejected("an admitted return with no decision", MISSING_COVERAGE, oneReturn, []);
		expectRejected("a return owned by another function", MISSING_COVERAGE, oneReturn, [voidReturn("control:return:other", OTHER_FUNCTION_ID)]);
		expectRejected("more Void returns than the admission names", MISSING_COVERAGE, oneReturn,
			[voidReturn("control:return:void:a"), voidReturn("control:return:void:b")]);
		expectRejected("a payloadless return that uses the value-return signal", MISSING_COVERAGE, oneReturn, [
			voidReturn("control:return:value-mechanism", null, {
				mechanism: OcamlControlTargetMechanism.RuntimeReturnSignal,
				runtimeCapabilityId: OcamlControlPlan.RETURN_SIGNAL_CAPABILITY_ID
			})
		]);

		// Corrupted Void records: each keeps the Void mechanism, so only validation stops it from counting.
		expectRejected("a Void return with a value-return proof", INVALID_PLAN, oneReturn, [
			voidReturn("control:return:wrong-proof", null, {proofId: OcamlControlPlan.EXACT_VALUE_RETURN_PROOF_ID})
		]);
		expectRejected("a Void return with the value-return runtime capability", INVALID_PLAN, oneReturn, [
			voidReturn("control:return:wrong-capability", null, {runtimeCapabilityId: OcamlControlPlan.RETURN_SIGNAL_CAPABILITY_ID})
		]);
		expectRejected("a Void return that exits another function", INVALID_PLAN, oneReturn,
			[voidReturn("control:return:wrong-target", null, {targetId: OTHER_FUNCTION_ID})]);
		expectRejected("a Void return with a loop-exit effect", INVALID_PLAN, oneReturn, [
			voidReturn("control:return:wrong-effect", null, {effect: OcamlControlEffect.ExitLoop})
		]);
		expectRejected("a Void return without a body revision", INVALID_PLAN, oneReturn,
			[voidReturn("control:return:missing-revision", null, {bodyRevision: ""})]);

		Sys.println("REFLAXE_OCAML_VOID_RETURN_COVERAGE:PASS");
		return macro null;
	}
}

/** One optional replacement per sealed fact of a fixture Void return decision. */
typedef VoidReturnChange = {
	?mechanism:OcamlControlTargetMechanism,
	?runtimeCapabilityId:String,
	?proofId:String,
	?targetId:String,
	?effect:OcamlControlEffect,
	?bodyRevision:String
}
