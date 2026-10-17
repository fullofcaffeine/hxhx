import sys.io.File;

/** Class creation and static initialization have distinct dependency order requirements. */
class M14JsStaticInheritanceCycleTest {
	static function main():Void {
		final root = "test/fixtures/js_inheritance";
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout",
			["60", "node_modules/.bin/haxe", "-cp", root, "--run", "StaticCycle"]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != "true\n")
			throw "upstream static inheritance contract differs: " + stdout + stderr;
		final path = root + "/StaticCycle.hx";
		final module = new ResolvedModule("StaticCycle", path, ParserStage.parse(File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(module, TyperIndex.build([module]));
		JsRuntimeFixture.assertRuntime(typed, "StaticCycle", "true\n");
		Sys.println("JS_STATIC_INHERITANCE_CYCLE:PASS");
	}
}
