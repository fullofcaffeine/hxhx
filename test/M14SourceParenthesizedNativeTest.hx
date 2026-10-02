import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Execute authored grouping, including an ordinary function with the retired helper name. */
class M14SourceParenthesizedNativeTest {
	public static function run():Void {
		final root = "test/oracle/source_parenthesized_seed";
		final path = root + "/src/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final functions = typed.getTypedClasses()[0].getFunctions();
		final revisions = [for (fn in functions) CompilerTypedTreeRevision.functionBody(fn)];
		final result = CppTargetCore.emit(new MacroExpandedProgram([typed], false),
			new BackendContext(".tmp/source-parenthesized-native", null, "Main", true, true, new haxe.ds.StringMap<String>()));
		if (!result.builtExecutable)
			throw "parenthesis contract requires native execution";
		for (index in 0...functions.length)
			if (CompilerTypedTreeRevision.functionBody(functions[index]) != revisions[index])
				throw "target changed parenthesized source";
		final process = new sys.io.Process(result.entryPath, []);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != sys.io.File.getContent(root + "/expected.stdout"))
			throw "parenthesis native behavior differs: " + stdout + stderr;
		Sys.println("SOURCE_PARENTHESIZED_NATIVE:PASS");
	}

	static function main():Void
		run();
}
