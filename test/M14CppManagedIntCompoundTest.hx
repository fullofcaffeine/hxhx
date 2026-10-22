import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Compare Int compound writes, RHS effects and captured storage with upstream behavior. */
class M14CppManagedIntCompoundTest {
	public static function run():Void {
		final expected = sys.io.File.getContent("test/oracle/managed_int_compound_seed/expected.stdout");
		final upstream = new sys.io.Process("haxe", ["-cp", "test/oracle/managed_int_compound_seed/src", "-main", "Main", "--interp"]);
		final observed = upstream.stdout.readAll().toString();
		final upstreamError = upstream.stderr.readAll().toString();
		final upstreamCode = upstream.exitCode();
		upstream.close();
		if (upstreamCode != 0 || observed != expected)
			throw "upstream compound assignment disagrees with independent expectation: " + observed + upstreamError;
		final fixture = CppResolvedFixture.load({sourceRoot: "test/oracle/managed_int_compound_seed/src", mainModule: "Main", requiredModules: ["Sys"]});
		final typed = fixture.main;
		final functions = typed.getTypedClasses()[0].getFunctions();
		final revisions = [for (fn in functions) CompilerTypedTreeRevision.functionBody(fn)];
		for (fn in functions) {
			final lowered = TypedControlLowering.functionBody(fn);
			if (CompilerTypedTreeRevision.functionBody(lowered) != CompilerTypedTreeRevision.functionBody(TypedControlLowering.functionBody(lowered)))
				throw "repeated integer compound assignment lowering changed control or local identities";
		}
		final context = new BackendContext(".tmp/managed-int-compound", null, "Main", true, true, fixture.defines);
		final result = CppTargetCore.emit(CppResolvedFixture.prepare(fixture), context);
		if (!result.builtExecutable)
			throw "integer compound assignment fixture requires a native executable";
		for (i in 0...functions.length)
			if (CompilerTypedTreeRevision.functionBody(functions[i]) != revisions[i])
				throw "integer compound assignment lowering changed typed source";
		final process = new sys.io.Process(result.entryPath, []);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != expected)
			throw "integer compound assignment changed observed behavior: " + stdout + stderr;
		Sys.println("MANAGED_INT_COMPOUND_NATIVE:PASS");
	}

	static function main():Void
		run();
}
