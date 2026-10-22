import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/** Compare escaped native captures with an independent upstream execution. */
class M14NativeClosureCaptureTest {
	static function main():Void {
		final root = "test/fixtures/native_closure_capture";
		final expected = "11\n13\n101\n16\n16\n101\n21\n22\n21\n13\n23\n17\n23\n101\n7\n7\n7\n9\n10\n";
		if (run("node_modules/.bin/haxe", ["-cp", root, "--run", "Main"]) != expected)
			throw "upstream closure capture contract differs";
		final path = root + "/Main.hx";
		final module = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		JsRuntimeFixture.assertRuntime(typed, "Main", expected);
		final output = ".tmp/native_closure_capture_" + Date.now().getTime();
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([typed], []), output, true);
		final observed = run(executable, []);
		if (observed != expected)
			throw "native closure capture differs; retained " + output + "\n" + observed;
		Sys.println("NATIVE_CLOSURE_CAPTURE:PASS artifacts=" + output);
		completeControl();
	}

	/** Load real String declarations, then prove the complete existing Main control fixture. */
	static function completeControl():Void {
		final root = "test/fixtures/js_control_region";
		final expected = "22\n20\n7\n4\n2\n3\n50\n30\n2\n11\n8\n13\n";
		if (run("node_modules/.bin/haxe", ["-cp", root, "--run", "Main"]) != expected)
			throw "upstream complete control contract differs";
		final args = Stage1Args.parse(["-cp", root, "-main", "Main"], true);
		if (args == null)
			throw "control fixture arguments did not parse";
		final paths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: Stage1Args.getExplicitClassPaths(args),
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: Stage1Args.getStandardLibraryRoot(args),
			targetDefine: "ocaml"
		});
		final defines = Stage3SetupSupport.buildDefinesMap([], "ocaml", "ocaml-native");
		final resolved = ResolverStage.parseProjectRoots(paths, ["Main"], defines);
		final index = TyperIndex.buildHeaders(resolved);
		final loader = new ModuleLoader(paths, defines, index);
		loader.markResolvedAlready(resolved);
		final mains = resolved.filter(module -> ResolvedModule.getModulePath(module) == "Main");
		if (mains.length != 1)
			throw "control fixture requires exactly one Main";
		// This regression executes Main against native runtime support. It does not
		// claim that every loaded standard-library module has been compiled or run.
		final typed = TyperStage.typeResolvedModule(mains[0], index, loader);
		final output = ".tmp/native_complete_control_" + Date.now().getTime();
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([typed], []), output, true);
		if (run(executable, []) != expected)
			throw "native complete control differs; retained " + output;
		Sys.println("NATIVE_COMPLETE_CONTROL:PASS artifacts=" + output);
	}

	static function run(command:String, arguments:Array<String>):String {
		final process = new sys.io.Process(command, arguments);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0)
			throw "closure capture command failed: " + stderr;
		return stdout;
	}
}
