import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.macro.Type.TypedExpr;
import haxe.macro.TypedExprTools;
import reflaxe.ocaml.lowered.OcamlControlPlan;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlDecision;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlEffect;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlLoopKind;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlLoopTarget;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlPayloadPlan;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlPayloadConversion;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlRuntimeTagPolicy;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlTargetKind;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlTargetMechanism;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlTransferKind;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;

/**
	Checks control-family independence, immutability, and fail-closed validation.

	The portable fixture proves behavior from a real typed Haxe program. This
	macro fixture deliberately corrupts return payloads, loop targets, and
	transfer records so an invalid family combination or stale body revision
	cannot reach OCaml syntax.
**/
class ControlPlanFixture {
	static inline final FUNCTION_ID = "Main|Main|static|function|value|generics:0|required:Int->Int";

	static function binding(?bodyRevision:String = "body:control-fixture"):OcamlFunctionPlanBinding {
		return {
			functionId: FUNCTION_ID,
			programRevision: "program:control-fixture",
			bodyRevision: bodyRevision,
			pipelineRevision: "typed-ocaml-function-plan-v30"
		};
	}

	static function returnDecision(id:String, min:Int, ?targetId:String, ?conversion:OcamlControlPayloadConversion, ?mechanism:OcamlControlTargetMechanism,
			?semanticTypeId:String, ?outputSemanticTypeId:String):OcamlControlDecision {
		final target = targetId ?? FUNCTION_ID;
		final selectedConversion = conversion ?? OcamlControlPayloadConversion.BoxAndRecoverExactValue;
		final selectedMechanism = mechanism ?? OcamlControlTargetMechanism.RuntimeReturnSignal;
		final semanticType = semanticTypeId ?? "Int";
		final outputSemanticType = outputSemanticTypeId ?? semanticType;
		final carrierType = switch (semanticType) {
			case "Int": "int";
			case "Bool": "bool";
			case "String": "string";
			case _: "unsupported";
		}
		final outputCarrierType = switch (outputSemanticType) {
			case "Int": "int";
			case "Bool": "bool";
			case "String": "string";
			case _: "unsupported";
		}
		final representationId = 'representation:$semanticType:internal-value';
		final outputRepresentationId = 'representation:$outputSemanticType:internal-value';
		final proof = 'fixture exact-$semanticType early-return crossing';
		return {
			id: id,
			source: {
				file: "test/oracle/control/Main.hx",
				min: min,
				max: min + 8
			},
			kind: OcamlControlTransferKind.Return,
			effect: OcamlControlEffect.ExitFunction,
			targetKind: OcamlControlTargetKind.Function,
			targetId: target,
			payload: {
				inputSemanticTypeId: semanticType,
				inputCarrierTypeId: carrierType,
				inputRepresentationId: representationId,
				signalCarrierTypeId: "Obj.t",
				outputSemanticTypeId: outputSemanticType,
				outputCarrierTypeId: outputCarrierType,
				outputRepresentationId: outputRepresentationId,
				conversion: selectedConversion,
				proofId: OcamlControlPlan.EXACT_VALUE_RETURN_PROOF_ID,
				proofClaim: proof
			},
			runtimeTags: [],
			runtimeTagPolicy: OcamlControlRuntimeTagPolicy.NoRuntimeTags,
			mechanism: selectedMechanism,
			runtimeCapabilityId: OcamlControlPlan.RETURN_SIGNAL_CAPABILITY_ID,
			profileEligibility: ["metal", "portable"],
			reason: 'fixture nested return exits its owning exact-$semanticType function',
			proofId: OcamlControlPlan.EXACT_VALUE_RETURN_PROOF_ID,
			proofClaim: proof,
			functionId: FUNCTION_ID,
			programRevision: "program:control-fixture",
			bodyRevision: "body:control-fixture",
			pipelineRevision: "typed-ocaml-function-plan-v30"
		};
	}

	static function loopTarget(id:String, min:Int, ?kind:OcamlControlLoopKind, ?bodyRevision:String):OcamlControlLoopTarget {
		return {
			id: id,
			source: {
				file: "test/oracle/control/Main.hx",
				min: min,
				max: min + 20
			},
			kind: kind ?? OcamlControlLoopKind.While,
			functionId: FUNCTION_ID,
			programRevision: "program:control-fixture",
			bodyRevision: bodyRevision ?? "body:control-fixture",
			pipelineRevision: "typed-ocaml-function-plan-v30",
			proofId: OcamlControlPlan.LEXICAL_LOOP_CONTROL_PROOF_ID,
			proofClaim: "fixture lexical loop target"
		};
	}

