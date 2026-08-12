import haxe.macro.Context;
import haxe.macro.Expr;
import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlIntUnaryPlan;
import reflaxe.ocaml.lowered.OcamlIntUnaryPlan.OcamlIntUnaryDecision;
import reflaxe.ocaml.lowered.OcamlIntUnaryPlan.OcamlIntUnaryOperation;
import reflaxe.ocaml.lowered.OcamlIntUnaryPlan.OcamlIntUnaryOperandCarrier;
import reflaxe.ocaml.lowered.OcamlIntUnaryPlan.OcamlIntUnaryPlanner;
import reflaxe.ocaml.runtimegen.OcamlRuntimeRequirementLedger;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseAuthority;
import reflaxe.ocaml.runtimegen.OcamlRuntimeUseModel.OcamlRuntimeUseOccurrence;

using StringTools;

/**
	Defines the independent source-level expectation for sealed integer unary work.

	The fixture intentionally names the planned operations and private helpers
	without asking `OcamlBuilder` how it currently prints them. This keeps the
	test useful if target syntax later changes but the Haxe behavior does not.
**/
class IntUnaryRuntimeUseFixture {
	static final binding:OcamlFunctionPlanBinding = {
		functionId: "IntUnaryRuntimeUseFixture.main",
		programRevision: "program:int-unary-runtime-use",
		bodyRevision: "body:int-unary-runtime-use",
		pipelineRevision: "pipeline:int-unary-runtime-use"
	};

	public static macro function run():Expr {
		final typed = Context.typeExpr(macro {
			final exact:Int = 7;
			- exact;
			~exact;
			final nullable:Null<Int> = null;
			- nullable;
			~nullable;
			final nested = () -> -exact;
			nested;
		});

		final plan = new OcamlIntUnaryPlanner(binding).plan(typed);
		final decisions = plan.decisions();
		assertDecision(decisions, OcamlIntUnaryOperation.Negate, OcamlIntUnaryOperandCarrier.ExactInt, ["HxInt.neg"]);
		assertDecision(decisions, OcamlIntUnaryOperation.BitwiseNot, OcamlIntUnaryOperandCarrier.ExactInt, ["HxInt.lognot"]);
		assertDecision(decisions, OcamlIntUnaryOperation.Negate, OcamlIntUnaryOperandCarrier.NullableInt, ["HxInt.neg", "HxRuntime.hx_null"]);
		assertDecision(decisions, OcamlIntUnaryOperation.BitwiseNot, OcamlIntUnaryOperandCarrier.NullableInt, ["HxInt.lognot", "HxRuntime.hx_null"]);
		if (decisions.length != 4)
			throw 'Expected four outer-function integer unary decisions, received ${decisions.length}.';
		for (decision in decisions)
			proveRuntimeUses(decision);
		expectFailure("stale binding", "belongs to another function or target pipeline", () -> plan.requirePlanBinding({
			functionId: binding.functionId,
			programRevision: binding.programRevision,
			bodyRevision: binding.bodyRevision,
			pipelineRevision: binding.pipelineRevision + ":stale"
		}));

		Sys.println("REFLAXE_OCAML_INT_UNARY_RUNTIME_USE:PASS");
		return macro null;
	}

	static function proveRuntimeUses(decision:OcamlIntUnaryDecision):Void {
		OcamlIntUnaryPlan.requireDecision(decision);
		final requirements = OcamlRuntimeRequirementLedger.requirementsForIntUnary(decision);
		if (requirements.length != 1)
			throw 'Integer unary decision "${decision.id}" must own one runtime requirement.';
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
			() -> OcamlIntUnaryPlan.requireDecision(copyDecision(decision, decision.operandCarrier, decision.runtimeUseOccurrences.concat([first]))));
		if (decision.runtimeUseOccurrences.length == 2) {
			final reordered = [decision.runtimeUseOccurrences[1], decision.runtimeUseOccurrences[0]];
			expectFailure("reordered decision", "invalid-runtime-use",
				() -> OcamlIntUnaryPlan.requireDecision(copyDecision(decision, decision.operandCarrier, reordered)));
		}
		final wrongOwner = copyOccurrence(first, first.ownerId + ":wrong");
		expectFailure("wrong owner", "invalid-runtime-use",
			() -> OcamlIntUnaryPlan.requireDecision(copyDecision(decision, decision.operandCarrier,
				[wrongOwner].concat(decision.runtimeUseOccurrences.slice(1)))));
		final wrongCarrier = decision.operandCarrier == OcamlIntUnaryOperandCarrier.ExactInt ? OcamlIntUnaryOperandCarrier.NullableInt : OcamlIntUnaryOperandCarrier.ExactInt;
		expectFailure("wrong conversion", "invalid-runtime-use",
			() -> OcamlIntUnaryPlan.requireDecision(copyDecision(decision, wrongCarrier, decision.runtimeUseOccurrences)));
	}

	static function assertDecision(decisions:Array<OcamlIntUnaryDecision>, operation:OcamlIntUnaryOperation, carrier:OcamlIntUnaryOperandCarrier,
			expectedSymbols:Array<String>):Void {
		final selected = decisions.filter(decision -> decision.operation == operation && decision.operandCarrier == carrier);
		if (selected.length != 1)
			throw 'Expected one ${(operation : String)}/${(carrier : String)} decision, received ${selected.length}.';
		final actualSymbols = selected[0].runtimeUseOccurrences.map(use -> use.exactSymbol);
		if (actualSymbols.join(",") != expectedSymbols.join(","))
			throw '${(operation : String)}/${(carrier : String)} expected ${expectedSymbols.join(",")}, received ${actualSymbols.join(",")}.';
	}

	static function copyDecision(source:OcamlIntUnaryDecision, operandCarrier:OcamlIntUnaryOperandCarrier,
			runtimeUseOccurrences:Array<OcamlRuntimeUseOccurrence>):OcamlIntUnaryDecision {
		return {
			id: source.id,
			revision: source.revision,
			source: {file: source.source.file, min: source.source.min, max: source.source.max},
			operation: source.operation,
			operandCarrier: operandCarrier,
			operandSemanticTypeId: source.operandSemanticTypeId,
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
