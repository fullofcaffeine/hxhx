import sys.io.File;

/** Compare mutable, escaping iteration captures with upstream without compiler-specific fixture hooks. */
class M14JsIterationCaptureTest {
	public static function run():Void {
		final root = "test/fixtures/js_iteration_captures";
		final output = JsRuntimeFixture.reserveOutput();
		@:privateAccess M14JsExprEmitterTryCatchIntegrationTest.command("haxe", ["-cp", root, "-main", "Main", "-js", output + "/upstream.js"]);
		@:privateAccess M14JsExprEmitterTryCatchIntegrationTest.command("node", [output + "/upstream.js"]);
		Sys.println("JS_ITERATION_CAPTURE_UPSTREAM:PASS");
		final path = root + "/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(File.getContent(path), path));
		final typed = M14Stage3RuntimeFixture.typeResolved({module: resolved, root: root});
		JsRuntimeFixture.assertRuntime(typed, "Main", "");
		@:privateAccess JsRuntimeFixture.removeOutput(output);
		Sys.println("JS_ITERATION_CAPTURE_RUNTIME:PASS");
	}

	static function main():Void
		run();
}
