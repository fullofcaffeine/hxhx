import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/**
	Type native runtime observers with the production OCaml declaration loader.
	Root-only indexes omit standard-library identities and can reject valid input
	before the runtime behavior under test is reached. Inline negative programs
	use the same providers and keep their own registered Main declaration.
 */
class M14Stage3RuntimeFixture {
	public static function typeMain(input:{source:String, path:String, root:String}):TypedModule {
		final module = new ResolvedModule("Main", input.path, ParserStage.parse(input.source, input.path));
		final arguments = Stage1Args.parse(["-cp", input.root, "-main", "Main"], true);
		final paths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: [input.root],
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: Stage1Args.getStandardLibraryRoot(arguments),
			targetDefine: "ocaml"
		});
		final index = TyperIndex.buildHeaders([module]);
		final loader = new ModuleLoader(paths, Stage3SetupSupport.buildDefinesMap([], "ocaml", "ocaml"), index);
		loader.markResolvedAlready([module]);
		return TyperStage.typeResolvedModule(module, index, loader, true);
	}
}
