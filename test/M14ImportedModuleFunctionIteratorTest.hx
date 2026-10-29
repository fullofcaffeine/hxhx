import sys.io.File;
import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;

/** Plain module imports preserve function ownership before array iterator replay. */
class M14ImportedModuleFunctionIteratorTest {
	static final root = "test/fixtures/imported_module_function_iterator";

	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	/** Rejected controls use upstream behavior rather than inferred import policy. */
	static function checkUpstreamRejection(module:String, diagnostic:String = "Unknown identifier"):Void {
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		final process = new sys.io.Process(timeout, ["30", "haxe", "-cp", root, "--run", module]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final status = process.exitCode();
		process.close();
		require(status != 0 && stderr.indexOf(diagnostic) >= 0, "upstream rejection changed for " + module + ": " + stdout + stderr);
	}

	/** The real imported signature must reject a written incompatible collection type. */
	static function checkWrongType():Void {
		checkUpstreamRejection("WrongTypeMain", "Bool should be Int");
		final path = root + "/WrongTypeMain.hx";
		var rejected = false;
		try {
			M14Stage3RuntimeFixture.typeMain({source: StringTools.replace(File.getContent(path), "class WrongTypeMain", "class Main"), path: path, root: root});
		} catch (error:TyperError) {
			rejected = Std.string(error).indexOf("array element Bool is not compatible with Int") >= 0;
		}
		require(rejected, "imported Bool call lost its signature in an incompatible array context");
	}

	/** Compare identical callable shapes whose source scopes have different import rules. */
	static function checkScopeIdentity():Void {
		function typed(source:String):TypedModule {
			final resolved = new ResolvedModule("Provider", "Provider.hx", ParserStage.parse(source, "Provider.hx"));
			return TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		}
		final moduleFunction = typed("function value():Bool return false; class Provider {}");
		final classMethod = typed("class Provider { public static function value():Bool return false; }");
		final moduleValue = moduleFunction.getTypedClasses()[0].getFunctions()[0];
		final classValue = classMethod.getTypedClasses()[0].getFunctions()[0];
		require(moduleValue.getDeclaration().getIsModuleLevel(), "module scope disappeared from the published declaration");
		require(!classValue.getDeclaration().getIsModuleLevel(), "ordinary static method acquired module scope");
		require(HxFunctionDecl.getIsModuleLevel(TypedBodySource.functionDeclaration(moduleValue)), "typed source projection lost module scope");
		require(!HxFunctionDecl.getIsModuleLevel(TypedBodySource.functionDeclaration(classValue)), "typed source projection invented module scope");
		require(moduleValue.getStableIdentity() != classValue.getStableIdentity(), "callable identity omitted source scope");
		require(CompilerTypedModuleRevision.fromTypedModule(moduleFunction)
			.publicInterfaceRevision != CompilerTypedModuleRevision.fromTypedModule(classMethod)
			.publicInterfaceRevision,
			"public interface revision omitted callable source scope");
	}

	/** Only parser-marked public module functions qualify for a bare plain import. */
	static function checkImports(index:TyperIndex):Void {
		final source = HxModuleDirective.normalImport("Functions");
		final directive = new TyModuleDirective(source, TypeImport, [for (provider in index.getByModulePath("Functions")) provider.getIdentity()]);
		final context = new TyperContext(index, "Main.hx", "Main", "", [source], "Main", null, [directive]);
		require(context.importedStaticMethod("record") != null, "plain import withheld a public module function");
		require(context.importedStaticMethod("hidden") == null, "plain import exposed a private module function");
		require(context.importedStaticMethod("classValue") == null, "plain import exposed an ordinary static method");
		final alias = HxModuleDirective.aliasImport("Functions", "Alias");
		final aliasContext = new TyperContext(index, "Main.hx", "Main", "", [alias], "Main", null,
			[new TyModuleDirective(alias, TypeImport, directive.getProviders())]);
		require(aliasContext.importedStaticMethod("record") == null, "a type alias exposed a bare module function");
		final path = root + "/NoPrimaryFunctions.hx";
		final secondary = new ResolvedModule("NoPrimaryFunctions", path, ParserStage.parse(File.getContent(path), path));
		final secondaryIndex = TyperIndex.build([secondary]);
		for (importPath in ["NoPrimaryFunctions", "NoPrimaryFunctions.Secondary"]) {
			final source = HxModuleDirective.normalImport(importPath);
			final providers = [
				for (provider in secondaryIndex.getByModulePath("NoPrimaryFunctions"))
					provider.getIdentity()
			];
			final context = new TyperContext(secondaryIndex, "Main.hx", "Main", "", [source], "Main", null,
				[new TyModuleDirective(source, TypeImport, providers)]);
			require((context.importedStaticMethod("moduleOnly") != null) == (importPath == "NoPrimaryFunctions"),
				"secondary type import changed module function visibility");
		}
	}

	static function main():Void {
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "haxe", arguments: ["-cp", root, "--run", "Main"], expected: expected});
		for (module in ["PrivateMain", "OrdinaryStaticMain", "ModuleAliasMain", "SecondaryTypeMain"])
			checkUpstreamRejection(module);
		checkWrongType();
		M14Stage3RuntimeFixture.observe({command: "haxe", arguments: ["-cp", root, "--run", "ShadowMain"], expected: "IMPORTED_MODULE_FUNCTION_SHADOW:PASS\n"});
		final shadowPath = root + "/ShadowMain.hx";
		M14Stage3RuntimeFixture.typeMain({
			source: StringTools.replace(File.getContent(shadowPath), "class ShadowMain", "class Main"),
			path: shadowPath,
			root: root
		});
		checkScopeIdentity();
		final resolved = [
			for (name in ["Main", "Functions", "OtherFunctions"]) {
				final path = root + "/" + name + ".hx";
				new ResolvedModule(name, path, ParserStage.parse(File.getContent(path), path));
			}
		];
		final arguments = Stage1Args.parse(["-cp", root, "-main", "Main"], true);
		final paths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: [root],
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: Stage1Args.getStandardLibraryRoot(arguments),
			targetDefine: "ocaml"
		});
		final index = TyperIndex.buildHeaders(resolved);
		final loader = new ModuleLoader(paths, Stage3SetupSupport.buildDefinesMap([], "ocaml", "ocaml"), index);
		loader.markResolvedAlready(resolved);
		require(loader.ensureTypeAvailable("Array", "", []) != null, "fixture requires the real Array provider");
		checkImports(index);
		final typed = [
			for (module in resolved)
				TyperStage.typeResolvedModule(module, index, loader, true)
		];
		final executable = EmitterStage.emitToDir(new MacroExpandedProgram(typed, false), ".tmp/imported-module-function-iterator");
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		Sys.println("M14_IMPORTED_MODULE_FUNCTION_ITERATOR:PASS");
	}
}
