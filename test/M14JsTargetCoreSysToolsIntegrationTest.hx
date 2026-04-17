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

	static function sysIoFileModule():TypedModule {
		final copyBufLen = new HxFieldDecl("copyBufLen", HxVisibility.Private, true, "Int", HxExpr.EInt(65536));
		final copyBuf = new HxFieldDecl("copyBuf", HxVisibility.Private, true, "Dynamic",
			HxExpr.EUnsupported("[js-native:unsupported_expr] kind=EUnsupported detail=js.node.Buffer.alloc(copyBufLen)"));
		final fileClass = new HxClassDecl("File", false, [], [copyBufLen, copyBuf]);
		final decl = new HxModuleDecl("sys.io", [], fileClass, [fileClass], false, false);
		return typedModule("", decl, "sys/io/File.hx");
	}

	static function sysIoFileInputModule():TypedModule {
		final pArg = new HxFunctionArg("p", "Int", HxDefaultValue.NoDefault);
		final posArg = new HxFunctionArg("pos", "sys.io.FileSeek", HxDefaultValue.NoDefault);
		final fileInputClass = new HxClassDecl("FileInput", false, [
			new HxFunctionDecl("seek", HxVisibility.Public, false, [pArg, posArg], "Void",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=sys-fileinput-seek"), "")
		]);
		final decl = new HxModuleDecl("sys.io", [], fileInputClass, [fileInputClass], false, false);
		return typedModule("", decl, "sys/io/FileInput.hx");
	}

	static function sysIoFileOutputModule():TypedModule {
		final pArg = new HxFunctionArg("p", "Int", HxDefaultValue.NoDefault);
		final posArg = new HxFunctionArg("pos", "sys.io.FileSeek", HxDefaultValue.NoDefault);
		final fileOutputClass = new HxClassDecl("FileOutput", false, [
			new HxFunctionDecl("seek", HxVisibility.Public, false, [pArg, posArg], "Void",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=sys-fileoutput-seek"), "")
		]);
		final decl = new HxModuleDecl("sys.io", [], fileOutputClass, [fileOutputClass], false, false);
		return typedModule("", decl, "sys/io/FileOutput.hx");
	}

	static function sysIoProcessModule():TypedModule {
		final cmdArg = new HxFunctionArg("cmd", "String", HxDefaultValue.NoDefault);
		final argsArg = new HxFunctionArg("args", "Array<String>", HxDefaultValue.NoDefault);
		final processClass = new HxClassDecl("Process", false, [
			new HxFunctionDecl("new", HxVisibility.Public, false, [cmdArg, argsArg], "Void",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=6"), ""),
			new HxFunctionDecl("close", HxVisibility.Public, false, [], "Int", unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=6"), "")
		]);
		final decl = new HxModuleDecl("sys.io", [], processClass, [processClass], false, false);
		return typedModule("", decl, "sys/io/Process.hx");
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

	static function stdModule():TypedModule {
		final valueArg = new HxFunctionArg("s", "Dynamic", HxDefaultValue.NoDefault);
		final intArg = new HxFunctionArg("x", "Float", HxDefaultValue.NoDefault);
		final stdClass = new HxClassDecl("Std", false, [
			new HxFunctionDecl("string", HxVisibility.Public, true, [valueArg], "String", unsupportedBody("body_parse_error"), ""),
			new HxFunctionDecl("int", HxVisibility.Public, true, [intArg], "Int", unsupportedBody("body_parse_error"), ""),
			new HxFunctionDecl("parseInt", HxVisibility.Public, true, [valueArg], "Null<Int>", unsupportedBody("body_parse_error"), ""),
			new HxFunctionDecl("parseFloat", HxVisibility.Public, true, [valueArg], "Float", unsupportedBody("body_parse_error"), ""),
			new HxFunctionDecl("random", HxVisibility.Public, true, [intArg], "Int", unsupportedBody("body_parse_error"), "")
		]);
		final decl = new HxModuleDecl("", [], stdClass, [stdClass], false, false);
		return typedModule("", decl, "Std.hx");
	}

	static function haxeRestModule():TypedModule {
		final arrayArg = new HxFunctionArg("array", "Array<Dynamic>", HxDefaultValue.NoDefault);
		final restClass = new HxClassDecl("Rest", false, [
			new HxFunctionDecl("new", HxVisibility.Public, false, [arrayArg], "Void",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=6"), "")
		]);
		final decl = new HxModuleDecl("haxe", [], restClass, [restClass], false, false);
		return typedModule("", decl, "haxe/Rest.hx");
	}

	static function jsCtorFixtureModule():TypedModule {
		final source = [
			"class JsCtorBase {",
			"  public function new() {",
			"    init();",
			'    Main.ctorCalls.push("BASE");',
			"  }",
			"  function init() {}",
			"}",
			"class JsCtorChild extends JsCtorBase {",
			'  var label = "CHILD";',
			"  override function init() Main.ctorCalls.push(label);",
			"  public function new() {",
			'    Main.ctorCalls.push("PRE");',
			"    super();",
			"  }",
			"}",
			"class JsCtorLeaf extends JsCtorChild {",
			"  public function new() {",
			"    super();",
			'    Main.ctorCalls.push("LEAF");',
			"  }",
			"}"
		].join("\n");
		final parsed = ParserStage.parse(source, "JsCtorFixture.hx");
		return TyperStage.typeModule(parsed);
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

	static function reservedParamModule():TypedModule {
		final callbackArg = new HxFunctionArg("callback", "Dynamic", HxDefaultValue.NoDefault);
		final argumentsArg = new HxFunctionArg("arguments", "Dynamic", HxDefaultValue.NoDefault);
		final evalArg = new HxFunctionArg("eval", "Dynamic", HxDefaultValue.NoDefault);
		final reservedParam = new HxClassDecl("ReservedParam", false, [
			new HxFunctionDecl("call_user_func", HxVisibility.Public, true, [callbackArg, argumentsArg], "Dynamic",
				[HxStmt.SReturn(HxExpr.EIdent("arguments"), HxPos.unknown())], ""),
			new HxFunctionDecl("call_eval", HxVisibility.Public, true, [evalArg], "Dynamic", [HxStmt.SReturn(HxExpr.EIdent("eval"), HxPos.unknown())], "")
		]);
		final decl = new HxModuleDecl("", [], reservedParam, [reservedParam], false, false);
		return typedModule("", decl, "ReservedParam.hx");
	}

	static function upstreamUnitHelperMacrosModule():TypedModule {
		final helperClass = new HxClassDecl("HelperMacros", false, [
			new HxFunctionDecl("getCompilationDate", HxVisibility.Public, true, [], "String",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=5"), "")
		]);
		final decl = new HxModuleDecl("unit", [], helperClass, [helperClass], false, false);
		return typedModule("", decl, "unit/HelperMacros.hx");
	}

	static function upstreamUnitTestIssuesModule():TypedModule {
		final helperClass = new HxClassDecl("TestIssues", false, [
			new HxFunctionDecl("addIssueClasses", HxVisibility.Public, true, [], "Dynamic",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=5"), "", ["macro"])
		]);
		final decl = new HxModuleDecl("unit", [], helperClass, [helperClass], false, false);
		return typedModule("", decl, "unit/TestIssues.hx");
	}

	static function upstreamUnitBuilderModule():TypedModule {
		final basePathArg = new HxFunctionArg("basePath", "String", HxDefaultValue.NoDefault);
		final helperClass = new HxClassDecl("UnitBuilder", false, [
			new HxFunctionDecl("generateSpec", HxVisibility.Public, true, [basePathArg], "Array<Dynamic>",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=compile-time-unit-spec-scan"), "", ["macro"])
		]);
		final decl = new HxModuleDecl("unit", [], helperClass, [helperClass], false, false);
		return typedModule("", decl, "unit/UnitBuilder.hx");
	}

	static function upstreamUnitDefaultTypeParametersModule():TypedModule {
		final testClass = new HxClassDecl("TestDefaultTypeParameters", false, [
			new HxFunctionDecl("printThings", HxVisibility.Public, true, [], "Array<String>",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=5"), "")
		]);
		final decl = new HxModuleDecl("unit", [], testClass, [testClass], false, false);
		return typedModule("", decl, "unit/TestDefaultTypeParameters.hx");
	}

	static function upstreamUnitTestLocalStaticModule():TypedModule {
		final testClass = new HxClassDecl("TestLocalStatic", false, [
			new HxFunctionDecl("basic", HxVisibility.Public, false, [], "Dynamic",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=static"), "")
		]);
		final decl = new HxModuleDecl("unit", [], testClass, [testClass], false, false);
		return typedModule("", decl, "unit/TestLocalStatic.hx");
	}

	static function upstreamUnitTestLocalsModule():TypedModule {
		final testClass = new HxClassDecl("TestLocals", false, [
			new HxFunctionDecl("testSubCapture", HxVisibility.Public, false, [], "Void",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=function:for_in"), "")
		]);
		final decl = new HxModuleDecl("unit", [], testClass, [testClass], false, false);
		return typedModule("", decl, "unit/TestLocals.hx");
	}

	static function upstreamUnitTestMapComprehensionModule():TypedModule {
		final testClass = new HxClassDecl("TestMapComprehension", false, [
			new HxFunctionDecl("testBasic", HxVisibility.Public, false, [], "Void",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=body_parse_error"), "")
		]);
		final decl = new HxModuleDecl("unit", [], testClass, [testClass], false, false);
		return typedModule("", decl, "unit/TestMapComprehension.hx");
	}

	static function macroCompilerModule():TypedModule {
		final flagArg = new HxFunctionArg("flag", "String", HxDefaultValue.NoDefault);
		final ident = new HxFieldDecl("ident", HxVisibility.Private, true, "Dynamic",
			HxExpr.ENew("EReg", [HxExpr.EString("^[A-Za-z_][A-Za-z0-9_]*$"), HxExpr.EString("")]));
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

	static function macroErrorModule():TypedModule {
		final messageArg = new HxFunctionArg("message", "String", HxDefaultValue.NoDefault);
		final posArg = new HxFunctionArg("pos", "Dynamic", HxDefaultValue.NoDefault);
		final previousArg = new HxFunctionArg("previous", "Dynamic", HxDefaultValue.NoDefault);
		final errorClass = new HxClassDecl("Error", false, [
			new HxFunctionDecl("new", HxVisibility.Public, false, [messageArg, posArg, previousArg], "Void", [
				HxStmt.SExpr(HxExpr.ECall(HxExpr.ESuper, [HxExpr.EIdent("message"), HxExpr.EIdent("previous")]), HxPos.unknown()),
				HxStmt.SExpr(HxExpr.EBinop("=", HxExpr.EIdent("pos"), HxExpr.EIdent("pos")), HxPos.unknown())
			], "")
		], [
			new HxFieldDecl("pos", HxVisibility.Public, false, "Dynamic", null),
			new HxFieldDecl("childErrors", HxVisibility.Public, false, "Dynamic", null)
		]);
		final decl = new HxModuleDecl("haxe.macro", [], errorClass, [errorClass], false, false);
		return typedModule("", decl, "haxe/macro/Error.hx");
	}

	static function haxeNotImplementedExceptionModule():TypedModule {
		final messageArg = new HxFunctionArg("message", "String", HxDefaultValue.Default(HxExpr.EString("Not implemented")));
		final previousArg = new HxFunctionArg("previous", "Dynamic", HxDefaultValue.NoDefault);
		final posArg = new HxFunctionArg("pos", "Dynamic", HxDefaultValue.NoDefault);
		final exceptionClass = new HxClassDecl("NotImplementedException", false, [
			new HxFunctionDecl("new", HxVisibility.Public, false, [messageArg, previousArg, posArg], "Void", [
				HxStmt.SExpr(HxExpr.ECall(HxExpr.ESuper, [HxExpr.EIdent("message"), HxExpr.EIdent("previous"), HxExpr.EIdent("pos")]), HxPos.unknown())
			], "")
		]);
		final decl = new HxModuleDecl("haxe.exceptions", [], exceptionClass, [exceptionClass], false, false);
		return typedModule("", decl, "haxe/exceptions/NotImplementedException.hx");
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
		final bufArg = new HxFunctionArg("buf", "Dynamic", HxDefaultValue.NoDefault);
		final resultArg = new HxFunctionArg("result", "Dynamic", HxDefaultValue.NoDefault);
		final nameArg = new HxFunctionArg("name", "String", HxDefaultValue.NoDefault);
		final isOkArg = new HxFunctionArg("isOk", "Bool", HxDefaultValue.NoDefault);
		final reportClass = new HxClassDecl("HtmlReport", false, [
			new HxFunctionDecl("addFixture", HxVisibility.Private, false, [bufArg, resultArg, nameArg, isOkArg], "Void",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=body_parse_error"), ""),
			new HxFunctionDecl("getTextResults", HxVisibility.Public, false, [], "String",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=body_parse_error"), "")
		], [platform]);
		final decl = new HxModuleDecl("utest.ui.text", [], reportClass, [reportClass], false, false);
		return typedModule("", decl, "utest/ui/text/HtmlReport.hx");
	}

	static function utestPlainTextReportModule():TypedModule {
		final resultArg = new HxFunctionArg("result", "Dynamic", HxDefaultValue.NoDefault);
		final handlerArg = new HxFunctionArg("handler", "Dynamic", HxDefaultValue.NoDefault);
		final reportClass = new HxClassDecl("PlainTextReport", false, [
			new HxFunctionDecl("start", HxVisibility.Private, false, [], "Void", [], ""),
			new HxFunctionDecl("setHandler", HxVisibility.Public, false, [handlerArg], "Void",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=6"), ""),
			new HxFunctionDecl("getResults", HxVisibility.Public, false, [], "String",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=body_parse_error"), ""),
			new HxFunctionDecl("complete", HxVisibility.Private, false, [resultArg], "Void",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=body_parse_error"), "")
		]);
		final decl = new HxModuleDecl("utest.ui.text", [], reportClass, [reportClass], false, false);
		return typedModule("", decl, "utest/ui/text/PlainTextReport.hx");
	}

	static function utestPrintReportModule():TypedModule {
		final runnerArg = new HxFunctionArg("runner", "Dynamic", HxDefaultValue.NoDefault);
		final reportClass = new HxClassDecl("PrintReport", false, [
			new HxFunctionDecl("new", HxVisibility.Public, false, [runnerArg], "Void",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=super(runner, _handler)"), "")
		]);
		final decl = new HxModuleDecl("utest.ui.text", [], reportClass, [reportClass], false, false);
		return typedModule("", decl, "utest/ui/text/PrintReport.hx");
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
		final classArg = new HxFunctionArg("cl", "Dynamic", HxDefaultValue.NoDefault);
		final currentArg = new HxFunctionArg("cc", "Dynamic", HxDefaultValue.NoDefault);
		final ifaceArg = new HxFunctionArg("iface", "Dynamic", HxDefaultValue.NoDefault);
		final bootClass = new HxClassDecl("Boot", false, [
			new HxFunctionDecl("__string_rec", HxVisibility.Public, true, [valueArg, indentArg], "String",
				unsupportedBody("[js-native:unsupported_expr] kind=ETryCatchRaw detail=opaque_block_expr"), ""),
			new HxFunctionDecl("__instanceof", HxVisibility.Public, true, [valueArg, classArg], "Bool",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=body_parse_error"), ""),
			new HxFunctionDecl("__interfLoop", HxVisibility.Public, true, [currentArg, ifaceArg], "Bool",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=body_parse_error"), ""),
			new HxFunctionDecl("__implements", HxVisibility.Public, true, [valueArg, ifaceArg], "Bool",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=body_parse_error"), ""),
			new HxFunctionDecl("__downcastCheck", HxVisibility.Public, true, [valueArg, classArg], "Bool",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=inline"), "")
		]);
		final decl = new HxModuleDecl("js", [], bootClass, [bootClass], false, false);
		return typedModule("", decl, "js/Boot.hx");
	}

	static function dateToolsModule():TypedModule {
		final dateArg = new HxFunctionArg("d", "Dynamic", HxDefaultValue.NoDefault);
		final tokenArg = new HxFunctionArg("e", "String", HxDefaultValue.NoDefault);
		final formatArg = new HxFunctionArg("f", "String", HxDefaultValue.NoDefault);
		final dateToolsClass = new HxClassDecl("DateTools", false, [
			new HxFunctionDecl("__format_get", HxVisibility.Private, true, [dateArg, tokenArg], "String",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=body_parse_error"), ""),
			new HxFunctionDecl("__format", HxVisibility.Private, true, [dateArg, formatArg], "String",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=body_parse_error"), ""),
			new HxFunctionDecl("format", HxVisibility.Public, true, [dateArg, formatArg], "String",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=body_parse_error"), "")
		]);
		final decl = new HxModuleDecl("", [], dateToolsClass, [dateToolsClass], false, false);
		return typedModule("", decl, "DateTools.hx");
	}

	static function dateModule():TypedModule {
		final yearArg = new HxFunctionArg("year", "Int", HxDefaultValue.NoDefault);
		final monthArg = new HxFunctionArg("month", "Int", HxDefaultValue.NoDefault);
		final dayArg = new HxFunctionArg("day", "Int", HxDefaultValue.NoDefault);
		final hourArg = new HxFunctionArg("hour", "Int", HxDefaultValue.NoDefault);
		final minuteArg = new HxFunctionArg("min", "Int", HxDefaultValue.NoDefault);
		final secondArg = new HxFunctionArg("sec", "Int", HxDefaultValue.NoDefault);
		final dateClass = new HxClassDecl("Date", false, [
			new HxFunctionDecl("new", HxVisibility.Public, false, [yearArg, monthArg, dayArg, hourArg, minuteArg, secondArg], "Void",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=6"), ""),
			new HxFunctionDecl("getTime", HxVisibility.Public, false, [], "Float",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=unsupported-date-gettime-body"), "")
		]);
		final decl = new HxModuleDecl("", [], dateClass, [dateClass], false, false);
		return typedModule("", decl, "Date.hx");
	}

	static function eRegModule():TypedModule {
		final patternArg = new HxFunctionArg("r", "String", HxDefaultValue.NoDefault);
		final optionsArg = new HxFunctionArg("opt", "String", HxDefaultValue.NoDefault);
		final stringArg = new HxFunctionArg("s", "String", HxDefaultValue.NoDefault);
		final matchedArg = new HxFunctionArg("n", "Int", HxDefaultValue.NoDefault);
		final replaceArg = new HxFunctionArg("by", "String", HxDefaultValue.NoDefault);
		final mapArg = new HxFunctionArg("f", "Dynamic", HxDefaultValue.NoDefault);
		final posArg = new HxFunctionArg("pos", "Int", HxDefaultValue.NoDefault);
		final lenArg = new HxFunctionArg("len", "Int", HxDefaultValue.NoDefault);
		final eRegClass = new HxClassDecl("EReg", false, [
			new HxFunctionDecl("new", HxVisibility.Public, false, [patternArg, optionsArg], "Void",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=ctor_body"), ""),
			new HxFunctionDecl("match", HxVisibility.Public, false, [stringArg], "Bool",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=body_parse_error"), ""),
			new HxFunctionDecl("matched", HxVisibility.Public, false, [matchedArg], "String",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=body_parse_error"), ""),
			new HxFunctionDecl("matchedLeft", HxVisibility.Public, false, [], "String",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=body_parse_error"), ""),
			new HxFunctionDecl("matchedRight", HxVisibility.Public, false, [], "String",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=body_parse_error"), ""),
			new HxFunctionDecl("matchedPos", HxVisibility.Public, false, [], "Dynamic",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=body_parse_error"), ""),
			new HxFunctionDecl("matchSub", HxVisibility.Public, false, [stringArg, posArg, lenArg], "Bool",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=body_parse_error"), ""),
			new HxFunctionDecl("split", HxVisibility.Public, false, [stringArg], "Array<String>",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=body_parse_error"), ""),
			new HxFunctionDecl("replace", HxVisibility.Public, false, [stringArg, replaceArg], "String",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=body_parse_error"), ""),
			new HxFunctionDecl("map", HxVisibility.Public, false, [stringArg, mapArg], "String",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=body_parse_error"), ""),
			new HxFunctionDecl("escape", HxVisibility.Public, true, [stringArg], "String",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=body_parse_error"), "")
		]);
		final decl = new HxModuleDecl("", [], eRegClass, [eRegClass], false, false);
		return typedModule("", decl, "EReg.hx");
	}

	static function reflectModule():TypedModule {
		final valueArg = new HxFunctionArg("v", "Dynamic", HxDefaultValue.NoDefault);
		final fieldArg = new HxFunctionArg("field", "String", HxDefaultValue.NoDefault);
		final reflectClass = new HxClassDecl("Reflect", false, [
			new HxFunctionDecl("field", HxVisibility.Public, true, [valueArg, fieldArg], "Dynamic",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=stdlib-reflect"), ""),
			new HxFunctionDecl("isFunction", HxVisibility.Public, true, [valueArg], "Bool",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=stdlib-reflect"), ""),
			new HxFunctionDecl("isObject", HxVisibility.Public, true, [valueArg], "Bool",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=stdlib-reflect"), "")
		]);
		final decl = new HxModuleDecl("", [], reflectClass, [reflectClass], false, false);
		return typedModule("", decl, "Reflect.hx");
	}

	static function typeModule():TypedModule {
		final nameArg = new HxFunctionArg("name", "String", HxDefaultValue.NoDefault);
		final valueArg = new HxFunctionArg("o", "Dynamic", HxDefaultValue.NoDefault);
		final classArg = new HxFunctionArg("c", "Dynamic", HxDefaultValue.NoDefault);
		final typeClass = new HxClassDecl("Type", false, [
			new HxFunctionDecl("resolveClass", HxVisibility.Public, true, [nameArg], "Dynamic",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=stdlib-type"), ""),
			new HxFunctionDecl("getClassName", HxVisibility.Public, true, [classArg], "String",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=stdlib-type"), ""),
			new HxFunctionDecl("getClass", HxVisibility.Public, true, [valueArg], "Dynamic",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=stdlib-type"), ""),
			new HxFunctionDecl("getInstanceFields", HxVisibility.Public, true, [classArg], "Array<String>",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=stdlib-type"), ""),
			new HxFunctionDecl("getClassFields", HxVisibility.Public, true, [classArg], "Array<String>",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=stdlib-type"), "")
		]);
		final decl = new HxModuleDecl("", [], typeClass, [typeClass], false, false);
		return typedModule("", decl, "Type.hx");
	}

	static function counterModule():TypedModule {
		final seedArg = new HxFunctionArg("seed", "Int", HxDefaultValue.Default(HxExpr.EInt(2)));
		final deltaArg = new HxFunctionArg("delta", "Int", HxDefaultValue.Default(HxExpr.EInt(3)));
		final valueField = new HxFieldDecl("value", HxVisibility.Public, false, "Int", HxExpr.EInt(1));
		final counterClass = new HxClassDecl("Counter", false, [
			new HxFunctionDecl("new", HxVisibility.Public, false, [seedArg], "Void", [
				HxStmt.SExpr(HxExpr.EBinop("=", HxExpr.EIdent("value"), HxExpr.EBinop("+", HxExpr.EIdent("value"), HxExpr.EIdent("seed"))), HxPos.unknown())
			], ""),
			new HxFunctionDecl("add", HxVisibility.Public, false, [deltaArg], "Int", [
				HxStmt.SExpr(HxExpr.EBinop("+=", HxExpr.EIdent("value"), HxExpr.EIdent("delta")), HxPos.unknown()),
				HxStmt.SReturn(HxExpr.EIdent("value"), HxPos.unknown())
			], "")
		], [valueField]);
		final decl = new HxModuleDecl("", [], counterClass, [counterClass], false, false);
		return typedModule("", decl, "Counter.hx");
	}

	static function arrayModule():TypedModule {
		final lengthArg = new HxFunctionArg("length", "Int", HxDefaultValue.NoDefault, true);
		final predicateArg = new HxFunctionArg("f", "Dynamic", HxDefaultValue.NoDefault);
		final arrayClass = new HxClassDecl("Array", false, [
			new HxFunctionDecl("new", HxVisibility.Public, false, [lengthArg], "Void",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=6"), ""),
			new HxFunctionDecl("filter", HxVisibility.Public, false, [predicateArg], "Array<Dynamic>",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=if_missing_else"), "")
		]);
		final decl = new HxModuleDecl("", [], arrayClass, [arrayClass], false, false);
		return typedModule("", decl, "Array.hx");
	}

	static function stringModule():TypedModule {
		final valueArg = new HxFunctionArg("value", "Dynamic", HxDefaultValue.NoDefault, true);
		final stringClass = new HxClassDecl("String", false, [
			new HxFunctionDecl("new", HxVisibility.Public, false, [valueArg], "Void",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=6"), ""),
			new HxFunctionDecl("toUpperCase", HxVisibility.Public, false, [], "String",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=6"), "")
		]);
		final decl = new HxModuleDecl("", [], stringClass, [stringClass], false, false);
		return typedModule("", decl, "String.hx");
	}

	static function anyModule():TypedModule {
		final anyClass = new HxClassDecl("Any", false, [
			new HxFunctionDecl("__promote", HxVisibility.Public, false, [], "Dynamic",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=6"), ""),
			new HxFunctionDecl("toString", HxVisibility.Public, false, [], "String",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=6"), "")
		]);
		final decl = new HxModuleDecl("", [], anyClass, [anyClass], false, false);
		return typedModule("", decl, "Any.hx");
	}

	static function jsNodeProcessModule():TypedModule {
		final userArg = new HxFunctionArg("user", "Dynamic", HxDefaultValue.NoDefault);
		final parsedTypeArg = new HxFunctionArg("Int", "Dynamic", HxDefaultValue.NoDefault);
		final extraGroupArg = new HxFunctionArg("extra_group", "Dynamic", HxDefaultValue.NoDefault);
		final duplicateParsedTypeArg = new HxFunctionArg("Int", "Dynamic", HxDefaultValue.NoDefault);
		final processClass = new HxClassDecl("Process", false, [
			new HxFunctionDecl("initgroups", HxVisibility.Public, false, [userArg, parsedTypeArg, extraGroupArg, duplicateParsedTypeArg], "Void",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=native-extern"), "")
		]);
		final decl = new HxModuleDecl("js.node", [], processClass, [processClass], false, false);
		return typedModule("", decl, "js/node/Process.hx");
	}

	static function jsHtmlBlobModule():TypedModule {
		final blobPartsArg = new HxFunctionArg("blobParts", "Dynamic", HxDefaultValue.NoDefault);
		final eitherArg = new HxFunctionArg("haxe", "Dynamic", HxDefaultValue.NoDefault);
		final duplicateEitherArg = new HxFunctionArg("haxe", "Dynamic", HxDefaultValue.NoDefault);
		final parsedStringArg = new HxFunctionArg("String", "Dynamic", HxDefaultValue.NoDefault);
		final optionsArg = new HxFunctionArg("options", "Dynamic", HxDefaultValue.NoDefault);
		final startArg = new HxFunctionArg("start", "Int", HxDefaultValue.NoDefault);
		final blobClass = new HxClassDecl("Blob", false, [
			new HxFunctionDecl("new", HxVisibility.Public, false, [blobPartsArg, eitherArg, duplicateEitherArg, parsedStringArg, optionsArg], "Void",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=native-extern-constructor"), ""),
			new HxFunctionDecl("slice", HxVisibility.Public, false, [startArg], "js.html.Blob",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=native-extern-prototype"), "")
		]);
		final decl = new HxModuleDecl("js.html", [], blobClass, [blobClass], false, false);
		return typedModule("", decl, "js/html/Blob.hx");
	}

	static function utestResultAggregatorModule():TypedModule {
		final runnerArg = new HxFunctionArg("runner", "Dynamic", HxDefaultValue.NoDefault);
		final aggregatorClass = new HxClassDecl("ResultAggregator", false, [
			new HxFunctionDecl("new", HxVisibility.Public, false, [runnerArg], "Void", [
				HxStmt.SExpr(HxExpr.ECall(HxExpr.EField(HxExpr.EField(HxExpr.EIdent("runner"), "onStart"), "add"), [HxExpr.EIdent("start")]), HxPos.unknown())
			],
				""),
			new HxFunctionDecl("start", HxVisibility.Public, false, [], "Void", [], ""),
			new HxFunctionDecl("progress", HxVisibility.Public, false, [], "Void", [], ""),
			new HxFunctionDecl("complete", HxVisibility.Public, false, [], "Void", [], "")
		]);
		final decl = new HxModuleDecl("utest.ui.common", [], aggregatorClass, [aggregatorClass], false, false);
		return typedModule("", decl, "utest/ui/common/ResultAggregator.hx");
	}

	static function utestRunnerModule():TypedModule {
		final selfArg = new HxFunctionArg("eThis", "Dynamic", HxDefaultValue.NoDefault);
		final pathArg = new HxFunctionArg("path", "Dynamic", HxDefaultValue.NoDefault);
		final recursiveArg = new HxFunctionArg("recursive", "Bool", HxDefaultValue.Default(HxExpr.EBool(true)));
		final runnerClass = new HxClassDecl("Runner", false, [
			new HxFunctionDecl("addCases", HxVisibility.Public, false, [selfArg, pathArg, recursiveArg], "Dynamic",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=5"), "")
		]);
		final decl = new HxModuleDecl("utest", [], runnerClass, [runnerClass], false, false);
		return typedModule("", decl, "utest/Runner.hx");
	}

	static function utestTestHandlerModule():TypedModule {
		final fixtureArg = new HxFunctionArg("fixture", "Dynamic", HxDefaultValue.NoDefault);
		final timeoutArg = new HxFunctionArg("timeout", "Int", HxDefaultValue.Default(HxExpr.EInt(250)));
		final fnArg = new HxFunctionArg("f", "Dynamic", HxDefaultValue.NoDefault);
		final handlerClass = new HxClassDecl("TestHandler", false, [
			new HxFunctionDecl("new", HxVisibility.Public, false, [fixtureArg], "Void", [], ""),
			new HxFunctionDecl("execute", HxVisibility.Public, false, [], "Void",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=body_parse_error"), ""),
			new HxFunctionDecl("addAsync", HxVisibility.Public, false, [fnArg, timeoutArg], "Dynamic",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=async-body"), "")
		], [
			new HxFieldDecl("fixture", HxVisibility.Public, false, "Dynamic", null),
			new HxFieldDecl("results", HxVisibility.Public, false, "Dynamic", null),
			new HxFieldDecl("finished", HxVisibility.Public, false, "Bool", HxExpr.EBool(false)),
			new HxFieldDecl("executionTime", HxVisibility.Public, false, "Float", HxExpr.EFloat(0)),
			new HxFieldDecl("startTime", HxVisibility.Private, false, "Float", HxExpr.EFloat(0)),
			new HxFieldDecl("onTested", HxVisibility.Public, false, "Dynamic", null),
			new HxFieldDecl("onTimeout", HxVisibility.Public, false, "Dynamic", null),
			new HxFieldDecl("onComplete", HxVisibility.Public, false, "Dynamic", null),
			new HxFieldDecl("onPrecheck", HxVisibility.Public, false, "Dynamic", null)
		]);
		final decl = new HxModuleDecl("utest", [], handlerClass, [handlerClass], false, false);
		return typedModule("", decl, "utest/TestHandler.hx");
	}

	static function utestResultModules():Array<TypedModule> {
		final errorsArg = new HxFunctionArg("errorsHavePriority", "Bool", HxDefaultValue.Default(HxExpr.EBool(true)));
		final classResult = new HxClassDecl("ClassResult", false, [
			new HxFunctionDecl("methodNames", HxVisibility.Public, false, [errorsArg], "Array<String>",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=body_parse_error"), "")
		]);
		final packageResult = new HxClassDecl("PackageResult", false, [
			new HxFunctionDecl("classNames", HxVisibility.Public, false, [errorsArg], "Array<String>",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=body_parse_error"), ""),
			new HxFunctionDecl("packageNames", HxVisibility.Public, false, [errorsArg], "Array<String>",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=body_parse_error"), "")
		]);
		final assertationArg = new HxFunctionArg("assertation", "Dynamic", HxDefaultValue.NoDefault);
		final fixtureResult = new HxClassDecl("FixtureResult", false, [
			new HxFunctionDecl("add", HxVisibility.Public, false, [assertationArg], "Void",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=body_parse_error"), "")
		]);
		return [
			typedModule("", new HxModuleDecl("utest.ui.common", [], classResult, [classResult], false, false), "utest/ui/common/ClassResult.hx"),
			typedModule("", new HxModuleDecl("utest.ui.common", [], packageResult, [packageResult], false, false), "utest/ui/common/PackageResult.hx"),
			typedModule("", new HxModuleDecl("utest.ui.common", [], fixtureResult, [fixtureResult], false, false), "utest/ui/common/FixtureResult.hx")
		];
	}

	static function haxeIoInputModule():TypedModule {
		final inputClass = new HxClassDecl("Input", false, [
			new HxFunctionDecl("readByte", HxVisibility.Public, false, [], "Int",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=throw"), "")
		]);
		final decl = new HxModuleDecl("haxe.io", [], inputClass, [inputClass], false, false);
		return typedModule("", decl, "haxe/io/Input.hx");
	}

	static function haxeIoBytesModule():TypedModule {
		final stringArg = new HxFunctionArg("s", "String", HxDefaultValue.NoDefault);
		final bytesClass = new HxClassDecl("Bytes", false, [
			new HxFunctionDecl("ofString", HxVisibility.Public, true, [stringArg], "String", [HxStmt.SReturn(HxExpr.EIdent("s"), HxPos.unknown())], "")
		]);
		final decl = new HxModuleDecl("haxe.io", [], bytesClass, [bytesClass], false, false);
		return typedModule("", decl, "haxe/io/Bytes.hx");
	}

	static function haxeCryptoBase64Module():TypedModule {
		final charsField = new HxFieldDecl("CHARS", HxVisibility.Private, true, "String", HxExpr.EString("abc"));
		final bytesField = new HxFieldDecl("BYTES", HxVisibility.Private, true, "String",
			HxExpr.ECall(HxExpr.EField(HxExpr.EField(HxExpr.EField(HxExpr.EIdent("haxe"), "io"), "Bytes"), "ofString"), [HxExpr.EIdent("CHARS")]));
		final base64Class = new HxClassDecl("Base64", false, [], [charsField, bytesField]);
		final decl = new HxModuleDecl("haxe.crypto", [], base64Class, [base64Class], false, false);
		return typedModule("", decl, "haxe/crypto/Base64.hx");
	}

	static function stringToolsModule():TypedModule {
		final stringArg = new HxFunctionArg("s", "String", HxDefaultValue.NoDefault);
		final prefixArg = new HxFunctionArg("start", "String", HxDefaultValue.NoDefault);
		final stringToolsClass = new HxClassDecl("StringTools", false, [
			new HxFunctionDecl("startsWith", HxVisibility.Public, true, [stringArg, prefixArg], "Bool",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=stdlib-stringtools"), "")
		]);
		final decl = new HxModuleDecl("", [], stringToolsClass, [stringToolsClass], false, false);
		return typedModule("", decl, "StringTools.hx");
	}

	static function upstreamUnitTestReflectModule():TypedModule {
		final nameArg = new HxFunctionArg("s", "String", HxDefaultValue.NoDefault);
		final pkgArg = new HxFunctionArg("s", "String", HxDefaultValue.NoDefault);
		final typeArg = new HxFunctionArg("s2", "String", HxDefaultValue.NoDefault);
		final typesField = new HxFieldDecl("TYPES", HxVisibility.Public, true, "Array<Dynamic>",
			HxExpr.EArrayDecl([HxExpr.EField(HxExpr.EIdent("unit"), "MyInterface")]));
		final namesField = new HxFieldDecl("TNAMES", HxVisibility.Public, true, "Array<String>", HxExpr.EArrayDecl([
			HxExpr.ECall(HxExpr.EIdent("u"), [HxExpr.EString("haxe.ds.StringMap")]),
			HxExpr.ECall(HxExpr.EIdent("u2"), [HxExpr.EString("unit"), HxExpr.EString("MyInterface")])
		]));
		final testReflectClass = new HxClassDecl("TestReflect", false, [
			new HxFunctionDecl("u", HxVisibility.Private, true, [nameArg], "String", [HxStmt.SReturn(HxExpr.EIdent("s"), HxPos.unknown())], ""),
			new HxFunctionDecl("u2", HxVisibility.Private, true, [pkgArg, typeArg], "String", [
				HxStmt.SReturn(HxExpr.EBinop("+", HxExpr.EBinop("+", HxExpr.EIdent("s"), HxExpr.EString(".")), HxExpr.EIdent("s2")), HxPos.unknown())
			], "")
		], [typesField, namesField]);
		final decl = new HxModuleDecl("unit", [], testReflectClass, [testReflectClass], false, false);
		return typedModule("", decl, "unit/TestReflect.hx");
	}

	static function phpBootModule():TypedModule {
		final aliasesField = new HxFieldDecl("aliases", HxVisibility.Public, true, "php.NativeAssocArray<String>", HxExpr.ENew("NativeAssocArray", []));
		final bootClass = new HxClassDecl("Boot", false, [], [aliasesField]);
		final decl = new HxModuleDecl("php", [], bootClass, [bootClass], false, false);
		return typedModule("", decl, "php/Boot.hx");
	}

	static function phpNativeAssocArrayModule():TypedModule {
		final assocClass = new HxClassDecl("NativeAssocArray", false, [new HxFunctionDecl("new", HxVisibility.Public, false, [], "Void", [], "")]);
		final decl = new HxModuleDecl("php", [], assocClass, [assocClass], false, false);
		return typedModule("", decl, "php/NativeAssocArray.hx");
	}

	static function haxeDsStringMapModule():TypedModule {
		final stringMapClass = new HxClassDecl("StringMap", false, [
			new HxFunctionDecl("new", HxVisibility.Public, false, [], "Void", unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=6"), "")
		]);
		final decl = new HxModuleDecl("haxe.ds", [], stringMapClass, [stringMapClass], false, false);
		return typedModule("", decl, "haxe/ds/StringMap.hx");
	}

	static function haxeDsIntMapModule():TypedModule {
		final intMapClass = new HxClassDecl("IntMap", false, [
			new HxFunctionDecl("new", HxVisibility.Public, false, [], "Void", unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=6"), "")
		]);
		final decl = new HxModuleDecl("haxe.ds", [], intMapClass, [intMapClass], false, false);
		return typedModule("", decl, "haxe/ds/IntMap.hx");
	}

	static function haxeDisplayProtocolModule():TypedModule {
		final methodArg = new HxFunctionArg("method", "String", HxDefaultValue.NoDefault);
		final requestClass = new HxClassDecl("HaxeRequestMethod", false, [
			new HxFunctionDecl("new", HxVisibility.Public, false, [methodArg], "Void", [
				HxStmt.SExpr(HxExpr.EBinop("=", HxExpr.EThis, HxExpr.EIdent("method")), HxPos.unknown())
			], "")
		]);
		final decl = new HxModuleDecl("haxe.display", [], requestClass, [requestClass], false, false);
		return typedModule("", decl, "haxe/display/Protocol.hx");
	}

	static function sysThreadThreadModule():TypedModule {
		final msgArg = new HxFunctionArg("msg", "Dynamic", HxDefaultValue.NoDefault);
		final threadClass = new HxClassDecl("Thread", false, [
			new HxFunctionDecl("sendMessage", HxVisibility.Public, false, [msgArg], "Void",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=6"), "")
		]);
		final decl = new HxModuleDecl("sys.thread", [], threadClass, [threadClass], false, false);
		return typedModule("", decl, "sys/thread/Thread.hx");
	}

	static function haxeXmlParserModule():TypedModule {
		final escapesField = new HxFieldDecl("escapes", HxVisibility.Public, true, "haxe.ds.StringMap<String>",
			HxExpr.ETryCatchRaw('opaque_block_expr:{ var h = new haxe.ds.StringMap(); h.set("lt", "<"); h; }'));
		final parserClass = new HxClassDecl("Parser", false, [], [escapesField]);
		final decl = new HxModuleDecl("haxe.xml", [], parserClass, [parserClass], false, false);
		return typedModule("", decl, "haxe/xml/Parser.hx");
	}

	static function xmlModule():TypedModule {
		final elementField = new HxFieldDecl("Element", HxVisibility.Public, true, "Dynamic", HxExpr.EField(HxExpr.EIdent("XmlType"), "Element"));
		final xmlClass = new HxClassDecl("Xml", false, [], [elementField]);
		final decl = new HxModuleDecl("", [], xmlClass, [xmlClass], false, false);
		return typedModule("", decl, "Xml.hx");
	}

	static function xmlTypeModule():TypedModule {
		final elementField = new HxFieldDecl("Element", HxVisibility.Public, true, "Dynamic", HxExpr.EInt(0));
		final xmlTypeClass = new HxClassDecl("XmlType", false, [], [elementField]);
		final decl = new HxModuleDecl("", [], xmlTypeClass, [xmlTypeClass], false, false);
		return typedModule("", decl, "XmlType.hx");
	}

	static function haxeFormatJsonParserModule():TypedModule {
		final parserClass = new HxClassDecl("JsonParser", false, [
			new HxFunctionDecl("doParse", HxVisibility.Public, false, [], "Dynamic",
				unsupportedBody("[js-native:unsupported_expr] kind=EUnsupported detail=body_parse_error"), "")
		]);
		final decl = new HxModuleDecl("haxe.format", [], parserClass, [parserClass], false, false);
		return typedModule("", decl, "haxe/format/JsonParser.hx");
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

	static function runNodeRequireScript(jsPath:String):String {
		final script = "const m = require(require('path').resolve(process.argv[1]));"
			+ "if (!m.unit || !m.unit.TestMain || typeof m.unit.TestMain.main !== 'function') throw new Error('missing unit.TestMain.main export');"
			+ "m.unit.TestMain.main();";
		final process = new sys.io.Process("node", ["-e", script, jsPath]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final exitCode = process.exitCode();
		process.close();
		assertTrue(exitCode == 0, "node require execution failed for " + jsPath + " with exit " + exitCode + ": " + stderr);
		return StringTools.trim(stdout);
	}

	static function upstreamUnitTestMainModule():TypedModule {
		final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [
			HxStmt.SExpr(HxExpr.ECall(HxExpr.EField(HxExpr.EIdent("Sys"), "println"), [HxExpr.EString("require-main")]), HxPos.unknown())
		], "");
		final testMain = new HxClassDecl("TestMain", true, [mainFn]);
		final decl = new HxModuleDecl("unit", [], testMain, [testMain], false, true);
		return typedModule("", decl, "unit/TestMain.hx");
	}

	static function protocolLine(key:String, payload:String):String {
		final escaped = StringTools.replace(StringTools.replace(StringTools.replace(StringTools.replace(payload, "\\", "\\\\"), "\n", "\\n"), "\r", "\\r"),
			"\t", "\\t");
		return "ast " + key + " " + escaped.length + ":" + escaped;
	}

	static function assertNativeStaticFinalDecode():Void {
		final plainField = "HX_CTOR\npublic\n1\n\n";
		final staticFinal = "HX_CTOR\npublic\n1\n\n\"_hx_constructor\"";
		final encoded = [
			"hxhx_frontend_v=2",
			protocolLine("class", "Main"),
			"ast static_main 1",
			protocolLine("field", plainField),
			protocolLine("static_final", staticFinal),
			"ok"
		].join("\n");
		final decl = ParserStageNativeDecode.decodeNativeProtocol(encoded);
		final fields = HxClassDecl.getFields(HxModuleDecl.getMainClass(decl));
		assertTrue(fields.length == 1, "native static_final should replace duplicate plain field records");
		final field = fields[0];
		assertTrue(HxFieldDecl.getIsFinal(field), "native static_final should decode as a final field");
		assertTrue(HxFieldDecl.getInitText(field) == "\"_hx_constructor\"", "native static_final should retain initializer text");
		switch (HxFieldDecl.getInit(field)) {
			case HxExpr.EString(v):
				assertTrue(v == "_hx_constructor", "native static_final should parse string initializers");
			case _:
				throw "native static_final should decode a string initializer expression";
		}
	}

	static function assertScannedHelperClassInheritance():Void {
		final source = [
			"class Base {}",
			"class Child extends Base {",
			"  public function new() {",
			"    Test.use(this);",
			"    super();",
			"  }",
			"}"
		].join("\n");
		final classes = ParserStageScanHelpers.scanModuleLocalHelperClasses(source, null);
		var child:Null<HxClassDecl> = null;
		for (cls in classes) {
			if (HxClassDecl.getName(cls) == "Child") {
				child = cls;
				break;
			}
		}
		assertTrue(child != null, "helper class scanner should discover module-local subclasses");
		assertTrue(HxClassDecl.getExtendsPath(child) == "Base", "helper class scanner should retain extends paths");

		var ctor:Null<HxFunctionDecl> = null;
		for (fn in HxClassDecl.getFunctions(child)) {
			if (HxFunctionDecl.getName(fn) == "new") {
				ctor = fn;
				break;
			}
		}
		assertTrue(ctor != null, "helper class scanner should retain constructors");
		var sawPreSuper = false;
		var sawSuper = false;
		for (stmt in HxFunctionDecl.getBody(ctor)) {
			switch (stmt) {
				case HxStmt.SExpr(HxExpr.ECall(HxExpr.ESuper, _), _):
					sawSuper = true;
				case _:
					if (!sawSuper)
						sawPreSuper = true;
			}
		}
		assertTrue(sawPreSuper, "helper class scanner should parse pre-super constructor work");
		assertTrue(sawSuper, "helper class scanner should parse super constructor calls");
	}

	static function assertScannedHelperAbstractExpressionBody():Void {
		final source = [
			"abstract LocalWrap(Int) from Int {",
			"  @:to inline public function toString():String return '$this';",
			"}"
		].join("\n");
		final abstracts = ParserStageScanHelpers.scanModuleLocalHelperAbstracts(source, null);
		var localWrap:Null<HxClassDecl> = null;
		for (cls in abstracts) {
			if (HxClassDecl.getName(cls) == "LocalWrap") {
				localWrap = cls;
				break;
			}
		}
		assertTrue(localWrap != null, "helper abstract scanner should discover module-local abstracts");
		var toStringFn:Null<HxFunctionDecl> = null;
		for (fn in HxClassDecl.getFunctions(localWrap)) {
			if (HxFunctionDecl.getName(fn) == "toString") {
				toStringFn = fn;
				break;
			}
		}
		assertTrue(toStringFn != null, "helper abstract scanner should retain expression-bodied instance methods");
		assertTrue(HxFunctionDecl.getBodyText(toStringFn) == "return '$this';",
			"helper abstract scanner should skip return type hints before expression-bodied method bodies");
		switch (HxFunctionDecl.getBody(toStringFn)) {
			case [
				HxStmt.SReturn(HxExpr.EBinop("+", HxExpr.EString(prefix), HxExpr.EIdent(name)), _)
			]:
				assertTrue(prefix == "", "interpolated abstract this string should start with an empty prefix");
				assertTrue(name == "this", "interpolated abstract this string should retain the this reference");
			case _:
				throw "helper abstract expression-bodied toString should parse into a return expression";
		}
	}

	static function main():Void {
		assertNativeStaticFinalDecode();
		assertScannedHelperClassInheritance();
		assertScannedHelperAbstractExpressionBody();

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
				"import utest.TestHandler;",
				"import utest.ui.common.ReportTools;",
				"class Main {",
				"  public static var ctorCalls:Array<String>;",
				'  static inline final HX_CTOR = "_hx_constructor";',
				"  static function main() {",
				'    Sys.println("std=" + Std.string("std-ok"));',
				'    Sys.println("inline-final=" + HX_CTOR);',
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
				"    Sys.println(untyped __js__(\"typeof window != 'undefined'\"));",
				'    var requiredPath = "fs";',
				'    Sys.println(untyped __js__("typeof require({0}).existsSync", requiredPath));',
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
				'    Sys.println(Boot.__instanceof(12, "Int"));',
				'    Sys.println(Boot.__instanceof(12.5, "Float"));',
				'    Sys.println(Boot.__instanceof("hxhx", "String"));',
				'    Sys.println(Boot.__instanceof([1], "Array"));',
				'    Sys.println(Boot.__instanceof(null, "Dynamic"));',
				"    var iface = { __isInterface__: true };",
				"    var cls = { __interfaces__: [iface], __super__: null };",
				"    var obj = { __class__: cls };",
				"    Sys.println(Boot.__interfLoop(cls, iface));",
				"    Sys.println(Boot.__implements(obj, iface));",
				"    Sys.println(Boot.__downcastCheck(obj, iface));",
				"    var date = {",
				"      getDay: function() return 4,",
				"      getMonth: function() return 0,",
				"      getFullYear: function() return 2020,",
				"      getDate: function() return 2,",
				"      getHours: function() return 3,",
				"      getMinutes: function() return 4,",
				"      getSeconds: function() return 5,",
				"      getTime: function() return 1577934245000.0",
				"    };",
				'    Sys.println(DateTools.format(date, "%Y-%m-%d %H:%M:%S %a %b"));',
				"    var nativeDate = new Date(2020, 0, 2, 3, 4, 5);",
				'    Sys.println("date-gettime-positive=" + (nativeDate.getTime() > 0));',
				'    var ident = new EReg("^[A-Za-z_][A-Za-z0-9_]*$", "");',
				'    Sys.println(ident.match("abc_12"));',
				'    Sys.println(ident.matched(0));',
				'    Sys.println(ident.match("12abc"));',
				'    var splitter = new EReg(",", "g");',
				'    Sys.println(splitter.split("a,b,c").join("|"));',
				'    Sys.println(EReg.escape("a+b"));',
				'    Sys.println("reflect-is-object=" + Reflect.isObject({x: 1}) + "," + Reflect.isObject("s") + "," + Reflect.isObject(function() return 1) + "," + Reflect.isObject(null));',
				'    var reflectedCounter = new Counter(1);',
				'    var reflectedFields = Type.getInstanceFields(Type.getClass(reflectedCounter));',
				'    Sys.println("type-fields=" + Type.getClassName(Type.getClass(reflectedCounter)) + ":" + reflectedFields.join("|") + ":" + Reflect.isFunction(Reflect.field(reflectedCounter, "add")));',
				'    Sys.println(haxe.io.Bytes.ofString("bytes-ref"));',
				'    Sys.println(haxe.crypto.Base64.BYTES);',
				'    Sys.println(StringTools.fastCodeAt("AZ", 1));',
				'    Sys.println("starts=" + StringTools.startsWith("testCase", "test") + "," + StringTools.startsWith("case", ""));',
				'    Sys.println("upper=" + "abc".toUpperCase());',
				'    Sys.println(unit.TestReflect.TYPES[0].__hx_name);',
				'    Sys.println(unit.TestReflect.TNAMES.join(","));',
				'    var generatedSpecs = [];',
				'    for (specClass in unit.UnitBuilder.generateSpec("src/unitstd")) generatedSpecs.push(specClass);',
				'    Sys.println("generated-specs=" + generatedSpecs.length);',
				'    Sys.println(php.Boot.aliases != null ? "assoc-ok" : "assoc-missing");',
				'    Sys.println(haxe.xml.Parser.escapes.get("lt"));',
				'    Sys.println("xml=" + Xml.Element);',
				"    var counter = new Counter(4);",
				"    Sys.println(counter.add(5));",
				"    Sys.println(counter.add());",
				"    ctorCalls = [];",
				"    new JsCtorLeaf();",
				'    Sys.println("ctor-order=" + ctorCalls.join("|"));',
				'    Sys.println("ctor-ref=" + untyped __js__("{0}.prototype.hasOwnProperty({1})", JsCtorChild, HX_CTOR));',
				"    Sys.println([1, 2, 3].filter(function(i) return i > 1).join(\",\"));",
				'    Sys.println(untyped __js__("(function(){ var it = [4,5].iterator(); return [it.hasNext(), it.next(), it.next(), it.hasNext()].join(\\",\\"); })()"));',
				"    var called = { value: false };",
				"    var handler = new TestHandler(null);",
				"    handler.fixture = {",
				"      ignoringInfo: { isIgnored: false, ignoreReason: null },",
				"      target: { testOk: function() { called.value = true; Sys.println(\"fixture-called\"); } },",
				"      method: \"testOk\",",
				"      setup: null,",
				"      setupAsync: null,",
				"      teardown: null,",
				"      teardownAsync: null",
				"    };",
				"    handler.results = [];",
				"    handler.onPrecheck = { dispatch: function(h) Sys.println(\"precheck\") };",
				"    handler.onTested = { dispatch: function(h) Sys.println(\"tested\") };",
				"    handler.onComplete = { dispatch: function(h) Sys.println(\"complete\") };",
				"    handler.execute();",
				"    Sys.println(called.value);",
				"    Sys.println(handler.finished);",
				"    Sys.println(handler.results.length);",
				"  }",
				"}"
			].join("\n");
			final modules = [
				mainModule(source),
				sysToolsModule(),
				pathModule(),
				fileSystemModule(),
				sysIoFileModule(),
				sysIoFileInputModule(),
				sysIoFileOutputModule(),
				sysIoProcessModule(),
				lambdaModule(),
				stdModule(),
				haxeRestModule(),
				jsCtorFixtureModule(),
				macroModule(),
				reservedParamModule(),
				upstreamUnitHelperMacrosModule(),
				upstreamUnitTestIssuesModule(),
				upstreamUnitBuilderModule(),
				upstreamUnitDefaultTypeParametersModule(),
				upstreamUnitTestLocalStaticModule(),
				upstreamUnitTestLocalsModule(),
				upstreamUnitTestMapComprehensionModule(),
				macroCompilerModule(),
				macroContextModule(),
				macroTypeToolsModule(),
				macroErrorModule(),
				haxeNotImplementedExceptionModule(),
				utestAssertModule(),
				utestHtmlReportModule(),
				utestPlainTextReportModule(),
				utestPrintReportModule(),
				utestReportToolsModule(),
				jsBootModule(),
				dateToolsModule(),
				dateModule(),
				eRegModule(),
				reflectModule(),
				typeModule(),
				counterModule(),
				arrayModule(),
				stringModule(),
				anyModule(),
				jsNodeProcessModule(),
				jsHtmlBlobModule(),
				utestResultAggregatorModule(),
				utestRunnerModule(),
				utestTestHandlerModule(),
				haxeIoInputModule(),
				haxeIoBytesModule(),
				haxeCryptoBase64Module(),
				stringToolsModule(),
				upstreamUnitTestMainModule(),
				upstreamUnitTestReflectModule(),
				phpBootModule(),
				phpNativeAssocArrayModule(),
				haxeDsStringMapModule(),
				haxeDsIntMapModule(),
				haxeDisplayProtocolModule(),
				sysThreadThreadModule(),
				haxeXmlParserModule(),
				xmlModule(),
				xmlTypeModule(),
				haxeFormatJsonParserModule()
			];
			for (module in utestResultModules())
				modules.push(module);
			final program = new MacroExpandedProgram(modules, false);
			FileSystem.createDirectory(outDir);
			final artifactPath = Path.join([outDir, "main.js"]);
			final context = new BackendContext(outDir, artifactPath, "Main", true, false, HxDefineMap.fromRawDefines(["js=1", "js-es=5"]));
			final result = new JsBackend().emit(program, context);

			final sourceMapPath = artifactPath + ".map";
			var hasSourceMapArtifact = false;
			for (artifact in result.artifacts) {
				if (artifact.kind == "source_map" && artifact.path == sourceMapPath)
					hasSourceMapArtifact = true;
			}
			assertTrue(FileSystem.exists(sourceMapPath), "JS backend should emit a source-map sidecar for runci artifact collection");
			assertTrue(hasSourceMapArtifact, "JS backend should report the source-map sidecar in EmitResult artifacts");
			final sourceMap = File.getContent(sourceMapPath);
			assertContains(sourceMap, "\"version\":3", "source-map sidecar should be valid sourcemap JSON");
			assertContains(sourceMap, "\"file\":\"main.js\"", "source-map sidecar should name the emitted JS file");

			final js = File.getContent(artifactPath);
			assertContains(js, "__hx_cls_haxe_SysTools.quoteUnixArg = function", "SysTools quoteUnixArg shim should emit");
			assertContains(js, "__hx_cls_haxe_SysTools.quoteWinArg = function", "SysTools quoteWinArg shim should emit");
			assertContains(js, "__hx_cls_haxe_io_Path.normalize = function", "Path normalize shim should emit");
			assertContains(js, "__hx_cls_sys_FileSystem.exists = function", "FileSystem exists shim should emit");
			assertContains(js, "__hx_cls_sys_io_File.copyBuf = (typeof Buffer !== \"undefined\" ? Buffer : require(\"buffer\").Buffer).alloc(65536)",
				"sys.io.File copy buffer should use Node Buffer global without unresolved js.node path");
			assertContains(js, "__hx_cls_sys_io_FileInput.prototype.seek = function", "unused sys.io.FileInput seek should emit a neutral JS body");
			assertNotContains(js, "sys-fileinput-seek", "unused sys.io.FileInput unsupported bodies should not leak into JS");
			assertContains(js, "__hx_cls_sys_io_FileOutput.prototype.seek = function", "unused sys.io.FileOutput seek should emit a neutral JS body");
			assertNotContains(js, "sys-fileoutput-seek", "unused sys.io.FileOutput unsupported bodies should not leak into JS");
			assertContains(js, "try {  return \"try-ok\";", "try expression should lower to a returning IIFE");
			assertContains(js, "__hx_cls_Macro.stripWhitespaces = function", "compile-time Macro fallback should emit");
			assertContains(js, "__hx_cls_Macro.extractJs = function", "compile-time Macro extractJs fallback should emit");
			assertContains(js, "__hx_cls_ReservedParam.call_user_func = function(callback, arguments_)",
				"strict-mode reserved static function parameters should be renamed");
			assertContains(js, "return arguments_;", "reserved static parameter body references should use the renamed argument");
			assertContains(js, "__hx_cls_ReservedParam.call_eval = function(eval_)", "strict-mode eval static parameter should be renamed");
			assertContains(js, "return eval_;", "eval static parameter body reference should use the renamed argument");
			assertContains(js, "__hx_cls_unit_HelperMacros.getCompilationDate = function", "upstream unit macro helper should emit a neutral static stub");
			assertContains(js, "__hx_cls_unit_TestIssues.addIssueClasses = function", "metadata-marked macro helper should emit a neutral static stub");
			assertContains(js, "__hx_cls_unit_UnitBuilder.generateSpec = function", "upstream unit spec builder helper should emit");
			assertContains(js, "return [];", "upstream unit spec builder helper should produce an iterable fallback");
			assertContains(js, "__hx_cls_unit_TestDefaultTypeParameters.printThings = function",
				"upstream unit default-type-parameter macro helper should emit a neutral static stub");
			assertContains(js, "__hx_cls_unit_TestLocalStatic.__basic_x++", "local static fixture should persist x on the class object");
			assertContains(js, "return {x: __hx_cls_unit_TestLocalStatic.__basic_x, y: \"final\"};",
				"local static fixture should return persisted x and final y");
			assertContains(js, "__hx_cls_unit_TestLocals.prototype.testSubCapture = function", "nested closure capture fixture should emit a known body");
			assertContains(js, "tmp.push(function() { return __hx_i + __hx_j; });", "nested closure capture fixture should preserve both captured loop values");
			assertContains(js, "if (actual !== expected) throw \"subcapture mismatch: \" + actual + \" != \" + expected;",
				"nested closure capture fixture should fail if capture semantics regress");
			assertContains(js, "__hx_cls_unit_TestMapComprehension.prototype.testBasic = function", "map-comprehension fixture should emit a known body");
			assertContains(js, "__hx_assert_map(map2, {1: 1}, \"map-entry-filter\");", "map-comprehension fixture should validate filtered map entries");
			assertContains(js, "__hx_cls_haxe_macro_Compiler.getDefine = function", "compile-time macro Compiler fallback should emit");
			assertContains(js, "__hx_cls_haxe_macro_Compiler.excludeFile = function", "parsed compile-time macro Compiler body should emit neutral function");
			assertContains(js, "__hx_cls_haxe_macro_Context.getLocalClass = function", "compile-time macro Context fallback should emit");
			assertContains(js, "__hx_cls_haxe_macro_TypeTools.toField = function", "compile-time macro TypeTools fallback should emit");
			assertContains(js, "var __hx_cls_haxe_macro_Error = function", "compile-time macro Error constructor should emit");
			assertNotContains(js, "super(message, previous)", "compile-time macro constructors should not emit raw JS super calls");
			assertContains(js, "var __hx_cls_haxe_exceptions_NotImplementedException = function",
				"stdlib exception constructors should still emit constructible functions");
			assertNotContains(js, "super(message, previous, pos)", "stdlib exception constructors should not emit raw JS super calls");
			assertContains(js, "__hx_cls_Lambda.flatten = function", "Lambda flatten shim should emit");
			assertContains(js, "__hx_cls_Lambda.filter = function", "Lambda filter shim should emit");
			assertContains(js, "__hx_cls_utest_Assert.getTypeName = function", "utest Assert getTypeName shim should emit");
			assertContains(js, "__hx_cls_utest_Assert.sameAs = function", "utest Assert sameAs shim should emit");
			assertContains(js, "__hx_cls_utest_ui_text_HtmlReport.platform = \"javascript\"",
				"utest HtmlReport platform static initializer should resolve for JS");
			assertContains(js, "__hx_cls_utest_ui_text_HtmlReport.prototype.addFixture = function",
				"utest HtmlReport addFixture should emit a neutral runtime stub");
			assertContains(js, "__hx_cls_utest_ui_text_HtmlReport.prototype.getTextResults = function",
				"utest HtmlReport text output should emit a neutral runtime stub");
			assertContains(js, "__hx_cls_utest_ui_text_PlainTextReport.prototype.getResults = function",
				"utest PlainTextReport getResults should emit a string-safe runtime stub");
			assertContains(js, "return \"\";", "utest PlainTextReport getResults should return a string");
			assertContains(js, "__hx_cls_utest_ui_text_PlainTextReport.prototype.setHandler = function",
				"utest PlainTextReport setHandler should emit a modeled setter");
			assertContains(js, "this.handler = handler;", "utest PlainTextReport setHandler should preserve handler assignment");
			assertContains(js, "__hx_cls_utest_ui_text_PlainTextReport.prototype.complete = function",
				"utest PlainTextReport complete should emit JS-native completion logic");
			assertContains(js, "process.exit(__hx_ok ? 0 : 1)", "utest PlainTextReport complete should preserve Node exit status");
			assertContains(js, "__hx_cls_utest_ui_text_PlainTextReport.call(this, runner, (this._handler",
				"utest PrintReport constructor should lower super call through the PlainTextReport constructor");
			assertContains(js, "for (var __hx_key in __hx_base_proto)",
				"utest PrintReport constructor should copy PlainTextReport prototype methods before the base constructor runs");
			assertContains(js, "this._handler.bind(this)", "utest PrintReport constructor should pass a bound output handler to PlainTextReport");
			assertContains(js, "this.__class__ = __hx_cls_utest_ui_text_PrintReport",
				"utest PrintReport constructor should restore the derived runtime class after the base constructor call");
			assertNotContains(js, "super(runner", "utest PrintReport constructor should not emit raw JS super syntax");
			assertContains(js, "__hx_cls_utest_ui_common_ReportTools.hasHeader = function", "utest ReportTools hasHeader shim should emit");
			assertContains(js, "__hx_cls_utest_ui_common_ReportTools.skipResult = function", "utest ReportTools skipResult shim should emit");
			assertContains(js, "__hx_cls_utest_ui_common_ReportTools.hasOutput = function", "utest ReportTools hasOutput shim should emit");
			assertContains(js, "__hx_cls_js_Boot.__string_rec = function", "js Boot string recursion shim should emit");
			assertContains(js, "__hx_cls_Std.string = function", "Std.string shim should emit");
			assertContains(js, "if (s == null) return \"null\";", "Std.string should be self-contained for null values");
			assertContains(js, "return String(s);", "Std.string should fall back to native JS stringification");
			assertContains(js, "__hx_cls_js_Boot.__instanceof = function", "js Boot instanceof shim should emit");
			assertContains(js, "__hx_cls_js_Boot.__downcastCheck = function", "js Boot downcast shim should emit");
			assertContains(js, "__hx_cls_DateTools.__format_get = function", "DateTools format token shim should emit");
			assertContains(js, "__hx_cls_DateTools.__format = function", "DateTools format scanner shim should emit");
			assertNotContains(js, "__hx_cls_Date.prototype.getTime", "native Date getTime should use the JS Date prototype");
			assertNotContains(js, "unsupported-date-gettime-body", "native Date unsupported instance bodies should not leak into JS");
			assertContains(js, "var __hx_cls_EReg = function", "EReg should emit a constructible regex wrapper");
			assertContains(js, "__hx_cls_EReg.prototype.match = function", "EReg match prototype method should emit");
			assertContains(js, "__hx_cls_EReg.escape = function", "EReg escape helper should emit");
			assertContains(js, "getClass: function (value)", "Type.getClass runtime helper should emit");
			assertContains(js, "getInstanceFields: function (cls)", "Type.getInstanceFields runtime helper should emit");
			assertContains(js, "__hx_cls_Type.getClass = function", "Type.getClass std shim should emit");
			assertContains(js, "__hx_cls_Type.getInstanceFields = function", "Type.getInstanceFields std shim should emit");
			assertContains(js, "return Type.getInstanceFields(c);", "Type.getInstanceFields std shim should delegate to runtime helper");
			assertContains(js, "__hx_cls_Reflect.field = function", "Reflect field shim should emit");
			assertContains(js, "__hx_cls_Reflect.isFunction = function", "Reflect isFunction shim should emit");
			assertContains(js, "__hx_cls_Reflect.isObject = function", "Reflect isObject shim should emit");
			assertContains(js, "typeof v === \"object\" || typeof v === \"string\"", "Reflect isObject should match Haxe JS object/string semantics");
			assertContains(js, "Object.defineProperty(Array.prototype, \"iterator\"",
				"runtime prelude should provide Haxe Array.iterator compatibility for native JS arrays");
			assertContains(js, "__hx_cls_haxe_io_Bytes.ofString(\"bytes-ref\")", "qualified package static refs should resolve to class bindings");
			assertNotContains(js, "haxe.io.Bytes.ofString", "qualified package static refs should not leak raw namespace access");
			assertContains(js, "__hx_cls_haxe_crypto_Base64.BYTES = __hx_cls_haxe_io_Bytes.ofString(__hx_cls_haxe_crypto_Base64.CHARS)",
				"same-class static field refs should resolve to class bindings");
			assertNotContains(js, "__hx_cls_haxe_io_Bytes.ofString(CHARS)", "same-class static field refs should not leak as globals");
			assertContains(js, "__hx_cls_StringTools.fastCodeAt = function", "StringTools.fastCodeAt shim should emit");
			assertContains(js, "return String(s).charCodeAt(index);", "StringTools.fastCodeAt should lower to JS charCodeAt");
			assertContains(js, "if (typeof __hx_cls_StringTools.startsWith !== \"function\")",
				"StringTools.startsWith runtime complement should backfill inline/erased std bodies");
			assertContains(js, "__hx_cls_StringTools.startsWith = function", "StringTools.startsWith shim should emit");
			assertContains(js, "return String(s).indexOf(String(start)) === 0;", "StringTools.startsWith should lower to JS prefix check");
			assertNotContains(js, "__hx_cls_String.prototype.toUpperCase",
				"native JS String prototype methods should not be re-emitted from unsupported std bodies");
			assertContains(js, "__hx_cls_Main.HX_CTOR = \"_hx_constructor\"", "static inline final string constants should keep simple runtime initializers");
			assertContains(js, "__hx_cls_JsCtorChild.prototype._hx_constructor = function",
				"pre-super constructors should expose the ES6 extracted constructor marker");
			assertContains(js, "__hx_cls_JsCtorBase._hx_skip_constructor = false",
				"base constructors with extracted descendants should expose the ES6 skip marker");
			assertNotContains(js, "__hx_cls_JsCtorLeaf.prototype._hx_constructor = function",
				"post-super-only constructors should not expose the extracted constructor marker");
			assertContains(js, "__hx_cls_unit_TestReflect.TYPES = [__hx_type_ref(\"unit.MyInterface\")]",
				"unresolved qualified value type refs should lower to runtime type placeholders");
			assertContains(js, "__hx_cls_unit_TestReflect.u = function", "same-class static helper should emit before static field calls");
			assertContains(js, "__hx_cls_unit_TestReflect.TNAMES = [__hx_cls_unit_TestReflect.u(\"haxe.ds.StringMap\")",
				"same-class static helper calls in static field initializers should use class bindings");
			assertContains(js, "__hx_export_path(\"unit.TestMain.main\", __hx_cls_unit_TestMain.main);",
				"module-level main functions should populate the CommonJS export namespace");
			assertNotContains(js, " unit.MyInterface", "qualified value type refs should not leak raw namespace access");
			assertTrue(js.indexOf("var __hx_cls_php_NativeAssocArray = function") < js.indexOf("__hx_cls_php_Boot.aliases = new __hx_cls_php_NativeAssocArray()"),
				"classes constructed by static field initializers should emit before dependent static fields");
			assertContains(js, "new __hx_cls_haxe_ds_StringMap()", "raw package-qualified constructors should rewrite to flat class bindings");
			assertNotContains(js, "new haxe.ds.StringMap()", "raw package-qualified constructors should not leak namespace access");
			assertContains(js, "__hx_cls_haxe_ds_StringMap.prototype.set = function", "StringMap set runtime complement should emit");
			assertContains(js, "__hx_cls_sys_thread_Thread.prototype.sendMessage = function",
				"unused sys.thread.Thread sendMessage should emit a neutral JS body");
			assertContains(js, "this.__hx_value = method", "abstract-style constructor assignment to this should lower to a backing value slot");
			assertNotContains(js, "this = method", "abstract-style constructor assignment should not emit invalid JS assignment to this");
			assertContains(js, "__hx_cls_sys_io_Process.prototype.close = function", "unused sys.io.Process methods should emit neutral JS bodies");
			assertTrue(js.indexOf("var __hx_cls_XmlType = function") < js.indexOf("__hx_cls_Xml.Element = __hx_cls_XmlType.Element"),
				"classes read by static field initializers should emit before dependent static fields");
			assertContains(js, "__hx_cls_haxe_macro_Compiler.ident = new __hx_cls_EReg", "compile-time macro Compiler ident regex should construct EReg");
			assertTrue(js.indexOf("var __hx_cls_EReg = function") < js.indexOf("__hx_cls_haxe_macro_Compiler.ident = new __hx_cls_EReg"),
				"EReg constructor should emit before static fields that instantiate it");
			assertContains(js, "var __hx_cls_Counter = function", "ordinary classes should emit constructible functions");
			assertContains(js, "this.value = 1", "ordinary class instance fields should initialize on this");
			assertContains(js, "__hx_cls_Counter.prototype.add = function", "ordinary class instance methods should emit on the prototype");
			assertContains(js, "if (delta == null) delta = 3", "ordinary class default arguments should lower inside instance methods");
			assertNotContains(js, "__hx_cls_Array.prototype.filter", "native JS Array prototype methods should not be re-emitted");
			assertNotContains(js, "__hx_cls_js_node_Process.prototype.initgroups", "native js.node extern prototype methods should not be re-emitted");
			assertContains(js, "var __hx_cls_js_html_Blob = ((globalThis != null && globalThis[\"Blob\"] != null) ? globalThis[\"Blob\"] : {})",
				"native js.html externs should bind to browser/Node globals instead of emitted Haxe constructors");
			assertNotContains(js, "var __hx_cls_js_html_Blob = function(blobParts", "native js.html extern constructors should not be emitted");
			assertNotContains(js, "__hx_cls_js_html_Blob.prototype.slice", "native js.html extern prototype methods should not be re-emitted");
			assertNotContains(js, "__js__(\"typeof window", "inline JS intrinsics should lower to raw JavaScript expressions");
			assertNotContains(js, "require({0})", "inline JS intrinsic placeholders should be replaced with emitted arguments");
			assertContains(js, "runner.onStart.add(this.start.bind(this))",
				"unqualified instance method references should lower to bound this-method closures");
			assertNotContains(js, "__hx_cls_haxe_io_Input.prototype.readByte", "haxe.io std support prototypes should not block JS smoke emit");
			assertNotContains(js, "__hx_cls_haxe_format_JsonParser.prototype.doParse", "haxe.format std support prototypes should not block JS smoke emit");
			assertContains(js, "__hx_cls_utest_Runner.prototype.addCases = function", "utest Runner addCases macro method should emit a neutral runtime stub");
			assertContains(js, "if (recursive == null) recursive = true;", "utest Runner addCases should keep default args");
			assertContains(js, "return null;", "utest Runner addCases should avoid compiling macro body into runtime JS");
			assertContains(js, "__hx_cls_utest_TestHandler.prototype.execute = function",
				"utest TestHandler execute should emit a JS-native sync runtime body");
			assertContains(js, "target[name]", "utest TestHandler execute should dispatch fixture methods by name");
			assertContains(js, "__hx_cls_utest_TestHandler.prototype.addAsync = function",
				"utest TestHandler helper methods should still emit prototype stubs");
			assertContains(js, "__hx_cls_utest_ui_common_ClassResult.prototype.methodNames = function",
				"utest ClassResult methodNames should emit a neutral runtime stub");
			assertContains(js, "__hx_cls_utest_ui_common_PackageResult.prototype.classNames = function",
				"utest PackageResult classNames should emit a neutral runtime stub");
			assertContains(js, "__hx_cls_utest_ui_common_PackageResult.prototype.packageNames = function",
				"utest PackageResult packageNames should emit a neutral runtime stub");
			assertContains(js, "__hx_cls_utest_ui_common_FixtureResult.prototype.add = function",
				"utest FixtureResult add should emit a JS-native result aggregation body");
			assertContains(js, "case \"SetupError\":", "utest FixtureResult add should classify setup errors by enum constructor");
			assertContains(js, "this.hasSetupError = true;", "utest FixtureResult add should preserve setup error flags");
			assertNotContains(js, "unsupported-testhandler", "utest TestHandler unsupported bodies should not leak into JS");
			assertNotContains(js, "should-not-emit", "compile-time macro API function bodies should be neutralized before regular JS emission");
			assertNotContains(js, "detail=5", "compile-time-only helper unsupported payload should not leak into JS");

			final stdout = runNodeScript(artifactPath);
			assertContains(stdout, "std=std-ok", "Std.string should stringify primitive strings through JS Boot");
			assertContains(stdout, "inline-final=_hx_constructor", "static inline final string constants should be available at runtime");
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
			assertContains(stdout, "try-ok\nfalse\nfunction\n`null`", "inline JS intrinsic should execute raw JavaScript templates under Node");
			assertContains(stdout, "`null`", "utest Assert.getTypeName should name null values");
			assertContains(stdout, "Int", "utest Assert.getTypeName should name integer values");
			assertContains(stdout, "Float", "utest Assert.getTypeName should name float values");
			assertContains(stdout, "String", "utest Assert.getTypeName should name string values");
			assertContains(stdout, "Array", "utest Assert.getTypeName should name array values");
			assertContains(stdout, "expected \"utest\" but it is \"other\"", "utest Assert.sameAs should report nested field mismatch");
			assertContains(stdout, "false\ntrue\ntrue\nfalse", "utest ReportTools should preserve header/output display policy");
			assertContains(stdout, "name : hxhx", "js Boot string recursion should render object fields");
			assertContains(stdout, "items : [1,null]", "js Boot string recursion should render arrays recursively");
			assertContains(stdout, "true\ntrue\ntrue\ntrue\nfalse", "js Boot instanceof should classify primitive and array values");
			assertContains(stdout, "true\ntrue\ntrue", "js Boot interface/downcast helpers should recognize direct interface matches");
			assertContains(stdout, "2020-01-02 03:04:05 Thu Jan", "DateTools.format should resolve common strftime tokens");
			assertContains(stdout, "date-gettime-positive=true", "Date.getTime should execute through the native JS Date prototype");
			assertContains(stdout, "true\nabc_12\nfalse", "EReg should construct and preserve match state");
			assertContains(stdout, "a|b|c", "EReg split should delegate to JS regular expressions");
			assertContains(stdout, "a\\+b", "EReg.escape should quote regex metacharacters");
			assertContains(stdout, "reflect-is-object=true,true,false,false", "Reflect.isObject should match Haxe JS behavior");
			assertContains(stdout, "type-fields=Counter:add:true", "Type/Reflect helpers should expose prototype test methods for utest-style discovery");
			assertContains(stdout, "bytes-ref", "qualified package static refs should execute through class bindings");
			assertContains(stdout, "abc", "same-class static field refs should execute through class bindings");
			assertContains(stdout, "90", "StringTools.fastCodeAt should return JS char codes");
			assertContains(stdout, "starts=true,true", "StringTools.startsWith should support utest prefix discovery and empty prefixes");
			assertContains(stdout, "upper=ABC", "native JS String prototype methods should remain available");
			assertContains(stdout, "unit.MyInterface", "unresolved qualified value type refs should preserve runtime type names");
			assertContains(stdout, "haxe.ds.StringMap,unit.MyInterface", "same-class static helper calls should execute during static field initialization");
			assertContains(stdout, "generated-specs=0", "unexpanded upstream unit spec builder should not crash JS for-in lowering");
			assertContains(stdout, "assoc-ok", "static field constructors should execute after dependency classes are assigned");
			assertContains(stdout, "<", "raw haxe.ds.StringMap static initializer should execute through the flat class binding");
			assertContains(stdout, "xml=0", "static field reads should execute after dependency classes are assigned");
			assertContains(stdout, "10\n13", "ordinary JS classes should construct, mutate instance fields, and apply default args");
			assertContains(stdout, "ctor-order=PRE|CHILD|BASE|LEAF",
				"constructor lowering should preserve pre-super, field init, expression-bodied overrides, and post-super ordering");
			assertContains(stdout, "ctor-ref=true", "enum-like class value refs should resolve to emitted JS class bindings");
			assertContains(stdout, "2,3", "native JS Array prototype methods should remain available");
			assertContains(stdout, "true,4,5,false", "runtime prelude should provide Haxe Array.iterator compatibility for native JS arrays");
			assertContains(stdout, "fixture-called\nprecheck\ntested\ncomplete\ntrue\ntrue\n1",
				"utest TestHandler execute should run a synchronous fixture and dispatch completion hooks");
			final requireStdout = runNodeRequireScript(artifactPath);
			assertContains(requireStdout, "require-main", "CommonJS require should expose unit.TestMain.main without breaking direct execution");
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
