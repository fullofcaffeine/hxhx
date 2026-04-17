import backend.BackendContext;
import backend.js.JsBackend;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

class M14JsTargetCoreNodeUrlExternIntegrationTest {
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
		final tmpRoot = Path.normalize(".tmp/m14_js_target_core_node_url_extern_" + Std.string(Date.now().getTime()));
		final outDir = Path.join([tmpRoot, "out"]);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);

		var failure:Null<String> = null;
		try {
			final inputArg = new HxFunctionArg("input", "String", HxDefaultValue.NoDefault);
			final urlClass = new HxClassDecl("URL", false, [
				new HxFunctionDecl("new", HxVisibility.Public, false, [inputArg], "Void",
					unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=6"), "")
			]);
			final urlDecl = new HxModuleDecl("js.node.url", [], urlClass, [urlClass], false, false);
			final urlModule = TyperStage.typeModule(new ParsedModule("", urlDecl, "js/node/url/URL.hx"));

			final urlVar = HxStmt.SVar("url", "js.node.url.URL", HxExpr.ENew("js.node.url.URL", [HxExpr.EString("https://example.com/path?q=1")]),
				HxPos.unknown());
			final printHost = HxStmt.SExpr(HxExpr.ECall(HxExpr.EField(HxExpr.EIdent("Sys"), "println"), [
				HxExpr.EBinop("+", HxExpr.EString("host="), HxExpr.EField(HxExpr.EIdent("url"), "host"))
			]), HxPos.unknown());
			final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [urlVar, printHost], "");
			final mainClass = new HxClassDecl("Main", true, [mainFn], []);
			final mainDecl = new HxModuleDecl("", [], mainClass, [mainClass], false, false);
			final mainModule = TyperStage.typeModule(new ParsedModule("", mainDecl, "Main.hx"));
			final program = MacroStage.expandProgram([urlModule, mainModule], []);

			FileSystem.createDirectory(outDir);
			final artifactPath = Path.join([outDir, "main.js"]);
			new JsBackend().emit(program, new BackendContext(outDir, artifactPath, "Main", true, false, HxDefineMap.fromRawDefines(["js=1"])));
			final js = File.getContent(artifactPath);
			assertContains(js, 'var __hx_cls_js_node_url_URL = require("url").URL;', "Node URL extern should bind to the Node url module export");
			assertContains(js, 'var url = new __hx_cls_js_node_url_URL("https://example.com/path?q=1");',
				"URL construction should use the bound Node URL constructor");
			assertNotContains(js, "detail=6", "unsupported extern constructor body should not leak into JS");

			final stdout = runNodeScript(artifactPath);
			assertContains(stdout, "host=example.com", "Node URL instance should execute through the host constructor");
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
