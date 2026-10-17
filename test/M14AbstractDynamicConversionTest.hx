import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Exercise authored opaque-value conversions through shared typing and real target execution. */
class M14AbstractDynamicConversionTest {
	public static function verify():Void {
		final root = "test/fixtures/abstract_dynamic_conversion";
		final source = sys.io.File.getContent(root + "/Main.hx");
		final expected = sys.io.File.getContent(root + "/expected.stdout");
		@:privateAccess M14AbstractMethodConversionTest.upstream("dynamic_runtime", source, expected);
		final javascript = JsSourceProgramFixture.build({sources: [{path: "Main.hx", source: source}], requiredModules: ["Std"]});
		JsRuntimeFixture.assertProgramRuntime(javascript, "Main", expected);
		Sys.println("ABSTRACT_DYNAMIC_CONVERSION_JS:PASS");
		verifyNative("test/fixtures/abstract_dynamic_output_native");
	}

	/** Run any retained conversion fixture through complete providers and a real native executable. */
	static function verifyNative(root:String):Void {
		final source = sys.io.File.getContent(root + "/Main.hx");
		final expected = sys.io.File.getContent(root + "/expected.stdout");
		@:privateAccess M14AbstractMethodConversionTest.upstream("dynamic_native", source, expected);
		final fixture = CppResolvedFixture.load({sourceRoot: root, mainModule: "Main", requiredModules: ["Sys", "Std"]});
		final program = CppResolvedFixture.prepare(fixture);
		final directory = ".tmp/abstract_dynamic_conversion_native";
		final result = CppTargetCore.emit(program, new BackendContext(directory, null, "Main", true, true, fixture.defines));
		if (!result.builtExecutable)
			throw "abstract Dynamic conversion requires a native executable";
		final process = new sys.io.Process(result.entryPath, []);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || output != expected || errors != "")
			throw "native abstract Dynamic conversion differs: " + output + errors;
		Sys.println("ABSTRACT_DYNAMIC_CONVERSION_CPP:PASS fixture=" + root);
	}

	/** Keep the separate integer-recovery gap reproducible without changing its source or expectation. */
	static function main():Void {
		final roots = Sys.args();
		if (roots.length != 1)
			throw "expected one conversion fixture directory";
		verifyNative(roots[0]);
	}
}
