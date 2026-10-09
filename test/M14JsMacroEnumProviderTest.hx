/** Compare reflected macro quotations with upstream while retaining authentic macro enum declarations. */
class M14JsMacroEnumProviderTest {
	static function main():Void {
		final fixture = "test/js_macro_enum_provider";
		final expected = "EField\n3\nSafe\nCInt\nOpAssignOp\nTFunction\n2\n";
		final output = JsRuntimeFixture.reserveOutput();
		final compiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
		for (mode in ["full", "std", "no"]) {
			final script = output + "/upstream-" + mode + ".js";
			@:privateAccess M14NekoTypedProgramProjectionIntegrationTest.run(compiler == null ? "node_modules/.bin/haxe" : compiler,
				["-cp", fixture, "-main", "Main", "-dce", mode, "-js", script]);
			if (@:privateAccess M14NekoTypedProgramProjectionIntegrationTest.run("node", [script]) != expected)
				throw "upstream macro enum contract changed: " + output;
			Sys.println("JS_MACRO_ENUM_PROVIDER_UPSTREAM:" + mode + ":PASS");
		}
		final loaded = JsSourceProgramFixture.load({
			sources: [{path: "Main.hx", source: sys.io.File.getContent(fixture + "/Main.hx")}],
			requiredModules: ["Type", "haxe.macro.Expr"]
		});
		for (mode in ["full", "std", "no"]) {
			final program = JsSourceProgramFixture.retain(loaded, mode);
			final script = output + "/candidate-" + mode + ".js";
			new backend.js.JsBackend().emit(program, new backend.BackendContext(output, script, "Main", true, false, HxDefineMap.fromRawDefines(["js=1"])));
			if (@:privateAccess M14NekoTypedProgramProjectionIntegrationTest.run("node", [script]) != expected)
				throw "candidate macro enum contract changed: " + mode + " " + output;
			Sys.println("JS_MACRO_ENUM_PROVIDER:" + mode + ":PASS");
		}
		Sys.println("JS_MACRO_ENUM_PROVIDER:PASS " + output);
	}
}
