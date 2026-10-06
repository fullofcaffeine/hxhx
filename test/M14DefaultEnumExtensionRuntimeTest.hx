import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;
import backend.BackendContext;
import backend.js.JsBackend;

/** Execute enum helpers only after typing their authentic standard-library dependency closure. */
class M14DefaultEnumExtensionRuntimeTest {
	static function main():Void {
		final root = "test/oracle/default_enum_extension_seed";
		final expected = sys.io.File.getContent(root + "/expected.stdout");
		final compiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
		final upstream = new sys.io.Process(compiler == null ? "node_modules/.bin/haxe" : compiler, ["-cp", root, "-main", "Main", "--interp"]);
		final output = upstream.stdout.readAll().toString();
		final errors = upstream.stderr.readAll().toString();
		final code = upstream.exitCode();
		upstream.close();
		if (code != 0 || errors.length != 0 || !StringTools.endsWith(output, ": " + expected))
			throw "upstream enum helpers differ: " + output + errors;
		Sys.println("DEFAULT_ENUM_EXTENSION_UPSTREAM:PASS");
		final args = Stage1Args.parse(["-cp", root, "-main", "Main"], true);
		final paths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: [root],
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: Stage1Args.getStandardLibraryRoot(args),
			targetDefine: "js"
		});
		final defines = Stage3SetupSupport.buildDefinesMap(["js-es=5"], "js", "js-native");
		final resolved = ResolverStage.parseProjectRoots(paths, ["Main"], defines);
		final index = TyperIndex.buildHeaders(resolved);
		final loader = new ModuleLoader(paths, defines, index);
		loader.markResolvedAlready(resolved);
		final pending = resolved.copy();
		final typed = new Array<TypedModule>();
		var cursor = 0;
		var provider = false;
		while (cursor < pending.length) {
			final module = pending[cursor++];
			if (ResolvedModule.getModulePath(module) == "haxe.EnumTools")
				provider = true;
			typed.push(TyperStage.typeResolvedModule(module, index, loader, true));
			for (loaded in loader.drainNewModules())
				pending.push(loaded);
		}
		if (!provider)
			throw "authentic enum provider was not loaded";
		final outputRoot = ".tmp/default-enum-extension-runtime";
		final script = outputRoot + "/main.js";
		new JsBackend().emit(MacroStage.expandProgram(typed, []), new BackendContext(outputRoot, script, "Main", true, false, defines));
		final child = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["60", "node", script]);
		final stdout = child.stdout.readAll().toString();
		final stderr = child.stderr.readAll().toString();
		final status = child.exitCode();
		child.close();
		if (status != 0 || stdout != expected || stderr.length != 0)
			throw "enum helper runtime differs: " + stdout + stderr;
		Sys.println("DEFAULT_ENUM_EXTENSION_RUNTIME:PASS");
	}
}
