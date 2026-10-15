import sys.io.File;

/** Execute the original local-function behaviors through real typing and control lowering. */
class M14JsStmtTryRuntimeTest {
	public static function run():Void {
		final root = "test/fixtures/js_statement_try";
		final output = JsRuntimeFixture.reserveOutput();
		final configured = Sys.getEnv("HXHX_UPSTREAM_HAXE");
		@:privateAccess M14JsExprEmitterTryCatchIntegrationTest.command(configured == null ? "node_modules/.bin/haxe" : configured,
			["-cp", root, "-main", "Main", "-js", output + "/upstream.js"]);
		@:privateAccess M14JsExprEmitterTryCatchIntegrationTest.command("node", [output + "/upstream.js"]);
		Sys.println("JS_STATEMENT_TRY_UPSTREAM:PASS");
		final program = JsSourceProgramFixture.build({
			sources: [{path: "Main.hx", source: File.getContent(root + "/Main.hx")}],
			requiredModules: ["haxe.io.Eof", "Std"],
			mode: "full"
		});
		JsRuntimeFixture.assertProgramRuntime(program, "Main", "");
		@:privateAccess JsRuntimeFixture.removeOutput(output);
		Sys.println("JS_STATEMENT_TRY_RUNTIME:PASS");
	}
}
