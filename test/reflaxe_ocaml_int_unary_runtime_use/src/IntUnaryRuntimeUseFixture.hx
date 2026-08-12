import haxe.macro.Context;
import haxe.macro.Expr;
import reflaxe.ocaml.lowered.OcamlFunctionPlanBinding;
import reflaxe.ocaml.lowered.OcamlIntUnaryPlan;
import reflaxe.ocaml.lowered.OcamlIntUnaryPlan.OcamlIntUnaryDecision;
import reflaxe.ocaml.lowered.OcamlIntUnaryPlan.OcamlIntUnaryOperation;
import reflaxe.ocaml.lowered.OcamlIntUnaryPlan.OcamlIntUnaryOperandCarrier;
import reflaxe.ocaml.lowered.OcamlIntUnaryPlan.OcamlIntUnaryPlanner;

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

		final decisions = new OcamlIntUnaryPlanner(binding).plan(typed).decisions();
		assertDecision(decisions, OcamlIntUnaryOperation.Negate, OcamlIntUnaryOperandCarrier.ExactInt, ["HxInt.neg"]);
		assertDecision(decisions, OcamlIntUnaryOperation.BitwiseNot, OcamlIntUnaryOperandCarrier.ExactInt, ["HxInt.lognot"]);
		assertDecision(decisions, OcamlIntUnaryOperation.Negate, OcamlIntUnaryOperandCarrier.NullableInt, ["HxRuntime.hx_null", "HxInt.neg"]);
		assertDecision(decisions, OcamlIntUnaryOperation.BitwiseNot, OcamlIntUnaryOperandCarrier.NullableInt, ["HxRuntime.hx_null", "HxInt.lognot"]);
		if (decisions.length != 4)
			throw 'Expected four outer-function integer unary decisions, received ${decisions.length}.';

		Sys.println("REFLAXE_OCAML_INT_UNARY_RUNTIME_USE:PASS");
		return macro null;
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
}
