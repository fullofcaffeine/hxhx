import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/** Observe authored startup scope against upstream using the actual JavaScript syntax provider. */
class M14JsClassInitializationScopeTest {
	static function main():Void {
		final root = "test/fixtures/js_class_initialization_scope";
		final output = JsRuntimeFixture.reserveOutput();
		@:privateAccess M14JsFunctionLiteralRuntimeTest.command("haxe", ["-cp", root, "-main", "Main", "-js", output + "/upstream.js"]);
		@:privateAccess M14JsFunctionLiteralRuntimeTest.command("node", [output + "/upstream.js"]);
		Sys.println("JS_CLASS_INITIALIZATION_SCOPE:upstream:PASS");
		final arguments = Stage1Args.parse(["-cp", root, "-main", "Main"], true);
		final paths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: Stage1Args.getExplicitClassPaths(arguments),
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: Stage1Args.getStandardLibraryRoot(arguments),
			targetDefine: "js"
		});
		final defines = Stage3SetupSupport.buildDefinesMap([], "js", "js-native");
		final modules = ResolverStage.parseProjectRootsShallow(paths, ["Main", "js.Syntax"], defines);
		final index = TyperIndex.buildHeaders(modules);
		final loader = new ModuleLoader(paths, defines, index, null, false);
		loader.markResolvedAlready(modules);
		final main = modules.filter(module -> ResolvedModule.getModulePath(module) == "Main");
		if (main.length != 1)
			throw "startup scope requires one main module";
		JsRuntimeFixture.assertRuntime(TyperStage.typeResolvedModule(main[0], index, loader), "Main", "");
		@:privateAccess JsRuntimeFixture.removeOutput(output);
		Sys.println("JS_CLASS_INITIALIZATION_SCOPE:PASS");
	}
}
