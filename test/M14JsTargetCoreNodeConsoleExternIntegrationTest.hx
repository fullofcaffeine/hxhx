import backend.BackendContext;
import backend.js.JsBackend;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

class M14JsTargetCoreNodeConsoleExternIntegrationTest {
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

	static function int64CompareModule():TypedModule {
		final left = new HxFunctionArg("left", "Dynamic", HxDefaultValue.NoDefault);
		final right = new HxFunctionArg("right", "Dynamic", HxDefaultValue.NoDefault);
		final compare = new HxFunctionDecl("compare", HxVisibility.Public, true, [left, right], "Int", unsupportedBody("if"), "");
		final ucompare = new HxFunctionDecl("ucompare", HxVisibility.Public, true, [left, right], "Int", unsupportedBody("if"), "");
		final int64Class = new HxClassDecl("Int64", false, [compare, ucompare], []);
		final int64Decl = new HxModuleDecl("haxe", [], int64Class, [int64Class], false, false);
		return TyperStage.typeModule(new ParsedModule("", int64Decl, "haxe/Int64.hx"));
	}

	static function emptyMainModule():TypedModule {
		final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [], "");
		final mainClass = new HxClassDecl("Main", true, [mainFn], []);
		final mainDecl = new HxModuleDecl("", [], mainClass, [mainClass], false, false);
		return TyperStage.typeModule(new ParsedModule("", mainDecl, "Main.hx"));
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
		final tmpRoot = Path.normalize(".tmp/m14_js_target_core_node_console_extern_" + Std.string(Date.now().getTime()));
		final outDir = Path.join([tmpRoot, "out"]);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);

		var failure:Null<String> = null;
		try {
			final stdoutArg = new HxFunctionArg("stdout", "Dynamic", HxDefaultValue.NoDefault);
			final consoleClass = new HxClassDecl("Console", false, [
				new HxFunctionDecl("new", HxVisibility.Public, false, [stdoutArg], "Void",
					unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=6"), "")
			]);
			final consoleDecl = new HxModuleDecl("js.node.console", [], consoleClass, [consoleClass], false, false);
			final consoleModule = TyperStage.typeModule(new ParsedModule("", consoleDecl, "js/node/console/Console.hx"));

			final consoleVar = HxStmt.SVar("nodeConsole", "js.node.console.Console",
				HxExpr.ENew("js.node.console.Console", [HxExpr.EField(HxExpr.EIdent("process"), "stdout")]), HxPos.unknown());
			final log = HxStmt.SExpr(HxExpr.ECall(HxExpr.EField(HxExpr.EIdent("nodeConsole"), "log"), [HxExpr.EString("console=ok")]), HxPos.unknown());
			final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [consoleVar, log], "");
			final mainClass = new HxClassDecl("Main", true, [mainFn], []);
			final mainDecl = new HxModuleDecl("", [], mainClass, [mainClass], false, false);
			final mainModule = TyperStage.typeModule(new ParsedModule("", mainDecl, "Main.hx"));
			final program = MacroStage.expandProgram([consoleModule, mainModule], []);

			FileSystem.createDirectory(outDir);
			final artifactPath = Path.join([outDir, "main.js"]);
			new JsBackend().emit(program, new BackendContext(outDir, artifactPath, "Main", true, false, HxDefineMap.fromRawDefines(["js=1"])));
			final js = File.getContent(artifactPath);
			assertContains(js, 'var __hx_cls_js_node_console_Console = require("console").Console;',
				"Node Console extern should bind to the Node console module export");
			assertContains(js, "var nodeConsole = new __hx_cls_js_node_console_Console(process.stdout);",
				"Console construction should use the bound Node Console constructor");
			assertNotContains(js, "detail=6", "unsupported extern constructor body should not leak into JS");

			final stdout = runNodeScript(artifactPath);
			assertContains(stdout, "console=ok", "Node Console instance should write through process.stdout");

			final int64OutDir = Path.join([tmpRoot, "int64"]);
			FileSystem.createDirectory(int64OutDir);
			final int64ArtifactPath = Path.join([int64OutDir, "main.js"]);
			new JsBackend().emit(MacroStage.expandProgram([int64CompareModule(), emptyMainModule()], []),
				new BackendContext(int64OutDir, int64ArtifactPath, "Main", true, false, HxDefineMap.fromRawDefines(["js=1"])));
			final int64Js = File.getContent(int64ArtifactPath);
			assertContains(int64Js, "var __hx_to_number = function(__hx_value)", "haxe.Int64.compare should use the audited JS-native helper body");
			assertContains(int64Js, "return __hx_left < __hx_right ? -1 : (__hx_left > __hx_right ? 1 : 0);",
				"haxe.Int64.compare should emit a numeric comparison result");
			assertNotContains(int64Js, "detail=if", "unsupported haxe.Int64 source body should not leak into JS");
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
