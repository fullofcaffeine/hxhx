import backend.BackendContext;
import backend.vm.NekoTargetCore;
import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;
import sys.FileSystem;
import sys.io.File;

/** Real standard type checks must use canonical runtime objects and preserve argument evaluation. */
class M14NekoStdIsOfTypeIntegrationTest {
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
		assertFixture("test/neko_std_is_of_type", "NEKO_STD_IS_OF_TYPE");
		assertFixture("test/neko_primitive_runtime_types", "NEKO_PRIMITIVE_RUNTIME_TYPES");
	}

	/** Exercise a standard-library consumer with ordinary roots and both generated layouts. */
	static function assertFixture(fixture:String, marker:String):Void {
		final root = ".tmp/" + fixture.split("/").pop() + "_" + Date.now().getTime();
		FileSystem.createDirectory(root);
		final expected = File.getContent(fixture + "/expected.stdout");
		run("haxe", ["-cp", fixture, "-main", "Main", "-neko", root + "/upstream.n"]);
		if (run("neko", [root + "/upstream.n"]) != expected)
			throw "upstream fixture result changed: " + fixture;

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
		var foundStandardProvider = false;
		while (cursor < pending.length) {
			final module = pending[cursor++];
			if (ResolvedModule.getModulePath(module) == "Std") {
				final provider = ResolvedModule.getFilePath(module).split("\\").join("/");
				if (!StringTools.endsWith(provider, "/neko/_std/Std.hx"))
					throw "fixture selected the wrong Std provider: " + provider;
				foundStandardProvider = true;
			}
			typed.push(TyperStage.typeResolvedModule(module, index, loader, true));
			for (loaded in loader.drainNewModules())
				pending.push(loaded);
		}
		if (!foundStandardProvider)
			throw "real Neko Std provider was not loaded";
		final program = new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules(typed, index), false);
		final context = new BackendContext(root, root + "/main.n", "Main", true, false, defines);
		final split = @:privateAccess NekoTargetCore.renderSplitProgram(program, context, root + "/main.neko");
		File.saveContent(split.entryPath, split.entrySource);
		for (part in split.support)
			File.saveContent(part.path, part.source);
		final single = @:privateAccess NekoTargetCore.renderProgram(program, context);
		File.saveContent(root + "/single.neko", single);
		for (file in FileSystem.readDirectory(root))
			if (StringTools.endsWith(file, ".neko"))
				run("nekoc", [root + "/" + file]);
		for (layout in ["main", "single"]) {
			final actual = run("neko", [root + "/" + layout + ".n"]);
			File.saveContent(root + "/" + layout + ".stdout", actual);
			if (actual != expected)
				throw fixture + " differs in " + layout + ": " + root;
			Sys.println(marker + ":PASS layout=" + layout);
		}
	}
}
