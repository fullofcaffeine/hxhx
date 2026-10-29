import sys.io.File;
import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/** Expected enum results select a declaration before argument checking and target projection. */
class M14ExpectedEnumConstructorTest {
	static final root = "test/fixtures/expected_enum_constructor";

	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function providers(source:String, ?moduleNames:Array<String>):Array<ResolvedModule> {
		final names = moduleNames == null ? ["First", "Second", "Main", "Functions"] : moduleNames;
		return [
			for (name in names) {
				final path = root + "/" + name + ".hx";
				new ResolvedModule(name, path, ParserStage.parse(name == "Main" ? source : File.getContent(path), path));
			}
		];
	}

	/** Require a concrete selected constructor, rather than accepting a placeholder typed call. */
	static function checkSelection(body:String, owner:String, imports:String = "import First; import Second;", enumConstructor:Bool = true,
			?resultOwner:String):Void {
		final source = imports + " class Main { static function main():Void { " + body + " } }";
		checkUpstream(source, false);
		final modules = providers(source);
		final typed = TyperStage.typeResolvedModule(modules[2], TyperIndex.build(modules));
		var found = 0;
		function expression(value:TypedExpr):Void {
			final declaration = value.getDeclaration();
			if (value.getTag() == Call && declaration != null) {
				require(declaration.getOwner().getCanonicalName() == owner, "wrong constructor declaration: " + declaration.getIdentity().getCanonicalKey());
				require(declaration.getIsEnumConstructor() == enumConstructor, "callable changed between function and enum constructor");
				require(value.getType().getNominalIdentity().getCanonicalName() == (resultOwner == null ? owner : resultOwner),
					"call result disagrees with its constructor declaration");
				found++;
			}
			for (child in value.getExpressions())
				expression(child);
		}
		function statement(value:TypedStmt):Void {
			for (child in value.getExpressions())
				expression(child);
			for (child in value.getStatements())
				statement(child);
		}
		for (type in typed.getTypedClasses())
			for (fn in type.getFunctions())
				for (body in fn.getBody().getStatements())
					statement(body);
		require(found > 0, "no exact enum constructor declaration was published");
		typed.getBackendProjection();
	}

	/** Compile the exact inline source with upstream, retaining meaningful argument diagnostics. */
	static function checkUpstream(source:String, rejected:Bool):Void {
		final path = ".tmp/expected-enum-negative";
		if (!sys.FileSystem.exists(path))
			sys.FileSystem.createDirectory(path);
		File.saveContent(path + "/Main.hx", source);
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		final process = new sys.io.Process(timeout, ["30", "haxe", "-cp", root, "-cp", path, "--run", "Main"]);
		final output = process.stdout.readAll().toString() + process.stderr.readAll().toString();
		final status = process.exitCode();
		process.close();
		require(rejected ? status != 0 && output.indexOf("should be") >= 0 : status == 0, "upstream argument contract changed: " + output);
	}

	/** Both compilers must reject the same source after selecting the expected owner. */
	static function checkRejected(body:String, imports:String = "import First; import Second;"):Void {
		final source = imports + " class Main { static function main():Void { " + body + " } }";
		checkUpstream(source, true);
		var rejected = false;
		var diagnostic = "";
		try {
			final modules = providers(source);
			TyperStage.typeResolvedModule(modules[2], TyperIndex.build(modules));
		} catch (error:TyperError) {
			diagnostic = error.message;
			rejected = diagnostic.indexOf("No compatible method signature") >= 0
				|| diagnostic.indexOf("not compatible") >= 0
				|| diagnostic.indexOf("should be") >= 0;
		}
		require(rejected, "local typing did not reject argument types: " + diagnostic);
	}

	/** Local and current-class callables win even when an enum result is expected. */
	static function checkPrecedence():Void {
		for (source in [
			"import First; import Second; class Main { static function main():Void { final Build = function(value:String, record:{name:String}):First return First.Build(value, record); final chosen:First = Build('local', null); } }",
			"import First; import Second; class Main { static function Build(value:String, record:{name:String}):First return First.Build(value, record); static function main():Void { final chosen:First = Build('class', null); } }"
		]) {
			checkUpstream(source, false);
			final modules = providers(source);
			final typed = TyperStage.typeResolvedModule(modules[2], TyperIndex.build(modules));
			final fn = typed.getTypedClasses()[0].getFunctions().filter(fn -> HxFunctionDecl.getName(fn.getSourceDeclaration()) == "main")[0];
			var calls = 0;
			function visit(value:TypedExpr):Void {
				if (value.getTag() == Lambda || value.getTag() == SourceFunction)
					return;
				if (value.getTag() == Call) {
					require(value.getDeclaration() == null
						|| !value.getDeclaration().getIsEnumConstructor(), "expected enum hid a closer callable");
					calls++;
				}
				for (child in value.getExpressions())
					visit(child);
			}
			for (statement in fn.getBody().getStatements())
				for (expression in statement.getExpressions())
					visit(expression);
			require(calls == 1, "precedence control did not inspect its bare call");
		}
		checkRejected("final Build = function(value:Int, flag:Bool):Second return Second.Build(value, flag); final chosen:First = Build('wrong', null);");
	}

	/** Use real standard declarations for complete source projection and native preparation. */
	static function typeModules(modules:Array<ResolvedModule>, classPath:String):Array<TypedModule> {
		final arguments = Stage1Args.parse(["-cp", classPath, "-main", "Main"], true);
		final paths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: [classPath],
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: Stage1Args.getStandardLibraryRoot(arguments),
			targetDefine: "ocaml"
		});
		final index = TyperIndex.buildHeaders(modules);
		final loader = new ModuleLoader(paths, Stage3SetupSupport.buildDefinesMap([], "ocaml", "ocaml"), index);
		loader.markResolvedAlready(modules);
		return [
			for (module in modules)
				TyperStage.typeResolvedModule(module, index, loader, true)
		];
	}

	static function main():Void {
		checkSelection("final value:First = Build('ok', null);", "First");
		checkSelection("final value:First = Build('ok', null);", "First", "import Second; import First;");
		checkSelection("final value:First = First.Build('ok', null);", "First");
		checkSelection("final value = Build(3, true);", "Second");
		checkSelection("final value:Second = Build(3, true);", "Second");
		checkSelection("final value:First = switch true { case true: Build('ok', null); case false: Build('other', null); };", "First");
		checkSelection("final value:Null<First> = Build('nullable', null);", "First");
		checkSelection("final value:Alias = Build('alias', null);", "First", "import First; import Second; typedef Alias = First;");
		for (directive in [
			"import Functions.Build;",
			"import Functions.other as Build;",
			"import Functions;"
		]) {
			final imports = "import First; import Second; " + directive;
			checkSelection("final value:First = Build('enum', null);", "First", imports);
			checkRejected("final value:First = Build(3, true);", imports);
			checkSelection("final value = Build(3, true);", "Functions", directive, false, "First");
		}
		checkRejected("final value:First = Build(3, true);");
		checkRejected("final value = Build('wrong', null);");
		checkPrecedence();
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		// The program API requires its entry module first; every imported enum remains present.
		final modules = providers(File.getContent(root + "/Main.hx"), ["Main", "First", "Second"]);
		final typed = typeModules(modules, root);
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(typed, false), ".tmp/expected-enum-constructor-imported");
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		Sys.println("M14_EXPECTED_ENUM_CONSTRUCTOR:PASS");
	}
}
