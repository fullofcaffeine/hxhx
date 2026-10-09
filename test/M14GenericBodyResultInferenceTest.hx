/** An omitted result annotation must use body inference, not a generic parameter variable. */
class M14GenericBodyResultInferenceTest {
	static function main():Void {
		final fixture = "test/generic_body_result";
		final source = sys.io.File.getContent(fixture + "/Main.hx");
		final expected = sys.io.File.getContent(fixture + "/expected.stdout");
		final upstream = @:privateAccess M14NekoTypedProgramProjectionIntegrationTest.run("haxe", ["-cp", fixture, "-main", "Main", "--interp"]);
		if (upstream != expected)
			throw "upstream body-inferred result contract changed";
		final parsed = ParserStage.parse(source, "Main.hx");
		final resolved = new ResolvedModule("Main", "Main.hx", parsed);
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final calls = new haxe.ds.StringMap<String>();
		function inspect(expression:TypedExpr):Void {
			final declaration = expression.getDeclaration();
			if (expression.getTag() == Call && declaration != null)
				calls.set(declaration.getSignature().getName(), expression.getType().getSemanticKey());
			for (child in expression.getExpressions())
				inspect(child);
		}
		for (owner in typed.getTypedClasses())
			for (fn in owner.getFunctions())
				if (fn.getDeclaration().getSignature().getName() == "main")
					for (statement in fn.getBody().getStatements())
						for (expression in statement.getExpressions())
							inspect(expression);
		if (calls.get("consume") != "primitive:Void" || calls.get("answer") != "primitive:Int")
			throw "generic call lost its body-inferred result";
		JsRuntimeFixture.assertRuntime(typed, "Main", expected);
		Sys.println("GENERIC_BODY_RESULT_INFERENCE:PASS");
	}
}