	static function loopDecision(id:String, min:Int, targetId:String, kind:OcamlControlTransferKind, ?targetKind:OcamlControlTargetKind,
			?payload:OcamlControlPayloadPlan):OcamlControlDecision {
		final isBreak = kind == OcamlControlTransferKind.Break;
		return {
			id: id,
			source: {
				file: "test/oracle/control/Main.hx",
				min: min,
				max: min + 8
			},
			kind: kind,
			effect: isBreak ? OcamlControlEffect.ExitLoop : OcamlControlEffect.NextLoopIteration,
			targetKind: targetKind ?? OcamlControlTargetKind.Loop,
			targetId: targetId,
			payload: payload,
			runtimeTags: [],
			runtimeTagPolicy: OcamlControlRuntimeTagPolicy.NoRuntimeTags,
			mechanism: isBreak ? OcamlControlTargetMechanism.RuntimeBreakSignal : OcamlControlTargetMechanism.RuntimeContinueSignal,
			runtimeCapabilityId: isBreak ? OcamlControlPlan.BREAK_SIGNAL_CAPABILITY_ID : OcamlControlPlan.CONTINUE_SIGNAL_CAPABILITY_ID,
			profileEligibility: ["metal", "portable"],
			reason: "fixture lexical loop transfer",
			proofId: OcamlControlPlan.LEXICAL_LOOP_CONTROL_PROOF_ID,
			proofClaim: "fixture lexical loop transfer",
			functionId: FUNCTION_ID,
			programRevision: "program:control-fixture",
			bodyRevision: "body:control-fixture",
			pipelineRevision: "typed-ocaml-function-plan-v30"
		};
	}

