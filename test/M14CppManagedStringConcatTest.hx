import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Compare exact String concatenation, nulls and operand effects with upstream behavior. */
class M14CppManagedStringConcatTest {
	static function rejects(operation:Void->Void, message:String):Void {
		try {
			operation();
		} catch (failure:haxe.Exception) {
			if (failure.message.indexOf(message) >= 0)
				return;
			throw failure;
		}
		throw "unsupported managed conversion was accepted";
	}

	public static function run():Void {
		final text = TyType.fromHintText("String");
		final integer = TyType.fromHintText("Int");
		rejects(() -> {
			backend.cpp.CppManagedInteger.resultType("+", text, integer);
		}, "exact Int or nullable Int operands");
		rejects(() -> {
			backend.cpp.CppManagedStringConcat.resultType(integer, integer);
		}, "exact String operand");
		for (name in ["Float", "Rendered"])
			rejects(() -> {
				backend.cpp.CppManagedStringConcat.resultType(text, TyType.fromHintText(name));
			}, "supported exact value formatting contract");

		if (backend.cpp.CppManagedStringConcat.resultType(text, TyType.fromHintText("Null<Int>")).getSemanticKey() != "primitive:String")
			throw "existing nullable integer formatting lost its String result";
		if (backend.cpp.CppManagedStringConcat.resultType(text, TyType.fromHintText("Dynamic")).getSemanticKey() != "primitive:String")
			throw "runtime-tagged concatenation lost its String result";

		final expected = sys.io.File.getContent("test/oracle/managed_string_concat_seed/expected.stdout");
		final upstream = new sys.io.Process("haxe", ["-cp", "test/oracle/managed_string_concat_seed/src", "-main", "Main", "--interp"]);
		final observed = upstream.stdout.readAll().toString();
		final upstreamError = upstream.stderr.readAll().toString();
		final upstreamCode = upstream.exitCode();
		upstream.close();
		if (upstreamCode != 0 || observed != expected)
			throw "upstream String concatenation disagrees with independent expectation: " + observed + upstreamError;
		final fixture = CppResolvedFixture.load({sourceRoot: "test/oracle/managed_string_concat_seed/src", mainModule: "Main", requiredModules: ["Sys"]});
		final typed = fixture.main;
		final functions = typed.getTypedClasses()[0].getFunctions();
		final revisions = [for (fn in functions) CompilerTypedTreeRevision.functionBody(fn)];
		for (fn in functions) {
			final lowered = TypedControlLowering.functionBody(fn);
			if (CompilerTypedTreeRevision.functionBody(lowered) != CompilerTypedTreeRevision.functionBody(TypedControlLowering.functionBody(lowered)))
				throw "repeated String concatenation lowering changed control or local identities";
		}
		final context = new BackendContext(".tmp/managed-string-concat", null, "Main", true, true, fixture.defines);
		final result = CppTargetCore.emit(CppResolvedFixture.prepare(fixture), context);
		if (!result.builtExecutable)
			throw "String concatenation fixture requires a native executable";
		for (i in 0...functions.length)
			if (CompilerTypedTreeRevision.functionBody(functions[i]) != revisions[i])
				throw "String concatenation lowering changed typed source";
		final process = new sys.io.Process(result.entryPath, []);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != expected)
			throw "String concatenation changed observed behavior: " + stdout + stderr;
		M14SourceMapComprehensionManagedTest.runFixture({
			sourceRoot: "test/oracle/managed_string_concat_seed/nulls",
			module: "NullConcat",
			observer: "test/cpp_managed_heap/StringConcatObserver.cpp",
			output: ".tmp/managed-string-null",
			marker: "MANAGED_STRING_NULL_NATIVE:PASS"
		});
		Sys.println("MANAGED_STRING_CONCAT_NATIVE:PASS");
		M14CppDynamicStringConcatTest.run();
	}

	static function main():Void
		run();
}
