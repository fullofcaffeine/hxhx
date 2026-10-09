import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/** Compare ordinary and local-function array iteration with independently compiled upstream behavior. */
class M14JsArrayPairsTest {
	static function main():Void {
		@:privateAccess M14JsStmtEmitterKeyValueForIntegrationTest.pairs();
		final root = "test/fixtures/js_array_pairs";
		final output = JsRuntimeFixture.reserveOutput();
		@:privateAccess M14JsFunctionLiteralRuntimeTest.command("haxe", ["-cp", root, "-main", "Main", "-js", output + "/upstream.js"]);
		@:privateAccess M14JsFunctionLiteralRuntimeTest.command("node", [output + "/upstream.js"]);
		final args = Stage1Args.parse(["-cp", root, "-main", "Main"], true);
		final paths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: [root],
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: Stage1Args.getStandardLibraryRoot(args),
			targetDefine: "js"
		});
		final path = root + "/Main.hx";
		final module = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final index = TyperIndex.buildHeaders([module]);
		final defines = Stage3SetupSupport.buildDefinesMap([], "js", "js-native");
		final loader = new ModuleLoader(paths, defines, index, null, false);
		loader.markResolvedAlready([module]);
		final typed = TyperStage.typeResolvedModule(module, index, loader, true);
		JsRuntimeFixture.assertRuntime(typed, "Main", "");
		@:privateAccess JsRuntimeFixture.removeOutput(output);
		Sys.println("JS_ARRAY_PAIRS:PASS");
	}
}
