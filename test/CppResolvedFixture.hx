import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/** A fixture's source module and complete real dependency closure before target lowering. */
typedef CppResolvedFixtureProgram = {
	final main:TypedModule;
	final modules:Array<TypedModule>;
	final index:TyperIndex;
	final defines:haxe.ds.StringMap<String>;
}

/**
	Use production classpath and lazy-loading rules for native C++ regression programs.
	Required modules must be present in the typed closure. A fixture cannot substitute
	unresolved type names or synthetic standard-library classes for these providers.
 */
function load(input:{
	sourceRoot:String,
	mainModule:String,
	requiredModules:Array<String>,
	?defines:Array<String>
}):CppResolvedFixtureProgram {
	final arguments = Stage1Args.parse(["-cp", input.sourceRoot, "-main", input.mainModule], true);
	if (arguments == null)
		throw "C++ fixture arguments did not parse";
	final paths = Stage3SetupSupport.projectClassPaths({
		explicitPaths: Stage1Args.getExplicitClassPaths(arguments),
		libraries: [],
		cwd: Sys.getCwd(),
		standardRoot: Stage1Args.getStandardLibraryRoot(arguments),
		targetDefine: "cpp"
	});
	final defines = Stage3SetupSupport.buildDefinesMap(input.defines == null ? [] : input.defines, "cpp", "cpp-native");
	final resolved = ResolverStage.parseProjectRoots(paths, [input.mainModule], defines);
	// Discover declaration dependencies before publishing signatures, as production
	// does. A root-only index can miss the types used by standard-library bounds.
	final index = TyperIndex.buildHeaders(resolved);
	final loader = new ModuleLoader(paths, defines, index);
	loader.markResolvedAlready(resolved);
	final pending = resolved.copy();
	final typed = new Array<TypedModule>();
	final loadedModules = new haxe.ds.StringMap<Bool>();
	var main:Null<TypedModule> = null;
	var cursor = 0;
	while (cursor < pending.length) {
		final module = pending[cursor++];
		final modulePath = ResolvedModule.getModulePath(module);
		loadedModules.set(modulePath, true);
		final result = TyperStage.typeResolvedModule(module, index, loader, true);
		typed.push(result);
		if (modulePath == input.mainModule)
			main = result;
		for (loaded in loader.drainNewModules())
			pending.push(loaded);
	}
	if (main == null)
		throw "C++ fixture did not type its exact main module";
	for (required in input.requiredModules)
		if (!loadedModules.exists(required))
			throw "C++ fixture did not load its real dependency: " + required;
	return {
		main: main,
		modules: typed,
		index: index,
		defines: defines
	};
}
