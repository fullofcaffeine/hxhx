import hxhx.Stage3SetupSupport;
import backend.BackendContext;
import backend.js.JsBackend;

/** Execute enum helpers only after typing their authentic standard-library dependency closure. */
class M14DefaultEnumExtensionRuntimeTest {
	static function main():Void {
		final root = "test/oracle/default_enum_extension_seed";
		final expected = sys.io.File.getContent(root + "/expected.stdout");
		final compiler = Sys.getEnv("HXHX_UPSTREAM_HAXE");
		final upstream = new sys.io.Process(compiler == null ? "node_modules/.bin/haxe" : compiler, ["-cp", root, "-main", "Main", "--interp"]);
		final output = upstream.stdout.readAll().toString();
		final errors = upstream.stderr.readAll().toString();
		final code = upstream.exitCode();
		upstream.close();
		if (code != 0 || errors.length != 0 || !StringTools.endsWith(output, ": " + expected))
			throw "upstream enum helpers differ: " + output + errors;
		Sys.println("DEFAULT_ENUM_EXTENSION_UPSTREAM:PASS");
		final defines = Stage3SetupSupport.buildDefinesMap(["js-es=5"], "js", "js-native");
		final program = JsSourceProgramFixture.build({
			sources: [{path: "Main.hx", source: sys.io.File.getContent(root + "/Main.hx")}],
			requiredModules: ["haxe.EnumTools", "Type"],
			defines: ["js-es=5"]
		});
		final outputRoot = ".tmp/default-enum-extension-runtime";
		final script = outputRoot + "/main.js";
		new JsBackend().emit(program, new BackendContext(outputRoot, script, "Main", true, false, defines));
		final child = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["60", "node", script]);
		final stdout = child.stdout.readAll().toString();
		final stderr = child.stderr.readAll().toString();
		final status = child.exitCode();
		child.close();
		if (status != 0 || stdout != expected || stderr.length != 0)
			throw "enum helper runtime differs: " + stdout + stderr;
		Sys.println("DEFAULT_ENUM_EXTENSION_RUNTIME:PASS");
	}
}
