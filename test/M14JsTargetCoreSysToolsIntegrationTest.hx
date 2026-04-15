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

	static function fileSystemModule():TypedModule {
		final pathArg = new HxFunctionArg("path", "String", HxDefaultValue.NoDefault);
		final fsClass = new HxClassDecl("FileSystem", false, [
			new HxFunctionDecl("exists", HxVisibility.Public, true, [pathArg], "Bool", unsupportedBody("[js-native:unsupported_expr] kind=ETryCatchRaw"), "")
		]);
		final decl = new HxModuleDecl("sys", [], fsClass, [fsClass], false, false);
		return typedModule("", decl, "sys/FileSystem.hx");
	}

	static function lambdaModule():TypedModule {
		final iterableArg = new HxFunctionArg("it", "Array<Array<Int>>", HxDefaultValue.NoDefault);
		final filterIterableArg = new HxFunctionArg("it", "Array<Int>", HxDefaultValue.NoDefault);
		final predicateArg = new HxFunctionArg("f", "Int->Bool", HxDefaultValue.NoDefault);
		final mapperArg = new HxFunctionArg("f", "Int->Array<Int>", HxDefaultValue.NoDefault);
		final lambdaClass = new HxClassDecl("Lambda", false, [
			new HxFunctionDecl("flatten", HxVisibility.Public, true, [iterableArg], "Array<Int>", unsupportedBody("body_parse_error"), ""),
			new HxFunctionDecl("filter", HxVisibility.Public, true, [filterIterableArg, predicateArg], "Array<Int>", unsupportedBody("if_missing_else"), ""),
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
		final ident = new HxFieldDecl("ident", HxVisibility.Private, true, "Dynamic", HxExpr.EUnsupported("[js-native:unsupported_expr]"));
		final compilerClass = new HxClassDecl("Compiler", false, [
			new HxFunctionDecl("getDefine", HxVisibility.Public, true, [flagArg], "String", unsupportedBody("[js-native:unsupported_expr]"), ""),
			new HxFunctionDecl("excludeFile", HxVisibility.Public, true, [flagArg], "Void",
				[HxStmt.SReturn(HxExpr.EString("should-not-emit"), HxPos.unknown())], "")
		], [ident]);
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

	static function macroTypeToolsModule():TypedModule {
		final typeToolsClass = new HxClassDecl("TypeTools", false, [
			new HxFunctionDecl("toField", HxVisibility.Public, true, [], "Dynamic", unsupportedBody("[js-native:unsupported_expr] kind=ETryCatchRaw"), "")
		]);
		final decl = new HxModuleDecl("haxe.macro", [], typeToolsClass, [typeToolsClass], false, false);
		return typedModule("", decl, "haxe/macro/TypeTools.hx");
	}

	static function utestAssertModule():TypedModule {
		final valueArg = new HxFunctionArg("v", "Dynamic", HxDefaultValue.NoDefault);
		final expectedArg = new HxFunctionArg("expected", "Dynamic", HxDefaultValue.NoDefault);
		final actualArg = new HxFunctionArg("value", "Dynamic", HxDefaultValue.NoDefault);
		final statusArg = new HxFunctionArg("status", "Dynamic", HxDefaultValue.NoDefault);
		final approxArg = new HxFunctionArg("approx", "Float", HxDefaultValue.NoDefault);
		final assertClass = new HxClassDecl("Assert", false, [
			new HxFunctionDecl("getTypeName", HxVisibility.Public, true, [valueArg], "String", unsupportedBody("body_parse_error"), ""),
			new HxFunctionDecl("sameAs", HxVisibility.Public, true, [expectedArg, actualArg, statusArg, approxArg], "Bool",
				unsupportedBody("body_parse_error"), "")
		]);
		final decl = new HxModuleDecl("utest", [], assertClass, [assertClass], false, false);
		return typedModule("", decl, "utest/Assert.hx");
	}

	static function utestHtmlReportModule():TypedModule {
		final platform = new HxFieldDecl("platform", HxVisibility.Private, true, "String",
			HxExpr.EUnsupported('[js-native:unsupported_expr] kind=EUnsupported detail=if php "php"#elseif cpp "cpp"#elseif js "javascript"#elseif flash "flash"#else "unknown"'));
		final reportClass = new HxClassDecl("HtmlReport", false, [], [platform]);
		final decl = new HxModuleDecl("utest.ui.text", [], reportClass, [reportClass], false, false);
		return typedModule("", decl, "utest/ui/text/HtmlReport.hx");
	}

	static function utestReportToolsModule():TypedModule {
		final reportArg = new HxFunctionArg("report", "Dynamic", HxDefaultValue.NoDefault);
		final statsArg = new HxFunctionArg("stats", "Dynamic", HxDefaultValue.NoDefault);
		final isOkArg = new HxFunctionArg("isOk", "Bool", HxDefaultValue.NoDefault);
		final toolsClass = new HxClassDecl("ReportTools", false, [
			new HxFunctionDecl("hasHeader", HxVisibility.Public, true, [reportArg, statsArg], "Bool", unsupportedBody("body_parse_error"), ""),
			new HxFunctionDecl("skipResult", HxVisibility.Public, true, [reportArg, statsArg, isOkArg], "Bool", unsupportedBody("body_parse_error"), ""),
			new HxFunctionDecl("hasOutput", HxVisibility.Public, true, [reportArg, statsArg], "Bool", unsupportedBody("body_parse_error"), "")
		]);
		final decl = new HxModuleDecl("utest.ui.common", [], toolsClass, [toolsClass], false, false);
		return typedModule("", decl, "utest/ui/common/ReportTools.hx");
	}

	static function jsBootModule():TypedModule {
		final valueArg = new HxFunctionArg("o", "Dynamic", HxDefaultValue.NoDefault);
		final indentArg = new HxFunctionArg("s", "String", HxDefaultValue.NoDefault);
		final bootClass = new HxClassDecl("Boot", false, [
			new HxFunctionDecl("__string_rec", HxVisibility.Public, true, [valueArg, indentArg], "String",
				unsupportedBody("[js-native:unsupported_expr] kind=ETryCatchRaw detail=opaque_block_expr"), "")
		]);
		final decl = new HxModuleDecl("js", [], bootClass, [bootClass], false, false);
		return typedModule("", decl, "js/Boot.hx");
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
				"import sys.FileSystem;",
				"import js.Boot;",
				"import utest.Assert;",
				"import utest.ui.common.ReportTools;",
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
				'    Sys.println(Lambda.filter([1, 2, 3, 4], function(i) return i > 2).join(","));',
				'    Sys.println(FileSystem.exists("."));',
				'    Sys.println(try { "try-ok"; } catch (e:Dynamic) { "try-fail"; });',
				'    Sys.println(Assert.getTypeName(null));',
				'    Sys.println(Assert.getTypeName(12));',
				'    Sys.println(Assert.getTypeName(12.5));',
				'    Sys.println(Assert.getTypeName("hi"));',
				'    Sys.println(Assert.getTypeName([1, 2]));',
				'    var sameStatus = { recursive: true, path: "", error: null, expectedValue: null, actualValue: null };',
				'    Sys.println(Assert.sameAs({ name: "utest", values: [1, 2] }, { name: "utest", values: [1, 2] }, sameStatus, 1e-5));',
				'    Sys.println(Assert.sameAs({ name: "utest" }, { name: "other" }, sameStatus, 1e-5));',
				'    Sys.println(sameStatus.error);',
				'    var report = { displayHeader: "ShowHeaderWithResults", displaySuccessResults: "NeverShowSuccessResults" };',
				'    var okStats = { isOk: true };',
				'    var badStats = { isOk: false };',
				"    Sys.println(ReportTools.hasHeader(report, okStats));",
				"    Sys.println(ReportTools.hasHeader(report, badStats));",
				"    Sys.println(ReportTools.skipResult(report, okStats, true));",
				"    Sys.println(ReportTools.hasOutput(report, okStats));",
				'    Sys.println(Boot.__string_rec({ name: "hxhx", items: [1, null] }, ""));',
				"  }",
				"}"
			].join("\n");
			final program = new MacroExpandedProgram([
				mainModule(source),
				sysToolsModule(),
				pathModule(),
				fileSystemModule(),
				lambdaModule(),
				macroModule(),
				macroCompilerModule(),
				macroContextModule(),
				macroTypeToolsModule(),
				utestAssertModule(),
				utestHtmlReportModule(),
				utestReportToolsModule(),
				jsBootModule()
			], false);
			FileSystem.createDirectory(outDir);
			final artifactPath = Path.join([outDir, "main.js"]);
			final context = new BackendContext(outDir, artifactPath, "Main", true, false, HxDefineMap.fromRawDefines(["js=1", "js-es=5"]));
			new JsBackend().emit(program, context);

			final js = File.getContent(artifactPath);
			assertContains(js, "__hx_cls_haxe_SysTools.quoteUnixArg = function", "SysTools quoteUnixArg shim should emit");
			assertContains(js, "__hx_cls_haxe_SysTools.quoteWinArg = function", "SysTools quoteWinArg shim should emit");
			assertContains(js, "__hx_cls_haxe_io_Path.normalize = function", "Path normalize shim should emit");
			assertContains(js, "__hx_cls_sys_FileSystem.exists = function", "FileSystem exists shim should emit");
			assertContains(js, "try {  return \"try-ok\";", "try expression should lower to a returning IIFE");
			assertContains(js, "__hx_cls_Macro.stripWhitespaces = function", "compile-time Macro fallback should emit");
			assertContains(js, "__hx_cls_Macro.extractJs = function", "compile-time Macro extractJs fallback should emit");
			assertContains(js, "__hx_cls_haxe_macro_Compiler.getDefine = function", "compile-time macro Compiler fallback should emit");
			assertContains(js, "__hx_cls_haxe_macro_Compiler.excludeFile = function", "parsed compile-time macro Compiler body should emit neutral function");
			assertContains(js, "__hx_cls_haxe_macro_Context.getLocalClass = function", "compile-time macro Context fallback should emit");
			assertContains(js, "__hx_cls_haxe_macro_TypeTools.toField = function", "compile-time macro TypeTools fallback should emit");
			assertContains(js, "__hx_cls_Lambda.flatten = function", "Lambda flatten shim should emit");
			assertContains(js, "__hx_cls_Lambda.filter = function", "Lambda filter shim should emit");
			assertContains(js, "__hx_cls_utest_Assert.getTypeName = function", "utest Assert getTypeName shim should emit");
			assertContains(js, "__hx_cls_utest_Assert.sameAs = function", "utest Assert sameAs shim should emit");
			assertContains(js, "__hx_cls_utest_ui_text_HtmlReport.platform = \"javascript\"",
				"utest HtmlReport platform static initializer should resolve for JS");
			assertContains(js, "__hx_cls_utest_ui_common_ReportTools.hasHeader = function", "utest ReportTools hasHeader shim should emit");
			assertContains(js, "__hx_cls_utest_ui_common_ReportTools.skipResult = function", "utest ReportTools skipResult shim should emit");
			assertContains(js, "__hx_cls_utest_ui_common_ReportTools.hasOutput = function", "utest ReportTools hasOutput shim should emit");
			assertContains(js, "__hx_cls_js_Boot.__string_rec = function", "js Boot string recursion shim should emit");
			assertContains(js, "__hx_cls_haxe_macro_Compiler.ident = null", "compile-time macro Compiler field fallback should emit");
			assertNotContains(js, "should-not-emit", "compile-time macro API function bodies should be neutralized before regular JS emission");

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
			assertContains(stdout, "3,4", "Lambda.filter should preserve matching items");
			assertContains(stdout, "true", "FileSystem.exists should use Node fs existsSync");
			assertContains(stdout, "try-ok", "try expression should return the successful branch value");
			assertContains(stdout, "`null`", "utest Assert.getTypeName should name null values");
			assertContains(stdout, "Int", "utest Assert.getTypeName should name integer values");
			assertContains(stdout, "Float", "utest Assert.getTypeName should name float values");
			assertContains(stdout, "String", "utest Assert.getTypeName should name string values");
			assertContains(stdout, "Array", "utest Assert.getTypeName should name array values");
			assertContains(stdout, "expected \"utest\" but it is \"other\"", "utest Assert.sameAs should report nested field mismatch");
			assertContains(stdout, "false\ntrue\ntrue\nfalse", "utest ReportTools should preserve header/output display policy");
			assertContains(stdout, "name : hxhx", "js Boot string recursion should render object fields");
			assertContains(stdout, "items : [1,null]", "js Boot string recursion should render arrays recursively");
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
