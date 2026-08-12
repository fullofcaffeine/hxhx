package;

import haxe.macro.Context;
import haxe.macro.Expr;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlStdIsOfTypePlan;
import reflaxe.ocaml.lowered.OcamlStdIsOfTypePlan.OcamlStdIsOfTypeDecision;
import reflaxe.ocaml.lowered.OcamlStdIsOfTypePlan.OcamlStdIsOfTypePlanner;
import reflaxe.ocaml.lowered.OcamlStdIsOfTypePlan.OcamlStdIsOfTypeStrategy;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

using StringTools;

/**
	Checks the complete private-runtime decision for `Std.isOfType()`.

	The fixture types real standard-library calls first. It then compares each
	decision with a manually authored table. This prevents the test from deriving
	its expected helper names from the implementation that it checks.
**/
class StdIsOfTypeRuntimeUseFixture {
	static final binding:OcamlFunctionPlanBinding = {
		functionId: "StdIsOfTypeRuntimeUseFixture.main",
		programRevision: "program:std-is-of-type-runtime-use",
		bodyRevision: "body:std-is-of-type-runtime-use",
		pipelineRevision: "pipeline:std-is-of-type-runtime-use"
	};

	public static macro function run():Expr {
		final typed = Context.typeExpr(macro {
			final value:Dynamic = 1;
			Std.isOfType(1, Int);
			Std.isOfType("one", Int);
			Std.isOfType(value, Int);
			Std.isOfType(value, Float);
			Std.isOfType(value, Bool);
			Std.isOfType(value, String);
			Std.isOfType(value, Array);
			Std.isOfType(value, StdIsOfTypeRuntimeUseEnum);
			final nested = () -> Std.isOfType(value, Int);
			nested;
		});

		final plan = new OcamlStdIsOfTypePlanner(binding).plan(typed);
		final decisions = plan.decisions();
		assertStrategy(decisions, OcamlStdIsOfTypeStrategy.StaticTrue, 1, []);
		assertStrategy(decisions, OcamlStdIsOfTypeStrategy.StaticFalse, 1, []);
		assertStrategy(decisions, OcamlStdIsOfTypeStrategy.DynamicInt, 1, ["HxRuntime.hx_null", "HxRuntime.is_boxed_bool"]);
		assertStrategy(decisions, OcamlStdIsOfTypeStrategy.DynamicFloat, 1, ["HxRuntime.hx_null", "HxRuntime.is_boxed_bool"]);
		assertStrategy(decisions, OcamlStdIsOfTypeStrategy.DynamicBool, 1, ["HxRuntime.hx_null", "HxRuntime.is_boxed_bool"]);
		assertStrategy(decisions, OcamlStdIsOfTypeStrategy.RuntimeFallback, 3, ["HxType.isOfType"]);
		if (decisions.length != 8)
			throw 'Expected eight outer-function Std.isOfType decisions, received ${decisions.length}.';

		for (decision in decisions)
			proveRuntimeUses(decision);

		expectFailure("stale binding", "belongs to another function or target pipeline", () -> plan.requirePlanBinding({
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: binding.bodyRevision,
			pipelineRevision: binding.pipelineRevision + ":stale"
		}));

		Sys.println("REFLAXE_OCAML_STD_IS_OF_TYPE_RUNTIME_USE:PASS");
		return macro null;
	}

	static function proveRuntimeUses(decision:OcamlStdIsOfTypeDecision):Void {
		OcamlStdIsOfTypePlan.requireDecision(decision);
		final requirements = OcamlRuntimeRequirementLedger.requirementsForStdIsOfType(decision);
		final symbols = decision.runtimeUseOccurrences.map(use -> use.exactSymbol);
		if (symbols.length == 0) {
			if (requirements.length != 0)
				throw 'Static decision "${decision.id}" must not request runtime source.';
			return;
		}
		if (requirements.length != 1)
			throw 'Runtime decision "${decision.id}" must own one requirement.';
		final authority = new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements, decision.runtimeUseOccurrences);
		final references = decision.runtimeUseOccurrences.map(use -> OcamlExpr.ERuntimeIdent(authority.expressionIdentifier(use.id, use.planRevision,
			use.exactSymbol)));
		authority.reconcileExpression(OcamlExpr.ESeq(references));

		final first = decision.runtimeUseOccurrences[0];
		expectFailure("stale helper", "stale runtime use",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
				decision.runtimeUseOccurrences).expressionIdentifier(first.id, first.planRevision + ":stale", first.exactSymbol));
		expectFailure("wrong symbol", "wrong target symbol",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
				decision.runtimeUseOccurrences).expressionIdentifier(first.id, first.planRevision, first.exactSymbol + "_wrong"));
		expectFailure("missing helper", "missing runtime use",
			() -> new OcamlRuntimeUseAuthority(decision.revision, "portable", requirements,
				decision.runtimeUseOccurrences).reconcileExpression(OcamlExpr.ESeq([])));
		expectFailure("extra helper", "invalid-runtime-use",
			() -> OcamlStdIsOfTypePlan.requireDecision(copyDecision(decision, decision.runtimeUseOccurrences.concat([first]))));

		if (decision.runtimeUseOccurrences.length == 2) {
			final reordered = [decision.runtimeUseOccurrences[1], decision.runtimeUseOccurrences[0]];
			expectFailure("reordered decision", "invalid-runtime-use", () -> OcamlStdIsOfTypePlan.requireDecision(copyDecision(decision, reordered)));
		}
		final wrongOwner = copyOccurrence(first, first.ownerId + ":wrong");
		expectFailure("wrong owner", "invalid-runtime-use",
			() -> OcamlStdIsOfTypePlan.requireDecision(copyDecision(decision, [wrongOwner].concat(decision.runtimeUseOccurrences.slice(1)))));
	}

	static function assertStrategy(decisions:Array<OcamlStdIsOfTypeDecision>, strategy:OcamlStdIsOfTypeStrategy, expected:Int, symbols:Array<String>):Void {
		final selected = decisions.filter(decision -> decision.strategy == strategy);
		if (selected.length != expected)
			throw 'Expected $expected ${(strategy : String)} decisions, received ${selected.length}. All strategies: ${decisions.map(decision -> (decision.strategy : String)).join(",")}.';
		for (decision in selected) {
			final actual = decision.runtimeUseOccurrences.map(use -> use.exactSymbol);
			if (actual.join(",") != symbols.join(","))
				throw '${(strategy : String)} expected ${symbols.join(",")}, received ${actual.join(",")}.';
		}
	}

	static function copyDecision(source:OcamlStdIsOfTypeDecision, runtimeUseOccurrences:Array<OcamlRuntimeUseOccurrence>):OcamlStdIsOfTypeDecision {
		return {
			id: source.id,
			revision: source.revision,
			source: {file: source.source.file, min: source.source.min, max: source.source.max},
			strategy: source.strategy,
			valueCarrier: source.valueCarrier,
			valueSemanticTypeId: source.valueSemanticTypeId,
			requestedTypeSemanticId: source.requestedTypeSemanticId,
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

	static function copyOccurrence(source:OcamlRuntimeUseOccurrence, ownerId:String):OcamlRuntimeUseOccurrence {
		return {
			id: source.id,
			planRevision: source.planRevision,
			ownerId: ownerId,
			requirementId: source.requirementId,
			domain: source.domain,
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
