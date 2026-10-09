import backend.BackendContext;
import backend.vm.NekoTargetCore;
import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;
import sys.FileSystem;
import sys.io.File;

/** Shared upstream and native Neko observer using production provider resolution. */
private function run(command:String, arguments:Array<String>):String {
	final process = new sys.io.Process(command, arguments);
	final output = process.stdout.readAll().toString();
	final errors = process.stderr.readAll().toString();
	final code = process.exitCode();
	process.close();
	if (code != 0)
		throw command + " failed: " + errors;
	return output;
}

/** Loads authored source through production target selection and retains both runtime outcomes. */
function exercise(fixture:String, requireExceptionProvider:Bool, upstreamNeko:Bool = true, ?roots:Array<String>, ?runtimeVariants:Array<String>):Void {
	// Report phase boundaries so a slow full-provider check identifies its active work.
	var phaseStarted = haxe.Timer.stamp();
	function completed(phase:String):Void {
		final now = haxe.Timer.stamp();
		Sys.println("NEKO_FIXTURE_PHASE fixture=" + fixture + " completed=" + phase + " elapsedSeconds=" + (now - phaseStarted));
		phaseStarted = now;
	}
	final root = ".tmp/neko_runtime_fixture_" + fixture.split("/").pop() + "_" + Date.now().getTime();
	FileSystem.createDirectory(root);
	final snapshots = [File.getContent(fixture + "/expected.stdout")];
	if (runtimeVariants != null)
		for (variant in runtimeVariants)
			snapshots.push(File.getContent(fixture + "/" + variant));
	final upstream = if (upstreamNeko) {
		run("haxe", ["-cp", fixture, "-main", "Main", "-neko", root + "/upstream.n"]);
		run("neko", [root + "/upstream.n"]);
	} else {
		run("haxe", ["-cp", fixture, "-main", "Main", "--interp"]);
	};
	File.saveContent(root + "/upstream.stdout", upstream);
	// Admit recorded upstream results, then require this runtime's exact result in both generated layouts.
	if (!snapshots.contains(upstream))
		throw "upstream fixture output changed: " + root + "\n" + upstream;
	Sys.println("UPSTREAM_NEKO_FIXTURE:PASS fixture=" + fixture + " artifacts=" + root);
	completed("upstream;next=resolve");

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
	final resolved = ResolverStage.parseProjectRoots(paths, roots == null ? ["Main"] : roots, defines);
	completed("resolve;next=type");
	// Match production: publish signatures only after the loader discovers their
	// declaration dependencies, including implicit exception carrier types.
	final index = TyperIndex.buildHeaders(resolved);
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
	completed("type;next=lower");
	final program = new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules(typed, index), false);
	completed("lower;next=render-split");
	final context = new BackendContext(root, root + "/main.n", "Main", true, false, defines);
	final split = @:privateAccess NekoTargetCore.renderSplitProgram(program, context, root + "/main.neko");
	File.saveContent(split.entryPath, split.entrySource);
	for (part in split.support)
		File.saveContent(part.path, part.source);
	completed("render-split;next=render-single");
	File.saveContent(root + "/single.neko", @:privateAccess NekoTargetCore.renderProgram(program, context));
	completed("render-single;next=compile-native");
	for (file in FileSystem.readDirectory(root))
		if (StringTools.endsWith(file, ".neko")) {
			if (File.getContent(root + "/" + file).indexOf("must-stay-unused") >= 0)
				throw "unused abstract helper became reachable in " + root + "/" + file;
			run("nekoc", [root + "/" + file]);
		}
	completed("compile-native;next=execute");
	var failed = false;
	for (layout in ["main", "single"]) {
		final process = new sys.io.Process("neko", [root + "/" + layout + ".n"]);
		final actual = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		File.saveContent(root + "/" + layout + ".stdout", actual);
		File.saveContent(root + "/" + layout + ".stderr", errors);
		if (code != 0 || actual != upstream) {
			failed = true;
			Sys.println("NEKO_RUNTIME_FIXTURE:FAIL fixture=" + fixture + " layout=" + layout + " exit=" + code);
		} else {
			Sys.println("NEKO_RUNTIME_FIXTURE:PASS fixture=" + fixture + " layout=" + layout);
		}
	}
	completed("execute");
	if (failed)
		throw "Neko fixture output differs: " + root;
}
