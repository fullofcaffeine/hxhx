import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/** Load actual reference declarations before checking null-call selection and native execution. */
function typeModule(resolved:ResolvedModule):TypedModule {
	final args = Stage1Args.parse(["-main", "Main"], true);
	if (args == null)
		throw "null-call fixture arguments did not parse";
	final paths = Stage3SetupSupport.projectClassPaths({
		explicitPaths: [],
		libraries: [],
		cwd: Sys.getCwd(),
		standardRoot: Stage1Args.getStandardLibraryRoot(args),
		targetDefine: "ocaml"
	});
	final index = TyperIndex.buildHeaders([resolved]);
	final loader = new ModuleLoader(paths, Stage3SetupSupport.buildDefinesMap([], "ocaml", "ocaml"), index);
	loader.markResolvedAlready([resolved]);
	if (loader.ensureTypeAvailable("Array", "", []) == null)
		throw "null-call fixture requires the real Array provider";
	return TyperStage.typeResolvedModule(resolved, index, loader, true);
}
