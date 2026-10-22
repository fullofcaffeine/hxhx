import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/** Compare discarded and consumed block results with upstream, then execute native OCaml control. */
class M14DiscardedControlTest {
	static function main():Void {
		exercise("js_discarded_syntax", true);
		exercise("discarded_control", false);
	}

	/** Load real declarations and keep target syntax confined to the JavaScript-only fixture. */
	static function exercise(name:String, syntax:Bool):Void {
		final fixture = "test/fixtures/" + name;
		final output = ".tmp/" + name;
		sys.FileSystem.createDirectory(output);
		final expected = sys.io.File.getContent(fixture + "/expected.stdout");
		if (syntax) {
			run("node_modules/.bin/haxe", ["-cp", fixture, "-main", "Main", "-js", output + "/upstream.js"]);
			assertOutput("node", [output + "/upstream.js"], expected);
		} else {
			assertOutput("node_modules/.bin/haxe", ["-cp", fixture, "--run", "Main"], expected);
		}
		Sys.println("DISCARDED_CONTROL_UPSTREAM:PASS " + name);
		final args = Stage1Args.parse(["-cp", fixture, "-main", "Main"], true);
		final target = syntax ? "js" : "ocaml";
		final paths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: Stage1Args.getExplicitClassPaths(args),
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: Stage1Args.getStandardLibraryRoot(args),
			targetDefine: target
		});
		final defines = Stage3SetupSupport.buildDefinesMap([], target, target + "-native");
		final modules = ResolverStage.parseProjectRoots(paths, ["Main"], defines);
		final index = TyperIndex.buildHeaders(modules);
		final loader = new ModuleLoader(paths, defines, index, null, true);
		loader.markResolvedAlready(modules);
		if (syntax && loader.ensureTypeAvailable("js.Syntax", "", []) == null)
			throw "missing real js.Syntax declaration";
		final mains = modules.filter(module -> ResolvedModule.getModulePath(module) == "Main");
		if (mains.length != 1)
			throw "discard fixture requires one Main";
		final typed = TyperStage.typeResolvedModule(mains[0], index, loader, true);
		final revision = CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity();
		for (owner in typed.getTypedClasses())
			for (fn in owner.getFunctions()) {
				final lowered = TypedControlLowering.functionBody(fn);
				if (CompilerTypedTreeRevision.functionBody(lowered) != CompilerTypedTreeRevision.functionBody(TypedControlLowering.functionBody(lowered)))
					throw "discard lowering changed on repeated application";
			}
		JsRuntimeFixture.assertRuntime(typed, "Main", expected);
		Sys.println("DISCARDED_CONTROL_JS:PASS " + name);
		if (!syntax) {
			final executable = EmitterStage.emitToDir(MacroStage.expandProgram([typed], []), output + "/native", true);
			assertOutput(executable, [], expected);
			Sys.println("DISCARDED_CONTROL_NATIVE:PASS");
		}
		if (CompilerTypedModuleRevision.fromTypedModule(typed).getCanonicalIdentity() != revision)
			throw "discard lowering or emission changed typed source";
	}

	static function assertOutput(command:String, args:Array<String>, expected:String):Void {
		final actual = run(command, args);
		if (actual != expected)
			throw "discarded control output differs: " + actual;
	}

	/** Bound each runtime observer and retain its diagnostic if compilation or execution fails. */
	static function run(command:String, args:Array<String>):String {
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["90", command].concat(args));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0)
			throw "discarded control observer failed: " + stdout + stderr;
		return stdout;
	}
}
