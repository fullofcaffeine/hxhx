import backend.BackendContext;
import backend.js.JsBackend;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

class M14JsTargetCoreNodeBufferExternIntegrationTest {
	static function assertTrue(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function assertContains(haystack:String, needle:String, label:String):Void {
		if (haystack.indexOf(needle) < 0)
			throw label + " (missing `" + needle + "`)";
	}

	static function assertNotContains(haystack:String, needle:String, label:String):Void {
		if (haystack.indexOf(needle) >= 0)
			throw label + " (unexpected `" + needle + "`)";
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

	static function unsupportedBody(reason:String):Array<HxStmt> {
		return [HxStmt.SReturn(HxExpr.EUnsupported(reason), HxPos.unknown())];
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
		final tmpRoot = Path.normalize(".tmp/m14_js_target_core_node_buffer_extern_" + Std.string(Date.now().getTime()));
		final outDir = Path.join([tmpRoot, "out"]);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);

		var failure:Null<String> = null;
		try {
			final stringArg = new HxFunctionArg("string", "String", HxDefaultValue.NoDefault);
			final bufferClass = new HxClassDecl("Buffer", false, [
				new HxFunctionDecl("new", HxVisibility.Public, false, [stringArg], "Void",
					unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=6"), "")
			], [], "js.lib.Uint8Array");
			final bufferDecl = new HxModuleDecl("js.node.buffer", [], bufferClass, [bufferClass], false, false);
			final bufferModule = TyperStage.typeModule(new ParsedModule("", bufferDecl, "js/node/buffer/Buffer.hx"));

			final bufferVar = HxStmt.SVar("buffer", "js.node.buffer.Buffer", HxExpr.ENew("js.node.buffer.Buffer", [HxExpr.EString("abc")]), HxPos.unknown());
			final printLength = HxStmt.SExpr(HxExpr.ECall(HxExpr.EField(HxExpr.EIdent("Sys"), "println"), [
				HxExpr.EBinop("+", HxExpr.EString("len="), HxExpr.EField(HxExpr.EIdent("buffer"), "length"))
			]), HxPos.unknown());
			final printText = HxStmt.SExpr(HxExpr.ECall(HxExpr.EField(HxExpr.EIdent("Sys"), "println"), [
				HxExpr.EBinop("+", HxExpr.EString("text="), HxExpr.ECall(HxExpr.EField(HxExpr.EIdent("buffer"), "toString"), []))
			]), HxPos.unknown());
			final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [bufferVar, printLength, printText], "");
			final mainClass = new HxClassDecl("Main", true, [mainFn], []);
			final mainDecl = new HxModuleDecl("", [], mainClass, [mainClass], false, false);
			final mainModule = TyperStage.typeModule(new ParsedModule("", mainDecl, "Main.hx"));
			final program = MacroStage.expandProgram([bufferModule, mainModule], []);

			FileSystem.createDirectory(outDir);
			final artifactPath = Path.join([outDir, "main.js"]);
			new JsBackend().emit(program, new BackendContext(outDir, artifactPath, "Main", true, false, HxDefineMap.fromRawDefines(["js=1"])));
			final js = File.getContent(artifactPath);
			assertContains(js, 'var __hx_cls_js_node_buffer_Buffer = require("buffer").Buffer;',
				"Node Buffer extern should bind to the Node buffer module export");
			assertContains(js, 'var buffer = new __hx_cls_js_node_buffer_Buffer("abc");', "Buffer construction should use the bound Node Buffer constructor");
			assertNotContains(js, "detail=6", "unsupported extern constructor body should not leak into JS");

			final stdout = runNodeScript(artifactPath);
			assertContains(stdout, "len=3", "Node Buffer length should execute through the host constructor");
			assertContains(stdout, "text=abc", "Node Buffer toString should execute through the host constructor");
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
