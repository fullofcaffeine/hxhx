import haxe.macro.Expr;
import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.ast.OcamlConst;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlPat;
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

	static function boundaryPlanFactsAreExact():Void {
		final value = valueDecision();
		final valueBoundary = OcamlReturnRuntimeUseContract.forBoundaryDecision(value);
		OcamlReturnRuntimeUseContract.requireForBoundaryDecision(value, valueBoundary);
		final valuePattern = OcamlReturnRuntimeUseContract.boundaryPatternOccurrence(valueBoundary);
		assertTrue(valueBoundary.runtimeUseOccurrences.length == 1, "One planned value-return boundary must own one private pattern constructor.");
		assertTrue(valuePattern.ownerId == value.id
			&& valuePattern.domain == OcamlRuntimeUseDomain.PatternConstructor
			&& valuePattern.exactSymbol == "HxRuntime.Hx_return",
			"The value-return boundary must match only the signal selected by its sealed decision.");

		final effectOnly = voidDecision();
		final voidBoundary = OcamlReturnRuntimeUseContract.forBoundaryDecision(effectOnly);
		OcamlReturnRuntimeUseContract.requireForBoundaryDecision(effectOnly, voidBoundary);
		final voidPattern = OcamlReturnRuntimeUseContract.boundaryPatternOccurrence(voidBoundary);
		assertTrue(voidPattern.ownerId == effectOnly.id
			&& voidPattern.domain == OcamlRuntimeUseDomain.PatternConstructor
			&& voidPattern.exactSymbol == "HxRuntime.Hx_return_void",
			"The Void-return boundary must match only its payloadless signal.");
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

	static function checkedBoundaryPattern(decision:OcamlControlDecision, ?finalOutput:OcamlFinalRuntimeUseAuthority):OcamlPat {
		final plan = OcamlReturnRuntimeUseContract.forBoundaryDecision(decision);
		final requirements = OcamlRuntimeRequirementLedger.requirementsForReturnDecision(decision);
		final authority = new OcamlRuntimeUseAuthority(plan.planRevision, PROFILE, requirements, plan.runtimeUseOccurrences, finalOutput);
		final occurrence = OcamlReturnRuntimeUseContract.boundaryPatternOccurrence(plan);
		final reference = authority.patternIdentifier(occurrence.id, plan.planRevision, occurrence.exactSymbol);
		final arguments = decision.mechanism == OcamlControlTargetMechanism.RuntimeReturnSignal ? [OcamlPat.PVar("returned")] : [];
		final pattern = OcamlPat.PRuntimeConstructor(reference, arguments);
		authority.reconcileExpression(patternExpression(pattern));
		return pattern;
	}

	static function patternExpression(pattern:OcamlPat):OcamlExpr {
		return OcamlExpr.ETry(OcamlExpr.EConst(OcamlConst.CUnit), [{pat: pattern, guard: null, expr: OcamlExpr.EConst(OcamlConst.CUnit)}]);
	}

	static function checkedSyntaxAndFinalOutput():Void {
		final finalOutput = new OcamlFinalRuntimeUseAuthority();
		finalOutput.beginProgram("program:return-runtime-use", PROFILE);
		final value = valueDecision();
		final valueExpression = OcamlExpr.ETry(checkedSignal(value, finalOutput), [
			{pat: checkedBoundaryPattern(value, finalOutput), guard: null, expr: OcamlExpr.EIdent("returned")}
		]);
		final effectOnly = voidDecision();
		final voidExpression = OcamlExpr.ETry(checkedSignal(effectOnly, finalOutput), [
			{pat: checkedBoundaryPattern(effectOnly, finalOutput), guard: null, expr: OcamlExpr.EConst(OcamlConst.CUnit)}
		]);
		finalOutput.observeExpression(valueExpression, "Main::value::return");
		finalOutput.observeExpression(voidExpression, "Main::stop::return");
		finalOutput.finishProgram();

		final printer = new OcamlASTPrinter();
		final valueSyntax = printer.printExpr(valueExpression);
		assertTrue(valueSyntax.contains("raise (HxRuntime.Hx_return payload)")
			&& valueSyntax.contains("| HxRuntime.Hx_return returned -> returned"),
			"The checked value signal and boundary must preserve their existing OCaml syntax.");
		final voidSyntax = printer.printExpr(voidExpression);
		assertTrue(voidSyntax.contains("raise (HxRuntime.Hx_return_void)") && voidSyntax.contains("| HxRuntime.Hx_return_void -> ()"),
			"The checked payloadless signal and boundary must preserve their existing OCaml syntax.");
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

		final boundaryPlan = OcamlReturnRuntimeUseContract.forBoundaryDecision(decision);
		final boundary = OcamlReturnRuntimeUseContract.boundaryPatternOccurrence(boundaryPlan);
		expectFailure("missing boundary occurrence", "invalid-runtime-use",
			() -> OcamlReturnRuntimeUseContract.requireForBoundaryDecision(decision, planWithOccurrences(boundaryPlan, [])));
		expectFailure("duplicate boundary occurrence", "invalid-runtime-use",
			() -> OcamlReturnRuntimeUseContract.requireForBoundaryDecision(decision, planWithOccurrences(boundaryPlan, [boundary, boundary])));
		expectFailure("stale boundary occurrence", "invalid-runtime-use",
			() -> OcamlReturnRuntimeUseContract.requireForBoundaryDecision(decision,
				planWithOccurrences(boundaryPlan, [copyOccurrence(boundary, null, null, null, boundary.planRevision + ":stale")])));
		expectFailure("foreign boundary owner", "invalid-runtime-use",
			() -> OcamlReturnRuntimeUseContract.requireForBoundaryDecision(decision,
				planWithOccurrences(boundaryPlan, [copyOccurrence(boundary, "control:return:other")])));
		expectFailure("wrong boundary symbol", "invalid-runtime-use",
			() -> OcamlReturnRuntimeUseContract.requireForBoundaryDecision(decision,
				planWithOccurrences(boundaryPlan, [copyOccurrence(boundary, null, null, "HxRuntime.Hx_return_void")])));
		expectFailure("wrong boundary domain", "invalid-runtime-use",
			() -> OcamlReturnRuntimeUseContract.requireForBoundaryDecision(decision,
				planWithOccurrences(boundaryPlan, [copyOccurrence(boundary, null, OcamlRuntimeUseDomain.ExpressionIdentifier)])));
		expectFailure("wrong boundary profile", "invalid-runtime-use",
			() -> OcamlReturnRuntimeUseContract.requireForBoundaryDecision(decision,
				planWithOccurrences(boundaryPlan, [copyOccurrence(boundary, null, null, null, null, ["metal"])])));
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

		final boundaryPlan = OcamlReturnRuntimeUseContract.forBoundaryDecision(decision);
		final boundary = OcamlReturnRuntimeUseContract.boundaryPatternOccurrence(boundaryPlan);
		expectFailure("missing boundary requirement", "has no exact requirement",
			() -> new OcamlRuntimeUseAuthority(boundaryPlan.planRevision, PROFILE, [],
				boundaryPlan.runtimeUseOccurrences).patternIdentifier(boundary.id, boundary.planRevision, boundary.exactSymbol));
		expectFailure("stale boundary plan", "stale runtime use",
			() -> new OcamlRuntimeUseAuthority(boundaryPlan.planRevision, PROFILE, requirements,
				boundaryPlan.runtimeUseOccurrences).patternIdentifier(boundary.id, boundary.planRevision + ":stale", boundary.exactSymbol));
		expectFailure("wrong boundary target symbol", "wrong target symbol",
			() -> new OcamlRuntimeUseAuthority(boundaryPlan.planRevision, PROFILE, requirements,
				boundaryPlan.runtimeUseOccurrences).patternIdentifier(boundary.id, boundary.planRevision, "HxRuntime.Hx_return_void"));
		expectFailure("wrong boundary target domain", "wrong target domain",
			() -> new OcamlRuntimeUseAuthority(boundaryPlan.planRevision, PROFILE, requirements,
				boundaryPlan.runtimeUseOccurrences).expressionIdentifier(boundary.id, boundary.planRevision, boundary.exactSymbol));
		expectFailure("wrong boundary target profile", "not eligible for profile",
			() -> new OcamlRuntimeUseAuthority(boundaryPlan.planRevision, "unsupported-profile", requirements,
				boundaryPlan.runtimeUseOccurrences).patternIdentifier(boundary.id, boundary.planRevision, boundary.exactSymbol));
		final duplicateBoundaryConstruction = new OcamlRuntimeUseAuthority(boundaryPlan.planRevision, PROFILE, requirements,
			boundaryPlan.runtimeUseOccurrences);
		duplicateBoundaryConstruction.patternIdentifier(boundary.id, boundary.planRevision, boundary.exactSymbol);
		expectFailure("duplicate boundary construction", "constructed more than once",
			() -> duplicateBoundaryConstruction.patternIdentifier(boundary.id, boundary.planRevision, boundary.exactSymbol));
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

		final boundaryPlan = OcamlReturnRuntimeUseContract.forBoundaryDecision(decision);
		final boundary = OcamlReturnRuntimeUseContract.boundaryPatternOccurrence(boundaryPlan);
		final plainBoundary = new OcamlRuntimeUseAuthority(boundaryPlan.planRevision, PROFILE, requirements, boundaryPlan.runtimeUseOccurrences);
		expectFailure("plain boundary", "plain private runtime reference HxRuntime.Hx_return",
			() -> plainBoundary.reconcileExpression(patternExpression(OcamlPat.PConstructor("HxRuntime.Hx_return", [OcamlPat.PVar("returned")]))));
		final missingBoundary = new OcamlRuntimeUseAuthority(boundaryPlan.planRevision, PROFILE, requirements, boundaryPlan.runtimeUseOccurrences);
		expectFailure("missing boundary", "missing runtime use " + boundary.id, () -> missingBoundary.reconcileExpression(OcamlExpr.EConst(OcamlConst.CUnit)));
		final duplicateBoundary = new OcamlRuntimeUseAuthority(boundaryPlan.planRevision, PROFILE, requirements, boundaryPlan.runtimeUseOccurrences);
		final boundaryReference = duplicateBoundary.patternIdentifier(boundary.id, boundary.planRevision, boundary.exactSymbol);
		expectFailure("duplicate boundary", "duplicate runtime use " + boundary.id,
			() -> duplicateBoundary.reconcileExpression(OcamlExpr.ETry(OcamlExpr.EConst(OcamlConst.CUnit), [
				{
					pat: OcamlPat.PRuntimeConstructor(boundaryReference, []),
					guard: null,
					expr: OcamlExpr.EConst(OcamlConst.CUnit)
				},
				{pat: OcamlPat.PRuntimeConstructor(boundaryReference, []), guard: null, expr: OcamlExpr.EConst(OcamlConst.CUnit)}
			])));

		final missingFinal = new OcamlFinalRuntimeUseAuthority();
		missingFinal.beginProgram(decision.programRevision, PROFILE);
		checkedBoundaryPattern(decision, missingFinal);
		expectFailure("missing final boundary", "missing final runtime use", missingFinal.finishProgram);
	}

	public static macro function run():Expr {
		planFactsAreExact();
		boundaryPlanFactsAreExact();
		requirementFactsAreExact();
		checkedSyntaxAndFinalOutput();
		planCorruptionFails();
		authorityCorruptionFails();
		reconciliationRejectsPlainMissingAndDuplicateUses();
		trace("RETURN_RUNTIME_USE:PASS");
		return macro null;
	}
}
