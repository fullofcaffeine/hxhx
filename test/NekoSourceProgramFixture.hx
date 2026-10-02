import haxe.io.Path;
import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/** Types in-memory fixture roots through the same provider and dependency discovery as a Neko build. */
function build(sources:Array<{path:String, source:String}>):MacroExpandedProgram {
	final filesystem = new CompilerSourceProvider();
	final files = new haxe.ds.StringMap<String>();
	final roots = new Array<String>();
	for (source in sources) {
		files.set(Path.normalize(source.path), source.source);
		roots.push(Path.withoutExtension(source.path).split("/").join("."));
	}
	final provider = CompilerSourceProvider.fromCallbacks(function(paths, modulePath) {
		final path = modulePath.split(".").join("/") + ".hx";
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
		throw "Neko fixture arguments did not parse";
	final paths = Stage3SetupSupport.projectClassPaths({
		explicitPaths: ["."],
		libraries: [],
		cwd: Sys.getCwd(),
		standardRoot: Stage1Args.getStandardLibraryRoot(args),
		targetDefine: "neko"
	});
	final defines = Stage3SetupSupport.buildDefinesMap([], "neko", "neko-native");
	final resolved = ResolverStage.parseProjectRoots(paths, roots, defines, provider);
	final index = TyperIndex.build(resolved);
	final loader = new ModuleLoader(paths, defines, index, null, true, provider);
	loader.markResolvedAlready(resolved);
	final pending = resolved.copy();
	final typed = new Array<TypedModule>();
	var cursor = 0;
	while (cursor < pending.length) {
		typed.push(TyperStage.typeResolvedModule(pending[cursor++], index, loader, true));
		for (loaded in loader.drainNewModules())
			pending.push(loaded);
	}
	return new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules(typed, index), false);
}
