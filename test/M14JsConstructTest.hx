import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/** Compare allocation, operand order, aliases, and same-name controls with upstream JavaScript. */
class M14JsConstructTest {
	static function main():Void {
		final root = "test/js_construct";
		final source = sys.io.File.getContent(root + "/Main.hx");
		final expected = sys.io.File.getContent(root + "/expected.stdout");
		final output = JsRuntimeFixture.reserveOutput();
		final compiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
		// The direct upstream intrinsic emits `new Main.choose()(argument())`,
		// which constructs the selector instead of its result. Type.createInstance
		// independently establishes the intended once-only operand order. Keep
		// the candidate's effectful construct expression unchanged.
		final reference = output + "/reference";
		sys.FileSystem.createDirectory(reference);
		final effectful = "NativeSyntax.construct(choose(), argument())";
		if (source.indexOf(effectful) < 0 || source.indexOf(effectful) != source.lastIndexOf(effectful))
			throw "construct reference requires one exact effectful allocation";
		sys.io.File.saveContent(reference + "/Main.hx", StringTools.replace(source, effectful, "Type.createInstance(choose(), [argument()])"));
		// Haxe 4.3.7's default spread lowering emits invalid constructor syntax.
		// ES6 supplies an executable upstream contract for this API's spread form.
		run(compiler == null ? "node_modules/.bin/haxe" : compiler, [
			"-cp",
			reference,
			"-main",
			"Main",
			"-D",
			"js-es=6",
			"-js",
			output + "/upstream.js"
		]);
		if (run("node", [output + "/upstream.js"]) != expected)
			throw "upstream construct output differs; retained " + output;
		final args = Stage1Args.parse(["-cp", root, "-main", "Main"], true);
		final paths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: [root],
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: Stage1Args.getStandardLibraryRoot(args),
			targetDefine: "js"
		});
		final module = new ResolvedModule("Main", root + "/Main.hx", ParserStage.parse(source, root + "/Main.hx"));
		final index = TyperIndex.buildHeaders([module]);
		final defines = Stage3SetupSupport.buildDefinesMap(["js-es=6"], "js", "js-native");
		final loader = new ModuleLoader(paths, defines, index, null, false);
		loader.markResolvedAlready([module]);
		final typed = TyperStage.typeResolvedModule(module, index, loader, true);
		final lowered = TypedAbstractOperatorLowering.lowerModules([typed], index);
		final script = output + "/candidate.js";
		new backend.js.JsBackend().emit(MacroStage.expandProgram(lowered, []), new backend.BackendContext(output, script, "Main", true, false, defines));
		if (run("node", [script]) != expected)
			throw "candidate construct output differs; retained " + output;
		Sys.println("JS_CONSTRUCT_RUNTIME:PASS " + output);
	}

	static function run(command:String, arguments:Array<String>):String {
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["60", command].concat(arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0)
			throw "construct observer failed: " + stdout + stderr;
		return stdout;
	}
}
