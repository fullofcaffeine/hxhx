import haxe.io.Path;
import sys.io.File;
import sys.FileSystem;

/** Removal must preserve observable initialization, source ownership, and secondary module identity. */
class M14TypedEmissionRetentionTest {
	static function main():Void {
		final root = Path.normalize(Sys.getCwd() + "/test/fixtures/js_feature_intrinsic");
		final defines = HxDefineMap.fromRawDefines(["js=1"]);
		final resolved = ResolverStage.parseProjectRoots([root], ["FeatureEmission"], defines);
		final index = TyperIndex.build(resolved);
		final modules = [for (module in resolved) TyperStage.typeResolvedModule(module, index)];
		final program = new MacroExpandedProgram(modules, false);
		final revision = program.getTypedProgramRevision().getCanonicalIdentity();
		final sources = new TypedFeatureSourceCatalog({program: program, classPaths: [root], standardRoot: root + "/origin_lib"});
		final entries = [
			for (module in modules)
				for (owner in module.getTypedClasses())
					for (fn in owner.getFunctions())
						if (fn.getDeclaration().getSignature().getName() == "main")
							fn
		];
		if (entries.length != 1 || modules.length != 2)
			throw "emission fixture requires its entry and secondary provider modules";
		final output = ".tmp/feature_emission_" + Date.now().getTime();
		FileSystem.createDirectory(output);
		for (mode in ["full", "std", "no"]) {
			final roots = TypedFeatureRoots.select({
				program: program,
				sources: sources,
				entryPoint: entries[0],
				mode: mode
			});
			final reachable = TypedFeatureMemberClosure.retain(roots);
			final names = new TypedFeatureDiscovery(reachable).namesFor(program);
			final retention = new TypedEmissionRetention({reachable: reachable, mode: mode});
			// Caller-owned array mutation cannot change a previously constructed decision.
			reachable.classes.resize(0);
			reachable.functions.resize(0);
			reachable.fields.resize(0);
			reject(() -> retention.apply(new MacroExpandedProgram(modules, false)), "emission retention belongs to another typed program");
			final emitted = retention.apply(program);
			if (mode == "no" && emitted != program)
				throw "no-DCE must preserve all declarations";
			if ((emitted.getTypedProgramRevision().getCanonicalIdentity() != revision) != (mode == "full"))
				throw "emission revision does not describe its declaration inventory";
			final selected = TypedFeatureSelection.lower(emitted, names);
			for (module in selected.getTypedModules()) {
				final projected = module.getBackendProjection();
				final legacy = module.getBackendDeclaration();
				if (HxModuleDecl.getClasses(legacy).length != projected.getClasses().length)
					throw "backend projection inventories disagree";
				if (module.getSourceOrigin().sourceModulePath == "FeatureEmissionProviders") {
					if (HxClassDecl.getName(HxModuleDecl.getMainClass(legacy)) != "FeatureEmissionProviders")
						throw "secondary retention changed the module header identity";
					if (projected.getClasses().length != (mode == "full" ? 1 : 2))
						throw "unused primary class was reintroduced during projection";
				}
				for (owner in module.getTypedClasses()) {
					if (HxClassDecl.getName(owner.getSourceDeclaration()) == "FeatureEmission") {
						if (owner.getFields().length != (mode == "full" ? 0 : 1)
							|| HxClassDecl.getFields(owner.getSourceDeclaration()).length != 1)
							throw "emission changed source fields or retained an unused field";
						for (view in [legacy, projected.getDeclaration()])
							for (decl in HxModuleDecl.getClasses(view))
								if (HxClassDecl.getName(decl) == "FeatureEmission"
									&& HxClassDecl.getFields(decl).length != owner.getFields().length)
									throw "backend projection resurrected a removed field";
					}
				}
			}
			final script = output + "/" + mode + ".js";
			new backend.js.JsBackend().emit(selected, new backend.BackendContext(output, script, "FeatureEmission", true, false, defines));
			final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", "node", script]);
			final stdout = process.stdout.readAll().toString();
			final stderr = process.stderr.readAll().toString();
			final code = process.exitCode();
			process.close();
			final expected = (mode == "full" ? "" : "primary:effect\nunused:effect\n") + "conditional:effect\nabsent\n3\n";
			if (code != 0 || stdout != expected)
				throw "emission runtime differs; retained " + script + ": " + stdout + stderr;
			Sys.println("TYPED_EMISSION_RETENTION:" + mode + ":PASS");
		}
		if (CompilerTypedProgramRevision.fromTypedModules(modules, false).getCanonicalIdentity() != revision)
			throw "emission changed the original typed revision";
		final entryOwner = modules[0].getTypedClasses()[0];
		final sourceFields = entryOwner.getFields();
		if (sourceFields.length != 1)
			throw "original entry class lost its field";
		sourceFields.resize(0);
		if (entryOwner.getFields().length != 1)
			throw "field inventory leaked its mutable array";
		final otherClass = modules[1].getTypedClasses()[1];
		reject(() -> entryOwner.withMembers({
			functions: entryOwner.getFunctions(),
			fields: otherClass.getFields(),
			initializers: []
		}), "typed class requires distinct owned field declarations");
		removeTree(output);
		startup(root);
		Sys.println("TYPED_EMISSION_RETENTION:PASS");
	}

	/** Compare cross-class startup and field ordering through the ordinary backend. */
	static function startup(root:String):Void {
		final resolution = new CompilerSourceProvider().resolveModule([root], "FeatureStartup");
		final path = resolution.filePath;
		if (path == null)
			throw "startup fixture did not resolve";
		final resolved = new ResolvedModule("FeatureStartup", path, ParserStage.parse(File.getContent(path), path), resolution.toOrigin("FeatureStartup"));
		final module = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final program = new MacroExpandedProgram([module], false);
		final sources = new TypedFeatureSourceCatalog({program: program, classPaths: [root], standardRoot: root + "/origin_lib"});
		final entry = [
			for (fn in module.getTypedClasses()[0].getFunctions())
				if (fn.getDeclaration().getSignature().getName() == "main") fn
		][0];
		for (mode in ["full", "std", "no"]) {
			final roots = TypedFeatureRoots.select({
				program: program,
				sources: sources,
				entryPoint: entry,
				mode: mode
			});
			final reachable = TypedFeatureMemberClosure.retain(roots);
			final emission = new TypedEmissionRetention({reachable: reachable, mode: mode}).apply(program);
			M14GenericConstructorArgumentTest.assertRuntime(emission.getTypedModules()[0], "FeatureStartup",
				"later:init\nentry:init\nlater:method\nlater:field\nentry:field\n3\n4\n");
			Sys.println("TYPED_EMISSION_STARTUP:" + mode + ":PASS");
		}
	}

	static function reject(action:Void->Void, expected:String):Void {
		var actual = "";
		try
			action()
		catch (error:haxe.Exception)
			actual = error.message;
		if (actual != expected)
			throw "emission ownership rejection differs: " + actual;
	}

	/** Remove only artifacts allocated by this test after every assertion passes. */
	static function removeTree(path:String):Void {
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				removeTree(Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
		} else
			FileSystem.deleteFile(path);
	}
}
