import backend.BackendContext;
import backend.js.JsBackend;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

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

	static function makeProgram(source:String, filePath:String):MacroExpandedProgram {
		final parsed = ParserStage.parse(source, filePath);
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
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
				'    Sys.println("fp=" + haxe.io.FPHelper.i32ToFloat(1065353216));',
				'    Sys.println("intl=" + Std.string(new js.lib.intl.NumberFormat("en-US") != null));',
				"  }",
				"}"
			].join("\n");
			final program = makeProgram(source, "JsLibExternRuntimeMain.hx");
			FileSystem.createDirectory(outDir);
			final artifactPath = Path.join([outDir, "main.js"]);
			final context = new BackendContext(outDir, artifactPath, "Main", true, false, HxDefineMap.fromRawDefines(["js=1", "js-es=5"]));
			final result = new JsBackend().emit(program, context);

			assertTrue(result.entryPath == artifactPath, "unexpected emitted JS path");
			assertTrue(FileSystem.exists(artifactPath), "missing emitted JS artifact");

			final js = File.getContent(artifactPath);
			assertContains(js, 'globalThis["ArrayBuffer"]', "js.lib.ArrayBuffer should reference native global");
			assertContains(js, 'globalThis["DataView"]', "js.lib.DataView should reference native global");
			assertContains(js, 'globalThis["Intl"]["NumberFormat"]', "js.lib.intl.NumberFormat should reference globalThis.Intl.NumberFormat");
			assertTrue(js.indexOf("var __hx_cls_js_lib_ArrayBuffer = {};") < 0, "js.lib.ArrayBuffer should not emit synthetic placeholder object");
			assertTrue(js.indexOf("var __hx_cls_js_lib_DataView = {};") < 0, "js.lib.DataView should not emit synthetic placeholder object");
			assertTrue(js.indexOf('var __hx_cls_js_lib_intl_NumberFormat = globalThis["intl"]["NumberFormat"];') < 0,
				"js.lib.intl.NumberFormat should not alias lowercase intl namespace");
			final arrayBufferAliasIndex = js.indexOf('__hx_cls_js_lib_ArrayBuffer = ');
			final fpHelperInitIndex = js.indexOf('__hx_cls_haxe_io_FPHelper.helper = ');
			assertTrue(arrayBufferAliasIndex >= 0, "js.lib.ArrayBuffer alias should be emitted");
			assertTrue(fpHelperInitIndex >= 0, "FPHelper helper initialization should be emitted");
			assertTrue(arrayBufferAliasIndex < fpHelperInitIndex, "js.lib.ArrayBuffer alias should be emitted before FPHelper static initialization");

			final stdout = runNodeScript(artifactPath);
			assertContains(stdout, "fp=1", "FPHelper should execute through native DataView/ArrayBuffer globals");
			assertContains(stdout, "intl=true", "Intl.NumberFormat should construct through native global");
		} catch (message:String) {
			failure = message;
		} catch (error:haxe.Exception) {
			failure = error.message;
		}

		if (failure != null) {
			Sys.println("debug_out=" + tmpRoot);
			throw failure;
		}
		deleteRecursive(tmpRoot);
	}
}
