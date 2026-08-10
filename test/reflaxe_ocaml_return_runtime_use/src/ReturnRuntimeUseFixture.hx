import haxe.macro.Expr;
import reflaxe.ocaml.ast.OcamlASTPrinter;
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
import reflaxe.ocaml.lowered.OcamlReturnRuntimeUseModel.OcamlReturnRuntimeUsePlan;
import reflaxe.ocaml.lowered.OcamlReturnRuntimeUseModel.OcamlReturnRuntimeUseContract;
import reflaxe.ocaml.runtimegen.OcamlFinalRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

using StringTools;

/**
	Checks the private OCaml signal raised for one sealed Haxe `return`.

	A return plan already says which function exits and how its optional value is
	represented. This fixture requires a second, narrower proof: only that exact
	plan may create the matching private `HxRuntime` identifier.
**/
class ReturnRuntimeUseFixture {
	static inline final PROFILE = "portable";

	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function expectFailure(label:String, expectedMessage:String, action:Void->Void):Void {
		var failed = false;
		try {
			action();
		} catch (error:Dynamic) {
			failed = true;
			final message = Std.string(error);
			if (!message.contains(expectedMessage))
				throw '$label failed with an unexpected message: $message';
		}
		if (!failed)
			throw '$label should have failed.';
	}

	static function valueDecision(?mechanism:OcamlControlTargetMechanism):OcamlControlDecision {
		return {
			id: "control:return:value",
			source: {file: "src/Main.hx", min: 10, max: 18},
			kind: OcamlControlTransferKind.Return,
			effect: OcamlControlEffect.ExitFunction,
			targetKind: OcamlControlTargetKind.Function,
			targetId: "Main|Main|static|value",
			payload: {
				inputSemanticTypeId: "Int",
				inputCarrierTypeId: "int",
				inputRepresentationId: "representation:Int:internal-value",
				signalCarrierTypeId: "Obj.t",
				outputSemanticTypeId: "Int",
				outputCarrierTypeId: "int",
				outputRepresentationId: "representation:Int:internal-value",
				conversion: OcamlControlPayloadConversion.BoxAndRecoverExactValue,
				nominalRepresentation: null,
				proofId: OcamlControlPlan.EXACT_VALUE_RETURN_PROOF_ID,
				proofClaim: "The fixture carries one exact Int through its owning function boundary."
			},
			runtimeTags: [],
			runtimeTagPolicy: OcamlControlRuntimeTagPolicy.NoRuntimeTags,
			mechanism: mechanism == null ? OcamlControlTargetMechanism.RuntimeReturnSignal : mechanism,
			runtimeCapabilityId: OcamlControlPlan.RETURN_SIGNAL_CAPABILITY_ID,
			profileEligibility: ["metal", "portable"],
			reason: "The nested source return exits its owning function.",
			proofId: OcamlControlPlan.EXACT_VALUE_RETURN_PROOF_ID,
			proofClaim: "The final typed fixture fixes one exact Int return.",
			functionId: "Main|Main|static|value",
			programRevision: "program:return-runtime-use",
			bodyRevision: "body:return-runtime-use",
			pipelineRevision: "typed-ocaml-function-plan-v33"
		};
	}

	static function voidDecision():OcamlControlDecision {
		return {
			id: "control:return:void",
			source: {file: "src/Main.hx", min: 30, max: 37},
			kind: OcamlControlTransferKind.Return,
			effect: OcamlControlEffect.ExitFunction,
			targetKind: OcamlControlTargetKind.Function,
			targetId: "Main|Main|instance|stop",
			payload: null,
			runtimeTags: [],
			runtimeTagPolicy: OcamlControlRuntimeTagPolicy.NoRuntimeTags,
			mechanism: OcamlControlTargetMechanism.RuntimeVoidReturnSignal,
			runtimeCapabilityId: OcamlControlPlan.VOID_RETURN_SIGNAL_CAPABILITY_ID,
			profileEligibility: ["metal", "portable"],
			reason: "The payloadless source return exits its owning function.",
			proofId: OcamlControlPlan.EFFECT_ONLY_VOID_RETURN_PROOF_ID,
			proofClaim: "The final typed fixture fixes one effect-only Void return.",
			functionId: "Main|Main|instance|stop",
			programRevision: "program:return-runtime-use",
			bodyRevision: "body:void-return-runtime-use",
			pipelineRevision: "typed-ocaml-function-plan-v33"
		};
	}

