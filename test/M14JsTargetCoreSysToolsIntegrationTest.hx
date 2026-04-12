import backend.BackendContext;
import backend.js.JsBackend;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

class M14JsTargetCoreSysToolsIntegrationTest {
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

	static function typedModule(source:String, decl:HxModuleDecl, filePath:String):TypedModule {
		return TyperStage.typeModule(new ParsedModule(source, decl, filePath));
	}

	static function sysToolsModule():TypedModule {
		final arg = new HxFunctionArg("argument", "String", HxDefaultValue.NoDefault);
		final escape = new HxFunctionArg("escapeMetaCharacters", "Bool", HxDefaultValue.NoDefault);
		final unsupportedBody = [
			HxStmt.SReturn(HxExpr.EUnsupported("regex-literal-placeholder"), HxPos.unknown())
		];
		final sysTools = new HxClassDecl("SysTools", false, [
			new HxFunctionDecl("quoteUnixArg", HxVisibility.Public, true, [arg], "String", unsupportedBody, ""),
			new HxFunctionDecl("quoteWinArg", HxVisibility.Public, true, [arg, escape], "String", unsupportedBody, "")
		]);
		final decl = new HxModuleDecl("haxe", [], sysTools, [sysTools], false, false);
		return typedModule("", decl, "haxe/SysTools.hx");
	}

	static function mainModule(source:String):TypedModule {
		final parsed = ParserStage.parse(source, "Main.hx");
		return TyperStage.typeModule(parsed);
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
		final tmpRoot = Path.normalize(".tmp/m14_js_target_core_systools_" + Std.string(Date.now().getTime()));
		final outDir = Path.join([tmpRoot, "out"]);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);

		var failure:Null<String> = null;
		try {
			final source = [
				"class Main {",
				"  static function main() {",
				'    Sys.println(SysTools.quoteUnixArg("a b"));',
				'    Sys.println(SysTools.quoteUnixArg("abc"));',
				'    Sys.println(SysTools.quoteWinArg("ab c", false));',
				"  }",
				"}"
			].join("\n");
			final program = new MacroExpandedProgram([mainModule(source), sysToolsModule()], false);
			FileSystem.createDirectory(outDir);
			final artifactPath = Path.join([outDir, "main.js"]);
			final context = new BackendContext(outDir, artifactPath, "Main", true, false, HxDefineMap.fromRawDefines(["js=1", "js-es=5"]));
			new JsBackend().emit(program, context);

			final js = File.getContent(artifactPath);
			assertContains(js, "__hx_cls_haxe_SysTools.quoteUnixArg = function", "SysTools quoteUnixArg shim should emit");
			assertContains(js, "__hx_cls_haxe_SysTools.quoteWinArg = function", "SysTools quoteWinArg shim should emit");

			final stdout = runNodeScript(artifactPath);
			assertContains(stdout, "'a b'", "quoteUnixArg should quote shell-unsafe spaces");
			assertContains(stdout, "abc", "quoteUnixArg should preserve shell-safe text");
			assertContains(stdout, "\"ab c\"", "quoteWinArg should quote space-containing text");
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