	static function throwDecision(id:String, min:Int, semanticTypeId:String, ?conversion:OcamlControlPayloadConversion, ?runtimeTags:Array<String>,
			?targetId:String, ?targetKind:OcamlControlTargetKind, ?mechanism:OcamlControlTargetMechanism, ?outputSemanticTypeId:String,
			?runtimeTagPolicy:OcamlControlRuntimeTagPolicy):OcamlControlDecision {
		final carrierTypeId = switch (semanticTypeId) {
			case "Int": "int";
			case "Bool": "bool";
			case "String": "string";
			case _: "unsupported";
		};
		final outputSemanticType = outputSemanticTypeId ?? semanticTypeId;
		final outputCarrierTypeId = switch (outputSemanticType) {
			case "Int": "int";
			case "Bool": "bool";
			case "String": "string";
			case _: "unsupported";
		};
		var selectedConversion = conversion ?? OcamlControlPlan.expectedThrowConversion(semanticTypeId);
		if (selectedConversion == null)
			selectedConversion = cast "unsupported";
		final proof = 'fixture exact-$semanticTypeId Haxe exception crossing';
		return {
			id: id,
			source: {
				file: "test/oracle/control/Main.hx",
				min: min,
				max: min + 8
			},
			kind: OcamlControlTransferKind.Throw,
			effect: OcamlControlEffect.RaiseHaxeValue,
			targetKind: targetKind ?? OcamlControlTargetKind.HaxeExceptionChannel,
			targetId: targetId ?? OcamlControlPlan.HAXE_EXCEPTION_CHANNEL_ID,
			payload: {
				inputSemanticTypeId: semanticTypeId,
				inputCarrierTypeId: carrierTypeId,
				inputRepresentationId: 'representation:$semanticTypeId:internal-value',
				signalCarrierTypeId: "Obj.t",
				outputSemanticTypeId: outputSemanticType,
				outputCarrierTypeId: outputCarrierTypeId,
				outputRepresentationId: 'representation:$outputSemanticType:internal-value',
				conversion: selectedConversion,
				proofId: OcamlControlPlan.EXACT_VALUE_THROW_PROOF_ID,
				proofClaim: proof
			},
			runtimeTags: runtimeTags ?? OcamlControlPlan.expectedThrowTags(semanticTypeId),
			runtimeTagPolicy: runtimeTagPolicy ?? OcamlControlRuntimeTagPolicy.MergeDynamicWithExactRuntimeValue,
			mechanism: mechanism ?? OcamlControlTargetMechanism.RuntimeTypedHaxeExceptionSignal,
			runtimeCapabilityId: OcamlControlPlan.THROW_SIGNAL_CAPABILITY_ID,
			profileEligibility: ["metal", "portable"],
			reason: 'fixture exact-$semanticTypeId value enters the Haxe exception channel',
			proofId: OcamlControlPlan.EXACT_VALUE_THROW_PROOF_ID,
			proofClaim: proof,
			functionId: FUNCTION_ID,
			programRevision: "program:control-fixture",
			bodyRevision: "body:control-fixture",
			pipelineRevision: "typed-ocaml-function-plan-v30"
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
		final first = returnDecision("control:return:first", 10);
		final second = returnDecision("control:return:second", 30);
		final loop = loopTarget("control-target:loop:first", 100);
		final loopBreak = loopDecision("control:break:first", 110, loop.id, OcamlControlTransferKind.Break);
		final loopContinue = loopDecision("control:continue:first", 120, loop.id, OcamlControlTransferKind.Continue);
		final forward = new OcamlControlPlan(true, true, false, binding(), [loop], [first, second, loopBreak, loopContinue]);
		final reverse = new OcamlControlPlan(true, true, false, binding(), [loop], [loopContinue, second, loopBreak, first]);
		if (forward.revision != reverse.revision)
			throw "Control-plan revision changed with input ordering";
		if (!forward.returnFamilyAdmitted
			|| !forward.loopFamilyAdmitted
			|| forward.throwFamilyAdmitted
			|| !forward.hasReturnTransfers()
			|| !forward.hasTransfersForTarget(loop.id)
			|| forward.loopTargets().length != 1
			|| forward.decisions().length != 4) {
			throw "Admitted control plan lost its sealed transfers";
		}
		if (forward.returnBoundaryDecision() == null)
			throw "Admitted control plan lost its return boundary";

		final copied = forward.decisions();
		copied[0].profileEligibility.push("corrupted");
		if (forward.decisions()[0].profileEligibility.length != 2)
			throw "Control decisions leaked mutable profile arrays";

		final empty = new OcamlControlPlan(true, true, true, binding(), [], []);
		if (!empty.returnFamilyAdmitted || !empty.loopFamilyAdmitted || !empty.throwFamilyAdmitted || empty.hasReturnTransfers()
			|| empty.returnBoundaryDecision() != null)
			throw "An admitted straight-line function did not retain independent empty families";
		final loopOnly = new OcamlControlPlan(false, true, false, binding(), [loop], [loopBreak, loopContinue]);
		if (loopOnly.returnFamilyAdmitted
			|| !loopOnly.loopFamilyAdmitted
			|| loopOnly.throwFamilyAdmitted
			|| loopOnly.hasReturnTransfers())
			throw "Loop-family admission accidentally claimed the return family";
		final returnOnly = new OcamlControlPlan(true, false, false, binding(), [], [first, second]);
		if (!returnOnly.returnFamilyAdmitted || returnOnly.loopFamilyAdmitted || returnOnly.throwFamilyAdmitted || !returnOnly.hasReturnTransfers())
			throw "Return-family admission accidentally claimed the loop family";
		final intThrow = throwDecision("control:throw:int", 170, "Int");
		final throwOnly = new OcamlControlPlan(false, false, true, binding(), [], [intThrow]);
		if (throwOnly.returnFamilyAdmitted || throwOnly.loopFamilyAdmitted || !throwOnly.throwFamilyAdmitted || throwOnly.hasReturnTransfers()
			|| throwOnly.decisions().length != 1) {
			throw "Throw-family admission accidentally claimed or discarded another control family";
		}
		final legacy = OcamlControlPlan.notAdmitted(binding());
		if (legacy.returnFamilyAdmitted || legacy.loopFamilyAdmitted || legacy.throwFamilyAdmitted || legacy.hasReturnTransfers())
			throw "A legacy function became control-plan admitted";

		OcamlControlPlan.requireDecision(returnDecision("control:return:bool", 40, null, null, null, "Bool"));
		OcamlControlPlan.requireDecision(returnDecision("control:return:string", 45, null, null, null, "String"));
		OcamlControlPlan.requireDecision(loopBreak);
		OcamlControlPlan.requireDecision(loopContinue);
		OcamlControlPlan.requireDecision(intThrow);
		OcamlControlPlan.requireDecision(throwDecision("control:throw:bool", 180, "Bool"));
		OcamlControlPlan.requireDecision(throwDecision("control:throw:string", 190, "String"));
		OcamlControlPlan.requireLoopTarget(loop);

		final missingId = returnDecision("", 50);
		expectThrows("invalid-plan", () -> new OcamlControlPlan(true, false, false, binding(), [], [missingId]));

		final staleReturnTarget = returnDecision("control:return:stale-target", 60, "Other|Other::value");
		expectThrows("invalid-plan", () -> new OcamlControlPlan(true, false, false, binding(), [], [staleReturnTarget]));

		final badConversion = returnDecision("control:return:bad-conversion", 70, null, cast "identity");
		expectThrows("invalid-plan", () -> new OcamlControlPlan(true, false, false, binding(), [], [badConversion]));

		final badMechanism = returnDecision("control:return:bad-mechanism", 80, null, null, cast "catch-all");
		expectThrows("invalid-plan", () -> new OcamlControlPlan(true, false, false, binding(), [], [badMechanism]));

		final unsupportedPayload = returnDecision("control:return:unsupported-payload", 85, null, null, null, "Float");
		expectThrows("invalid-plan", () -> new OcamlControlPlan(true, false, false, binding(), [], [unsupportedPayload]));

		final mismatchedPayload = returnDecision("control:return:mismatched-payload", 87, null, null, null, "Int", "Bool");
		expectThrows("invalid-plan", () -> new OcamlControlPlan(true, false, false, binding(), [], [mismatchedPayload]));

		final badThrowConversion = throwDecision("control:throw:bad-conversion", 200, "Int", cast "identity");
		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, false, true, binding(), [], [badThrowConversion]));
		final badThrowTags = throwDecision("control:throw:bad-tags", 210, "Int", null, ["Int"]);
		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, false, true, binding(), [], [badThrowTags]));
		final badThrowTagPolicy = throwDecision("control:throw:bad-tag-policy", 215, "Int", null, null, null, null, null, null,
			OcamlControlRuntimeTagPolicy.NoRuntimeTags);
		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, false, true, binding(), [], [badThrowTagPolicy]));
		final badThrowTarget = throwDecision("control:throw:bad-target", 220, "Int", null, null, FUNCTION_ID, OcamlControlTargetKind.Function);
		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, false, true, binding(), [], [badThrowTarget]));
		final badThrowMechanism = throwDecision("control:throw:bad-mechanism", 230, "Int", null, null, null, null, cast "catch-all");
		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, false, true, binding(), [], [badThrowMechanism]));
		final unsupportedThrow = throwDecision("control:throw:unsupported", 240, "Float");
		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, false, true, binding(), [], [unsupportedThrow]));
		final mismatchedThrow = throwDecision("control:throw:mismatched", 250, "Int", null, null, null, null, null, "Bool");
		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, false, true, binding(), [], [mismatchedThrow]));
		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, false, false, binding(), [], [intThrow]));

		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, true, false, binding(), [loop], [first, loopBreak]));
		expectThrows("duplicate-decision", () -> new OcamlControlPlan(true, false, false, binding(), [], [first, first]));

		final sameSource = returnDecision("control:return:same-source", 10);
		expectThrows("duplicate-source-occurrence", () -> new OcamlControlPlan(true, false, false, binding(), [], [first, sameSource]));

		final typedLoop = Context.typeExpr(macro {
			while (true) {
				if (true)
					break;
				break;
			}
		});
		final typedLoops:Array<TypedExpr> = [];
		final typedBreaks:Array<TypedExpr> = [];
		function collectControlNodes(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TWhile(_, _, _):
					typedLoops.push(expression);
				case TBreak:
					typedBreaks.push(expression);
				case _:
			}
			TypedExprTools.iter(expression, collectControlNodes);
		}
		collectControlNodes(typedLoop);
		if (typedLoops.length != 1 || typedBreaks.length != 2)
			throw "The same-span occurrence fixture did not produce one loop and two break nodes";
		final sameSourceBreakA = loopDecision("control:break:same-source:a", 110, loop.id, OcamlControlTransferKind.Break);
		final sameSourceBreakB = loopDecision("control:break:same-source:b", 110, loop.id, OcamlControlTransferKind.Break);
		final indexedSameSource = new OcamlControlPlan(false, true, false, binding(), [loop], [sameSourceBreakA, sameSourceBreakB],
			[{expression: typedLoops[0], targetId: loop.id}], [
			{expression: typedBreaks[0], decisionId: sameSourceBreakA.id},
			{expression: typedBreaks[1], decisionId: sameSourceBreakB.id}
		]);
		if (indexedSameSource.decisionFor(typedBreaks[0])?.id != sameSourceBreakA.id
			|| indexedSameSource.decisionFor(typedBreaks[1])?.id != sameSourceBreakB.id) {
			throw "The typed occurrence index collapsed distinct same-span break nodes";
		}
		expectThrows("incomplete-occurrence-index",
			() -> new OcamlControlPlan(false, true, false, binding(), [loop], [sameSourceBreakA], [{expression: typedLoops[0], targetId: loop.id}], null));
		expectThrows("missing-target-occurrence",
			() -> new OcamlControlPlan(false, true, false, binding(), [loop], [sameSourceBreakA], [],
				[{expression: typedBreaks[0], decisionId: sameSourceBreakA.id}]));
		expectThrows("missing-decision-occurrence",
			() -> new OcamlControlPlan(false, true, false, binding(), [loop], [sameSourceBreakA], [{expression: typedLoops[0], targetId: loop.id}], []));
		expectThrows("duplicate-target-occurrence", () -> new OcamlControlPlan(false, true, false, binding(), [loop], [sameSourceBreakA], [
			{expression: typedLoops[0], targetId: loop.id},
			{expression: typedLoops[0], targetId: loop.id}
		], [{expression: typedBreaks[0], decisionId: sameSourceBreakA.id}]));
		expectThrows("duplicate-decision-occurrence",
			() -> new OcamlControlPlan(false, true, false, binding(), [loop], [sameSourceBreakA], [{expression: typedLoops[0], targetId: loop.id}], [
				{expression: typedBreaks[0], decisionId: sameSourceBreakA.id},
				{expression: typedBreaks[0], decisionId: sameSourceBreakA.id}
			]));
		expectThrows("ambiguous-decision-occurrence",
			() -> new OcamlControlPlan(false, true, false, binding(), [loop], [sameSourceBreakA, sameSourceBreakB],
				[{expression: typedLoops[0], targetId: loop.id}], [
				{expression: typedBreaks[0], decisionId: sameSourceBreakA.id},
				{expression: typedBreaks[0], decisionId: sameSourceBreakB.id}
			]));

		final typedThrowsRoot = Context.typeExpr(macro {
			if (true)
				throw 1;
			throw 2;
		});
		final typedThrows:Array<TypedExpr> = [];
		function collectThrowNodes(expression:TypedExpr):Void {
			switch (expression.expr) {
				case TThrow(_):
					typedThrows.push(expression);
				case _:
			}
			TypedExprTools.iter(expression, collectThrowNodes);
		}
		collectThrowNodes(typedThrowsRoot);
		if (typedThrows.length != 2)
			throw "The exact throw occurrence fixture did not produce two throw nodes";
		final sameSourceThrowA = throwDecision("control:throw:same-source:a", 260, "Int");
		final sameSourceThrowB = throwDecision("control:throw:same-source:b", 260, "Int");
		final indexedThrows = new OcamlControlPlan(false, false, true, binding(), [], [sameSourceThrowA, sameSourceThrowB], [], [
			{expression: typedThrows[0], decisionId: sameSourceThrowA.id},
			{expression: typedThrows[1], decisionId: sameSourceThrowB.id}
		]);
		if (indexedThrows.decisionFor(typedThrows[0])?.id != sameSourceThrowA.id
			|| indexedThrows.decisionFor(typedThrows[1])?.id != sameSourceThrowB.id) {
			throw "The typed occurrence index collapsed distinct same-span throw nodes";
		}

		expectThrows("missing-target", () -> new OcamlControlPlan(false, true, false, binding(), [], [loopBreak]));
		final wrongTargetKind = loopDecision("control:break:wrong-kind", 130, loop.id, OcamlControlTransferKind.Break, OcamlControlTargetKind.Function);
		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, true, false, binding(), [loop], [wrongTargetKind]));
		final payloadBearingLoop = loopDecision("control:break:payload", 140, loop.id, OcamlControlTransferKind.Break, null, first.payload);
		expectThrows("invalid-plan", () -> new OcamlControlPlan(false, true, false, binding(), [loop], [payloadBearingLoop]));
		final staleLoop = loopTarget("control-target:loop:stale", 150, null, "body:other");
		expectThrows("stale-target", () -> new OcamlControlPlan(false, true, false, binding(), [staleLoop], []));
		final duplicateLoop = loopTarget(loop.id, 160);
		expectThrows("duplicate-target", () -> new OcamlControlPlan(false, true, false, binding(), [loop, duplicateLoop], []));
		final sameLoopSource = loopTarget("control-target:loop:same-source", 100);
		expectThrows("duplicate-target-source", () -> new OcamlControlPlan(false, true, false, binding(), [loop, sameLoopSource], []));

		expectThrows("stale-plan", () -> forward.requirePlanBinding(binding("body:other")));

		Sys.println("REFLAXE_OCAML_CONTROL_PLAN_FIXTURE:PASS");
		return macro null;
	}
}
