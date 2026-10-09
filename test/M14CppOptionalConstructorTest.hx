import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Execute the same optional-argument contract upstream and through generated native C++. */
class M14CppOptionalConstructorTest {
	static function main():Void {
		final root = "test/oracle/cpp_optional_constructor_seed";
		final overrideCompiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
		final haxe = overrideCompiler == null ? "node_modules/.bin/haxe" : overrideCompiler;
		if (Sys.command(haxe, ["-cp", root, "-main", "Main", "--interp"]) != 0)
			throw "optional constructor upstream assertions failed";
		final path = root + "/Main.hx";
		final module = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		final output = ".tmp/cpp-optional-constructor";
		final result = CppTargetCore.emit(new MacroExpandedProgram([typed], false),
			new BackendContext(output, null, "Main", true, true, new haxe.ds.StringMap()));
		if (!result.builtExecutable || Sys.command(result.entryPath, []) != 0)
			throw "optional constructor native assertions failed";
		CppManagedAssertionFixture.sanitizers(output, "CPP_OPTIONAL_CONSTRUCTOR");
		Sys.println("CPP_OPTIONAL_CONSTRUCTOR:PASS");
	}
}
