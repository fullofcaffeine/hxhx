import haxe.macro.Context;
import haxe.macro.Expr;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlStringEqualityPlan;
import reflaxe.ocaml.lowered.OcamlStringEqualityPlan.OcamlStringEqualityDecision;
import reflaxe.ocaml.lowered.OcamlStringEqualityPlan.OcamlStringEqualityKind;
import reflaxe.ocaml.lowered.OcamlStringEqualityPlan.OcamlStringEqualityPlanner;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

using StringTools;

/**
	Defines the expected runtime ownership for Haxe String equality.

	The expectation names `HxString.equals` directly. It does not inspect the
	target builder. Thus, a generator change cannot update this test by accident.
**/
class StringEqualityRuntimeUseFixture {
	static final binding:OcamlFunctionPlanBinding = {
		functionId: "StringEqualityRuntimeUseFixture.main",
		programRevision: "program:string-equality",
		bodyRevision: "body:string-equality",
		pipelineRevision: "pipeline:string-equality"
	};

	public static macro function run():Expr {
		final typed = Context.typeExpr(macro {
			final left:String = "same";
			final right:Null<String> = "same";
			left == right;
			left != right;
			left == null;
			final dynamicValue:Dynamic = right;
			dynamicValue == left;
			final nullableInt:Null<Int> = 1;
			nullableInt == 1;
			final nested = () -> left == right;
			nested;
		});

		final plan = new OcamlStringEqualityPlanner(binding).plan(typed);
		final decisions = plan.decisions();
		assertDecision(decisions, OcamlStringEqualityKind.Equal, "String", "Null<String>");
		assertDecision(decisions, OcamlStringEqualityKind.NotEqual, "String", "Null<String>");
		if (decisions.length != 2)
			throw 'Expected two outer String equality decisions, received ${decisions.length}.';

		for (decision in decisions)
			proveRuntimeUse(decision);
		expectFailure("stale binding", "belongs to another function or target pipeline", () -> plan.requirePlanBinding({
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: binding.bodyRevision,
			pipelineRevision: binding.pipelineRevision + ":stale"
		}));

		Sys.println("REFLAXE_OCAML_STRING_EQUALITY_RUNTIME_USE:PASS");
		return macro null;
	}

	static function proveRuntimeUse(decision:OcamlStringEqualityDecision):Void {
		OcamlStringEqualityPlan.requireDecision(decision);
		final requirements = OcamlRuntimeRequirementLedger.requirementsForStringEquality(decision);
		if (requirements.length != 1 || requirements[0].rootModules.join(",") != "HxString")
			throw 'Decision "${decision.id}" must require only HxString.';

		final authority = new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements, decision.runtimeUseOccurrences);
		final use = decision.runtimeUseOccurrences[0];
		final reference = OcamlExpr.ERuntimeIdent(authority.expressionIdentifier(use.id, use.planRevision, use.exactSymbol));
		authority.reconcileExpression(reference);

		expectFailure("wrong symbol", "wrong target symbol",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
				decision.runtimeUseOccurrences).expressionIdentifier(use.id, use.planRevision, use.exactSymbol + "_wrong"));
		expectFailure("missing helper", "missing runtime use",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
				decision.runtimeUseOccurrences).reconcileExpression(OcamlExpr.ESeq([])));
		expectFailure("duplicate helper", "invalid-plan",
			() -> OcamlStringEqualityPlan.requireDecision(copyDecision(decision, decision.kind, decision.runtimeUseOccurrences.concat([use]))));
		expectFailure("wrong owner", "invalid-runtime-use",
			() -> OcamlStringEqualityPlan.requireDecision(copyDecision(decision, decision.kind, [copyOccurrence(use, use.ownerId + ":wrong")])));
		final wrongKind = decision.kind == OcamlStringEqualityKind.Equal ? OcamlStringEqualityKind.NotEqual : OcamlStringEqualityKind.Equal;
		expectFailure("changed operator", "invalid-runtime-use",
			() -> OcamlStringEqualityPlan.requireDecision(copyDecision(decision, wrongKind, decision.runtimeUseOccurrences)));
		final wrongDomain = copyOccurrence(use, use.ownerId, OcamlRuntimeUseDomain.TypeIdentifier);
		expectFailure("wrong domain", "invalid-runtime-use",
			() -> OcamlStringEqualityPlan.requireDecision(copyDecision(decision, decision.kind, [wrongDomain])));
	}

	static function assertDecision(decisions:Array<OcamlStringEqualityDecision>, kind:OcamlStringEqualityKind, leftType:String, rightType:String):Void {
		final selected = decisions.filter(decision -> decision.kind == kind);
		if (selected.length != 1)
			throw 'Expected one ${(kind : String)} decision, received ${selected.length}.';
		final decision = selected[0];
		if (decision.leftSemanticTypeId != leftType || decision.rightSemanticTypeId != rightType)
			throw '${(kind : String)} expected $leftType/$rightType, received ${decision.leftSemanticTypeId}/${decision.rightSemanticTypeId}.';
		if (decision.runtimeUseOccurrences.length != 1 || decision.runtimeUseOccurrences[0].exactSymbol != "HxString.equals")
			throw '${(kind : String)} must own exactly one HxString.equals identifier.';
	}

	static function copyDecision(source:OcamlStringEqualityDecision, kind:OcamlStringEqualityKind,
			runtimeUseOccurrences:Array<OcamlRuntimeUseOccurrence>):OcamlStringEqualityDecision {
		return {
			id: source.id,
			revision: source.revision,
			source: {file: source.source.file, min: source.source.min, max: source.source.max},
			kind: kind,
			leftSemanticTypeId: source.leftSemanticTypeId,
			rightSemanticTypeId: source.rightSemanticTypeId,
			resultSemanticTypeId: source.resultSemanticTypeId,
			order: source.order,
			profileEligibility: source.profileEligibility.copy(),
			runtimeRequirementIds: source.runtimeRequirementIds.copy(),
			runtimeUseOccurrences: runtimeUseOccurrences,
			proofId: source.proofId,
			proofClaim: source.proofClaim,
			functionId: source.functionId,
			programRevision: source.programRevision,
			bodyRevision: source.bodyRevision,
			pipelineRevision: source.pipelineRevision
		};
	}

	static function copyOccurrence(source:OcamlRuntimeUseOccurrence, ownerId:String, ?domain:OcamlRuntimeUseDomain):OcamlRuntimeUseOccurrence {
		return {
			id: source.id,
			planRevision: source.planRevision,
			ownerId: ownerId,
			requirementId: source.requirementId,
			domain: domain ?? source.domain,
			exactSymbol: source.exactSymbol,
			role: source.role,
			order: source.order,
			source: {
				file: source.source.file,
				min: source.source.min,
				max: source.source.max
			},
			profileEligibility: source.profileEligibility.copy(),
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
			throw '$label must fail with "$marker", received ${message == null ? "no failure" : message}.';
	}
}
