/** Diagnostic replay reads only results belonging to unchanged occurrences in the same inference owner. */
class M14DiagnosticProbeFactsTest {
	static function rejected(action:() -> Void, expected:String):Void {
		try {
			action();
		} catch (error:haxe.Exception) {
			if (!StringTools.startsWith(error.message, expected))
				throw error;
			return;
		}
		throw "diagnostic probe accepted invalid facts: " + expected;
	}

	public static function run():Void {
		final arguments:Array<HxExpr> = [EInt(1)];
		final source:HxExpr = ECall(EIdent("probe"), arguments);
		final copied:HxExpr = ECall(EIdent("probe"), [EInt(1)]);
		final inference = new TyFunctionInference("Main.first");
		final accepted:TyDiagnosticProbeOutcome = Accepted(TyType.fromHintText("Int"));
		inference.diagnosticProbe(source, () -> accepted);
		final candidate = inference.fork();
		candidate.diagnosticProbe(source, () -> Rejected("private candidate"));
		if (inference.requireDiagnosticProbe(source) != accepted)
			throw "speculative diagnostic changed its parent outcome";
		rejected(() -> {
			new TyFunctionInference("Main.other").requireDiagnosticProbe(source);
		}, "diagnostic probe is absent from function inference:");
		rejected(() -> {
			inference.requireDiagnosticProbe(copied);
		}, "diagnostic probe is absent from function inference:");
		arguments.push(EInt(2));
		rejected(() -> {
			inference.diagnosticProbe(source, () -> accepted);
		}, "diagnostic probe source changed during inference");
		arguments.pop();
		inference.seal([]);
		if (inference.diagnosticProbe(source, () -> {
			throw "sealed replay retyped its input";
		}) != accepted || inference.fork().requireDiagnosticProbe(source) != accepted)
			throw "sealed replay lost the retained diagnostic outcome";
		rejected(() -> {
			inference.diagnosticProbe(copied, () -> accepted);
		}, "diagnostic probe is absent from function inference:");
		arguments.push(EInt(2));
		rejected(() -> {
			inference.requireDiagnosticProbe(source);
		}, "diagnostic probe source changed after inference");
		arguments.pop();
		final failing = new TyFunctionInference("Main.failing");
		rejected(() -> {
			failing.diagnosticProbe(source, () -> {
				throw "internal query failure";
			});
		}, "internal query failure");
		rejected(() -> {
			failing.requireDiagnosticProbe(source);
		}, "diagnostic probe is absent from function inference:");
		Sys.println("DIAGNOSTIC_PROBE_FACTS:PASS");
	}
}
