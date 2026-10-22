/** Compare the original quotation cases using actual enum values from the public macro declarations. */
class M14JsMacroQuotationRuntimeTest {
	public static function run():Void {
		final root = "test/fixtures/js_macro_quotation";
		final output = JsRuntimeFixture.reserveOutput();
		final configured = Sys.getEnv("HXHX_UPSTREAM_HAXE");
		@:privateAccess M14JsFunctionLiteralRuntimeTest.command(configured == null ? "node_modules/.bin/haxe" : configured, [
			"-cp",
			root,
			"-cp",
			root + "/support",
			"-main",
			"Main",
			"-js",
			output + "/upstream.js"
		]);
		@:privateAccess M14JsFunctionLiteralRuntimeTest.command("node", ["--use-strict", output + "/upstream.js"]);
		@:privateAccess JsRuntimeFixture.removeOutput(output);
		Sys.println("JS_MACRO_QUOTATION_UPSTREAM:PASS");
		final program = JsSourceProgramFixture.build({
			sources: [
				{path: "Main.hx", source: sys.io.File.getContent(root + "/Main.hx")},
				{path: "QuotationCases.hx", source: sys.io.File.getContent(root + "/support/QuotationCases.hx")}
			],
			requiredModules: ["haxe.macro.Expr"],
			mode: "full"
		});
		JsRuntimeFixture.assertProgramRuntime(program, "Main", "", ["--use-strict"]);
		Sys.println("JS_MACRO_QUOTATION_RUNTIME:PASS");
	}

	static function main():Void {
		run();
	}
}
