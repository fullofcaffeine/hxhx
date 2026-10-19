import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;
import sys.io.File;

/**
	Compile the complete exception dependency graph through production OCaml setup.
	The fixture supplies no provider copies, target path overrides, or emitter overlay.
	Upstream output remains the independent observer for exception and stack behavior.
 */
class M14Stage3ExceptionProvidersTest {
	static function main():Void {
		final fixture = "test/ocaml_exception_provider";
		final expected = File.getContent(fixture + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({
			command: "node_modules/.bin/haxe",
			arguments: ["-D", "no-deprecation-warnings", "-cp", fixture, "--run", "Main"],
			expected: expected
		});
		final root = ".tmp/m14_stage3_exception_providers";
		final path = fixture + "/Main.hx";
		final module = new ResolvedModule("Main", path, ParserStage.parse(File.getContent(path), path));
		final standardRoot = Stage1Args.getStandardLibraryRoot(Stage1Args.parse([], true));
		final paths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: [fixture],
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: standardRoot,
			targetDefine: "ocaml"
		});
		final index = TyperIndex.buildHeaders([module]);
		final loader = new ModuleLoader(paths, Stage3SetupSupport.buildDefinesMap([], "ocaml", "ocaml-stage3"), index);
		loader.markResolvedAlready([module]);
		final pending = [module];
		final typed = new Array<TypedModule>();
		var cursor = 0;
		while (cursor < pending.length) {
			typed.push(TyperStage.typeResolvedModule(pending[cursor++], index, loader, true));
			for (provider in loader.drainNewModules())
				pending.push(provider);
		}
		final bundleIndex = paths.indexOf(CompilerBundledSources.targetRoot("ocaml"));
		if (bundleIndex < 0)
			throw "production setup omitted the OCaml source bundle";
		for (name in [
			"Math",
			"StringTools",
			"haxe.io.FPHelper",
			"haxe.Exception",
			"haxe.ValueException",
			"haxe.CallStack",
			"haxe.NativeStackTrace"
		]) {
			final matches = typed.filter(provider -> provider.getSourceOrigin().sourceModulePath == name);
			if (matches.length != 1 || matches[0].getSourceOrigin().selectedClassPathIndex != bundleIndex)
				throw "exception observer did not select its bundled provider: " + name;
		}
		final prepared = TypedAbstractOperatorLowering.lowerModules(typed, index);
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram(prepared, []), root + "/out", true, true);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		Sys.println("M14_STAGE3_EXCEPTION_PROVIDERS:PASS");
	}
}
