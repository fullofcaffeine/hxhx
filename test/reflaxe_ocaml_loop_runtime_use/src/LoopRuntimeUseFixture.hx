package;

import haxe.macro.Expr;
import reflaxe.ocaml.ast.OcamlConst;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.ast.OcamlPat;
import reflaxe.ocaml.lowered.OcamlControlPlan;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlDecision;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlEffect;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlLoopKind;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlLoopTarget;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlRuntimeTagPolicy;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlTargetKind;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlTargetMechanism;
import reflaxe.ocaml.lowered.OcamlControlPlan.OcamlControlTransferKind;
import reflaxe.ocaml.lowered.OcamlLoopRuntimeUseModel.OcamlLoopRuntimeUseContract;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

/** Proves that lexical loop signals cannot bypass their exact runtime-use owners. */
class LoopRuntimeUseFixture {
	static var failureIndex = 0;

	public static macro function run():Expr {
		final target = loopTarget();
		final decision = breakDecision(target.id);
		proveTargetPattern(target, decision);
		proveTransferRaise(decision);
		Sys.println("REFLAXE_OCAML_LOOP_RUNTIME_USE_FIXTURE:PASS");
		return macro null;
	}

	static function proveTargetPattern(target:OcamlControlLoopTarget, decision:OcamlControlDecision):Void {
		final plan = OcamlLoopRuntimeUseContract.forTarget(target, [decision]);
		final occurrence = OcamlLoopRuntimeUseContract.patternOccurrence(plan, OcamlControlTransferKind.Break);
		final requirements = OcamlRuntimeRequirementLedger.requirementsForLoopTarget(target, [decision]);
		final authority = new OcamlRuntimeUseAuthority(plan.planRevision, "portable", requirements, plan.runtimeUseOccurrences);
		final reference = authority.patternIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol);
		authority.reconcileExpression(patternExpression(OcamlPat.PRuntimeConstructor(reference, [])));

