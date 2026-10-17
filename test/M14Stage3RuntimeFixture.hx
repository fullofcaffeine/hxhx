import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/**
	Type native runtime observers with the production OCaml declaration loader.
	Root-only indexes omit standard-library identities and can reject valid input
	before the runtime behavior under test is reached. Inline negative programs
	use the same providers and keep their own registered Main declaration.
 */
class M14Stage3RuntimeFixture {
	/** Require the same observable output from upstream and native programs, including successful exit. */
	public static function observe(input:{
		command:String,
		arguments:Array<String>,
		expected:String,
		?timeoutSeconds:Int
	}):Void {
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		final seconds = input.timeoutSeconds == null ? 30 : input.timeoutSeconds;
		if (seconds <= 0)
			throw "runtime fixture observation requires a positive timeout";
		final process = new sys.io.Process(timeout, [Std.string(seconds), input.command].concat(input.arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != input.expected || stderr != "")
			throw "runtime fixture observation failed: exit=" + code + " stdout=" + stdout + " stderr=" + stderr;
	}

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
