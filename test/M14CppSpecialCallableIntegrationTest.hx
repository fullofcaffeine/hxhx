import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Compile and execute authored Haxe to observe specialized argument carriers and evaluation count. */
class M14CppSpecialCallableIntegrationTest {
	/** Use the same installed declaration as the upstream compiler, without a copied stdlib shape. */
	static macro function posInfosSourcePath():haxe.macro.Expr.ExprOf<String> {
		return macro $v{haxe.macro.Context.resolvePath("haxe/PosInfos.hx")};
	}

	public static function run():Void {
		for (withoutPosition in [false, true])
			runVariant(withoutPosition);
		runVariant(true, true);
		Sys.println("CPP_SPECIAL_CALLABLE_NATIVE:PASS");
	}

	/** Exercise source-declared and target-added position arguments against the same runtime expectation. */
	static function runVariant(withoutPosition:Bool, withoutGeneric:Bool = false):Void {
		final root = "test/oracle/cpp_special_callable_seed";
		final path = root + "/src/Main.hx";
		final posPath = posInfosSourcePath();
		final defines = new haxe.ds.StringMap<String>();
		if (withoutPosition)
			defines.set("eq_without_pos", "1");
		if (withoutGeneric)
			defines.set("allow_without_generic", "1");
		final source = HxConditionalCompilation.filterSource(sys.io.File.getContent(path), defines);
		final resolved = [
			new ResolvedModule("Main", path, ParserStage.parse(source, path)),
			new ResolvedModule("haxe.PosInfos", posPath, ParserStage.parse(sys.io.File.getContent(posPath), posPath))
		];
		final index = TyperIndex.build(resolved);
		final program = new MacroExpandedProgram([for (module in resolved) TyperStage.typeResolvedModule(module, index)], false);
		final outputDirectory = ".tmp/cpp-special-callable" + (withoutPosition ? "-without-pos" : "") + (withoutGeneric ? "-without-generic" : "");
		final context = new BackendContext(outputDirectory, null, "Main", true, true, defines);
		final result = CppTargetCore.emit(program, context);
		if (!result.builtExecutable)
			throw "Specialized callable test requires a native executable";
		// A successful executable build alone does not reject accidentally unused callback results.
		final compiler = @:privateAccess CppTargetCore.cppCompilerCommand();
		if (compiler == null || Sys.command(compiler, [
			"-std=c++17",
			"-Werror=unused-value",
			"-fsyntax-only",
			outputDirectory + "/src/Main.cpp"
		]) != 0)
			throw "Specialized callable output must compile without unused-value warnings";
		final process = new sys.io.Process(result.entryPath, []);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != sys.io.File.getContent(root + "/expected.stdout"))
			throw "Specialized callable behavior differs: " + stdout + stderr;
		Sys.println("CPP_SPECIAL_CALLABLE_VARIANT:PASS withoutPosition=" + withoutPosition + " withoutGeneric=" + withoutGeneric);
	}

	static function main():Void
		run();
}
