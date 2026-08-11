package;

import haxe.macro.Expr;
import reflaxe.ocaml.ast.OcamlConst;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.lowered.OcamlControlPlan;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlDecision;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlEffect;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlPayloadConversion;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlRuntimeTagPolicy;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlTargetKind;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlTargetMechanism;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlTransferKind;
import reflaxe.ocaml.lowered.OcamlEnumDynamicCarrier;
import reflaxe.ocaml.lowered.OcamlThrowRuntimeUseModel.OcamlThrowRuntimeUseContract;
import reflaxe.ocaml.lowered.OcamlThrowRuntimeUseModel.OcamlThrowRuntimeUsePlan;
import reflaxe.ocaml.runtimegen.OcamlFinalRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementModel.OcamlRuntimeRequirement;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

using StringTools;

/**
	Checks the private OCaml calls that carry one sealed Haxe `throw`.

	For example, a Boolean throw first boxes the value, then raises the private
	exception signal. The control plan already chooses that conversion and its
	runtime tags. This fixture proves that only the exact decision can print each
	helper in that order, and that packaging receives every required module.
**/
class ThrowRuntimeUseFixture {
	static inline final PROFILE = "portable";

	public static macro function run():Expr {
		final decision = intThrowDecision();
		final plan = OcamlThrowRuntimeUseContract.forDecision(decision);
		OcamlThrowRuntimeUseContract.requireForDecision(decision, plan);
		final occurrence = OcamlThrowRuntimeUseContract.signalOccurrence(plan);
		if (occurrence.ownerId != decision.id
			|| occurrence.exactSymbol != "HxType.hx_throw_typed_rtti"
			|| occurrence.source.min != decision.source.min)
			throw "A sealed throw did not retain its exact private runtime occurrence.";

		proveRequirement(decision, plan);
		proveDecisionFailures(decision, plan, occurrence);
		proveAuthorityFailures(decision, plan, occurrence);
		proveFinalOutput(decision, plan, occurrence);
		provePayloadHelperSchedules();
		Sys.println("REFLAXE_OCAML_THROW_RUNTIME_USE:PASS");
		return macro null;
	}

	static function provePayloadHelperSchedules():Void {
		final boolDecision = throwDecision("control:throw:bool", "Bool", "bool", "representation:Bool:internal-value",
			OcamlControlPayloadConversion.BoxBoolAndRecoverExactValue, OcamlControlPlan.EXACT_VALUE_THROW_PROOF_ID, false);
		proveSymbols(boolDecision, ["HxType.hx_throw_typed_rtti", "HxRuntime.box_bool"], ["HxRuntime", "HxType"]);
		final nullableBoolDecision = throwDecision("control:throw:nullable-bool", "Null<Bool>", "Obj.t", "representation:Null<Bool>:internal-value",
			OcamlControlPayloadConversion.NormalizeNullableBoolThrowCarrier, OcamlControlPlan.NULLABLE_BOOL_THROW_PROOF_ID, false);
		proveSymbols(nullableBoolDecision, [
			"HxType.hx_throw_typed_rtti",
			"HxRuntime.is_null",
			"HxRuntime.box_bool",
			"HxRuntime.unbox_bool_or_obj"
		], ["HxRuntime", "HxType"]);
		final enumDecision = throwDecision("control:throw:enum", "fixture.Signal", OcamlEnumDynamicCarrier.CARRIER_MODEL + ":fixture.Signal",
			OcamlControlPlan.enumThrowRepresentationId("fixture.Signal"), OcamlControlPayloadConversion.BoxEnumThrowCarrier,
			OcamlControlPlan.EXACT_ENUM_THROW_PROOF_ID, true);
		proveSymbols(enumDecision, ["HxType.hx_throw_typed_rtti", "HxEnum.box_if_needed"], ["HxEnum", "HxType"]);

		final nullablePlan = OcamlThrowRuntimeUseContract.forDecision(nullableBoolDecision);
		final reordered = nullablePlan.runtimeUseOccurrences.copy();
		final previous = reordered[2];
		reordered[2] = reordered[3];
		reordered[3] = previous;
		expectFailure("reordered payload helpers", "reordered",
			() -> OcamlThrowRuntimeUseContract.requireForDecision(nullableBoolDecision, withUses(nullablePlan, reordered)));
		expectFailure("wrong payload helper", "conflicting",
			() -> OcamlThrowRuntimeUseContract.requireForDecision(nullableBoolDecision, withUses(nullablePlan, [
				nullablePlan.runtimeUseOccurrences[0],
				copyUse(nullablePlan.runtimeUseOccurrences[1], null, "HxRuntime.is_not_null"),
				nullablePlan.runtimeUseOccurrences[2],
				nullablePlan.runtimeUseOccurrences[3]
			])));
		provePayloadFinalOutput(boolDecision);
	}

