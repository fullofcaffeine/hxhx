import sys.io.File;

/** Real Map and Array providers own the authored key/value iterator behavior. */
class M14JsKeyValueRuntimeTest {
	public static function run():Void {
		final root = "test/fixtures/js_key_value_iteration";
		final output = JsRuntimeFixture.reserveOutput();
		final configured = Sys.getEnv("HXHX_UPSTREAM_HAXE");
		@:privateAccess M14JsExprEmitterTryCatchIntegrationTest.command(configured == null ? "node_modules/.bin/haxe" : configured,
			["-cp", root, "-main", "Main", "-js", output + "/upstream.js"]);
		@:privateAccess M14JsExprEmitterTryCatchIntegrationTest.command("node", [output + "/upstream.js"]);
		Sys.println("JS_KEY_VALUE_UPSTREAM:PASS");
		final program = JsSourceProgramFixture.build({
			sources: [
				{path: "Main.hx", source: File.getContent(root + "/Main.hx")},
				{path: "Extractors.hx", source: File.getContent(root + "/Extractors.hx")}
			],
			requiredModules: ["Array", "haxe.ds.Map", "haxe.ds.StringMap", "Std"],
			mode: "full"
		});
		JsRuntimeFixture.assertProgramRuntime(program, "Main", "");
		@:privateAccess JsRuntimeFixture.removeOutput(output);
		Sys.println("JS_KEY_VALUE_RUNTIME:PASS");
	}
}
