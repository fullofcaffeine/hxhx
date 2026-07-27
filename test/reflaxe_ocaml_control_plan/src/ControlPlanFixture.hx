import haxe.macro.Expr;
import reflaxe.ocaml.lowered.OcamlControlPlan;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlDecision;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlEffect;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlPayloadConversion;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlTargetMechanism;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlTransferKind;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;

/**
	Checks exact-Int control-plan immutability and fail-closed validation.

	The portable fixture proves behavior from a real typed Haxe program. This
	macro fixture deliberately corrupts individual records so a stale target,
	unsupported payload, duplicate source occurrence, or mismatched body
	revision cannot reach OCaml syntax.
**/
class ControlPlanFixture {
	static inline final FUNCTION_ID = "Main|Main|static|function|value|generics:0|required:Int->Int";

	static function binding(?bodyRevision:String = "body:control-fixture"):OcamlFunctionPlanBinding {
		return {
			functionId: FUNCTION_ID,
			programRevision: "program:control-fixture",
			bodyRevision: bodyRevision,
			pipelineRevision: "typed-ocaml-function-plan-v26"
		};
	}

	static function decision(id:String, min:Int, ?targetFunctionId:String, ?conversion:OcamlControlPayloadConversion,
			?mechanism:OcamlControlTargetMechanism):OcamlControlDecision {
		final target = targetFunctionId ?? FUNCTION_ID;
		final selectedConversion = conversion ?? OcamlControlPayloadConversion.BoxAndRecoverExactInt;
		final selectedMechanism = mechanism ?? OcamlControlTargetMechanism.RuntimeReturnSignal;
		final proof = "fixture exact-Int early-return crossing";
		return {
			id: id,
			source: {
				file: "test/oracle/control/Main.hx",
				min: min,
				max: min + 8
			},
			kind: OcamlControlTransferKind.Return,
			effect: OcamlControlEffect.ExitFunction,
			targetFunctionId: target,
			payload: {
				inputSemanticTypeId: "Int",
				inputCarrierTypeId: "int",
				inputRepresentationId: "representation:Int:internal-value",
				signalCarrierTypeId: "Obj.t",
				outputSemanticTypeId: "Int",
				outputCarrierTypeId: "int",
				outputRepresentationId: "representation:Int:internal-value",
				conversion: selectedConversion,
				proofId: OcamlControlPlan.EXACT_INT_RETURN_PROOF_ID,
				proofClaim: proof
			},
			mechanism: selectedMechanism,
			runtimeCapabilityId: OcamlControlPlan.RETURN_SIGNAL_CAPABILITY_ID,
			profileEligibility: ["metal", "portable"],
			reason: "fixture nested return exits its owning exact-Int function",
			proofId: OcamlControlPlan.EXACT_INT_RETURN_PROOF_ID,
			proofClaim: proof,
			functionId: FUNCTION_ID,
			programRevision: "program:control-fixture",
			bodyRevision: "body:control-fixture",
			pipelineRevision: "typed-ocaml-function-plan-v26"
		};
	}

	static function expectThrows(marker:String, operation:Void->Void):Void {
		try {
			operation();
		} catch (error:Dynamic) {
			final message = Std.string(error);
			if (message.indexOf(marker) < 0)
				throw 'Expected failure containing "$marker", got "$message"';
			return;
		}
		throw 'Expected failure containing "$marker"';
	}

	public static macro function run():Expr {
		final first = decision("control:return:first", 10);
		final second = decision("control:return:second", 30);
		final forward = new OcamlControlPlan(true, binding(), [first, second]);
		final reverse = new OcamlControlPlan(true, binding(), [second, first]);
		if (forward.revision != reverse.revision)
			throw "Control-plan revision changed with input ordering";
		if (!forward.admittedFunction || !forward.hasReturnTransfers() || forward.decisions().length != 2)
			throw "Admitted control plan lost its sealed transfers";
		if (forward.returnBoundaryDecision() == null)
			throw "Admitted control plan lost its return boundary";

		final copied = forward.decisions();
		copied[0].profileEligibility.push("corrupted");
		if (forward.decisions()[0].profileEligibility.length != 2)
			throw "Control decisions leaked mutable profile arrays";

		final empty = new OcamlControlPlan(true, binding(), []);
		if (!empty.admittedFunction || empty.hasReturnTransfers() || empty.returnBoundaryDecision() != null)
			throw "An admitted straight-line function did not remain explicit and empty";
		final legacy = OcamlControlPlan.notAdmitted(binding());
		if (legacy.admittedFunction || legacy.hasReturnTransfers())
			throw "A legacy function became control-plan admitted";

		final missingId = decision("", 50);
		expectThrows("invalid-plan", () -> new OcamlControlPlan(true, binding(), [missingId]));

		final staleTarget = decision("control:return:stale-target", 60, "Other|Other::value");
		expectThrows("stale-binding", () -> new OcamlControlPlan(true, binding(), [staleTarget]));

		final badConversion = decision("control:return:bad-conversion", 70, null, cast "identity");
		expectThrows("invalid-plan", () -> new OcamlControlPlan(true, binding(), [badConversion]));

		final badMechanism = decision("control:return:bad-mechanism", 80, null, null, cast "catch-all");
		expectThrows("invalid-plan", () -> new OcamlControlPlan(true, binding(), [badMechanism]));

		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, binding(), [first]));
		expectThrows("duplicate-decision", () -> new OcamlControlPlan(true, binding(), [first, first]));

		final sameSource = decision("control:return:same-source", 10);
		expectThrows("duplicate-source-occurrence", () -> new OcamlControlPlan(true, binding(), [first, sameSource]));

		expectThrows("stale-plan", () -> forward.requirePlanBinding(binding("body:other")));

		Sys.println("REFLAXE_OCAML_CONTROL_PLAN_FIXTURE:PASS");
		return macro null;
	}
}
