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

	static function unsupportedBody(reason:String):Array<HxStmt> {
		return [HxStmt.SReturn(HxExpr.EUnsupported(reason), HxPos.unknown())];
	}

	static function sysToolsModule():TypedModule {
		final arg = new HxFunctionArg("argument", "String", HxDefaultValue.NoDefault);
		final escape = new HxFunctionArg("escapeMetaCharacters", "Bool", HxDefaultValue.NoDefault);
		final sysTools = new HxClassDecl("SysTools", false, [
			new HxFunctionDecl("quoteUnixArg", HxVisibility.Public, true, [arg], "String", unsupportedBody("regex-literal-placeholder"), ""),
			new HxFunctionDecl("quoteWinArg", HxVisibility.Public, true, [arg, escape], "String", unsupportedBody("regex-literal-placeholder"), "")
		]);
		final decl = new HxModuleDecl("haxe", [], sysTools, [sysTools], false, false);
		return typedModule("", decl, "haxe/SysTools.hx");
	}

	static function pathModule():TypedModule {
		final pathArg = new HxFunctionArg("path", "String", HxDefaultValue.NoDefault);
		final extArg = new HxFunctionArg("ext", "String", HxDefaultValue.NoDefault);
		final pathsArg = new HxFunctionArg("paths", "Array<String>", HxDefaultValue.NoDefault);
		final allowSlashesArg = new HxFunctionArg("allowSlashes", "Bool", HxDefaultValue.NoDefault);
		final path = new HxClassDecl("Path", false, [
			new HxFunctionDecl("withoutExtension", HxVisibility.Public, true, [pathArg], "String", unsupportedBody("body_parse_error"), ""),
			new HxFunctionDecl("withoutDirectory", HxVisibility.Public, true, [pathArg], "String", unsupportedBody("body_parse_error"), ""),
			new HxFunctionDecl("directory", HxVisibility.Public, true, [pathArg], "String", unsupportedBody("body_parse_error"), ""),
			new HxFunctionDecl("extension", HxVisibility.Public, true, [pathArg], "String", unsupportedBody("body_parse_error"), ""),
			new HxFunctionDecl("withExtension", HxVisibility.Public, true, [pathArg, extArg], "String", unsupportedBody("body_parse_error"), ""),
			new HxFunctionDecl("join", HxVisibility.Public, true, [pathsArg], "String", unsupportedBody("body_parse_error"), ""),
			new HxFunctionDecl("normalize", HxVisibility.Public, true, [pathArg], "String", unsupportedBody("body_parse_error"), ""),
			new HxFunctionDecl("addTrailingSlash", HxVisibility.Public, true, [pathArg], "String", unsupportedBody("body_parse_error"), ""),
			new HxFunctionDecl("removeTrailingSlashes", HxVisibility.Public, true, [pathArg], "String", unsupportedBody("body_parse_error"), ""),
			new HxFunctionDecl("isAbsolute", HxVisibility.Public, true, [pathArg], "Bool", unsupportedBody("body_parse_error"), ""),
			new HxFunctionDecl("unescape", HxVisibility.Private, true, [pathArg], "String", unsupportedBody("body_parse_error"), ""),
			new HxFunctionDecl("escape", HxVisibility.Private, true, [pathArg, allowSlashesArg], "String", unsupportedBody("body_parse_error"), "")
		]);
		final decl = new HxModuleDecl("haxe.io", [], path, [path], false, false);
		return typedModule("", decl, "haxe/io/Path.hx");
	}

	static function lambdaModule():TypedModule {
		final iterableArg = new HxFunctionArg("it", "Array<Array<Int>>", HxDefaultValue.NoDefault);
		final mapperArg = new HxFunctionArg("f", "Int->Array<Int>", HxDefaultValue.NoDefault);
		final lambdaClass = new HxClassDecl("Lambda", false, [
			new HxFunctionDecl("flatten", HxVisibility.Public, true, [iterableArg], "Array<Int>", unsupportedBody("body_parse_error"), ""),
			new HxFunctionDecl("flatMap", HxVisibility.Public, true, [iterableArg, mapperArg], "Array<Int>", unsupportedBody("body_parse_error"), "")
		]);
		final decl = new HxModuleDecl("", [], lambdaClass, [lambdaClass], false, false);
		return typedModule("", decl, "Lambda.hx");
	}

	static function macroModule():TypedModule {
		final inputArg = new HxFunctionArg("input", "String", HxDefaultValue.NoDefault);
		final metadataArg = new HxFunctionArg("meta", "Metadata", HxDefaultValue.NoDefault);
		final macroClass = new HxClassDecl("Macro", false, [
			new HxFunctionDecl("register", HxVisibility.Public, true, [inputArg], "Void", unsupportedBody("body_parse_error"), ""),
			new HxFunctionDecl("run", HxVisibility.Public, true, [], "Void", unsupportedBody("body_parse_error"), ""),
			new HxFunctionDecl("test", HxVisibility.Public, true, [], "Void", unsupportedBody("body_parse_error"), ""),
			new HxFunctionDecl("stripWhitespaces", HxVisibility.Public, true, [inputArg], "String", unsupportedBody("[js-native:unsupported_expr]"), ""),
			new HxFunctionDecl("extractJs", HxVisibility.Public, true, [metadataArg], "String", unsupportedBody("body_parse_error"), ""),
			new HxFunctionDecl("getOutput", HxVisibility.Public, true, [inputArg], "String", unsupportedBody("body_parse_error"), "")
		]);
		final decl = new HxModuleDecl("", [], macroClass, [macroClass], false, false);
		return typedModule("", decl, "Macro.hx");
	}

	static function macroCompilerModule():TypedModule {
		final flagArg = new HxFunctionArg("flag", "String", HxDefaultValue.NoDefault);
		final compilerClass = new HxClassDecl("Compiler", false, [
			new HxFunctionDecl("getDefine", HxVisibility.Public, true, [flagArg], "String", unsupportedBody("[js-native:unsupported_expr]"), "")
		]);
		final decl = new HxModuleDecl("haxe.macro", [], compilerClass, [compilerClass], false, false);
		return typedModule("", decl, "haxe/macro/Compiler.hx");
	}

	static function macroContextModule():TypedModule {
		final contextClass = new HxClassDecl("Context", false, [
			new HxFunctionDecl("getLocalClass", HxVisibility.Public, true, [], "String", unsupportedBody("body_parse_error"), "")
		]);
		final decl = new HxModuleDecl("haxe.macro", [], contextClass, [contextClass], false, false);
		return typedModule("", decl, "haxe/macro/Context.hx");
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
				'    Sys.println(Path.normalize("foo//bar/./baz"));',
				'    Sys.println(Path.normalize("/foo/../bar"));',
				'    Sys.println(Path.removeTrailingSlashes("foo///"));',
				'    Sys.println(Path.withoutExtension("dir/name.txt"));',
				'    Sys.println(Path.join(["foo", "bar", "..", "baz"]));',
				'    Sys.println(Lambda.flatten([[1, 2], [3]]).join(","));',
				"  }",
				"}"
			].join("\n");
			final program = new MacroExpandedProgram([
				mainModule(source),
				sysToolsModule(),
				pathModule(),
				lambdaModule(),
				macroModule(),
				macroCompilerModule(),
				macroContextModule()
			], false);
			FileSystem.createDirectory(outDir);
			final artifactPath = Path.join([outDir, "main.js"]);
			final context = new BackendContext(outDir, artifactPath, "Main", true, false, HxDefineMap.fromRawDefines(["js=1", "js-es=5"]));
			new JsBackend().emit(program, context);

			final js = File.getContent(artifactPath);
			assertContains(js, "__hx_cls_haxe_SysTools.quoteUnixArg = function", "SysTools quoteUnixArg shim should emit");
			assertContains(js, "__hx_cls_haxe_SysTools.quoteWinArg = function", "SysTools quoteWinArg shim should emit");
			assertContains(js, "__hx_cls_haxe_io_Path.normalize = function", "Path normalize shim should emit");
			assertContains(js, "__hx_cls_Macro.stripWhitespaces = function", "compile-time Macro fallback should emit");
			assertContains(js, "__hx_cls_Macro.extractJs = function", "compile-time Macro extractJs fallback should emit");
			assertContains(js, "__hx_cls_haxe_macro_Compiler.getDefine = function", "compile-time macro Compiler fallback should emit");
			assertContains(js, "__hx_cls_haxe_macro_Context.getLocalClass = function", "compile-time macro Context fallback should emit");
			assertContains(js, "__hx_cls_Lambda.flatten = function", "Lambda flatten shim should emit");

			final stdout = runNodeScript(artifactPath);
			assertContains(stdout, "'a b'", "quoteUnixArg should quote shell-unsafe spaces");
			assertContains(stdout, "abc", "quoteUnixArg should preserve shell-safe text");
			assertContains(stdout, "\"ab c\"", "quoteWinArg should quote space-containing text");
			assertContains(stdout, "foo/bar/baz", "Path.normalize should collapse relative path segments");
			assertContains(stdout, "/bar", "Path.normalize should preserve absolute paths while resolving parents");
			assertContains(stdout, "foo", "Path.removeTrailingSlashes should trim slash suffixes");
			assertContains(stdout, "dir/name", "Path.withoutExtension should remove the final file extension");
			assertContains(stdout, "foo/baz", "Path.join should combine and normalize segments");
			assertContains(stdout, "1,2,3", "Lambda.flatten should concatenate nested iterables");
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
