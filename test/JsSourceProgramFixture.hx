import haxe.io.Path;
import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/** Types in-memory fixture roots through the production JavaScript providers and verifies the required real dependencies. */
function build(input:{sources:Array<{path:String, source:String}>, requiredModules:Array<String>}):MacroExpandedProgram {
	final filesystem = new CompilerSourceProvider();
	final files = new haxe.ds.StringMap<String>();
	final roots = new Array<String>();
	final cwd = Path.normalize(Sys.getCwd());
	for (source in input.sources) {
		files.set(Path.normalize(Path.join([cwd, source.path])), source.source);
		roots.push(Path.withoutExtension(source.path).split("/").join("."));
	}
	final provider = CompilerSourceProvider.fromCallbacks(function(paths, modulePath) {
		final path = Path.normalize(Path.join([cwd, modulePath.split(".").join("/") + ".hx"]));
		return files.exists(path) ? new CompilerModuleResolution("fixture:" + modulePath, haxe.crypto.Sha256.encode(files.get(path)), path, 0,
			false) : filesystem.resolveModule(paths, modulePath);
	}, function(path) {
		final normalized = Path.normalize(path);
		return files.exists(normalized) ? files.get(normalized) : filesystem.readSource(path);
	},
		filesystem.parseFilteredSource, filesystem.readDirectory, path -> files.exists(Path.normalize(path)) || filesystem.isFile(path),
		filesystem.prepareFinish, filesystem.finish, filesystem.report);
	final args = Stage1Args.parse(["-main", "Main"], true);
	if (args == null)
		throw "JavaScript fixture arguments did not parse";
	final paths = Stage3SetupSupport.projectClassPaths({
		explicitPaths: ["."],
		libraries: [],
		cwd: Sys.getCwd(),
		standardRoot: Stage1Args.getStandardLibraryRoot(args),
		targetDefine: "js"
	});
	final defines = Stage3SetupSupport.buildDefinesMap([], "js", "js-native");
	final resolved = ResolverStage.parseProjectRoots(paths, roots, defines, provider);
	// Let the loader discover signature-only dependencies before publishing types,
	// including types used by declarations in the eagerly resolved standard library.
	final index = TyperIndex.buildHeaders(resolved);
	final loader = new ModuleLoader(paths, defines, index, null, true, provider);
	loader.markResolvedAlready(resolved);
	final pending = resolved.copy();
	final typed = new Array<TypedModule>();
	var cursor = 0;
	final loaded = new haxe.ds.StringMap<String>();
	while (cursor < pending.length) {
		final module = pending[cursor++];
		loaded.set(ResolvedModule.getModulePath(module), ResolvedModule.getFilePath(module));
		typed.push(TyperStage.typeResolvedModule(module, index, loader, true));
		for (loaded in loader.drainNewModules())
			pending.push(loaded);
	}
	for (required in input.requiredModules) {
		final path = loaded.get(required);
		if (path == null || files.exists(Path.normalize(path)) || !sys.FileSystem.exists(path))
			throw "JavaScript fixture did not load its real provider: " + required;
	}
	final program = new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules(typed, index), false);
	final entries = [
		for (module in program.getTypedModules())
			for (owner in module.getTypedClasses())
				if (owner.getSemanticInfo().getIdentity().getCanonicalName() == "Main")
					for (fn in owner.getFunctions())
						if (fn.getDeclaration().getIsStatic() && fn.getDeclaration().getSignature().getName() == "main")
							fn
	];
	if (entries.length != 1)
		throw "JavaScript fixture requires one exact Main.main entry point";
	final sources = new TypedFeatureSourceCatalog({program: program, classPaths: paths, standardRoot: Stage1Args.getStandardLibraryRoot(args)});
	// Keep the complete provider graph under no DCE. Feature activation still uses
	// source-aware reference closure: unused SDK definitions do not enable features.
	final reachable = TypedFeatureMemberClosure.retain(TypedFeatureRoots.select({
		program: program,
		sources: sources,
		entryPoint: entries[0],
		mode: "no"
	}));
	final features = new TypedFeatureDiscovery(reachable);
	final retained = new TypedEmissionRetention({reachable: reachable, mode: "no"}).apply(program);
	return TypedFeatureSelection.lower(retained, features.namesFor(program));
}
