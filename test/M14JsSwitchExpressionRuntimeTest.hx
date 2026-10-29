/** Compare original source-switch behavior with upstream before retiring raw-emitter assertions. */
class M14JsSwitchExpressionRuntimeTest {
	/** Check ordered trace effects without confusing the known formatting gap with catch behavior. */
	static function assertUpstreamOutput(path:String, source:String, root:String):Void {
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", "node", "--use-strict", path]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		final lines = source.split("\n");
		final expected = [
			for (index in 0...lines.length)
				switch (StringTools.trim(lines[index])) {
					case "trace(e);":
						root + "/Main.hx:" + (index + 1) + ": failure\n";
					case "trace(name);":
						root + "/Main.hx:" + (index + 1) + ": observer\n";
					case _:
						"";
				}
		].join("");
		if (code != 0 || stderr != "" || stdout != expected)
			throw "upstream switch observer differs: " + code + "\n" + stdout + stderr;
	}

	public static function run():Void {
		final root = "test/fixtures/js_switch_expression";
		final quotations = "test/fixtures/js_macro_quotation/support";
		final source = sys.io.File.getContent(root + "/Main.hx");
		final output = JsRuntimeFixture.reserveOutput();
		final configured = Sys.getEnv("HXHX_UPSTREAM_HAXE");
		@:privateAccess M14JsFunctionLiteralRuntimeTest.command(configured == null ? "node_modules/.bin/haxe" : configured,
			["-cp", root, "-cp", quotations, "-main", "Main", "-js", output + "/upstream.js"]);
		assertUpstreamOutput(output + "/upstream.js", source, root);
		Sys.println("JS_SWITCH_EXPRESSION_UPSTREAM:PASS");
		final program = JsSourceProgramFixture.build({
			sources: [
				{path: "Main.hx", source: source},
				{path: "QuotationCases.hx", source: sys.io.File.getContent(quotations + "/QuotationCases.hx")}
			],
			requiredModules: ["Std", "Array", "haxe.macro.Expr"],
			mode: "full"
		});
		// Bare tracing still omits positions and ignores logger replacement (haxe_ocaml-hgtz2).
		// Preserve this test's original ordered effects and final rethrow contract.
		JsRuntimeFixture.assertProgramRuntime(program, "Main", "failure\nobserver\n", ["--use-strict"]);
		Sys.println("JS_SWITCH_EXPRESSION_RUNTIME:PASS");
		sys.FileSystem.deleteFile(output + "/upstream.js");
		sys.FileSystem.deleteDirectory(output);
	}

	static function main():Void {
		run();
	}
}
