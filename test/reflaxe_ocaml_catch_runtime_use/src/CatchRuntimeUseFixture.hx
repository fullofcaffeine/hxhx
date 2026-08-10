import haxe.macro.Expr;
import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.ast.OcamlConst;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlModuleItem;
import reflaxe.ocaml.ast.OcamlPat;
import reflaxe.ocaml.lowered.OcamlCatchRuntimeUseModel;
import reflaxe.ocaml.lowered.OcamlCatchRuntimeUseModel.OcamlCatchRuntimeUsePlan;
import reflaxe.ocaml.lowered.OcamlControlPlan;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlCatchBranchResultPolicy;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlCatchChainDecision;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlCatchClauseDecision;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlCatchEffect;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlCatchInputChannel;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlCatchMatchPolicy;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlCatchPayloadConversion;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlCatchPrivateControlPolicy;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlCatchUnmatchedPolicy;
import reflaxe.ocaml.runtimegen.OcamlFinalRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

using StringTools;

/**
	Checks the private runtime names used by one sealed Haxe catch chain.

	The printed OCaml pattern and rethrow call are ordinary target syntax. Their
	hidden IDs prove that both names came from the same final typed catch decision,
	not from a builder-wide permission or a scan of rendered text.
**/
class CatchRuntimeUseFixture {
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

	static function clause():OcamlCatchClauseDecision {
		return {
			id: "catch-clause:dynamic",
			source: {file: "src/Main.hx", min: 20, max: 32},
			order: 0,
			variableName: "error",
			semanticTypeId: "Dynamic",
			signalCarrierTypeId: "Obj.t",
			outputCarrierTypeId: "Obj.t",
			outputRepresentationId: OcamlControlPlan.DYNAMIC_CONTROL_REPRESENTATION_ID,
			matchPolicy: OcamlCatchMatchPolicy.MatchAll,
			runtimeTag: null,
			conversion: OcamlCatchPayloadConversion.PreserveDynamicCarrier,
			nominalRepresentation: null,
			bodyResultPolicy: OcamlCatchBranchResultPolicy.PreserveTypedResult,
			effects: [
				OcamlCatchEffect.SelectFirstMatchingClause,
				OcamlCatchEffect.BindCatchVariable,
				OcamlCatchEffect.ExecuteCatchBody
			],
			proofId: OcamlControlPlan.REPRESENTED_VALUE_CATCH_PROOF_ID,
			proofClaim: "The final typed fixture has one Dynamic catch clause.",
			functionId: "Main|Main|static|catchFixture",
			programRevision: "program:catch-runtime-use",
			bodyRevision: "body:catch-runtime-use",
			pipelineRevision: "typed-ocaml-function-plan-v33"
		};
	}

	static function chain():OcamlCatchChainDecision {
		return {
			id: "catch-chain:fixture",
			source: {file: "src/Main.hx", min: 10, max: 40},
			clauses: [clause()],
			tryBodyResultPolicy: OcamlCatchBranchResultPolicy.PreserveTypedResult,
			inputChannels: [
				OcamlCatchInputChannel.HaxeExceptionSignal,
				OcamlCatchInputChannel.TargetNativeException
			],
			targetNativeRuntimeTags: ["OcamlExn"],
			haxeUnmatchedPolicy: OcamlCatchUnmatchedPolicy.RethrowHaxeExceptionSignal,
			targetNativeUnmatchedPolicy: OcamlCatchUnmatchedPolicy.ReraiseTargetNativeException,
			privateControlPolicy: OcamlCatchPrivateControlPolicy.PropagatePrivateControlSignals,
			runtimeCapabilityId: OcamlControlPlan.CATCH_SIGNAL_CAPABILITY_ID,
			profileEligibility: ["metal", "portable"],
			reason: "The sealed fixture preserves unmatched Haxe exceptions.",
			proofId: OcamlControlPlan.REPRESENTED_VALUE_CATCH_PROOF_ID,
			proofClaim: "The final typed fixture fixes both catch input channels and unmatched behavior.",
			functionId: "Main|Main|static|catchFixture",
			programRevision: "program:catch-runtime-use",
			bodyRevision: "body:catch-runtime-use",
			pipelineRevision: "typed-ocaml-function-plan-v33"
		};
	}

	static function checkedTry(?finalOutput:OcamlFinalRuntimeUseAuthority):OcamlExpr {
		final selected = chain();
		final plan = OcamlCatchRuntimeUseContract.forChain(selected);
		OcamlCatchRuntimeUseContract.requireForChain(selected, plan);
		final requirements = OcamlRuntimeRequirementLedger.requirementsForCatchChain(selected);
		final authority = new OcamlRuntimeUseAuthority(plan.planRevision, PROFILE, requirements, plan.runtimeUseOccurrences, finalOutput);
		final patternUse = OcamlCatchRuntimeUseContract.patternOccurrence(plan);
		final rethrowUse = OcamlCatchRuntimeUseContract.rethrowOccurrence(plan);
		final patternReference = authority.patternIdentifier(patternUse.id, plan.planRevision, patternUse.exactSymbol);
		final rethrowReference = authority.expressionIdentifier(rethrowUse.id, plan.planRevision, rethrowUse.exactSymbol);
		final expression = OcamlExpr.ETry(OcamlExpr.EConst(OcamlConst.CUnit), [
			{
				pat: OcamlPat.PRuntimeConstructor(patternReference, [OcamlPat.PVar("value"), OcamlPat.PVar("tags")]),
				guard: null,
				expr: OcamlExpr.EApp(OcamlExpr.ERuntimeIdent(rethrowReference), [OcamlExpr.EIdent("value"), OcamlExpr.EIdent("tags")])
			}
		]);
		authority.reconcileExpression(expression);
		return expression;
	}

