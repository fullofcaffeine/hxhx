import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Execute mutable callbacks and inspect result types through the real C++ runtime. */
class M14CppCallableAnnotationIntegrationTest {
	/** Use the installed declaration so optional position calls cross the real standard-library boundary. */
	static macro function posInfosSourcePath():haxe.macro.Expr.ExprOf<String> {
		return macro $v{haxe.macro.Context.resolvePath("haxe/PosInfos.hx")};
	}

	public static function run():Void {
		final root = "test/oracle/cpp_callable_annotation_seed";
		final path = root + "/src/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final posPath = posInfosSourcePath();
		final positionModule = new ResolvedModule("haxe.PosInfos", posPath, ParserStage.parse(sys.io.File.getContent(posPath), posPath));
		final modules = [resolved, positionModule];
		final index = TyperIndex.build(modules);
		final program = new MacroExpandedProgram([for (module in modules) TyperStage.typeResolvedModule(module, index)], false);
		final context = new BackendContext(".tmp/cpp-callable-annotation", null, "Main", true, true, new haxe.ds.StringMap<String>());
		final result = CppTargetCore.emit(program, context);
		if (!result.builtExecutable)
			throw "Callable annotation observer requires a native executable";
		final process = new sys.io.Process(result.entryPath, []);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != sys.io.File.getContent(root + "/expected.stdout"))
			throw "Callable annotation behavior differs: " + stdout + stderr;
		Sys.println("CPP_CALLABLE_ANNOTATION_NATIVE:PASS");
	}

	static function main():Void
		run();
}
