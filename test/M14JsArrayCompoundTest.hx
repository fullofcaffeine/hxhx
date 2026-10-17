/** Indexed compound assignments retain storage, evaluate the RHS lazily, and preserve its receiver. */
class M14JsArrayCompoundTest {
	static function main():Void {
		final source = sys.io.File.getContent("test/oracle/js_array_compound_seed/Main.hx");
		final expected = sys.io.File.getContent("test/oracle/js_array_compound_seed/expected.stdout");
		final upstream = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", [
			"30",
			"node_modules/.bin/haxe",
			"-cp",
			"test/oracle/js_array_compound_seed",
			"-main",
			"Main",
			"--interp"
		]);
		final stdout = upstream.stdout.readAll().toString();
		final stderr = upstream.stderr.readAll().toString();
		final code = upstream.exitCode();
		upstream.close();
		if (code != 0 || stdout != expected)
			throw "Upstream indexed compound behavior differs: " + stdout + stderr;
		Sys.println("UPSTREAM_ARRAY_COMPOUND:PASS");
		final module = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		JsRuntimeFixture.assertRuntime(typed, "Main", expected);
		Sys.println("JS_ARRAY_COMPOUND:PASS");
		originalAbstractOperators();
	}

	/** Keep the original array-backed abstract regression, including all preceding operator observations. */
	static function originalAbstractOperators():Void {
		final root = "test/oracle/cpp_abstract_binary_operator_seed";
		final loaded = JsSourceProgramFixture.load({
			sources: [{path: "Main.hx", source: sys.io.File.getContent(root + "/src/Main.hx")}],
			requiredModules: ["Std", "js.Syntax"]
		});
		JsRuntimeFixture.assertProgramRuntime(JsSourceProgramFixture.retain(loaded, "full"), "Main", sys.io.File.getContent(root + "/expected.stdout"));
		Sys.println("JS_ARRAY_COMPOUND_ABSTRACT_ORIGINAL:PASS");
	}
}
