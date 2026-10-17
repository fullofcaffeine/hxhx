import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Prove that call adaptation consumes the neutral support class's selected signatures. */
class M14CppNeutralCallableIntegrationTest {
	/** Use the installed source declaration rather than a copied standard-library shape. */
	static macro function posInfosSourcePath():haxe.macro.Expr.ExprOf<String> {
		return macro $v{haxe.macro.Context.resolvePath("haxe/PosInfos.hx")};
	}

	public static function run():Void {
		final root = "test/oracle/cpp_neutral_callable_seed";
		final sources = [
			{module: "Main", path: root + "/src/Main.hx"},
			{module: "utest.Assert", path: root + "/src/utest/Assert.hx"},
			{module: "haxe.PosInfos", path: posInfosSourcePath()}
		];
		final resolved = [
			for (source in sources)
				new ResolvedModule(source.module, source.path, ParserStage.parse(sys.io.File.getContent(source.path), source.path))
		];
		final index = TyperIndex.build(resolved);
		final program = new MacroExpandedProgram([for (module in resolved) TyperStage.typeResolvedModule(module, index)], false);
		final context = new BackendContext(".tmp/cpp-neutral-callable", null, "Main", true, true, new haxe.ds.StringMap<String>());
		final result = CppTargetCore.emit(program, context);
		if (!result.builtExecutable)
			throw "Neutral callable test requires a native executable";
		final process = new sys.io.Process(result.entryPath, []);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != sys.io.File.getContent(root + "/expected.stdout"))
			throw "Neutral callable behavior differs: " + stdout + stderr;
		Sys.println("CPP_NEUTRAL_CALLABLE_NATIVE:PASS");
	}

	static function main():Void
		run();
}
