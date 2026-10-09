import backend.BackendContext;
import backend.js.JsBackend;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

/** Real JS providers must retain native constructor use and execute the same library calls as upstream. */
class M14JsTargetCoreJsLibExternRuntimeIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack.indexOf(needle) < 0)
			throw label + " (missing `" + needle + "`)";
	}

	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
			return;
		}
		FileSystem.deleteFile(path);
	}

	/** Load the real JS library closure instead of emitting unresolved type names. */
	static function makeProgram(source:String):MacroExpandedProgram {
		return JsSourceProgramFixture.build({
			sources: [{path: "Main.hx", source: source}],
			requiredModules: [
				"Math",
				"Std",
				"haxe.io.FPHelper",
				"js.lib.ArrayBuffer",
				"js.lib.DataView",
				"js.lib.intl.NumberFormat"
			]
		});
	}

	static function runNodeScript(jsPath:String):String {
		final process = new sys.io.Process("node", [jsPath]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final exitCode = process.exitCode();
		process.close();
		assertTrue(exitCode == 0, "node execution failed for " + jsPath + " with exit " + exitCode + ": " + stderr);
		return StringTools.trim(stdout);
	}

	static function main():Void {
		final tmpRoot = Path.normalize(".tmp/m14_js_target_core_js_lib_runtime_" + Std.string(Date.now().getTime()));
		final outDir = Path.join([tmpRoot, "out"]);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);

		var failure:Null<String> = null;
		try {
			final source = [
				"class Main {",
				"  static function main() {",
				'    trace("fp=" + haxe.io.FPHelper.i32ToFloat(1065353216));',
				'    trace("intl=" + Std.string(new js.lib.intl.NumberFormat("en-US") != null));',
				"  }",
				"}"
			].join("\n");
			File.saveContent(Path.join([tmpRoot, "Main.hx"]), source);
			final upstreamJs = Path.join([tmpRoot, "upstream.js"]);
			assertTrue(Sys.command("node_modules/.bin/haxe", ["-cp", tmpRoot, "-main", "Main", "-dce", "no", "-js", upstreamJs]) == 0,
				"upstream library fixture must compile");
			final upstreamOutput = runNodeScript(upstreamJs);
			assertContains(upstreamOutput, "fp=1", "upstream FPHelper result");
			assertContains(upstreamOutput, "intl=true", "upstream Intl.NumberFormat construction");
			final program = makeProgram(source);
			FileSystem.createDirectory(outDir);
			final artifactPath = Path.join([outDir, "main.js"]);
			final context = new BackendContext(outDir, artifactPath, "Main", true, false, HxDefineMap.fromRawDefines(["js=1", "js-es=5"]));
			final result = new JsBackend().emit(program, context);

			assertTrue(result.entryPath == artifactPath, "unexpected emitted JS path");
			assertTrue(FileSystem.exists(artifactPath), "missing emitted JS artifact");

			final js = File.getContent(artifactPath);
			// Upstream reads these authored native paths at use, without startup aliases.
			assertContains(js, 'new DataView(new ArrayBuffer(8))', "FPHelper must initialize through native DataView and ArrayBuffer");
			assertContains(js, 'new Intl["NumberFormat"](', "NumberFormat must use the authored uppercase native namespace");
			for (name in ["ArrayBuffer", "DataView", "intl_NumberFormat"])
				assertTrue(js.indexOf("var __hx_cls_js_lib_" + name + " = ") < 0, "native extern must not create an eager alias or a placeholder: " + name);
			final fpHelperInitIndex = js.indexOf('__hx_cls_haxe_io_FPHelper.helper = ');
			final mainCallIndex = js.indexOf('__hx_cls_Main.main();');
			assertTrue(fpHelperInitIndex >= 0, "FPHelper helper initialization should be emitted");
			assertTrue(mainCallIndex > fpHelperInitIndex, "FPHelper must initialize before the program entry point runs");

			final stdout = runNodeScript(artifactPath);
			assertContains(stdout, "fp=1", "FPHelper should execute through native DataView/ArrayBuffer globals");
			assertContains(stdout, "intl=true", "Intl.NumberFormat should construct through native global");
		} catch (message:String) {
			failure = message;
		} catch (error:haxe.Exception) {
			failure = error.message;
		}

		if (failure != null) {
			trace("debug_out=" + tmpRoot);
			throw failure;
		}
		deleteRecursive(tmpRoot);
	}
}
