import backend.BackendContext;
import backend.js.JsBackend;
import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/** Compare host selection, repeat loads, and inactive UID effects with upstream JavaScript. */
class M14JsGlobalStartupTest {
	static function main():Void {
		final root = "test/fixtures/js_global_startup";
		final output = JsRuntimeFixture.reserveOutput();
		for (uid in [false, true]) {
			final mode = uid ? "uid" : "idle";
			final args = Stage1Args.parse(["-cp", root, "-main", "Main"], true);
			final paths = Stage3SetupSupport.projectClassPaths({
				explicitPaths: Stage1Args.getExplicitClassPaths(args),
				libraries: [],
				cwd: Sys.getCwd(),
				standardRoot: Stage1Args.getStandardLibraryRoot(args),
				targetDefine: "js"
			});
			final raw = uid ? ["uid"] : [];
			final defines = Stage3SetupSupport.buildDefinesMap(raw, "js", "js-native");
			final modules = ResolverStage.parseProjectRootsShallow(paths, ["Main", "js.Syntax"], defines);
			final index = TyperIndex.buildHeaders(modules);
			final loader = new ModuleLoader(paths, defines, index, null, false);
			loader.markResolvedAlready(modules);
			final main = modules.filter(module -> ResolvedModule.getModulePath(module) == "Main");
			if (main.length != 1)
				throw "global fixture requires one main";
			final program = MacroStage.expandProgram([TyperStage.typeResolvedModule(main[0], index, loader)], []);
			// This reduced program has no unused functions; the real Map test supplies production reachability.
			final features = TypedFeatureDiscovery.allRetained(program).namesFor(program);
			final selected = TypedFeatureSelection.lower(program, features);
			// Caller-owned arrays and returned inventories cannot change an already selected program.
			features.resize(0);
			selected.getSelectedRuntimeFeatures().resize(0);
			if (program.getSelectedRuntimeFeatures().length != 0)
				throw "feature selection mutated its input program";
			for (classic in [false, true]) {
				final tag = mode + (classic ? "-classic" : "-wrapped");
				final upstream = output + "/" + tag + "-upstream.js";
				final command = ["-cp", root, "-main", "Main", "-js", upstream];
				if (uid) {
					command.push("-D");
					command.push("uid");
				}
				if (classic) {
					command.push("-D");
					command.push("js-classic");
				}
				@:privateAccess M14JsFunctionLiteralRuntimeTest.command("haxe", command);
				@:privateAccess M14JsFunctionLiteralRuntimeTest.command("node", [root + "/observe.cjs", upstream, mode]);
				Sys.println("JS_GLOBAL_STARTUP:" + tag + ":upstream:PASS");
				final candidate = output + "/" + tag + "-candidate.js";
				new JsBackend().emit(selected,
					new BackendContext(output, candidate, "Main", true, false, HxDefineMap.fromRawDefines(classic ? ["js=1", "js-classic"] : ["js=1"])));
				@:privateAccess M14JsFunctionLiteralRuntimeTest.command("node", [root + "/observe.cjs", candidate, mode]);
				Sys.println("JS_GLOBAL_STARTUP:" + tag + ":local:PASS");
			}
		}
		@:privateAccess JsRuntimeFixture.removeOutput(output);
	}
}
