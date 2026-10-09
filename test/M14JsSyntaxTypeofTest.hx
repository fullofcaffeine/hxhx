import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/** Real-provider integration for JavaScript typeof; the executable fixture asserts its observable contract. */
class M14JsSyntaxTypeofTest {
	static function command(executable:String, arguments:Array<String>):Void {
		final child = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", executable].concat(arguments));
		final stdout = child.stdout.readAll().toString();
		final stderr = child.stderr.readAll().toString();
		final code = child.exitCode();
		child.close();
		if (code != 0 || stdout != "" || stderr != "")
			throw "typeof observer failed: " + executable + ": " + code + "\n" + stdout + stderr;
	}

	static function main():Void {
		final root = "test/fixtures/js_syntax_typeof";
		final output = JsRuntimeFixture.reserveOutput();
		command("node_modules/.bin/haxe", ["-cp", root, "-main", "Main", "-js", output + "/upstream.js"]);
		command("node", [output + "/upstream.js"]);
		sys.FileSystem.deleteFile(output + "/upstream.js");
		sys.FileSystem.deleteDirectory(output);
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
			throw "typeof fixture requires one main module";
		final typed = TyperStage.typeResolvedModule(main[0], index, loader);
		JsRuntimeFixture.assertRuntime(typed, "Main", "");
		Sys.println("JS_SYNTAX_TYPEOF:PASS");
	}
}
