/** Retain actual Type and EnumValueMap bodies so synthetic runtime helpers cannot mask a layout mismatch. */
class M14JsEnumProviderTest {
	static function main():Void {
		final fixture = "test/js_enum_provider";
		final expected = "JS_ENUM_PROVIDER:PASS\n";
		final output = JsRuntimeFixture.reserveOutput();
		final compiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
		@:privateAccess M14NekoTypedProgramProjectionIntegrationTest.run(compiler == null ? "node_modules/.bin/haxe" : compiler,
			["-cp", fixture, "-main", "Main", "-js", output + "/upstream.js"]);
		if (@:privateAccess M14NekoTypedProgramProjectionIntegrationTest.run("node", [output + "/upstream.js"]) != expected)
			throw "upstream enum provider contract changed: " + output;
		Sys.println("JS_ENUM_PROVIDER_UPSTREAM:PASS");
		final program = JsSourceProgramFixture.build({
			sources: [{path: "Main.hx", source: sys.io.File.getContent(fixture + "/Main.hx")}],
			requiredModules: ["Type", "haxe.ds.EnumValueMap"]
		});
		final script = output + "/candidate.js";
		new backend.js.JsBackend().emit(program, new backend.BackendContext(output, script, "Main", true, false, HxDefineMap.fromRawDefines(["js=1"])));
		if (@:privateAccess M14NekoTypedProgramProjectionIntegrationTest.run("node", [script]) != expected)
			throw "candidate enum provider contract changed: " + output;
		Sys.println("JS_ENUM_PROVIDER:PASS " + output);
	}
}
