import sys.io.File;

/** Execute shared local-function control and reject destinations that cross function or loop boundaries. */
class M14JsControlRegionTest {
	static function main():Void {
		final source = File.getContent("test/fixtures/js_control_region/Main.hx");
		final expected = "22\n20\n7\n4\n2\n3\n50\n30\n2\n11\n8\n13\n";
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", [
			"30",
			"node_modules/.bin/haxe",
			"-cp",
			"test/fixtures/js_control_region",
			"--run",
			"Main"
		]);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || output != expected)
			throw "upstream local function control differs: " + output + errors;
		final module = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		JsRuntimeFixture.assertRuntime(TyperStage.typeResolvedModule(module, TyperIndex.build([module])), "Main", expected);
		final position = HxPos.unknown();
		for (entry in [
			HxExpr.ELoweredControl(Return, "another-function", [EInt(1)], position),
			HxExpr.ELoweredControl(Break, "outside-loop", [], position),
			HxExpr.ELoweredControl(Scope, "invented-target", [], position),
			HxExpr.ELoweredControl(While(Normal), "loop", [
				EBool(true),
				ELoweredControl(Scope, "", [ELoweredControl(Continue, "another-loop", [], position)], position)
			], position)
		]) {
			var rejected = false;
			try {
				TypedControlStatements.functionBody(ELoweredControl(FunctionBody, "function", [entry], position));
			} catch (error:String) {
				rejected = error.indexOf("layout or destination") >= 0;
			}
			if (!rejected)
				throw "invalid local control destination was accepted";
		}
		Sys.println("JS_CONTROL_REGION:PASS");
	}
}
