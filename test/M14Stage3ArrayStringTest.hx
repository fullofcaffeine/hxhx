/** Require both typed and erased array conversion without hiding either failure. */
class M14Stage3ArrayStringTest {
	/** Context must not relabel an incompatible element as an integer. */
	static function rejectInvalidElement(moduleName:String, actualType:String):Void {
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		final process = new sys.io.Process(timeout, [
			"60",
			"node_modules/.bin/haxe",
			"-cp",
			"test/fixtures/stage3_bool_string",
			"-main",
			moduleName,
			"--no-output"
		]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 1 || stderr.indexOf(actualType) < 0 || stderr.indexOf("Int") < 0)
			throw "upstream did not reject the invalid array element: " + stdout + stderr;
		var rejected = false;
		try {
			M14Stage3BoolStringTest.typeModule(moduleName);
		} catch (error:TyperError) {
			rejected = Std.string(error).indexOf("array element " + actualType + " is not compatible with Int") >= 0;
		}
		if (!rejected)
			throw "array context hid an incompatible element";
	}

	static function main():Void {
		rejectInvalidElement("InvalidArrayMain", "Bool");
		rejectInvalidElement("InvalidArrayNarrowingMain", "Float");
		M14Stage3BoolStringTest.run("ArrayMain", "array.expected.stdout");
		Sys.println("M14_STAGE3_TYPED_ARRAY_STRING:PASS");
		M14Stage3BoolStringTest.run("ContextArrayMain", "context-array.expected.stdout");
		Sys.println("M14_STAGE3_CONTEXT_ARRAY_STRING:PASS");
		M14Stage3BoolStringTest.run("DynamicArrayMain", "dynamic-array.expected.stdout");
		Sys.println("M14_STAGE3_ARRAY_STRING:PASS");
	}
}
