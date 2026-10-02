import backend.BackendContext;
import backend.vm.NekoTargetCore;
import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;
import sys.FileSystem;
import sys.io.File;

/** Compares ordinary inherited construction with upstream in both Neko layouts. */
class M14NekoInheritedConstructionIntegrationTest {
	static function run(command:String, arguments:Array<String>):String {
		final process = new sys.io.Process(command, arguments);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0)
			throw command + " failed: " + errors;
		return output;
	}

	static function main():Void {
		exercise("test/neko_inherited_construction", false);
		exercise("test/neko_value_exception_construction", true);
	}

	/** Loads authored source through production target selection and retains both runtime outcomes. */
	static function exercise(fixture:String, requireExceptionProvider:Bool):Void {
		final root = ".tmp/neko_inherited_construction_" + Date.now().getTime();
		FileSystem.createDirectory(root);
		final expected = File.getContent(fixture + "/expected.stdout");
		run("haxe", ["-cp", fixture, "-main", "Main", "-neko", root + "/upstream.n"]);
		final upstream = run("neko", [root + "/upstream.n"]);
		File.saveContent(root + "/upstream.stdout", upstream);
		if (upstream != expected)
			throw "upstream inherited construction changed: " + root;
		Sys.println("UPSTREAM_INHERITED_CONSTRUCTION:PASS artifacts=" + root);

		final arguments = Stage1Args.parse(["-cp", fixture, "-main", "Main"], true);
		if (arguments == null)
			throw "fixture arguments did not parse";
		final paths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: Stage1Args.getExplicitClassPaths(arguments),
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: Stage1Args.getStandardLibraryRoot(arguments),
			targetDefine: "neko"
		});
		final defines = Stage3SetupSupport.buildDefinesMap([], "neko", "neko-native");
		final resolved = ResolverStage.parseProjectRoots(paths, ["Main"], defines);
		final index = TyperIndex.build(resolved);
		final loader = new ModuleLoader(paths, defines, index);
		loader.markResolvedAlready(resolved);
		final pending = resolved.copy();
		final typed = new Array<TypedModule>();
		var cursor = 0;
		var foundExceptionProvider = false;
		while (cursor < pending.length) {
			final module = pending[cursor++];
			if (ResolvedModule.getModulePath(module) == "haxe.Exception") {
				final provider = ResolvedModule.getFilePath(module).split("\\").join("/");
				if (!StringTools.endsWith(provider, "/neko/_std/haxe/Exception.hx"))
					throw "fixture selected the wrong exception provider: " + provider;
				foundExceptionProvider = true;
			}
			typed.push(TyperStage.typeResolvedModule(module, index, loader, true));
			for (loaded in loader.drainNewModules())
				pending.push(loaded);
		}
		if (requireExceptionProvider && !foundExceptionProvider)
			throw "real Neko exception provider was not loaded";
		final program = new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules(typed, index), false);
		final context = new BackendContext(root, root + "/main.n", "Main", true, false, defines);
		final split = @:privateAccess NekoTargetCore.renderSplitProgram(program, context, root + "/main.neko");
		File.saveContent(split.entryPath, split.entrySource);
		for (part in split.support)
			File.saveContent(part.path, part.source);
		File.saveContent(root + "/single.neko", @:privateAccess NekoTargetCore.renderProgram(program, context));
		for (file in FileSystem.readDirectory(root))
			if (StringTools.endsWith(file, ".neko"))
				run("nekoc", [root + "/" + file]);
		var failed = false;
		for (layout in ["main", "single"]) {
			final process = new sys.io.Process("neko", [root + "/" + layout + ".n"]);
			final actual = process.stdout.readAll().toString();
			final errors = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			File.saveContent(root + "/" + layout + ".stdout", actual);
			File.saveContent(root + "/" + layout + ".stderr", errors);
			if (code != 0 || actual != expected) {
				failed = true;
				Sys.println("NEKO_INHERITED_CONSTRUCTION:FAIL layout=" + layout + " exit=" + code);
			} else {
				Sys.println("NEKO_INHERITED_CONSTRUCTION:PASS layout=" + layout);
			}
		}
		if (failed)
			throw "inherited construction differs: " + root;
	}
}
