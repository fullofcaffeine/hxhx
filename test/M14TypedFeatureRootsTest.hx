import haxe.io.Path;
import sys.io.File;

/** Compare entry, initialization and keep roots with independently observed upstream output. */
class M14TypedFeatureRootsTest {
	static function main():Void {
		final root = Path.normalize(Sys.getCwd() + "/test/fixtures/js_feature_intrinsic");
		final paths = [root];
		final source = new CompilerSourceProvider();
		final resolution = source.resolveModule(paths, "FeatureRetention");
		final path = resolution.filePath;
		if (path == null)
			throw "feature retention fixture did not resolve";
		final resolved = new ResolvedModule("FeatureRetention", path, ParserStage.parse(File.getContent(path), path), resolution.toOrigin("FeatureRetention"));
		final module = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final program = new MacroExpandedProgram([module], false);
		// The SDK location is distinct from this user-only fixture's selected source.
		final catalog = new TypedFeatureSourceCatalog({program: program, classPaths: paths, standardRoot: root + "/origin_lib"});
		final entries = [
			for (owner in module.getTypedClasses())
				for (fn in owner.getFunctions())
					if (fn.getDeclaration().getSignature().getName() == "main")
						fn
		];
		if (entries.length != 1)
			throw "feature roots fixture requires one entry point";
		for (mode in ["full", "std", "no"]) {
			final roots = TypedFeatureRoots.select({
				program: program,
				sources: catalog,
				entryPoint: entries[0],
				mode: mode
			});
			final reachable = TypedFeatureMemberClosure.retain(roots);
			final features = new TypedFeatureDiscovery(reachable);
			final emission = new TypedEmissionRetention({reachable: reachable, mode: mode}).apply(program);
			final lowered = TypedFeatureSelection.lower(emission, features.namesFor(program));
			final expected = "init:on\nkept:on\n"
				+
				(mode == "full" ? "field:off\nunused:off\nkept-class:on\nunused-class:off\nunused-init:off\n" : "field:on\nunused:on\nkept-class:on\nunused-class:on\nunused-init:on\n");
			M14GenericConstructorArgumentTest.assertRuntime(lowered.getTypedModules()[0], "FeatureRetention", expected);
			Sys.println("TYPED_FEATURE_ROOTS:" + mode + ":PASS");
		}
		reject(() -> TypedFeatureRoots.select({
			program: program,
			sources: catalog,
			entryPoint: entries[0],
			mode: "invalid"
		}), "unsupported feature retention mode: invalid");
		reject(() -> TypedFeatureRoots.select({
			program: program,
			sources: catalog,
			entryPoint: entries[0].withBody(entries[0].getBody()),
			mode: "full"
		}), "feature roots require an owned entry function");
		Sys.println("TYPED_FEATURE_ROOTS:PASS");
		origins(root);
	}

	/** Replay the upstream source-location matrix through ordinary resolution and generated JavaScript. */
	static function origins(root:String):Void {
		final temporary = Path.normalize(Sys.getCwd() + "/.tmp/feature_origin_local_" + Date.now().getTime());
		final sdk = temporary + "/std";
		sys.FileSystem.createDirectory(sdk);
		File.copy(root + "/origin_lib/FeatureOriginLibrary.hx", sdk + "/FeatureOriginLibrary.hx");
		for (sourceKind in ["sdk", "project", "explicit-sdk"]) {
			for (called in [false, true]) {
				final paths = sourceKind == "project" ? [root, root + "/origin_lib", sdk] : sourceKind == "explicit-sdk" ? [sdk, root] : [root, sdk];
				final defines = HxDefineMap.fromRawDefines(called ? ["js=1", "feature_origin_call=1"] : ["js=1"]);
				final resolved = ResolverStage.parseProjectRoots(paths, ["FeatureOrigin"], defines);
				final index = TyperIndex.build(resolved);
				final modules = [for (module in resolved) TyperStage.typeResolvedModule(module, index)];
				final program = new MacroExpandedProgram(modules, false);
				final catalog = new TypedFeatureSourceCatalog({program: program, classPaths: paths, standardRoot: sdk});
				final entries = [
					for (module in modules)
						for (owner in module.getTypedClasses())
							for (fn in owner.getFunctions())
								if (fn.getDeclaration().getSignature().getName() == "main")
									fn
				];
				if (entries.length != 1 || modules.length != 2)
					throw "source-location fixture must resolve its entry and library modules";
				for (mode in ["full", "std", "no"]) {
					final roots = TypedFeatureRoots.select({
						program: program,
						sources: catalog,
						entryPoint: entries[0],
						mode: mode
					});
					final reachable = TypedFeatureMemberClosure.retain(roots);
					final features = new TypedFeatureDiscovery(reachable);
					final emission = new TypedEmissionRetention({reachable: reachable, mode: mode}).apply(program);
					final lowered = TypedFeatureSelection.lower(emission, features.namesFor(program));
					final expectedUnused = called || mode == "no" || (sourceKind == "project" && mode == "std");
					final unused = [
						for (module in lowered.getTypedModules())
							for (owner in module.getTypedClasses())
								for (fn in owner.getFunctions())
									if (fn.getDeclaration().getSignature().getName() == "unused")
										fn
					];
					if (unused.length != (expectedUnused ? 1 : 0))
						throw "emission confused SDK retention with feature relevance";
					final script = temporary + "/" + sourceKind + "-" + called + "-" + mode + ".js";
					new backend.js.JsBackend().emit(lowered, new backend.BackendContext(temporary, script, "FeatureOrigin", true, false, defines));
					final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", "node", script]);
					final stdout = process.stdout.readAll().toString();
					final stderr = process.stderr.readAll().toString();
					final status = process.exitCode();
					process.close();
					final enabled = called || (sourceKind == "project" && mode != "full");
					if (status != 0 || stdout != (enabled ? "library:on\nused\n" : "library:off\nused\n"))
						throw "local feature origin differs; retained " + script + ": " + stdout + stderr;
					Sys.println("TYPED_FEATURE_ORIGIN:" + sourceKind + ":" + called + ":" + mode + ":PASS");
				}
			}
		}
		removeTree(temporary);
		Sys.println("TYPED_FEATURE_ORIGIN:PASS");
	}

	/** Remove only the temporary directory allocated by this source-location test. */
	static function removeTree(path:String):Void {
		if (sys.FileSystem.isDirectory(path)) {
			for (entry in sys.FileSystem.readDirectory(path))
				removeTree(Path.join([path, entry]));
			sys.FileSystem.deleteDirectory(path);
		} else
			sys.FileSystem.deleteFile(path);
	}

	static function reject(action:Void->Void, expected:String):Void {
		var diagnostic = "";
		try {
			action();
		} catch (error:haxe.Exception) {
			diagnostic = error.message;
		}
		if (diagnostic != expected)
			throw "feature root rejection differs: " + diagnostic;
	}
}
