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
		final context = loadContext(input);
		return TyperStage.typeResolvedModule(context.main, context.index, context.loader, true);
	}

	/**
		Retain a root-only range observer and its already parsed source.
		Load the real interval provider before typing, without resolving unrelated
		standard calls whose modules this low-level observer does not emit.
	 */
	public static function typeResolved(input:{module:ResolvedModule, root:String}):TypedModule {
		final context = loadResolvedContext(input);
		final provider = context.loader.ensureDeclarationAvailable("IntIterator", {
			packagePath: "",
			modulePath: "",
			directives: [],
			filePath: ResolvedModule.getFilePath(input.module),
			position: HxPos.unknown(),
			parameters: []
		});
		if (provider == null)
			throw "range observer requires the real core IntIterator provider";
		final modules = [input.module].concat(context.loader.drainNewModules());
		return TyperStage.typeResolvedModule(input.module, TyperIndex.build(modules));
	}

	/**
		Prepare the original root observer with real provider bodies, including
		required extern-inline expansion. These focused tests emit only their root;
		they do not establish native support for the entire standard-library closure.
	 */
	public static function prepareMain(input:{source:String, path:String, root:String}):TypedModule {
		final roots = prepareProgram(input).filter(module -> module.getSourceOrigin().sourceModulePath == "Main");
		if (roots.length != 1)
			throw "native runtime fixture requires its exact prepared Main module";
		return roots[0];
	}

	/**
		Prepare the root observer together with every provider module that typing loaded.
		Use this when the root calls ordinary (not extern) inline provider members, such as
		the `haxe.Rest` abstract API: those members stay calls into the provider's emitted
		module, so the native build needs that module next to `Main`.
	 */
	public static function prepareProgram(input:{source:String, path:String, root:String}):Array<TypedModule> {
		final context = loadContext(input);
		final pending = [context.main];
		final typed = new Array<TypedModule>();
		var cursor = 0;
		while (cursor < pending.length) {
			typed.push(TyperStage.typeResolvedModule(pending[cursor++], context.index, context.loader, true));
			for (module in context.loader.drainNewModules())
				pending.push(module);
		}
		// Use the production Stage3 native-call contract, so standard Map calls stay
		// calls for the emitter's runtime adapter exactly as in a driver request.
		// Read it from the light policy module: Neko and other target tests share
		// this helper without reflaxe.ocaml, and OcamlStage3Backend loads the emitter.
		return TypedAbstractOperatorLowering.lowerModules(typed, context.index, backend.ocaml.Stage3OcamlNativeCallPolicy.retain);
	}

	/** Focused typing and native preparation share the same provider identity and classpath rules. */
	static function loadContext(input:{source:String, path:String, root:String}):{
		main:ResolvedModule,
		index:TyperIndex,
		loader:ModuleLoader
	} {
		final module = new ResolvedModule("Main", input.path, ParserStage.parse(input.source, input.path));
		return loadResolvedContext({module: module, root: input.root});
	}

	static function loadResolvedContext(input:{module:ResolvedModule, root:String}):{
		main:ResolvedModule,
		index:TyperIndex,
		loader:ModuleLoader
	} {
		final module = input.module;
		final arguments = Stage1Args.parse(["-cp", input.root, "-main", ResolvedModule.getModulePath(module)], true);
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
		return {main: module, index: index, loader: loader};
	}
}