	static function copyOccurrence(source:OcamlRuntimeUseOccurrence, ?ownerId:String, ?domain:OcamlRuntimeUseDomain, ?exactSymbol:String,
			?planRevision:String, ?profiles:Array<String>, ?id:String, ?role:String, ?cardinality:Int):OcamlRuntimeUseOccurrence {
		return {
			id: id == null ? source.id : id,
			planRevision: planRevision == null ? source.planRevision : planRevision,
			ownerId: ownerId == null ? source.ownerId : ownerId,
			requirementId: source.requirementId,
			domain: domain == null ? source.domain : domain,
			exactSymbol: exactSymbol == null ? source.exactSymbol : exactSymbol,
			role: role == null ? source.role : role,
			order: source.order,
			source: source.source,
			profileEligibility: profiles == null ? source.profileEligibility.copy() : profiles.copy(),
			cardinality: cardinality == null ? source.cardinality : cardinality
		};
	}

	static function planWithOccurrences(source:OcamlReturnRuntimeUsePlan, occurrences:Array<OcamlRuntimeUseOccurrence>):OcamlReturnRuntimeUsePlan {
		return {
			decisionId: source.decisionId,
			planRevision: source.planRevision,
			runtimeRequirementIds: source.runtimeRequirementIds.copy(),
			runtimeUseOccurrences: occurrences
		};
	}

	static function planFactsAreExact():Void {
		final value = valueDecision();
		final valuePlan = OcamlReturnRuntimeUseContract.forDecision(value);
		OcamlReturnRuntimeUseContract.requireForDecision(value, valuePlan);
		final valueUse = OcamlReturnRuntimeUseContract.signalOccurrence(valuePlan);
		assertTrue(valuePlan.runtimeUseOccurrences.length == 1, "One admitted return must own one private runtime identifier.");
		assertTrue(valueUse.ownerId == value.id && valueUse.exactSymbol == "HxRuntime.Hx_return",
			"A value return must own only its exact value-bearing signal.");
		assertTrue(valueUse.source.min == value.source.min && valueUse.source.max == value.source.max,
			"The runtime occurrence must retain the exact typed return source span.");

		final effectOnly = voidDecision();
		final voidPlan = OcamlReturnRuntimeUseContract.forDecision(effectOnly);
		OcamlReturnRuntimeUseContract.requireForDecision(effectOnly, voidPlan);
		final voidUse = OcamlReturnRuntimeUseContract.signalOccurrence(voidPlan);
		assertTrue(voidUse.ownerId == effectOnly.id && voidUse.exactSymbol == "HxRuntime.Hx_return_void",
			"A payloadless return must own only its effect-only signal.");
	}

	static function requirementFactsAreExact():Void {
		final value = valueDecision();
		final valueRequirements = OcamlRuntimeRequirementLedger.requirementsForReturnDecision(value);
		assertTrue(valueRequirements.length == 1
			&& valueRequirements[0].id == OcamlReturnRuntimeUseContract.requirementId(value)
			&& valueRequirements[0].rootModules.join(",") == "HxRuntime"
			&& valueRequirements[0].subject.id == "Int",
			"The value return requirement must name its exact Haxe result and HxRuntime root.");
		final effectOnly = voidDecision();
		final voidRequirements = OcamlRuntimeRequirementLedger.requirementsForReturnDecision(effectOnly);
		assertTrue(voidRequirements.length == 1 && voidRequirements[0].subject.id == "Void",
			"The payloadless return requirement must remain effect-only instead of inventing a result carrier.");
	}

