import reflaxe.ocaml.ast.OcamlExpr;
import reflaxe.ocaml.runtimegen.OcamlFinalRuntimeUseAuthority;
import reflaxe.ocaml.target.OcamlTargetExpressionFact;
import reflaxe.ocaml.target.OcamlTargetExpressionLowerer;
import reflaxe.ocaml.target.OcamlTargetLiteralFact;

/** Reject malformed conversions and prove that runtime ownership survives final output. */
class NullableValuesValidation {
	public static function check():Void {
		final integer = OcamlTargetExpressionFact.literalExpression("root/operand", OcamlTargetLiteralFact.intLiteral(0, "Int"));
		final nullValue = OcamlTargetExpressionFact.nullableIntNull("root/operand");
		reject(() -> OcamlTargetExpressionFact.boxNullableInt("root", nullValue), "exact operand path and types");
		reject(() -> OcamlTargetExpressionFact.unwrapNullableInt("root", integer), "exact operand path and types");
		reject(() -> OcamlTargetExpressionFact.testNullableIntNull("root", integer), "exact operand path and types");
		reject(() -> OcamlTargetExpressionFact.boxNullableInt("root/other", integer), "exact operand path and types");
		final finalUses = new OcamlFinalRuntimeUseAuthority();
		finalUses.beginProgram("nullable-validation", "portable");
		final lowered = OcamlTargetExpressionLowerer.lower(OcamlTargetExpressionFact.unwrapNullableInt("root", nullValue), "nullable-validation:owner",
			"portable", finalUses);
		if (lowered.runtimeRequirements.length != 2)
			throw "Both the null producer and checked unwrap require runtime ownership";
		finalUses.observeExpression(lowered.expression, "Observer.ml");
		finalUses.finishProgram();
		final missing = new OcamlFinalRuntimeUseAuthority();
		missing.beginProgram("nullable-validation", "portable");
		OcamlTargetExpressionLowerer.lower(OcamlTargetExpressionFact.nullableIntNull("root"), "nullable-validation:missing", "portable", missing);
		reject(() -> missing.finishProgram(), "missing final runtime use");
		final unowned = new reflaxe.ocaml.target.OcamlTargetRuntimePlan("nullable-validation:raw", nullValue.getCanonicalIdentity(), [nullValue], "portable");
		reject(() -> unowned.reconcile(OcamlExpr.EIdent("HxRuntime.hx_null")), "plain private runtime reference");
	}

	public static function reject(action:() -> Void, expected:String):Void {
		try {
			action();
		} catch (error:haxe.Exception) {
			if (error.message.indexOf(expected) >= 0)
				return;
			throw error;
		}
		throw "Expected nullable rejection: " + expected;
	}
}