	static function proveSymbols(decision:OcamlControlDecision, expected:Array<String>, expectedRoots:Array<String>):Void {
		final plan = OcamlThrowRuntimeUseContract.forDecision(decision);
		OcamlThrowRuntimeUseContract.requireForDecision(decision, plan);
		final actual = plan.runtimeUseOccurrences.map(occurrence -> occurrence.exactSymbol);
		if (actual.join(",") != expected.join(","))
			throw 'Throw ${decision.id} expected ${expected.join(",")}, received ${actual.join(",")}.';
		for (index in 0...plan.runtimeUseOccurrences.length)
			if (plan.runtimeUseOccurrences[index].order != index)
				throw 'Throw ${decision.id} runtime use ${plan.runtimeUseOccurrences[index].id} has order ${plan.runtimeUseOccurrences[index].order}; expected $index.';
		final requirements = OcamlRuntimeRequirementLedger.requirementsForThrowDecision(decision);
		if (requirements.length != 1 || requirements[0].rootModules.join(",") != expectedRoots.join(","))
			throw 'Throw ${decision.id} expected runtime roots ${expectedRoots.join(",")}, received ${requirements[0].rootModules.join(",")}.';
	}

	static function provePayloadFinalOutput(decision:OcamlControlDecision):Void {
		final plan = OcamlThrowRuntimeUseContract.forDecision(decision);
		final requirements = OcamlRuntimeRequirementLedger.requirementsForThrowDecision(decision);
		final finalOutput = new OcamlFinalRuntimeUseAuthority();
		finalOutput.beginProgram(decision.programRevision, PROFILE);
		final authority = new OcamlRuntimeUseAuthority(plan.planRevision, PROFILE, requirements, plan.runtimeUseOccurrences, finalOutput);
		final signalOccurrence = plan.runtimeUseOccurrences[0];
		final boxOccurrence = plan.runtimeUseOccurrences[1];
		final signal = OcamlExpr.ERuntimeIdent(authority.expressionIdentifier(signalOccurrence.id, signalOccurrence.planRevision,
			signalOccurrence.exactSymbol));
		final box = OcamlExpr.ERuntimeIdent(authority.expressionIdentifier(boxOccurrence.id, boxOccurrence.planRevision, boxOccurrence.exactSymbol));
		final expression = OcamlExpr.EApp(signal, [
			OcamlExpr.EApp(box, [OcamlExpr.EIdent("payload")]),
			OcamlExpr.EList([OcamlExpr.EConst(OcamlConst.CString("Dynamic"))])
		]);
		authority.reconcileExpression(expression);
		finalOutput.observeExpression(expression, "Main::main::bool-throw");
		finalOutput.finishProgram();
	}

	static function intThrowDecision():OcamlControlDecision {
		return throwDecision("control:throw:int", "Int", "int", "representation:Int:internal-value", OcamlControlPayloadConversion.ReprAndRecoverExactValue,
			OcamlControlPlan.EXACT_VALUE_THROW_PROOF_ID, false);
	}

