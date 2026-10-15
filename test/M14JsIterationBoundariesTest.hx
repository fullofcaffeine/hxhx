import sys.io.File;

/** Compare source-owned callbacks in protocol queries and field initializers with upstream. */
class M14JsIterationBoundariesTest {
	public static function run():Void {
		final root = "test/fixtures/js_iteration_boundaries";
		final output = JsRuntimeFixture.reserveOutput();
		@:privateAccess M14JsExprEmitterTryCatchIntegrationTest.command("node_modules/.bin/haxe",
			["-cp", root, "-main", "Main", "-js", output + "/upstream.js"]);
		@:privateAccess M14JsExprEmitterTryCatchIntegrationTest.command("node", [output + "/upstream.js"]);
		Sys.println("JS_ITERATION_BOUNDARIES_UPSTREAM:PASS");
		final path = root + "/Main.hx";
		final module = new ResolvedModule("Main", path, ParserStage.parse(File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		JsRuntimeFixture.assertRuntime(typed, "Main", "");
		@:privateAccess JsRuntimeFixture.removeOutput(output);
		Sys.println("JS_ITERATION_BOUNDARIES_RUNTIME:PASS");
	}

	static function main():Void
		run();
}
