import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Run authored constructor-default assertions upstream and in managed native C++. */
class M14CppConstructorDefaultsTest {
	static function main():Void {
		final root = "test/oracle/cpp_constructor_defaults_seed";
		final overrideCompiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
		final haxe = overrideCompiler == null ? "node_modules/.bin/haxe" : overrideCompiler;
		if (Sys.command(haxe, ["-cp", root, "-main", "Main", "--interp"]) != 0)
			throw "constructor defaults upstream assertions failed";
		final path = root + "/Main.hx";
		final module = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		final output = ".tmp/cpp-constructor-defaults";
		final result = CppTargetCore.emit(new MacroExpandedProgram([typed], false),
			new BackendContext(output, null, "Main", true, true, new haxe.ds.StringMap()));
		if (!result.builtExecutable || Sys.command(result.entryPath, []) != 0)
			throw "constructor defaults native assertions failed";
		CppManagedAssertionFixture.sanitizers(output, "CPP_CONSTRUCTOR_DEFAULTS");
		Sys.println("CPP_CONSTRUCTOR_DEFAULTS:PASS");
	}
}