	static function throwDecision(id:String, semanticTypeId:String, carrierTypeId:String, representationId:String, conversion:OcamlControlPayloadConversion,
			proofId:String, directEnum:Bool):OcamlControlDecision {
		return {
			id: id,
			source: {file: "src/Main.hx", min: 12, max: 20},
			kind: OcamlControlTransferKind.Throw,
			effect: OcamlControlEffect.RaiseHaxeValue,
			targetKind: OcamlControlTargetKind.HaxeExceptionChannel,
			targetId: OcamlControlPlan.HAXE_EXCEPTION_CHANNEL_ID,
			payload: {
				inputSemanticTypeId: semanticTypeId,
				inputCarrierTypeId: carrierTypeId,
				inputRepresentationId: representationId,
				signalCarrierTypeId: "Obj.t",
				outputSemanticTypeId: semanticTypeId,
				outputCarrierTypeId: carrierTypeId,
				outputRepresentationId: representationId,
				conversion: conversion,
				proofId: proofId,
				proofClaim: "The fixture carries one checked value through the Haxe exception channel.",
				nominalRepresentation: null
			},
			runtimeTags: OcamlControlPlan.expectedThrowTags(semanticTypeId, false, directEnum, false),
			runtimeTagPolicy: OcamlControlRuntimeTagPolicy.MergeDynamicWithExactRuntimeValue,
			mechanism: OcamlControlTargetMechanism.RuntimeTypedHaxeExceptionSignal,
			runtimeCapabilityId: OcamlControlPlan.THROW_SIGNAL_CAPABILITY_ID,
			profileEligibility: ["metal", "portable"],
			reason: "The typed fixture throws one checked value.",
			proofId: proofId,
			proofClaim: "The final typed fixture fixes one checked throw.",
			functionId: "Main|Main|static|main",
			programRevision: "program:throw-runtime-use",
			bodyRevision: "body:throw-runtime-use",
			pipelineRevision: "typed-ocaml-function-plan-v33"
		};
	}

	static function proveRequirement(decision:OcamlControlDecision, plan:OcamlThrowRuntimeUsePlan):Void {
		final requirements = OcamlRuntimeRequirementLedger.requirementsForThrowDecision(decision);
		if (requirements.length != 1
			|| requirements[0].id != plan.runtimeRequirementIds[0]
			|| requirements[0].rootModules.join(",") != "HxType"
			|| requirements[0].subject.id != "Int")
			throw "A sealed throw did not produce its exact HxType runtime requirement.";
	}

	static function proveDecisionFailures(decision:OcamlControlDecision, plan:OcamlThrowRuntimeUsePlan, occurrence:OcamlRuntimeUseOccurrence):Void {
		expectFailure("missing occurrence", "invalid-runtime-use", () -> OcamlThrowRuntimeUseContract.requireForDecision(decision, withUses(plan, [])));
		expectFailure("duplicate occurrence", "invalid-runtime-use",
			() -> OcamlThrowRuntimeUseContract.requireForDecision(decision, withUses(plan, [occurrence, occurrence])));
		expectFailure("foreign owner", "invalid-runtime-use",
			() -> OcamlThrowRuntimeUseContract.requireForDecision(decision, withUses(plan, [copyUse(occurrence, "control:throw:other")])));
		expectFailure("wrong symbol", "invalid-runtime-use",
			() -> OcamlThrowRuntimeUseContract.requireForDecision(decision, withUses(plan, [copyUse(occurrence, null, "HxType.hx_throw_typed")])));
		expectFailure("wrong domain", "invalid-runtime-use",
			() -> OcamlThrowRuntimeUseContract.requireForDecision(decision,
				withUses(plan, [copyUse(occurrence, null, null, OcamlRuntimeUseDomain.PatternConstructor)])));
		expectFailure("wrong profile", "invalid-runtime-use",
			() -> OcamlThrowRuntimeUseContract.requireForDecision(decision, withUses(plan, [copyUse(occurrence, null, null, null, ["metal"])])));
	}

