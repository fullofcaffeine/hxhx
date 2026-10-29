/** Retain upstream expectations and the exact unsupported boundary until general extractors are implemented. */
class M14JsGeneralExtractorRuntimeTest {
	/** Verify the independent source first, then load its ordinary typed declarations. */
	static function load():MacroExpandedProgram {
		final root = "test/fixtures/js_general_extractors";
		final output = JsRuntimeFixture.reserveOutput();
		final configured = Sys.getEnv("HXHX_UPSTREAM_HAXE");
		@:privateAccess M14JsFunctionLiteralRuntimeTest.command(configured == null ? "node_modules/.bin/haxe" : configured,
			["-cp", root, "-main", "Main", "-js", output + "/upstream.js"]);
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", "node", "--use-strict", output + "/upstream.js"]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != "" || stderr != "")
			throw "upstream general extractor observer differs: " + stdout + stderr;
		@:privateAccess JsRuntimeFixture.removeOutput(output);
		Sys.println("JS_GENERAL_EXTRACTOR_UPSTREAM:PASS");
		return JsSourceProgramFixture.build({
			sources: [
				for (name in ["Main.hx", "Extractors.hx"])
					{path: name, source: sys.io.File.getContent(root + "/" + name)}
			],
			requiredModules: [],
			mode: "full"
		});
	}

	/** The integration gate records an explicit rejection, never general-extractor runtime support. */
	public static function assertCurrentBoundary():Void {
		final program = load();
		final output = JsRuntimeFixture.reserveOutput();
		try {
			new backend.js.JsBackend().emit(program,
				new backend.BackendContext(output, output + "/main.js", "Main", false, HxDefineMap.fromRawDefines(["js=1", "js-es=5"])));
		} catch (message:String) {
			if (message.indexOf("JavaScript named pattern requires its exact selected declaration in Main.extract") < 0)
				throw message;
			@:privateAccess JsRuntimeFixture.removeOutput(output);
			Sys.println("JS_GENERAL_EXTRACTOR_UNSUPPORTED:PASS");
			return;
		}
		throw "general extractor support changed; reconcile haxe_ocaml-l0oh8 and require the strict runtime observer";
	}

	/** This strict command remains failing until haxe_ocaml-l0oh8 preserves actual extractor behavior. */
	static function main():Void {
		JsRuntimeFixture.assertProgramRuntime(load(), "Main", "", ["--use-strict"]);
		Sys.println("JS_GENERAL_EXTRACTOR_RUNTIME:PASS");
	}
}
