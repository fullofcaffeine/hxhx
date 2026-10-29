import hxhx.Stage1Compiler.Stage1Args;
import hxhx.Stage3SetupSupport;
import sys.FileSystem;
import sys.io.File;

/**
	Compile actual OCaml providers before observing StringTools fields and calls.
	The fixture selects exact repository overrides explicitly; it does not promote
	those providers in the compiler or claim the exception-provider acceptance gate.
 */
class M14Stage3StringToolsFieldsTest {
	static function main():Void {
		final fixture = "test/portable/fixtures/string_tools_code_provider";
		final expected = File.getContent(fixture + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({
			command: "node_modules/.bin/haxe",
			arguments: ["-D", "no-deprecation-warnings", "-cp", fixture + "/src", "--run", "Main"],
			expected: expected
		});
		final root = ".tmp/m14_stage3_stringtools_fields";
		final providers = root + "/providers";
		for (relative in [
			"Math.hx",
			"StringTools.hx",
			"haxe/io/FPHelper.hx",
			"haxe/Exception.hx",
			"haxe/ValueException.hx",
			"haxe/CallStack.hx",
			"haxe/NativeStackTrace.hx"
		]) {
			final destination = providers + "/" + relative;
			FileSystem.createDirectory(haxe.io.Path.directory(destination));
			File.copy("packages/reflaxe.ocaml/std/ocaml/_std/" + relative, destination);
		}
		final path = fixture + "/src/Main.hx";
		final module = new ResolvedModule("Main", path, ParserStage.parse(File.getContent(path), path));
		final standardRoot = Stage1Args.getStandardLibraryRoot(Stage1Args.parse([], true));
		final paths = Stage3SetupSupport.projectClassPaths({
			explicitPaths: [fixture + "/src", providers],
			libraries: [],
			cwd: Sys.getCwd(),
			standardRoot: standardRoot,
			targetDefine: "ocaml"
		});
		final index = TyperIndex.buildHeaders([module]);
		final loader = new ModuleLoader(paths, Stage3SetupSupport.buildDefinesMap(["ocaml_output"], "ocaml", "ocaml-stage3"), index);
		loader.markResolvedAlready([module]);
		final pending = [module];
		final typed = new Array<TypedModule>();
		var cursor = 0;
		while (cursor < pending.length) {
			typed.push(TyperStage.typeResolvedModule(pending[cursor++], index, loader, true));
			for (provider in loader.drainNewModules())
				pending.push(provider);
		}
		final prepared = TypedAbstractOperatorLowering.lowerModules(typed, index);
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram(prepared, []), root + "/out", true);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: expected});
		Sys.println("M14_STAGE3_STRINGTOOLS_FIELDS:PASS");
	}
}