	static function checkedSignal(decision:OcamlControlDecision, ?finalOutput:OcamlFinalRuntimeUseAuthority):OcamlExpr {
		final plan = OcamlReturnRuntimeUseContract.forDecision(decision);
		final requirements = OcamlRuntimeRequirementLedger.requirementsForReturnDecision(decision);
		final authority = new OcamlRuntimeUseAuthority(plan.planRevision, PROFILE, requirements, plan.runtimeUseOccurrences, finalOutput);
		final occurrence = OcamlReturnRuntimeUseContract.signalOccurrence(plan);
		final reference = authority.expressionIdentifier(occurrence.id, plan.planRevision, occurrence.exactSymbol);
		final expression = switch (decision.mechanism) {
			case RuntimeReturnSignal: OcamlExpr.ERaise(OcamlExpr.EApp(OcamlExpr.ERuntimeIdent(reference), [OcamlExpr.EIdent("payload")]));
			case RuntimeVoidReturnSignal: OcamlExpr.ERaise(OcamlExpr.ERuntimeIdent(reference));
			case _: throw "The checked return fixture received an unsupported mechanism.";
		};
		authority.reconcileExpression(expression);
		return expression;
	}

	static function checkedSyntaxAndFinalOutput():Void {
		final finalOutput = new OcamlFinalRuntimeUseAuthority();
		finalOutput.beginProgram("program:return-runtime-use", PROFILE);
		final valueExpression = checkedSignal(valueDecision(), finalOutput);
		final voidExpression = checkedSignal(voidDecision(), finalOutput);
		finalOutput.observeExpression(valueExpression, "Main::value::return");
		finalOutput.observeExpression(voidExpression, "Main::stop::return");
		finalOutput.finishProgram();

		final printer = new OcamlASTPrinter();
		assertTrue(printer.printExpr(valueExpression).contains("raise (HxRuntime.Hx_return payload)"),
			"The checked value signal must preserve its existing OCaml syntax.");
		assertTrue(printer.printExpr(voidExpression).contains("raise (HxRuntime.Hx_return_void)"),
			"The checked payloadless signal must preserve its existing OCaml syntax.");
	}

	static function planCorruptionFails():Void {
		final decision = valueDecision();
		final plan = OcamlReturnRuntimeUseContract.forDecision(decision);
		final occurrence = OcamlReturnRuntimeUseContract.signalOccurrence(plan);
		expectFailure("missing occurrence", "invalid-runtime-use",
			() -> OcamlReturnRuntimeUseContract.requireForDecision(decision, planWithOccurrences(plan, [])));
		expectFailure("duplicate occurrence", "invalid-runtime-use",
			() -> OcamlReturnRuntimeUseContract.requireForDecision(decision, planWithOccurrences(plan, [occurrence, occurrence])));
		expectFailure("wrong owner", "invalid-runtime-use",
			() -> OcamlReturnRuntimeUseContract.requireForDecision(decision, planWithOccurrences(plan, [copyOccurrence(occurrence, "control:return:other")])));
		expectFailure("wrong symbol", "invalid-runtime-use",
			() -> OcamlReturnRuntimeUseContract.requireForDecision(decision,
				planWithOccurrences(plan, [copyOccurrence(occurrence, null, null, "HxRuntime.Hx_return_void")])));
		expectFailure("wrong domain", "invalid-runtime-use",
			() -> OcamlReturnRuntimeUseContract.requireForDecision(decision,
				planWithOccurrences(plan, [copyOccurrence(occurrence, null, OcamlRuntimeUseDomain.PatternConstructor)])));
		expectFailure("wrong profile", "invalid-runtime-use",
			() -> OcamlReturnRuntimeUseContract.requireForDecision(decision,
				planWithOccurrences(plan, [copyOccurrence(occurrence, null, null, null, null, ["metal"])])));
		expectFailure("wrong cardinality", "invalid-runtime-use",
			() -> OcamlReturnRuntimeUseContract.requireForDecision(decision,
				planWithOccurrences(plan, [copyOccurrence(occurrence, null, null, null, null, null, null, null, 2)])));

		final wrongMechanism = valueDecision(OcamlControlTargetMechanism.RuntimeBreakSignal);
		expectFailure("wrong mechanism", "invalid-plan", () -> OcamlReturnRuntimeUseContract.forDecision(wrongMechanism));
	}