	static function proveAuthorityFailures(decision:OcamlControlDecision, plan:OcamlThrowRuntimeUsePlan, occurrence:OcamlRuntimeUseOccurrence):Void {
		final requirements = OcamlRuntimeRequirementLedger.requirementsForThrowDecision(decision);
		expectFailure("missing requirement", "has no exact requirement",
			() -> new OcamlRuntimeUseAuthority(plan.planRevision, PROFILE, [],
				plan.runtimeUseOccurrences).expressionIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol));
		expectFailure("stale plan", "stale runtime use",
			() -> new OcamlRuntimeUseAuthority(plan.planRevision, PROFILE, requirements,
				plan.runtimeUseOccurrences).expressionIdentifier(occurrence.id, occurrence.planRevision + ":stale", occurrence.exactSymbol));
		expectFailure("wrong target symbol", "wrong target symbol",
			() -> new OcamlRuntimeUseAuthority(plan.planRevision, PROFILE, requirements,
				plan.runtimeUseOccurrences).expressionIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol + "_wrong"));
		expectFailure("wrong target domain", "wrong target domain",
			() -> new OcamlRuntimeUseAuthority(plan.planRevision, PROFILE, requirements,
				plan.runtimeUseOccurrences).patternIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol));

		final duplicate = new OcamlRuntimeUseAuthority(plan.planRevision, PROFILE, requirements, plan.runtimeUseOccurrences);
		duplicate.expressionIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol);
		expectFailure("duplicate construction", "constructed more than once",
			() -> duplicate.expressionIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol));
	}

	static function proveFinalOutput(decision:OcamlControlDecision, plan:OcamlThrowRuntimeUsePlan, occurrence:OcamlRuntimeUseOccurrence):Void {
		final requirements = OcamlRuntimeRequirementLedger.requirementsForThrowDecision(decision);
		final finalOutput = new OcamlFinalRuntimeUseAuthority();
		finalOutput.beginProgram(decision.programRevision, PROFILE);
		final expression = checkedThrow(plan, occurrence, requirements, finalOutput);
		finalOutput.observeExpression(expression, "Main::main::throw");
		finalOutput.finishProgram();

		final missing = new OcamlFinalRuntimeUseAuthority();
		missing.beginProgram(decision.programRevision, PROFILE);
		checkedThrow(plan, occurrence, requirements, missing);
		expectFailure("missing final output", "missing final runtime use", missing.finishProgram);

		final plain = new OcamlRuntimeUseAuthority(plan.planRevision, PROFILE, requirements, plan.runtimeUseOccurrences);
		expectFailure("plain target call", "plain private runtime reference HxType.hx_throw_typed_rtti",
			() -> plain.reconcileExpression(OcamlExpr.EField(OcamlExpr.EIdent("HxType"), "hx_throw_typed_rtti")));
	}

	static function checkedThrow(plan:OcamlThrowRuntimeUsePlan, occurrence:OcamlRuntimeUseOccurrence, requirements:Array<OcamlRuntimeRequirement>,
			finalOutput:OcamlFinalRuntimeUseAuthority):OcamlExpr {
		final authority = new OcamlRuntimeUseAuthority(plan.planRevision, PROFILE, requirements, plan.runtimeUseOccurrences, finalOutput);
		final target = OcamlExpr.ERuntimeIdent(authority.expressionIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol));
		final expression = OcamlExpr.EApp(target, [
			OcamlExpr.EIdent("payload"),
			OcamlExpr.EList([OcamlExpr.EConst(OcamlConst.CString("Dynamic"))])
		]);
		authority.reconcileExpression(expression);
		return expression;
	}

	static function withUses(plan:OcamlThrowRuntimeUsePlan, uses:Array<OcamlRuntimeUseOccurrence>):OcamlThrowRuntimeUsePlan {
		return {
			decisionId: plan.decisionId,
			planRevision: plan.planRevision,
			runtimeRequirementIds: plan.runtimeRequirementIds.copy(),
			runtimeUseOccurrences: uses
		};
	}

	static function copyUse(source:OcamlRuntimeUseOccurrence, ?ownerId:String, ?exactSymbol:String, ?domain:OcamlRuntimeUseDomain,
			?profiles:Array<String>):OcamlRuntimeUseOccurrence {
		return {
			id: source.id,
			planRevision: source.planRevision,
			ownerId: ownerId == null ? source.ownerId : ownerId,
			requirementId: source.requirementId,
			domain: domain == null ? source.domain : domain,
			exactSymbol: exactSymbol == null ? source.exactSymbol : exactSymbol,
			role: source.role,
			order: source.order,
			source: source.source,
			profileEligibility: profiles == null ? source.profileEligibility.copy() : profiles,
			cardinality: source.cardinality
		};
	}

	static function expectFailure(label:String, marker:String, operation:Void->Void):Void {
		var message:Null<String> = null;
		try {
			operation();
		} catch (error:Dynamic) {
			message = Std.string(error);
		}
		if (message == null || !message.contains(marker))
			throw '$label must fail with "$marker", received ${message == null ? "no error" : message}.';
	}
}
