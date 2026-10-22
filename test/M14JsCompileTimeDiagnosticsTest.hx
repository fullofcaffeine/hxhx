import sys.io.File;

/** Compare diagnostic values with real upstream macros, then execute the typed JavaScript result. */
class M14JsCompileTimeDiagnosticsTest {
	public static function run():Void {
		M14DiagnosticProbeFactsTest.run();
		final root = "test/fixtures/js_compile_time_diagnostics";
		final output = JsRuntimeFixture.reserveOutput();
		final configured = Sys.getEnv("HXHX_UPSTREAM_HAXE");
		@:privateAccess M14JsExprEmitterTryCatchIntegrationTest.command(configured == null ? "node_modules/.bin/haxe" : configured,
			["-cp", root, "-main", "Main", "-js", output + "/upstream.js"]);
		@:privateAccess M14JsExprEmitterTryCatchIntegrationTest.command("node", [output + "/upstream.js"]);
		Sys.println("JS_COMPILE_TIME_DIAGNOSTICS_UPSTREAM:PASS");
		final path = root + "/Main.hx";
		final module = new ResolvedModule("Main", path, ParserStage.parse(File.getContent(path), path));
		final previousStrict = Sys.getEnv("HXHX_TYPER_STRICT");
		Sys.putEnv("HXHX_TYPER_STRICT", "1");
		final typed = try {
			TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		} catch (error:haxe.Exception) {
			Sys.putEnv("HXHX_TYPER_STRICT", previousStrict);
			throw error;
		}
		Sys.putEnv("HXHX_TYPER_STRICT", previousStrict);
		JsRuntimeFixture.assertRuntime(typed, "Main", "");
		@:privateAccess JsRuntimeFixture.removeOutput(output);
		Sys.println("JS_COMPILE_TIME_DIAGNOSTICS_RUNTIME:PASS");
	}

	static function main():Void {
		run();
	}
}