	static function validLocalAndFinalUse():Void {
		final finalOutput = new OcamlFinalRuntimeUseAuthority();
		finalOutput.beginProgram("program:catch-runtime-use", PROFILE);
		final expression = checkedTry(finalOutput);
		finalOutput.observeExpression(expression, "Main::catchFixture");
		finalOutput.finishProgram();

		final rendered = new OcamlASTPrinter().printExpr(expression);
		assertTrue(rendered.contains("HxRuntime.Hx_exception (value, tags)"), "The checked pattern must print the exact runtime constructor.");
		assertTrue(rendered.contains("HxRuntime.hx_throw_typed value tags"), "The checked rethrow must print the exact runtime helper.");
	}

	static function copyOccurrence(source:OcamlRuntimeUseOccurrence, ?ownerId:String, ?domain:OcamlRuntimeUseDomain, ?exactSymbol:String,
			?planRevision:String, ?profiles:Array<String>):OcamlRuntimeUseOccurrence {
		return {
			id: source.id,
			planRevision: planRevision == null ? source.planRevision : planRevision,
			ownerId: ownerId == null ? source.ownerId : ownerId,
			requirementId: source.requirementId,
			domain: domain == null ? source.domain : domain,
			exactSymbol: exactSymbol == null ? source.exactSymbol : exactSymbol,
			role: source.role,
			order: source.order,
			source: source.source,
			profileEligibility: profiles == null ? source.profileEligibility.copy() : profiles.copy(),
			cardinality: source.cardinality
		};
	}

	static function planWithOccurrences(source:OcamlCatchRuntimeUsePlan, occurrences:Array<OcamlRuntimeUseOccurrence>):OcamlCatchRuntimeUsePlan {
		return {
			chainId: source.chainId,
			planRevision: source.planRevision,
			runtimeRequirementIds: source.runtimeRequirementIds.copy(),
			runtimeUseOccurrences: occurrences
		};
	}

	static function planAndConstructionFailures():Void {
		final selected = chain();
		final plan = OcamlCatchRuntimeUseContract.forChain(selected);
		final pattern = OcamlCatchRuntimeUseContract.patternOccurrence(plan);
		final rethrow = OcamlCatchRuntimeUseContract.rethrowOccurrence(plan);
		expectFailure("missing occurrence", "invalid-runtime-use",
			() -> OcamlCatchRuntimeUseContract.requireForChain(selected, planWithOccurrences(plan, [pattern])));
		expectFailure("wrong owner", "invalid-runtime-use",
			() -> OcamlCatchRuntimeUseContract.requireForChain(selected, planWithOccurrences(plan, [copyOccurrence(pattern, "catch-chain:other"), rethrow])));

		final requirements = OcamlRuntimeRequirementLedger.requirementsForCatchChain(selected);
		final missingRequirement = new OcamlRuntimeUseAuthority(plan.planRevision, PROFILE, [], plan.runtimeUseOccurrences);
		expectFailure("missing runtime requirement", "has no exact requirement",
			() -> missingRequirement.patternIdentifier(pattern.id, plan.planRevision, pattern.exactSymbol));
		final stale = new OcamlRuntimeUseAuthority(plan.planRevision, PROFILE, requirements, plan.runtimeUseOccurrences);
		expectFailure("stale pattern", "stale runtime use", () -> stale.patternIdentifier(pattern.id, "plan:stale", pattern.exactSymbol));
		final wrongSymbol = new OcamlRuntimeUseAuthority(plan.planRevision, PROFILE, requirements, plan.runtimeUseOccurrences);
		expectFailure("wrong pattern symbol", "wrong target symbol", () -> wrongSymbol.patternIdentifier(pattern.id, plan.planRevision, "HxRuntime.Hx_other"));
		final wrongDomain = new OcamlRuntimeUseAuthority(plan.planRevision, PROFILE, requirements, plan.runtimeUseOccurrences);
		expectFailure("wrong pattern domain", "wrong target domain",
			() -> wrongDomain.expressionIdentifier(pattern.id, plan.planRevision, pattern.exactSymbol));
		final wrongProfile = new OcamlRuntimeUseAuthority(plan.planRevision, "unsupported-profile", requirements, plan.runtimeUseOccurrences);
		expectFailure("wrong pattern profile", "not eligible for profile",
			() -> wrongProfile.patternIdentifier(pattern.id, plan.planRevision, pattern.exactSymbol));
	}

