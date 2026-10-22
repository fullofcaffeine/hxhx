/** Prove Map collection syntax against upstream and the real provider graph under every retention mode. */
class M14JsMapProviderTest {
	static function main():Void {
		final fixture = "test/js_map_provider";
		final output = JsRuntimeFixture.reserveOutput();
		final configured = Sys.getEnv("HXHX_UPSTREAM_HAXE");
		@:privateAccess M14JsFunctionLiteralRuntimeTest.command(configured == null ? "node_modules/.bin/haxe" : configured,
			["-cp", fixture, "-main", "Main", "-js", output + "/upstream.js"]);
		@:privateAccess M14JsFunctionLiteralRuntimeTest.command("node", ["--use-strict", output + "/upstream.js"]);
		Sys.println("JS_MAP_PROVIDER_UPSTREAM:PASS");
		final loaded = JsSourceProgramFixture.load({
			sources: [{path: "Main.hx", source: sys.io.File.getContent(fixture + "/Main.hx")}],
			requiredModules: [
				"haxe.ds.Map",
				"haxe.ds.StringMap",
				"haxe.ds.IntMap",
				"haxe.ds.ObjectMap",
				"haxe.ds.EnumValueMap"
			]
		});
		for (mode in ["full", "std", "no"]) {
			JsRuntimeFixture.assertProgramRuntime(JsSourceProgramFixture.retain(loaded, mode), "Main", "", ["--use-strict"]);
			Sys.println("JS_MAP_PROVIDER_RUNTIME:PASS " + mode);
		}
		sys.FileSystem.deleteFile(output + "/upstream.js");
		sys.FileSystem.deleteDirectory(output);
	}
}