	static function authorityCorruptionFails():Void {
		final decision = valueDecision();
		final plan = OcamlReturnRuntimeUseContract.forDecision(decision);
		final occurrence = OcamlReturnRuntimeUseContract.signalOccurrence(plan);
		final requirements = OcamlRuntimeRequirementLedger.requirementsForReturnDecision(decision);

		final missingRequirement = new OcamlRuntimeUseAuthority(plan.planRevision, PROFILE, [], plan.runtimeUseOccurrences);
		expectFailure("missing requirement", "has no exact requirement",
			() -> missingRequirement.expressionIdentifier(occurrence.id, plan.planRevision, occurrence.exactSymbol));
		final stale = new OcamlRuntimeUseAuthority(plan.planRevision, PROFILE, requirements, plan.runtimeUseOccurrences);
		expectFailure("stale plan", "stale runtime use", () -> stale.expressionIdentifier(occurrence.id, "plan:stale", occurrence.exactSymbol));
		final wrongSymbol = new OcamlRuntimeUseAuthority(plan.planRevision, PROFILE, requirements, plan.runtimeUseOccurrences);
		expectFailure("wrong symbol", "wrong target symbol",
			() -> wrongSymbol.expressionIdentifier(occurrence.id, plan.planRevision, "HxRuntime.Hx_return_void"));
		final wrongDomain = new OcamlRuntimeUseAuthority(plan.planRevision, PROFILE, requirements, plan.runtimeUseOccurrences);
		expectFailure("wrong domain", "wrong target domain", () -> wrongDomain.patternIdentifier(occurrence.id, plan.planRevision, occurrence.exactSymbol));
		final wrongProfile = new OcamlRuntimeUseAuthority(plan.planRevision, "unsupported-profile", requirements, plan.runtimeUseOccurrences);
		expectFailure("wrong profile", "not eligible for profile",
			() -> wrongProfile.expressionIdentifier(occurrence.id, plan.planRevision, occurrence.exactSymbol));

		final duplicateConstruction = new OcamlRuntimeUseAuthority(plan.planRevision, PROFILE, requirements, plan.runtimeUseOccurrences);
		duplicateConstruction.expressionIdentifier(occurrence.id, plan.planRevision, occurrence.exactSymbol);
		expectFailure("duplicate construction", "constructed more than once",
			() -> duplicateConstruction.expressionIdentifier(occurrence.id, plan.planRevision, occurrence.exactSymbol));
	}

	static function reconciliationRejectsPlainMissingAndDuplicateUses():Void {
		final decision = valueDecision();
		final plan = OcamlReturnRuntimeUseContract.forDecision(decision);
		final occurrence = OcamlReturnRuntimeUseContract.signalOccurrence(plan);
		final requirements = OcamlRuntimeRequirementLedger.requirementsForReturnDecision(decision);

		final plain = new OcamlRuntimeUseAuthority(plan.planRevision, PROFILE, requirements, plan.runtimeUseOccurrences);
		expectFailure("plain signal", "plain private runtime reference HxRuntime.Hx_return",
			() -> plain.reconcileExpression(OcamlExpr.ERaise(OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "Hx_return"),
				[OcamlExpr.EIdent("payload")]))));

		final missing = new OcamlRuntimeUseAuthority(plan.planRevision, PROFILE, requirements, plan.runtimeUseOccurrences);
		expectFailure("missing signal", "missing runtime use " + occurrence.id, () -> missing.reconcileExpression(OcamlExpr.EConst(OcamlConst.CUnit)));

		final duplicate = new OcamlRuntimeUseAuthority(plan.planRevision, PROFILE, requirements, plan.runtimeUseOccurrences);
		final reference = duplicate.expressionIdentifier(occurrence.id, plan.planRevision, occurrence.exactSymbol);
		expectFailure("duplicate signal", "duplicate runtime use " + occurrence.id,
			() -> duplicate.reconcileExpression(OcamlExpr.ESeq([OcamlExpr.ERuntimeIdent(reference), OcamlExpr.ERuntimeIdent(reference)])));
	}

	public static macro function run():Expr {
		planFactsAreExact();
		requirementFactsAreExact();
		checkedSyntaxAndFinalOutput();
		planCorruptionFails();
		authorityCorruptionFails();
		reconciliationRejectsPlainMissingAndDuplicateUses();
		trace("RETURN_RUNTIME_USE:PASS");
		return macro null;
	}
}
