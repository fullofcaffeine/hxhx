package;

import haxe.macro.Context;
import haxe.macro.Expr;
import reflaxe.ocaml.ast.OcamlConst;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.lowered.OcamlDynamicEqualityPlan.OcamlDynamicEqualityDecision;
import reflaxe.ocaml.lowered.OcamlDynamicEqualityPlan.OcamlDynamicEqualityKind;
import reflaxe.ocaml.lowered.OcamlDynamicEqualityPlan.OcamlDynamicEqualityPlanner;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseDomain;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

using StringTools;

/**
	Checks which expressions can select Haxe Dynamic equality after type checking.

	The fixture types real Haxe comparisons and one switch. Each selected source
	expression must authorize one exact `HxRuntime.dynamic_equals` identifier.
	A nested function gets a separate plan. Its helper uses must not enter the
	enclosing function's plan.
**/
class DynamicEqualityRuntimeUseFixture {
	static final binding:OcamlFunctionPlanBinding = {
		functionId: "DynamicEqualityRuntimeUseFixture.main",
		programRevision: "program:dynamic-equality-runtime-use",
		bodyRevision: "body:dynamic-equality-runtime-use",
		pipelineRevision: "pipeline:dynamic-equality-runtime-use"
	};

	public static macro function run():Expr {
		final typed = Context.typeExpr(macro {
			final value:Dynamic = Type.getClass([]);
			final equal = value == 1;
			final notEqual = value != false;
			final exact = 1 == 1;
			final selected = switch (value) {
				case Array, String:
					"class";
				case null:
					"null";
				default:
					"other";
			};
			final nested = () -> {
				final nestedValue:Dynamic = 2;
				return nestedValue == 2;
			};
			equal;
			notEqual;
			exact;
			selected;
			nested;
		});

		final plan = new OcamlDynamicEqualityPlanner(binding).plan(typed);
		final decisions = plan.decisions();
		assertKindCount(decisions, OcamlDynamicEqualityKind.Equal, 1);
		assertKindCount(decisions, OcamlDynamicEqualityKind.NotEqual, 1);
		assertKindCount(decisions, OcamlDynamicEqualityKind.SwitchCase, 2);
		if (decisions.length != 4)
			throw 'Expected four outer-function Dynamic equality decisions, received ${decisions.length}.';

		for (decision in decisions)
			proveRuntimeUse(decision);

		expectFailure("stale plan binding", "belongs to another function or target pipeline", () -> plan.requirePlanBinding({
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: binding.bodyRevision,
			pipelineRevision: binding.pipelineRevision + ":stale"
		}));

		Sys.println("REFLAXE_OCAML_DYNAMIC_EQUALITY_RUNTIME_USE:PASS");
		return macro null;
	}

	static function proveRuntimeUse(decision:OcamlDynamicEqualityDecision):Void {
		final requirements = OcamlRuntimeRequirementLedger.requirementsForDynamicEquality(decision);
		if (requirements.length != 1 || decision.runtimeRequirementIds.length != 1 || decision.runtimeUseOccurrences.length != 1)
			throw 'Dynamic equality decision "${decision.id}" must own one requirement and one runtime use.';
		final occurrence = decision.runtimeUseOccurrences[0];
		final authority = new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements, decision.runtimeUseOccurrences);
		final reference = authority.expressionIdentifier(occurrence.id, occurrence.planRevision, occurrence.exactSymbol);
		authority.reconcileExpression(OcamlExpr.ERuntimeIdent(reference));

		expectFailure("plain helper", "plain private runtime reference HxRuntime.dynamic_equals",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
				decision.runtimeUseOccurrences).reconcileExpression(OcamlExpr.EField(OcamlExpr.EIdent("HxRuntime"), "dynamic_equals")));
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

	static function assertKindCount(decisions:Array<OcamlDynamicEqualityDecision>, kind:OcamlDynamicEqualityKind, expected:Int):Void {
		final actual = decisions.filter(decision -> decision.kind == kind).length;
		if (actual != expected)
			throw 'Expected $expected ${(kind : String)} decision(s), received $actual.';
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