	static function missingAndDuplicatePatternUsesFail():Void {
		final selected = chain();
		final plan = OcamlCatchRuntimeUseContract.forChain(selected);
		final requirements = OcamlRuntimeRequirementLedger.requirementsForCatchChain(selected);
		final pattern = OcamlCatchRuntimeUseContract.patternOccurrence(plan);
		final rethrow = OcamlCatchRuntimeUseContract.rethrowOccurrence(plan);

		final missing = new OcamlRuntimeUseAuthority(plan.planRevision, PROFILE, requirements, plan.runtimeUseOccurrences);
		final missingPattern = missing.patternIdentifier(pattern.id, plan.planRevision, pattern.exactSymbol);
		expectFailure("missing rethrow", "missing runtime use " + rethrow.id,
			() -> missing.reconcileExpression(OcamlExpr.ETry(OcamlExpr.EConst(OcamlConst.CUnit), [
				{
					pat: OcamlPat.PRuntimeConstructor(missingPattern, []),
					guard: null,
					expr: OcamlExpr.EConst(OcamlConst.CUnit)
				}
			])));

		final duplicate = new OcamlRuntimeUseAuthority(plan.planRevision, PROFILE, requirements, plan.runtimeUseOccurrences);
		final duplicatePattern = duplicate.patternIdentifier(pattern.id, plan.planRevision, pattern.exactSymbol);
		final duplicateRethrow = duplicate.expressionIdentifier(rethrow.id, plan.planRevision, rethrow.exactSymbol);
		expectFailure("duplicate pattern", "duplicate runtime use " + pattern.id,
			() -> duplicate.reconcileExpression(OcamlExpr.ETry(OcamlExpr.EConst(OcamlConst.CUnit), [
				{
					pat: OcamlPat.PRuntimeConstructor(duplicatePattern, []),
					guard: null,
					expr: OcamlExpr.ERuntimeIdent(duplicateRethrow)
				},
				{pat: OcamlPat.PRuntimeConstructor(duplicatePattern, []), guard: null, expr: OcamlExpr.EConst(OcamlConst.CUnit)}
			])));
	}

	static function finalPatternCopyAndCorruption():Void {
		final copiedOutput = new OcamlFinalRuntimeUseAuthority();
		copiedOutput.beginProgram("program:catch-runtime-use-copy", PROFILE);
		final original = checkedTry(copiedOutput);
		final copied = copiedOutput.copyExpressionForOutput(original, "target-native-catch-copy");
		copiedOutput.observeModuleItems([
			OcamlModuleItem.ILet([{name: "original", expr: original}, {name: "copied", expr: copied}], false)
		]);
		copiedOutput.finishProgram();

		final corruptedOutput = new OcamlFinalRuntimeUseAuthority();
		corruptedOutput.beginProgram("program:catch-runtime-use-corruption", PROFILE);
		final corrupted = checkedTry(corruptedOutput);
		switch (corrupted) {
			case ETry(_, [{pat: PRuntimeConstructor(reference, _)}]):
				// The production field is immutable. Reflect is confined to this negative
				// test so it can simulate damaged boundary data that ordinary Haxe code
				// cannot construct.
				Reflect.setField(reference, "ownerId", "catch-chain:wrong-owner");
			case _:
				throw "The catch corruption fixture lost its checked pattern.";
		}
		expectFailure("wrong final pattern owner", "wrong owner", () -> corruptedOutput.observeExpression(corrupted));
	}

	static function plainPatternFails():Void {
		final selected = chain();
		final plan = OcamlCatchRuntimeUseContract.forChain(selected);
		final requirements = OcamlRuntimeRequirementLedger.requirementsForCatchChain(selected);
		final authority = new OcamlRuntimeUseAuthority(plan.planRevision, PROFILE, requirements, plan.runtimeUseOccurrences);
		final rethrowUse = OcamlCatchRuntimeUseContract.rethrowOccurrence(plan);
		final rethrowReference = authority.expressionIdentifier(rethrowUse.id, plan.planRevision, rethrowUse.exactSymbol);
		final expression = OcamlExpr.ETry(OcamlExpr.EConst(OcamlConst.CUnit), [
			{
				pat: OcamlPat.PConstructor("HxRuntime.Hx_exception", [OcamlPat.PVar("value"), OcamlPat.PVar("tags")]),
				guard: null,
				expr: OcamlExpr.EApp(OcamlExpr.ERuntimeIdent(rethrowReference), [OcamlExpr.EIdent("value"), OcamlExpr.EIdent("tags")])
			}
		]);
		expectFailure("plain catch pattern", "plain private runtime reference HxRuntime.Hx_exception", () -> authority.reconcileExpression(expression));
	}

	public static macro function run():Expr {
		validLocalAndFinalUse();
		planAndConstructionFailures();
		missingAndDuplicatePatternUsesFail();
		finalPatternCopyAndCorruption();
		plainPatternFails();
		trace("CATCH_RUNTIME_USE:PASS");
		return macro null;
	}
}