		expectThrows("missing runtime use",
			() -> new OcamlRuntimeUseAuthority(plan.planRevision, "portable", requirements,
				plan.runtimeUseOccurrences).reconcileExpression(OcamlExpr.EConst(OcamlConst.CUnit)));
		final duplicateAuthority = new OcamlRuntimeUseAuthority(plan.planRevision, "portable", requirements, plan.runtimeUseOccurrences);
		final duplicate = duplicateAuthority.patternIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol);
		expectThrows("duplicate runtime use", () -> duplicateAuthority.reconcileExpression(OcamlExpr.EMatch(OcamlExpr.EConst(OcamlConst.CUnit), [
			{pat: OcamlPat.PRuntimeConstructor(duplicate, []), guard: null, expr: OcamlExpr.EConst(OcamlConst.CUnit)},
			{pat: OcamlPat.PRuntimeConstructor(duplicate, []), guard: null, expr: OcamlExpr.EConst(OcamlConst.CUnit)}
		])));
		expectThrows("stale runtime use",
			() -> new OcamlRuntimeUseAuthority(plan.planRevision, "portable", requirements,
				plan.runtimeUseOccurrences).patternIdentifier(occurrence.id, plan.planRevision + ":stale", occurrence.exactSymbol));
		expectThrows("wrong target symbol",
			() -> new OcamlRuntimeUseAuthority(plan.planRevision, "portable", requirements,
				plan.runtimeUseOccurrences).patternIdentifier(occurrence.id, plan.planRevision, "HxRuntime.Hx_continue"));
		expectThrows("wrong target domain",
			() -> new OcamlRuntimeUseAuthority(plan.planRevision, "portable", requirements,
				plan.runtimeUseOccurrences).expressionIdentifier(occurrence.id, plan.planRevision, occurrence.exactSymbol));
		final metalOnly = copyOccurrence(occurrence, ["metal"]);
		expectThrows("not eligible for profile portable",
			() -> new OcamlRuntimeUseAuthority(plan.planRevision, "portable", requirements,
				[metalOnly]).patternIdentifier(metalOnly.id, metalOnly.planRevision, metalOnly.exactSymbol));
		expectThrows("plain private runtime reference HxRuntime.Hx_break",
			() -> new OcamlRuntimeUseAuthority(plan.planRevision, "portable", requirements,
				plan.runtimeUseOccurrences).reconcileExpression(patternExpression(OcamlPat.PConstructor("HxRuntime.Hx_break", []))));
	}

	static function proveTransferRaise(decision:OcamlControlDecision):Void {
		final plan = OcamlLoopRuntimeUseContract.forDecision(decision);
		final occurrence = OcamlLoopRuntimeUseContract.signalOccurrence(plan);
		final requirements = OcamlRuntimeRequirementLedger.requirementsForLoopDecision(decision);
		final authority = new OcamlRuntimeUseAuthority(plan.planRevision, "portable", requirements, plan.runtimeUseOccurrences);
		final reference = authority.expressionIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol);
		authority.reconcileExpression(OcamlExpr.ERuntimeIdent(reference));
		expectThrows("plain private runtime reference HxRuntime.Hx_break",
			() -> new OcamlRuntimeUseAuthority(plan.planRevision, "portable", requirements,
				plan.runtimeUseOccurrences).reconcileExpression(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "Hx_break")));
	}

	static function patternExpression(pattern:OcamlPat):OcamlExpr {
		return OcamlExpr.EMatch(OcamlExpr.EConst(OcamlConst.CUnit), [{pat: pattern, guard: null, expr: OcamlExpr.EConst(OcamlConst.CUnit)}]);
	}

	static function loopTarget():OcamlControlLoopTarget {
		return {
			id: "loop-runtime-use-target",
			source: {file: "test/LoopRuntimeUse.hx", min: 10, max: 20},
			kind: OcamlControlLoopKind.While,
			functionId: "LoopRuntimeUse.main",
			programRevision: "program:loop-runtime-use",
			bodyRevision: "body:loop-runtime-use",
			pipelineRevision: "pipeline:loop-runtime-use",
			proofId: OcamlControlPlan.LEXICAL_LOOP_CONTROL_PROOF_ID,
			proofClaim: "fixture lexical loop target"
		};
	}

	static function breakDecision(targetId:String):OcamlControlDecision {
		return {
			id: "loop-runtime-use-break",
			source: {file: "test/LoopRuntimeUse.hx", min: 15, max: 16},
			kind: OcamlControlTransferKind.Break,
			effect: OcamlControlEffect.ExitLoop,
			targetKind: OcamlControlTargetKind.Loop,
			targetId: targetId,
			payload: null,
			runtimeTags: [],
			runtimeTagPolicy: OcamlControlRuntimeTagPolicy.NoRuntimeTags,
			mechanism: OcamlControlTargetMechanism.RuntimeBreakSignal,
			runtimeCapabilityId: OcamlControlPlan.BREAK_SIGNAL_CAPABILITY_ID,
			profileEligibility: ["metal", "portable"],
			reason: "fixture lexical break",
			proofId: OcamlControlPlan.LEXICAL_LOOP_CONTROL_PROOF_ID,
			proofClaim: "fixture lexical loop transfer",
			functionId: "LoopRuntimeUse.main",
			programRevision: "program:loop-runtime-use",
			bodyRevision: "body:loop-runtime-use",
			pipelineRevision: "pipeline:loop-runtime-use"
		};
	}

	static function copyOccurrence(occurrence:OcamlRuntimeUseOccurrence, profiles:Array<String>):OcamlRuntimeUseOccurrence {
		return {
			id: occurrence.id,
			planRevision: occurrence.planRevision,
			ownerId: occurrence.ownerId,
			requirementId: occurrence.requirementId,
			domain: occurrence.domain,
			exactSymbol: occurrence.exactSymbol,
			role: occurrence.role,
			order: occurrence.order,
			source: occurrence.source,
			profileEligibility: profiles,
			cardinality: occurrence.cardinality
		};
	}

	static function expectThrows(marker:String, operation:Void->Void):Void {
		failureIndex++;
		var message:Null<String> = null;
		try {
			operation();
		} catch (error:Dynamic) {
			message = Std.string(error);
		}
		if (message == null || message.indexOf(marker) < 0)
			throw 'Expected loop runtime-use failure $failureIndex containing "$marker", received ${message == null ? "no failure" : message}';
	}
}
