import haxe.macro.Expr;
import reflaxe.ocaml.ast.OcamlASTPrinter;
import reflaxe.ocaml.ast.OcamlConst;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlModuleItem;
import reflaxe.ocaml.ast.OcamlMatchCase;
import reflaxe.ocaml.ast.OcamlPat;
import reflaxe.ocaml.lowered.OcamlCatchRuntimeUseModel;
import reflaxe.ocaml.lowered.OcamlCatchRuntimeUseModel.OcamlCatchRuntimeUsePlan;
import reflaxe.ocaml.lowered.OcamlCatchRuntimeUseModel.OcamlCatchRuntimeTagUseRole;
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

	static function exactIntClause():OcamlCatchClauseDecision {
		return {
			id: "catch-clause:int",
			source: {file: "src/Main.hx", min: 20, max: 32},
			order: 0,
			variableName: "value",
			semanticTypeId: "Int",
			signalCarrierTypeId: "Obj.t",
			outputCarrierTypeId: "int",
			outputRepresentationId: "representation:Int:internal-value",
			matchPolicy: OcamlCatchMatchPolicy.ExactRuntimeTag,
			runtimeTag: "Int",
			conversion: OcamlCatchPayloadConversion.RecoverExactValue,
			nominalRepresentation: null,
			bodyResultPolicy: OcamlCatchBranchResultPolicy.PreserveTypedResult,
			effects: [
				OcamlCatchEffect.SelectFirstMatchingClause,
				OcamlCatchEffect.BindCatchVariable,
				OcamlCatchEffect.ExecuteCatchBody
			],
			proofId: OcamlControlPlan.REPRESENTED_VALUE_CATCH_PROOF_ID,
			proofClaim: "The final typed fixture has one exact Int catch clause.",
			functionId: "Main|Main|static|catchFixture",
			programRevision: "program:catch-runtime-use",
			bodyRevision: "body:catch-runtime-use",
			pipelineRevision: "typed-ocaml-function-plan-v33"
		};
	}

	static function exactIntChain():OcamlCatchChainDecision {
		final selected = chain();
		return {
			id: selected.id,
			source: selected.source,
			clauses: [exactIntClause()],
			tryBodyResultPolicy: selected.tryBodyResultPolicy,
			inputChannels: selected.inputChannels,
			targetNativeRuntimeTags: selected.targetNativeRuntimeTags,
			haxeUnmatchedPolicy: selected.haxeUnmatchedPolicy,
			targetNativeUnmatchedPolicy: selected.targetNativeUnmatchedPolicy,
			privateControlPolicy: selected.privateControlPolicy,
			runtimeCapabilityId: selected.runtimeCapabilityId,
			profileEligibility: selected.profileEligibility,
			reason: selected.reason,
			proofId: selected.proofId,
			proofClaim: selected.proofClaim,
			functionId: selected.functionId,
			programRevision: selected.programRevision,
			bodyRevision: selected.bodyRevision,
			pipelineRevision: selected.pipelineRevision
		};
	}

	static function valueExceptionClause():OcamlCatchClauseDecision {
		return {
			id: "catch-clause:value-exception",
			source: {file: "src/Main.hx", min: 33, max: 48},
			order: 1,
			variableName: "error",
			semanticTypeId: "haxe.ValueException",
			signalCarrierTypeId: "Obj.t",
			outputCarrierTypeId: "Haxe_ValueException.t",
			outputRepresentationId: OcamlControlPlan.HAXE_VALUE_EXCEPTION_CONTROL_REPRESENTATION_ID,
			matchPolicy: OcamlCatchMatchPolicy.MatchHaxeValueException,
			runtimeTag: null,
			conversion: OcamlCatchPayloadConversion.PreserveOrWrapHaxeValueException,
			nominalRepresentation: null,
			bodyResultPolicy: OcamlCatchBranchResultPolicy.PreserveTypedResult,
			effects: [
				OcamlCatchEffect.SelectFirstMatchingClause,
				OcamlCatchEffect.BindCatchVariable,
				OcamlCatchEffect.ExecuteCatchBody
			],
			proofId: OcamlControlPlan.REPRESENTED_VALUE_CATCH_PROOF_ID,
			proofClaim: "The final typed fixture has one haxe.ValueException catch clause.",
			functionId: "Main|Main|static|catchFixture",
			programRevision: "program:catch-runtime-use",
			bodyRevision: "body:catch-runtime-use",
			pipelineRevision: "typed-ocaml-function-plan-v33"
		};
	}

	static function orderedTagChain():OcamlCatchChainDecision {
		final selected = exactIntChain();
		return {
			id: selected.id,
			source: selected.source,
			clauses: [exactIntClause(), valueExceptionClause()],
			tryBodyResultPolicy: selected.tryBodyResultPolicy,
			inputChannels: selected.inputChannels,
			targetNativeRuntimeTags: selected.targetNativeRuntimeTags,
			haxeUnmatchedPolicy: selected.haxeUnmatchedPolicy,
			targetNativeUnmatchedPolicy: selected.targetNativeUnmatchedPolicy,
			privateControlPolicy: selected.privateControlPolicy,
			runtimeCapabilityId: selected.runtimeCapabilityId,
			profileEligibility: selected.profileEligibility,
			reason: selected.reason,
			proofId: selected.proofId,
			proofClaim: selected.proofClaim,
			functionId: selected.functionId,
			programRevision: selected.programRevision,
			bodyRevision: selected.bodyRevision,
			pipelineRevision: selected.pipelineRevision
		};
	}

	static function exactTagTestIsPlanned():Void {
		final plan = OcamlCatchRuntimeUseContract.forChain(exactIntChain());
		final tagTests = plan.runtimeUseOccurrences.filter(use -> use.exactSymbol == "HxRuntime.tags_has");
		assertTrue(tagTests.length == 1, "One exact Int catch must own one runtime-tag test before syntax is built.");
	}

	static function tagTestsFollowClauseAndRoleOrder():Void {
		final selected = orderedTagChain();
		final plan = OcamlCatchRuntimeUseContract.forChain(selected);
		OcamlCatchRuntimeUseContract.requireForChain(selected, plan);
		final exact = OcamlCatchRuntimeUseContract.runtimeTagOccurrence(plan, "catch-clause:int", OcamlCatchRuntimeTagUseRole.MatchExactRuntimeTag);
		final matchValue = OcamlCatchRuntimeUseContract.runtimeTagOccurrence(plan, "catch-clause:value-exception",
			OcamlCatchRuntimeTagUseRole.MatchValueException);
		final matchAny = OcamlCatchRuntimeUseContract.runtimeTagOccurrence(plan, "catch-clause:value-exception", OcamlCatchRuntimeTagUseRole.MatchAnyException);
		final convertValue = OcamlCatchRuntimeUseContract.runtimeTagOccurrence(plan, "catch-clause:value-exception",
			OcamlCatchRuntimeTagUseRole.ConvertValueException);
		assertTrue([exact.order, matchValue.order, matchAny.order, convertValue.order].join(",") == "5,6,7,8",
			"Catch tag tests must follow source clause order and then their expression order.");
		assertTrue(exact.source.min == 20 && convertValue.source.min == 33, "Each catch tag test must retain the source span of its exact clause.");
		assertTrue(plan.runtimeUseOccurrences.length == 10,
			"The private control cases, Haxe pattern, four tag tests, and unmatched rethrow must form one complete catch-owned runtime plan.");
	}

	static function checkedTry(?finalOutput:OcamlFinalRuntimeUseAuthority):OcamlExpr {
		final selected = chain();
		final plan = OcamlCatchRuntimeUseContract.forChain(selected);
		OcamlCatchRuntimeUseContract.requireForChain(selected, plan);
		final requirements = OcamlRuntimeRequirementLedger.requirementsForCatchChain(selected);
		final authority = new OcamlRuntimeUseAuthority(plan.planRevision, PROFILE, requirements, plan.runtimeUseOccurrences, finalOutput);
		final patternUse = OcamlCatchRuntimeUseContract.patternOccurrence(plan);
		final rethrowUse = OcamlCatchRuntimeUseContract.rethrowOccurrence(plan);
		final breakPatternUse = OcamlCatchRuntimeUseContract.privateControlOccurrence(plan, OcamlCatchRuntimeUseContract.PRIVATE_BREAK_PATTERN_ROLE);
		final breakReraiseUse = OcamlCatchRuntimeUseContract.privateControlOccurrence(plan, OcamlCatchRuntimeUseContract.PRIVATE_BREAK_RERAISE_ROLE);
		final continuePatternUse = OcamlCatchRuntimeUseContract.privateControlOccurrence(plan, OcamlCatchRuntimeUseContract.PRIVATE_CONTINUE_PATTERN_ROLE);
		final continueReraiseUse = OcamlCatchRuntimeUseContract.privateControlOccurrence(plan, OcamlCatchRuntimeUseContract.PRIVATE_CONTINUE_RERAISE_ROLE);
		final breakPatternReference = authority.patternIdentifier(breakPatternUse.id, plan.planRevision, breakPatternUse.exactSymbol);
		final breakReraiseReference = authority.expressionIdentifier(breakReraiseUse.id, plan.planRevision, breakReraiseUse.exactSymbol);
		final continuePatternReference = authority.patternIdentifier(continuePatternUse.id, plan.planRevision, continuePatternUse.exactSymbol);
		final continueReraiseReference = authority.expressionIdentifier(continueReraiseUse.id, plan.planRevision, continueReraiseUse.exactSymbol);
		final patternReference = authority.patternIdentifier(patternUse.id, plan.planRevision, patternUse.exactSymbol);
		final rethrowReference = authority.expressionIdentifier(rethrowUse.id, plan.planRevision, rethrowUse.exactSymbol);
		final expression = OcamlExpr.ETry(OcamlExpr.EConst(OcamlConst.CUnit), [
			{
				pat: OcamlPat.PRuntimeConstructor(breakPatternReference, []),
				guard: null,
				expr: OcamlExpr.ERaise(OcamlExpr.ERuntimeIdent(breakReraiseReference))
			},
			{
				pat: OcamlPat.PRuntimeConstructor(continuePatternReference, []),
				guard: null,
				expr: OcamlExpr.ERaise(OcamlExpr.ERuntimeIdent(continueReraiseReference))
			},
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
			?planRevision:String, ?profiles:Array<String>, ?id:String, ?role:String, ?order:Int, ?cardinality:Int):OcamlRuntimeUseOccurrence {
		return {
			id: id == null ? source.id : id,
			planRevision: planRevision == null ? source.planRevision : planRevision,
			ownerId: ownerId == null ? source.ownerId : ownerId,
			requirementId: source.requirementId,
			domain: domain == null ? source.domain : domain,
			exactSymbol: exactSymbol == null ? source.exactSymbol : exactSymbol,
			role: role == null ? source.role : role,
			order: order == null ? source.order : order,
			source: source.source,
			profileEligibility: profiles == null ? source.profileEligibility.copy() : profiles.copy(),
			cardinality: cardinality == null ? source.cardinality : cardinality
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

	static function tagPlanCorruptionFails():Void {
		final selected = orderedTagChain();
		final plan = OcamlCatchRuntimeUseContract.forChain(selected);
		final exact = OcamlCatchRuntimeUseContract.runtimeTagOccurrence(plan, "catch-clause:int", OcamlCatchRuntimeTagUseRole.MatchExactRuntimeTag);
		final matchValue = OcamlCatchRuntimeUseContract.runtimeTagOccurrence(plan, "catch-clause:value-exception",
			OcamlCatchRuntimeTagUseRole.MatchValueException);
		final occurrences = plan.runtimeUseOccurrences;
		expectFailure("missing tag occurrence", "invalid-runtime-use",
			() -> OcamlCatchRuntimeUseContract.requireForChain(selected, planWithOccurrences(plan, occurrences.filter(use -> use.id != exact.id))));
		expectFailure("reordered tag occurrence", "invalid-runtime-use", () -> {
			final changed = occurrences.copy();
			changed[exact.order] = matchValue;
			changed[matchValue.order] = exact;
			OcamlCatchRuntimeUseContract.requireForChain(selected, planWithOccurrences(plan, changed));
		});
		expectFailure("wrong tag owner", "invalid-runtime-use", () -> {
			final changed = occurrences.copy();
			changed[exact.order] = copyOccurrence(exact, "catch-chain:other");
			OcamlCatchRuntimeUseContract.requireForChain(selected, planWithOccurrences(plan, changed));
		});
		expectFailure("wrong tag clause", "invalid-runtime-use", () -> {
			final changed = occurrences.copy();
			changed[exact.order] = copyOccurrence(exact, null, null, null, null, null, exact.id + ":other-clause");
			OcamlCatchRuntimeUseContract.requireForChain(selected, planWithOccurrences(plan, changed));
		});
		expectFailure("wrong tag role", "invalid-runtime-use", () -> {
			final changed = occurrences.copy();
			changed[exact.order] = copyOccurrence(exact, null, null, null, null, null, null, exact.role + ":other");
			OcamlCatchRuntimeUseContract.requireForChain(selected, planWithOccurrences(plan, changed));
		});
		expectFailure("wrong tag symbol", "invalid-runtime-use", () -> {
			final changed = occurrences.copy();
			changed[exact.order] = copyOccurrence(exact, null, null, "HxRuntime.is_null");
			OcamlCatchRuntimeUseContract.requireForChain(selected, planWithOccurrences(plan, changed));
		});
		expectFailure("wrong tag domain", "invalid-runtime-use", () -> {
			final changed = occurrences.copy();
			changed[exact.order] = copyOccurrence(exact, null, OcamlRuntimeUseDomain.PatternConstructor);
			OcamlCatchRuntimeUseContract.requireForChain(selected, planWithOccurrences(plan, changed));
		});
		expectFailure("wrong tag profile", "invalid-runtime-use", () -> {
			final changed = occurrences.copy();
			changed[exact.order] = copyOccurrence(exact, null, null, null, null, ["metal"]);
			OcamlCatchRuntimeUseContract.requireForChain(selected, planWithOccurrences(plan, changed));
		});
		expectFailure("wrong tag cardinality", "invalid-runtime-use", () -> {
			final changed = occurrences.copy();
			changed[exact.order] = copyOccurrence(exact, null, null, null, null, null, null, null, null, 2);
			OcamlCatchRuntimeUseContract.requireForChain(selected, planWithOccurrences(plan, changed));
		});
	}

	static function checkedTagConstructionAndFailures():Void {
		final selected = exactIntChain();
		final plan = OcamlCatchRuntimeUseContract.forChain(selected);
		final requirements = OcamlRuntimeRequirementLedger.requirementsForCatchChain(selected);
		final pattern = OcamlCatchRuntimeUseContract.patternOccurrence(plan);
		final tag = OcamlCatchRuntimeUseContract.runtimeTagOccurrence(plan, "catch-clause:int", OcamlCatchRuntimeTagUseRole.MatchExactRuntimeTag);
		final rethrow = OcamlCatchRuntimeUseContract.rethrowOccurrence(plan);

		final authority = new OcamlRuntimeUseAuthority(plan.planRevision, PROFILE, requirements, plan.runtimeUseOccurrences);
		final patternReference = authority.patternIdentifier(pattern.id, plan.planRevision, pattern.exactSymbol);
		final tagReference = authority.expressionIdentifier(tag.id, plan.planRevision, tag.exactSymbol);
		final rethrowReference = authority.expressionIdentifier(rethrow.id, plan.planRevision, rethrow.exactSymbol);
		final cases = privateControlCases(plan, authority);
		cases.push({
			pat: OcamlPat.PRuntimeConstructor(patternReference, [OcamlPat.PVar("value"), OcamlPat.PVar("tags")]),
			guard: null,
			expr: OcamlExpr.EIf(OcamlExpr.EApp(OcamlExpr.ERuntimeIdent(tagReference), [OcamlExpr.EIdent("tags"), OcamlExpr.EConst(OcamlConst.CString("Int"))]),
				OcamlExpr.EConst(OcamlConst.CUnit),
				OcamlExpr.EApp(OcamlExpr.ERuntimeIdent(rethrowReference), [OcamlExpr.EIdent("value"), OcamlExpr.EIdent("tags")]))
		});
		final expression = OcamlExpr.ETry(OcamlExpr.EConst(OcamlConst.CUnit), cases);
		authority.reconcileExpression(expression);
		final rendered = new OcamlASTPrinter().printExpr(expression);
		assertTrue(rendered.contains("HxRuntime.tags_has tags \"Int\""), "The checked exact catch tag test must print unchanged OCaml syntax.");

		final duplicate = new OcamlRuntimeUseAuthority(plan.planRevision, PROFILE, requirements, plan.runtimeUseOccurrences);
		duplicate.expressionIdentifier(tag.id, plan.planRevision, tag.exactSymbol);
		expectFailure("duplicate tag construction", "constructed more than once",
			() -> duplicate.expressionIdentifier(tag.id, plan.planRevision, tag.exactSymbol));
	}

	static function privateControlCases(plan:OcamlCatchRuntimeUsePlan, authority:OcamlRuntimeUseAuthority):Array<OcamlMatchCase> {
		final breakPattern = OcamlCatchRuntimeUseContract.privateControlOccurrence(plan, OcamlCatchRuntimeUseContract.PRIVATE_BREAK_PATTERN_ROLE);
		final breakReraise = OcamlCatchRuntimeUseContract.privateControlOccurrence(plan, OcamlCatchRuntimeUseContract.PRIVATE_BREAK_RERAISE_ROLE);
		final continuePattern = OcamlCatchRuntimeUseContract.privateControlOccurrence(plan, OcamlCatchRuntimeUseContract.PRIVATE_CONTINUE_PATTERN_ROLE);
		final continueReraise = OcamlCatchRuntimeUseContract.privateControlOccurrence(plan, OcamlCatchRuntimeUseContract.PRIVATE_CONTINUE_RERAISE_ROLE);
		return [
			{
				pat: OcamlPat.PRuntimeConstructor(authority.patternIdentifier(breakPattern.id, plan.planRevision, breakPattern.exactSymbol), []),
				guard: null,
				expr: OcamlExpr.ERaise(OcamlExpr.ERuntimeIdent(authority.expressionIdentifier(breakReraise.id, plan.planRevision, breakReraise.exactSymbol)))
			},
			{
				pat: OcamlPat.PRuntimeConstructor(authority.patternIdentifier(continuePattern.id, plan.planRevision, continuePattern.exactSymbol), []),
				guard: null,
				expr: OcamlExpr.ERaise(OcamlExpr.ERuntimeIdent(authority.expressionIdentifier(continueReraise.id, plan.planRevision,
					continueReraise.exactSymbol)))
			}
		];
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
			case ETry(_, cases):
				final haxePattern = cases.filter(item -> switch (item.pat) {
					case PRuntimeConstructor(reference, _): reference.exactSymbol == "HxRuntime.Hx_exception";
					case _: false;
				});
				if (haxePattern.length != 1)
					throw "The catch corruption fixture lost its checked Haxe exception pattern.";
				switch (haxePattern[0].pat) {
					case PRuntimeConstructor(reference, _):
						// The production field is immutable. Reflect is confined to this
						// negative test so it can simulate damaged boundary data.
						Reflect.setField(reference, "ownerId", "catch-chain:wrong-owner");
					case _:
				}
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

	static function plainTagTestFails():Void {
		final selected = exactIntChain();
		final plan = OcamlCatchRuntimeUseContract.forChain(selected);
		final requirements = OcamlRuntimeRequirementLedger.requirementsForCatchChain(selected);
		final authority = new OcamlRuntimeUseAuthority(plan.planRevision, PROFILE, requirements, plan.runtimeUseOccurrences);
		final pattern = OcamlCatchRuntimeUseContract.patternOccurrence(plan);
		final rethrow = OcamlCatchRuntimeUseContract.rethrowOccurrence(plan);
		final patternReference = authority.patternIdentifier(pattern.id, plan.planRevision, pattern.exactSymbol);
		final rethrowReference = authority.expressionIdentifier(rethrow.id, plan.planRevision, rethrow.exactSymbol);
		final expression = OcamlExpr.ETry(OcamlExpr.EConst(OcamlConst.CUnit), [
			{
				pat: OcamlPat.PRuntimeConstructor(patternReference, [OcamlPat.PVar("value"), OcamlPat.PVar("tags")]),
				guard: null,
				expr: OcamlExpr.EIf(OcamlExpr.EApp(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "tags_has"),
					[OcamlExpr.EIdent("tags"), OcamlExpr.EConst(OcamlConst.CString("Int"))]),
					OcamlExpr.EConst(OcamlConst.CUnit),
					OcamlExpr.EApp(OcamlExpr.ERuntimeIdent(rethrowReference), [OcamlExpr.EIdent("value"), OcamlExpr.EIdent("tags")]))
			}
		]);
		expectFailure("plain catch tag test", "plain private runtime reference HxRuntime.tags_has", () -> authority.reconcileExpression(expression));
	}

	public static macro function run():Expr {
		exactTagTestIsPlanned();
		tagTestsFollowClauseAndRoleOrder();
		validLocalAndFinalUse();
		planAndConstructionFailures();
		tagPlanCorruptionFails();
		checkedTagConstructionAndFailures();
		missingAndDuplicatePatternUsesFail();
		finalPatternCopyAndCorruption();
		plainPatternFails();
		plainTagTestFails();
		trace("CATCH_RUNTIME_USE:PASS");
		return macro null;
	}
}
