import sys.io.File;
import sys.FileSystem;

/**
	Observe authored try and block expressions after real provider typing and lowering.
	Upstream JavaScript and the candidate execute the same independent assertions.
	The fixture preserves the former raw-emitter behaviors without obsolete parser
	markers or dependence on generated temporary names.
 */
class M14JsExprEmitterTryCatchIntegrationTest {
	/** Bound upstream compilation and execution, retaining failed artifacts. */
	static function command(executable:String, arguments:Array<String>):Void {
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["30", executable].concat(arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != "" || stderr != "")
			throw "try/block observer failed: " + executable + ": " + code + "\n" + stdout + stderr;
	}

	static function main():Void {
		final root = "test/fixtures/js_try_values";
		final output = JsRuntimeFixture.reserveOutput();
		final upstream = Sys.getEnv("HXHX_UPSTREAM_HAXE");
		command(upstream == null ? "node_modules/.bin/haxe" : upstream, ["-cp", root, "-main", "Main", "-js", output + "/upstream.js"]);
		command("node", ["--use-strict", output + "/upstream.js"]);
		Sys.println("JS_TRY_VALUES_UPSTREAM:PASS");
		final program = JsSourceProgramFixture.build({
			sources: [{path: "Main.hx", source: File.getContent(root + "/Main.hx")}],
			requiredModules: ["haxe.Exception", "haxe.ds.StringMap"],
			mode: "full"
		});
		JsRuntimeFixture.assertProgramRuntime(program, "Main", "", ["--use-strict"]);
		FileSystem.deleteFile(output + "/upstream.js");
		FileSystem.deleteDirectory(output);
		Sys.println("JS_TRY_VALUES_RUNTIME:PASS");
	}
}
