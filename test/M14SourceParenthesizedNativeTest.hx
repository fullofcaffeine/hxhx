import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Execute authored grouping, including an ordinary function with the retired helper name. */
class M14SourceParenthesizedNativeTest {
	public static function run():Void {
		// Parentheses do not add effects, but must not hide an effectful receiver
		// from the native static-call guard.
		final effectful = HxExpr.EParenthesized(EField(ECall(EIdent("make"), []), "method"), HxPos.unknown());
		if (@:privateAccess backend.cpp.CppManagedRootedExpression.staticQualifier(effectful))
			throw "grouped static-call selection discarded a receiver effect";
		final root = "test/oracle/source_parenthesized_seed";
		final fixture = CppResolvedFixture.load({sourceRoot: root + "/src", mainModule: "Main", requiredModules: ["Sys"]});
		final typed = fixture.main;
		final functions = typed.getTypedClasses()[0].getFunctions();
		final revisions = [for (fn in functions) CompilerTypedTreeRevision.functionBody(fn)];
		final result = CppTargetCore.emit(CppResolvedFixture.prepare(fixture),
			new BackendContext(".tmp/source-parenthesized-native", null, "Main", true, true, fixture.defines));
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
