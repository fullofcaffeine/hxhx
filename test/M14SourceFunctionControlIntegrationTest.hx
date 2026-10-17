import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Execute an authored nested return through shared lowering and strict native projection. */
class M14SourceFunctionControlIntegrationTest {
	public static function run():Void {
		final root = "test/oracle/source_function_control_seed";
		final fixture = CppResolvedFixture.load({
			sourceRoot: root + "/src",
			mainModule: "Main",
			requiredModules: ["Sys"]
		});
		final typed = fixture.main;
		final main = typed.getTypedClasses()[0].getFunctions()[0];
		final revision = CompilerTypedTreeRevision.functionBody(main);
		final program = CppResolvedFixture.prepare(fixture);
		final context = new BackendContext(".tmp/source-function-control", null, "Main", true, true, fixture.defines);
		final result = CppTargetCore.emit(program, context);
		if (!result.builtExecutable)
			throw "Source-function tracer requires a native executable";
		if (CompilerTypedTreeRevision.functionBody(main) != revision
			|| main.getBody().getStatements()[0].getExpressions()[0].getTag() != SourceFunction)
			throw "control lowering mutated the authored typed function";
		final process = new sys.io.Process(result.entryPath, []);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != sys.io.File.getContent(root + "/expected.stdout"))
			throw "Source-function return changed observable behavior: " + stdout + stderr;
		M14SourceConditionalControlTest.run();
		M14SourceLoopControlTest.run();
		M14SourceWhileValueTest.run();
		M14SourceDoWhileSyntaxTest.run();
		M14SourceDoWhileTest.run();
		M14SourceForSyntaxTest.run();
		M14SourceForTypingTest.run();
		M14SourceForReturnTest.run();
		M14SourceSwitchSyntaxTest.run();
		M14SourceTrySyntaxTest.run();
		M14SourceTryTypingTest.run();
		M14SourceFieldInitializerControlTest.run();
		M14SourceParenthesizedSyntaxTest.run();
		M14SourceParenthesizedNativeTest.run();
		M14SourceLocalAssignmentControlTest.run();
		M14SourceNamedSyntaxTest.run();
		M14SourceNamedTypingTest.run();
		M14TypedCapturePlanTest.run();
		M14TypedCaptureLoweringTest.run();
		M14TypedBackendCaptureCatalogTest.run();
		M14CppManagedStoragePlanTest.run();
		M14SourceSwitchLoopTest.run();
		Sys.println("SOURCE_FUNCTION_NATIVE:PASS");
	}

	static function main():Void
		run();
}
