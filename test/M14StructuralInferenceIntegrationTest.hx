import sys.io.File;

/** Compare generic nested-record results with upstream and execute their published JavaScript types. */
class M14StructuralInferenceIntegrationTest {
	static function main():Void {
		final fixture = "test/fixtures/structural_inference";
		final expected = "ok\nok\n7\n7\ntrue\n";
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout",
			["30", "node_modules/.bin/haxe", "-cp", fixture, "--run", "Main"]);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || output != expected)
			throw "upstream nested record inference differs: " + output + errors;
		final module = new ResolvedModule("Main", "Main.hx", ParserStage.parse(File.getContent(fixture + "/Main.hx"), "Main.hx"));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		final main = typed.getTypedClasses()[0].getFunctions().filter(fn -> fn.getDeclaration().getSignature().getName() == "main")[0];
		final statements = main.getBody().getStatements();
		for (index in 0...2) {
			final type = statements[index].getLocalBindings()[0].getType();
			final fields = type.getAnonymousFieldTypes();
			final key = index == 0 ? "primitive:String" : "primitive:Int";
			if (!type.isAnonymous()
				|| fields.length != 2
				|| fields[0].getSemanticKey() != key
				|| fields[1].getAnonymousFieldTypes()[0].getSemanticKey() != key)
				throw "nested record publication lost a concrete generic result: " + type.getSemanticKey();
		}
		final contextual = statements[2].getExpressions()[0].getType();
		if (contextual.getAnonymousFieldTypes()[0].unwrapNull().getSemanticKey() != "primitive:String")
			throw "expected record context did not solve the call result: " + contextual.getSemanticKey();
		JsRuntimeFixture.assertRuntime(typed, "Main", expected);
		Sys.println("STRUCTURAL_INFERENCE_INTEGRATION:PASS");
	}
}
