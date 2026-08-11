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
	Checks the private OCaml call that carries one sealed Haxe `throw`.

	The control plan already chooses the payload conversion and runtime tags. This
	fixture proves that only that exact decision can print the matching `HxType`
	call, and that runtime packaging receives the same typed reason.
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
		Sys.println("REFLAXE_OCAML_THROW_RUNTIME_USE:PASS");
		return macro null;
	}

	static function intThrowDecision():OcamlControlDecision {
		return {
			id: "control:throw:int",
			source: {file: "src/Main.hx", min: 12, max: 20},
			kind: OcamlControlTransferKind.Throw,
			effect: OcamlControlEffect.RaiseHaxeValue,
			targetKind: OcamlControlTargetKind.HaxeExceptionChannel,
			targetId: OcamlControlPlan.HAXE_EXCEPTION_CHANNEL_ID,
			payload: {
				inputSemanticTypeId: "Int",
				inputCarrierTypeId: "int",
				inputRepresentationId: "representation:Int:internal-value",
				signalCarrierTypeId: "Obj.t",
				outputSemanticTypeId: "Int",
				outputCarrierTypeId: "int",
				outputRepresentationId: "representation:Int:internal-value",
				conversion: OcamlControlPayloadConversion.ReprAndRecoverExactValue,
				proofId: OcamlControlPlan.EXACT_VALUE_THROW_PROOF_ID,
				proofClaim: "The fixture carries one exact Int through the Haxe exception channel.",
				nominalRepresentation: null
			},
			runtimeTags: ["Dynamic"],
			runtimeTagPolicy: OcamlControlRuntimeTagPolicy.MergeDynamicWithExactRuntimeValue,
			mechanism: OcamlControlTargetMechanism.RuntimeTypedHaxeExceptionSignal,
			runtimeCapabilityId: OcamlControlPlan.THROW_SIGNAL_CAPABILITY_ID,
			profileEligibility: ["metal", "portable"],
			reason: "The typed fixture throws one exact Int.",
			proofId: OcamlControlPlan.EXACT_VALUE_THROW_PROOF_ID,
			proofClaim: "The final typed fixture fixes one exact Int throw.",
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
