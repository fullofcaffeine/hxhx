package;

import haxe.macro.Context;
import haxe.macro.Expr;
import reflaxe.ocaml.ast.OcamlConst;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.lowered.OcamlDynamicStringPlan;
import reflaxe.ocaml.lowered.OcamlDynamicStringPlan.OcamlDynamicStringDecision;
import reflaxe.ocaml.lowered.OcamlDynamicStringPlan.OcamlDynamicStringPlanner;
import reflaxe.ocaml.lowered.OcamlDynamicStringPlan.OcamlDynamicStringStrategy;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

using StringTools;

/**
	Checks which typed expressions can request Dynamic string conversion.

	The expected counts are authored from Haxe source behavior. They do not use
	the OCaml builder to decide which expressions should receive permission.
**/
class DynamicStringRuntimeUseFixture {
	static final binding:OcamlFunctionPlanBinding = {
		functionId: "DynamicStringRuntimeUseFixture.main",
		programRevision: "program:dynamic-string-runtime-use",
		bodyRevision: "body:dynamic-string-runtime-use",
		pipelineRevision: "pipeline:dynamic-string-runtime-use"
	};

	public static macro function run():Expr {
		final typed = Context.typeExpr(macro {
			final value:Dynamic = {name: "field"};
			final direct = Std.string(value);
			final concatenated = "value=" + value;
			final field = Reflect.field(value, value);
			final boxed = Std.string(new DynamicStringBox(1));
			final staticValue = Std.string(1);
			final nested = () -> Std.string(value);
			direct;
			concatenated;
			field;
			boxed;
			staticValue;
			nested;
		});

		final plan = new OcamlDynamicStringPlanner(binding).plan(typed);
		final decisions = plan.decisions();
		assertStrategyCount(decisions, OcamlDynamicStringStrategy.DirectCarrier, 3);
		assertStrategyCount(decisions, OcamlDynamicStringStrategy.BoxWithObjRepr, 1);
		if (decisions.length != 4)
			throw 'Expected four outer-function Dynamic string decisions, received ${decisions.length}.';
		for (decision in decisions)
			proveRuntimeUse(decision);

		expectFailure("stale plan binding", "belongs to another function or target pipeline", () -> plan.requirePlanBinding({
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: binding.bodyRevision,
			pipelineRevision: binding.pipelineRevision + ":stale"
		}));

		final wrongStrategy = withStrategy(decisions[0],
			decisions[0].strategy == OcamlDynamicStringStrategy.DirectCarrier ? OcamlDynamicStringStrategy.BoxWithObjRepr : OcamlDynamicStringStrategy.DirectCarrier);
		expectFailure("wrong strategy", "stale-plan", () -> OcamlDynamicStringPlan.requireDecision(wrongStrategy));

		Sys.println("REFLAXE_OCAML_DYNAMIC_STRING_RUNTIME_USE:PASS");
		return macro null;
	}

	static function proveRuntimeUse(decision:OcamlDynamicStringDecision):Void {
		final requirements = OcamlRuntimeRequirementLedger.requirementsForDynamicString(decision);
		if (requirements.length != 1 || decision.runtimeRequirementIds.length != 1 || decision.runtimeUseOccurrences.length != 1)
			throw 'Dynamic string decision "${decision.id}" must own one requirement and one runtime use.';
		final occurrence = decision.runtimeUseOccurrences[0];
		final authority = new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements, decision.runtimeUseOccurrences);
		final reference = authority.expressionIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol);
		authority.reconcileExpression(OcamlExpr.ERuntimeIdent(reference));

		expectFailure("plain helper", "plain private runtime reference HxDynamic.toStdString",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
				decision.runtimeUseOccurrences).reconcileExpression(OcamlExpr.EField(OcamlExpr.EIdent("HxDynamic"), "toStdString")));
		expectFailure("missing helper", "missing runtime use",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
				decision.runtimeUseOccurrences).reconcileExpression(OcamlExpr.EConst(OcamlConst.CUnit)));
		expectFailure("stale helper", "stale runtime use",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
				decision.runtimeUseOccurrences).expressionIdentifier(occurrence.id, occurrence.planRevision + ":stale", occurrence.exactSymbol));
		expectFailure("wrong helper symbol", "wrong target symbol",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
				decision.runtimeUseOccurrences).expressionIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol + "_wrong"));
		expectFailure("wrong helper domain", "wrong target domain",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
				decision.runtimeUseOccurrences).typeIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol));

		final metalOnly = copyOccurrence(occurrence, OcamlRuntimeUseDomain.ExpressionIdentifier, ["metal"]);
		expectFailure("wrong helper profile", "not eligible for profile portable",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
				[metalOnly]).expressionIdentifier(metalOnly.id, metalOnly.planRevision, metalOnly.exactSymbol));
		final wrongCardinality = copyOccurrence(occurrence, OcamlRuntimeUseDomain.ExpressionIdentifier, occurrence.profileEligibility, 2);
		expectFailure("wrong helper cardinality", "must have cardinality 1",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements, [wrongCardinality]));
		expectFailure("duplicate helper", "constructed more than once", () -> {
			final duplicate = new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements, decision.runtimeUseOccurrences);
			duplicate.expressionIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol);
			duplicate.expressionIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol);
		});
	}

	static function withStrategy(source:OcamlDynamicStringDecision, strategy:OcamlDynamicStringStrategy):OcamlDynamicStringDecision {
		return {
			id: source.id,
			revision: source.revision,
			source: {file: source.source.file, min: source.source.min, max: source.source.max},
			ownerSource: {file: source.ownerSource.file, min: source.ownerSource.min, max: source.ownerSource.max},
			sourceKind: source.sourceKind,
			strategy: strategy,
			semanticTypeId: source.semanticTypeId,
			inputCarrierTypeId: source.inputCarrierTypeId,
			order: source.order,
			profileEligibility: source.profileEligibility.copy(),
			runtimeRequirementIds: source.runtimeRequirementIds.copy(),
			runtimeUseOccurrences: source.runtimeUseOccurrences.copy(),
			proofId: source.proofId,
			proofClaim: source.proofClaim,
			functionId: source.functionId,
			programRevision: source.programRevision,
			bodyRevision: source.bodyRevision,
			pipelineRevision: source.pipelineRevision
		};
	}

	static function copyOccurrence(source:OcamlRuntimeUseOccurrence, domain:OcamlRuntimeUseDomain, profiles:Array<String>,
			?cardinality:Int):OcamlRuntimeUseOccurrence {
		return {
			id: source.id,
			planRevision: source.planRevision,
			ownerId: source.ownerId,
			requirementId: source.requirementId,
			domain: domain,
			exactSymbol: source.exactSymbol,
			role: source.role,
			order: source.order,
			source: {
				file: source.source.file,
				min: source.source.min,
				max: source.source.max
			},
			profileEligibility: profiles,
			cardinality: cardinality == null ? source.cardinality : cardinality
		};
	}

	static function assertStrategyCount(decisions:Array<OcamlDynamicStringDecision>, strategy:OcamlDynamicStringStrategy, expected:Int):Void {
		final actual = decisions.filter(decision -> decision.strategy == strategy).length;
		if (actual != expected)
			throw 'Expected $expected ${(strategy : String)} decision(s), received $actual.';
	}

	static function expectFailure(label:String, marker:String, operation:Void->Void):Void {
		var message:Null<String> = null;
		try {
			operation();
		} catch (error:Dynamic) {
			message = Std.string(error);
		}
		if (message == null || !message.contains(marker))
			throw '$label should fail with "$marker", received ${message == null ? "no failure" : message}.';
	}
}
