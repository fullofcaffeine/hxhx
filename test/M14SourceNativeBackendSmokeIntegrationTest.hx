import backend.BackendContext;
import backend.BackendRegistry;
import backend.GenIrProgram;
import haxe.ds.StringMap;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

class M14SourceNativeBackendSmokeIntegrationTest {
	static function assertTrue(cond:Bool, message:String):Void {
		if (!cond)
			throw message;
	}

	static function assertContains(haystack:String, needle:String, message:String):Void {
		if (haystack.indexOf(needle) < 0)
			throw message + " (missing `" + needle + "` in `" + haystack + "`)";
	}

	static function assertNotContains(haystack:String, needle:String, message:String):Void {
		if (haystack.indexOf(needle) >= 0)
			throw message + " (unexpected `" + needle + "` in `" + haystack + "`)";
	}

	static function commandExists(name:String):Bool {
		return Sys.command("sh", ["-c", "command -v " + name + " >/dev/null 2>&1"]) == 0;
	}

	static function commandOutput(command:String, args:Array<String>):{code:Int, stdout:String, stderr:String} {
		final process = new sys.io.Process(command, args);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		return {code: code, stdout: stdout, stderr: stderr};
	}

	static function protocolLine(key:String, payload:String):String {
		final escaped = StringTools.replace(StringTools.replace(StringTools.replace(StringTools.replace(payload, "\\", "\\\\"), "\n", "\\n"), "\r", "\\r"),
			"\t", "\\t");
		return "ast " + key + " " + escaped.length + ":" + escaped;
	}

	static function deleteRecursive(path:String):Void {
		if (!FileSystem.exists(path))
			return;
		if (FileSystem.isDirectory(path)) {
			for (entry in FileSystem.readDirectory(path))
				deleteRecursive(Path.join([path, entry]));
			FileSystem.deleteDirectory(path);
		} else {
			FileSystem.deleteFile(path);
		}
	}

	static function program(label:String):GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    Std.string(\"expr-statement\");",
			"    Sys.println(\"source-native:\" + \"" + label + "\");",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function typedSyntheticModule(filePath:String, decl:HxModuleDecl):TypedModule {
		final mainClass = HxModuleDecl.getMainClass(decl);
		final env = new TyModuleEnv(HxModuleDecl.getPackagePath(decl), HxModuleDecl.getImports(decl), new TyClassEnv(HxClassDecl.getName(mainClass), []));
		return new TypedModule(new ParsedModule("", decl, filePath), env);
	}

	static function unsupportedDoWhileProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    do {",
			"      Sys.println(\"loop\");",
			"    } while (true);",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function whileProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var count = 0;",
			"    while (count < 2) {",
			"      count += 1;",
			"    }",
			"    Sys.println(Std.string(count));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function ifStatementProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var value = 1;",
			"    if (value == 1) {",
			"      Sys.println(\"yes\");",
			"    } else {",
			"      Sys.println(\"no\");",
			"    }",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function genericCallProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    Math.isFinite(1.5);",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function traceProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    trace(\"trace-native\");",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function javaLambdaTraceProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var f = i -> trace(12);",
			"    f(1);",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function unaryOperatorProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var flag = !false;",
			"    var delta = -1;",
			"    Sys.println(Std.string(flag));",
			"    Sys.println(Std.string(delta));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function postfixStatementProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var count = 1;",
			"    count++;",
			"    count--;",
			"    Sys.println(Std.string(count));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function ternaryProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var label = true ? \"yes\" : \"no\";",
			"    Sys.println(Std.string(label));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function arrayAccessProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var values = [1, 2];",
			"    var first = values[0];",
			"    Sys.println(Std.string(first));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function arrayComprehensionProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var values = [1, 2];",
			"    var doubled = [for (value in values) value * 2];",
			"    Sys.println(Std.string(doubled));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function guardedArrayComprehensionProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function keep(value:Int):Bool {",
			"    return value > 1;",
			"  }",
			"  static function main() {",
			"    var values = [1, 2];",
			"    var kept = [for (value in values) if (keep(value)) value];",
			"    Sys.println(Std.string(kept));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function anonymousObjectProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var info = { label: \"ok\", count: 1 };",
			"    Sys.println(info.label);",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function loopControlProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var i = 0;",
			"    while (i < 5) {",
			"      i += 1;",
			"      if (i == 2) continue;",
			"      if (i == 4) break;",
			"      Sys.println(Std.string(i));",
			"    }",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function postfixExpressionProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var x = 1;",
			"    var oldX = x++;",
			"    var info = { count: 3 };",
			"    var oldCount = info.count++;",
			"    var values = [5];",
			"    var oldFirst = values[0]++;",
			"    Sys.println(Std.string(oldX));",
			"    Sys.println(Std.string(oldCount));",
			"    Sys.println(Std.string(oldFirst));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function unsignedRightShiftProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var shifted = -1 >>> 1;",
			"    Sys.println(Std.string(shifted));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function helperClassProgram():GenIrProgram {
		final src = [
			"class Helper {",
			"  public static function message() {",
			"    return \"helper\";",
			"  }",
			"}",
			"",
			"class Main {",
			"  static function main() {",
			"    Sys.println(Helper.message());",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpStaticClassAccessProgram():GenIrProgram {
		final src = [
			"class Helper {",
			"  public static function message() {",
			"    return \"helper\";",
			"  }",
			"}",
			"",
			"class Flags {",
			"  public static var ready:Bool = true;",
			"}",
			"",
			"class Main {",
			"  static function main() {",
			"    if (Flags.ready) {",
			"      Sys.println(Helper.message());",
			"    }",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpSysArgsProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var verbose = Sys.args().indexOf(\"-v\") >= 0;",
			"    Sys.println(Std.string(verbose));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpWebProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    if (php.Web.isModNeko) {",
			"      php.Web.setHeader(\"Content-Type\", \"text/plain\");",
			"    }",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpMacroExprProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var expr = macro untyped (\"bar\");",
			"    Sys.println(Std.string(expr));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpDollarStringProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var code = \"" + "$" + "__hxhx_result[] = 1;\";",
			"    Sys.println(code);",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpInt64LiteralExtensionProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var a = 32.ofInt();",
			"    var b = (-4).ofInt();",
			"    var c = 3000000000000i64 + \"\";",
			"    var d = 0xFFFFFFFFFFFFFFFFi64 + \"\";",
			"    Sys.println(Std.string(a));",
			"    Sys.println(Std.string(b));",
			"    Sys.println(c);",
			"    Sys.println(d);",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpArrayConstructorProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var values = new Array();",
			"    Sys.println(Std.string(values.length));",
			"    var items = [1, 2, 3];",
			"    Sys.println(Std.string(items.length));",
			"    Sys.println(Std.string(\"abc\".length));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpArrayOperationsProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var a:Array<Null<Int>> = [1, 2, 3];",
			"    a.sort(Reflect.compare);",
			"    Sys.println(a.join(\"#\"));",
			"    Sys.println(Std.string(a[3]));",
			"    a.remove(2);",
			"    Sys.println(Std.string(a.length));",
			"    Sys.println(Std.string(a[1]));",
			"    a.splice(1, 1);",
			"    Sys.println(Std.string(a.length));",
			"    var it = a.iterator();",
			"    Sys.println(Std.string(it.hasNext()));",
			"    Sys.println(Std.string(it.next()));",
			"    var m = new Map();",
			"    m.remove(\"a\");",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpReservedTypeNameProgram():GenIrProgram {
		final src = [
			"class Abstract {",
			"  public static function getName():String {",
			"    return \"Abstract\";",
			"  }",
			"}",
			"class Main {",
			"  static function main() {",
			"    Sys.println(Abstract.getName());",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpDuplicateStaticFieldProgram():GenIrProgram {
		final mainFn = new HxFunctionDecl("main", Public, true, [], "Void",
			[SExpr(ECall(EField(EIdent("Sys"), "println"), [EString("ok")]), HxPos.unknown())], "");
		final mainClass = new HxClassDecl("Main", true, [mainFn], []);
		final duplicate = new HxFieldDecl("Expr", Public, true, "", null);
		final helperClass = new HxClassDecl("Expr", false, [], [duplicate, duplicate]);
		final decl = new HxModuleDecl("", [], mainClass, [mainClass, helperClass], false, false);
		final parsed = new ParsedModule("", decl, "Main.hx");
		final typed = new TypedModule(parsed, new TyModuleEnv("", [], new TyClassEnv("Main", [])));
		return new MacroExpandedProgram([typed], false, []);
	}

	static function phpDuplicateMethodProgram():GenIrProgram {
		final mainFn = new HxFunctionDecl("main", Public, true, [], "Void",
			[SExpr(ECall(EField(EIdent("Sys"), "println"), [EString("ok")]), HxPos.unknown())], "");
		final mainClass = new HxClassDecl("Main", true, [mainFn], []);
		final first = new HxFunctionDecl("test", Public, true, [], "String", [SReturn(EString("one"), HxPos.unknown())], "");
		final second = new HxFunctionDecl("test", Public, true, [], "String", [SReturn(EString("two"), HxPos.unknown())], "");
		final helperClass = new HxClassDecl("StaticOverloadClass", false, [first, second], []);
		final decl = new HxModuleDecl("", [], mainClass, [mainClass, helperClass], false, false);
		final parsed = new ParsedModule("", decl, "Main.hx");
		final typed = new TypedModule(parsed, new TyModuleEnv("", [], new TyClassEnv("Main", [])));
		return new MacroExpandedProgram([typed], false, []);
	}

	static function phpReservedValueNameProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var GLOBALS = 1;",
			"    var _SERVER = 2;",
			"    Sys.println(Std.string(GLOBALS + _SERVER));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpNonConstantStaticFieldProgram():GenIrProgram {
		final src = [
			"class Helper {",
			"  public static var names = [label(\"x\")];",
			"  static function label(s:String):String {",
			"    return s;",
			"  }",
			"}",
			"class Main {",
			"  static function main() {",
			"    Sys.println(Std.string(Helper.names));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpArrayPostfixStatementProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var values = [0];",
			"    var index = 0;",
			"    values[index]++;",
			"    Sys.println(Std.string(values[index]));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpCrossPackageSupportClassProgram():GenIrProgram {
		final mainFn = new HxFunctionDecl("main", Public, true, [], "Void",
			[SExpr(ECall(EField(EIdent("Sys"), "println"), [EString("ok")]), HxPos.unknown())], "");
		final mainClass = new HxClassDecl("TestMain", true, [mainFn], []);
		final mainDecl = new HxModuleDecl("", [], mainClass, [mainClass], false, false);
		final mainParsed = new ParsedModule("", mainDecl, "tests/unit/src/unit/TestMain.hx");
		final mainTyped = new TypedModule(mainParsed, new TyModuleEnv("", [], new TyClassEnv("TestMain", [])));
		final helperClass = new HxClassDecl("TestBytes", false, [], []);
		final helperDecl = new HxModuleDecl("unit", [], helperClass, [helperClass], false, false);
		final helperParsed = new ParsedModule("", helperDecl, "unit/TestBytes.hx");
		final helperTyped = new TypedModule(helperParsed, new TyModuleEnv("unit", [], new TyClassEnv("TestBytes", [])));
		final externalClass = new HxClassDecl("Runner", false, [], []);
		final externalDecl = new HxModuleDecl("utest", [], externalClass, [externalClass], false, false);
		final externalParsed = new ParsedModule("", externalDecl, "tests/.haxelib/utest/git/src/utest/Runner.hx");
		final externalTyped = new TypedModule(externalParsed, new TyModuleEnv("utest", [], new TyClassEnv("Runner", [])));
		return new MacroExpandedProgram([mainTyped, helperTyped, externalTyped], false, []);
	}

	static function phpMacroTypeProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var fn = macro :X -> Y;",
			"    var named = macro :(a:Int) -> String;",
			"    var optional = macro :?Int;",
			"    Sys.println(Std.string(fn));",
			"    Sys.println(Std.string(named));",
			"    Sys.println(Std.string(optional));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpTryCatchExpressionProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var label = try {",
			"      \"ok\";",
			"    } catch (e:Dynamic) {",
			"      \"bad\";",
			"    };",
			"    Sys.println(label);",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpTypeErrorProbeProgram():GenIrProgram {
		final src = [
			"class HelperMacros {",
			"  public static function typeError(e) {",
			"    return false;",
			"  }",
			"  public static function typeErrorText(e) {",
			"    return \"\";",
			"  }",
			"}",
			"",
			"class MyNotIterator {",
			"  public function new() {}",
			"}",
			"",
			"class Main {",
			"  static function main() {",
			"    var ok = HelperMacros.typeError(for (key => value in new MyNotIterator()) { });",
			"    var message = HelperMacros.typeErrorText(for (key => value in 1) { });",
			"    Sys.println(Std.string(ok));",
			"    Sys.println(message);",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpTypeErrorBlockProbeProgram():GenIrProgram {
		final src = [
			"class HelperMacros {",
			"  public static function typeError(e) {",
			"    return false;",
			"  }",
			"}",
			"",
			"class Main {",
			"  static function main() {",
			"    var ok = HelperMacros.typeError({ var b:{v:Int} = {v:1.2}; });",
			"    var bad = HelperMacros.typeError({ var b:{v:Dynamic} = {v:\"foo\"}; });",
			"    var z = null;",
			"    var castInt = HelperMacros.typeError({ var i:Int = z; });",
			"    var castString = HelperMacros.typeError({ var s:String = z; });",
			"    Sys.println(Std.string(ok));",
			"    Sys.println(Std.string(bad));",
			"    Sys.println(Std.string(castInt));",
			"    Sys.println(Std.string(castString));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpFollowWithAbstractsProbeProgram():GenIrProgram {
		final src = [
			"typedef TypedefToStringMap<T> = Map<String,T>;",
			"",
			"class MyMacroHelper {",
			"  public static function followWithAbstracts(e) {",
			"    return \"\";",
			"  }",
			"  public static function followWithAbstractsOnce(e) {",
			"    return \"\";",
			"  }",
			"}",
			"",
			"class Main {",
			"  static function main() {",
			"    var direct = MyMacroHelper.followWithAbstracts(new Map<String,String>());",
			"    var once = MyMacroHelper.followWithAbstractsOnce({ var x:TypedefToStringMap<String>; x; });",
			"    var viaTypedef = MyMacroHelper.followWithAbstracts(new TypedefToStringMap<String>());",
			"    Sys.println(direct);",
			"    Sys.println(once);",
			"    Sys.println(viaTypedef);",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpMapRuntimeProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var m = new Map<String,Int>();",
			"    m.set(\"a\", 1);",
			"    Sys.println(Std.string(m.exists(\"a\")));",
			"    Sys.println(Std.string(m.get(\"a\")));",
			"    Sys.println(Std.string(m.remove(\"a\")));",
			"    var sm = new haxe.ds.StringMap<Int>();",
			"    sm.set(\"b\", 2);",
			"    Sys.println(Std.string(sm.get(\"b\")));",
			"    var im = new haxe.ds.IntMap<Int>();",
			"    im.set(-4815, 8546);",
			"    Sys.println(Std.string(im.exists(-4815)));",
			"    im.remove(-4815);",
			"    Sys.println(Std.string(im.exists(-4815)));",
			"    var br = new Map<Int,Int>();",
			"    br[1] = 0;",
			"    var x = 1;",
			"    br[x++] += 4;",
			"    Sys.println(Std.string(x));",
			"    Sys.println(Std.string(br[1]));",
			"    Sys.println([1 => 1].toString());",
			"    Sys.println([\"foo\" => 1].toString());",
			"    var keyword = { \"new\": \"test\" };",
			"    Sys.println(Reflect.field(keyword, \"new\"));",
			"    var x = 5;",
			"    Sys.println('${5}');",
			"    Sys.println('a${x}b');",
			"    var values = Lambda.array(sm);",
			"    Sys.println(values.join(\"#\"));",
			"    var keys = Lambda.array({ iterator: sm.keys });",
			"    Sys.println(keys.join(\"#\"));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpSamePackageQualifiedStaticProgram():GenIrProgram {
		final src = [
			"package unit;",
			"",
			"class UnitBuilder {",
			"  public static function generateSpec(path:String) {",
			"    return [path];",
			"  }",
			"}",
			"",
			"class Main {",
			"  static function main() {",
			"    var specs = unit.UnitBuilder.generateSpec(\"src/unitstd\");",
			"    Sys.println(Std.string(specs.length));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpInstanceFieldMethodCallProgram():GenIrProgram {
		final src = [
			"class Dispatcher {",
			"  public function new() {}",
			"  public function add(listener) { }",
			"}",
			"",
			"class RunnerLike {",
			"  public var onProgress = new Dispatcher();",
			"  public function new() {}",
			"}",
			"",
			"class Main {",
			"  static function main() {",
			"    var runner = new RunnerLike();",
			"    runner.onProgress.add(function(e) { });",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function javaLambdaSequenceCallbackProgram():GenIrProgram {
		final src = [
			"class Dispatcher {",
			"  public function new() {}",
			"  public function add(listener) { }",
			"}",
			"",
			"class RunnerLike {",
			"  public var onProgress = new Dispatcher();",
			"  public function new() {}",
			"}",
			"",
			"class Main {",
			"  static function main() {",
			"    var runner = new RunnerLike();",
			"    var success = true;",
			"    runner.onProgress.add(function(e) {",
			"      for (item in [\"Success\", \"Failure\"]) {",
			"        switch (item) {",
			"          case \"Success\":",
			"          case \"Warning\":",
			"          case \"Ignore\":",
			"          default:",
			"            success = false;",
			"        }",
			"      }",
			"      Sys.println(\"done\");",
			"    });",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function javaSupportClassProgram():GenIrProgram {
		final src = [
			"import Map;",
			"import Type;",
			"import StringTools;",
			"import Helper.label;",
			"import haxe.ds.List;",
			"import haxe.io.Bytes;",
			"import haxe.CallStack;",
			"import utest.ui.common.IReport;",
			"import MyClass.UsingBase;",
			"",
			"function testTopLevel(callback) {",
			"  callback(1);",
			"}",
			"",
			"class Helper {",
			"  public function new() {}",
			"  public function label() {",
			"    return \"helper\";",
			"  }",
			"  public function assert(message, ?pos) { }",
			"  public function setNative(native) { }",
			"  public function setUnderscore(_) { }",
			"}",
			"",
			"class JavaObjectShape {",
			"  public function new() {}",
			"  public function toString() { return \"shape\"; }",
			"  public function hashCode() { return 1; }",
			"  public function equals(other) { return true; }",
			"  public function wide(a, b, c, d) { }",
			"}",
			"",
			"class SignalOwner {",
			"  public var onProgress = null;",
			"  public function new() {}",
			"  public static function create() { return new SignalOwner(); }",
			"}",
			"",
			"class FunctionalSupport {",
			"  public function new() {}",
			"  public static function consume(callback) { }",
			"  public static function choose(callback, value) { }",
			"}",
			"",
			"class Main {",
			"  static function main() {",
			"    var helper = new Helper();",
			"    Sys.println(Std.string(helper.label()));",
			"    helper.assert(\"ok\");",
			"    testTopLevel(i -> Sys.println(\"callback\"));",
			"    Sys.println(Std.string(FunctionalSupport.choose(plusOne, 4)));",
			"    Sys.println(Std.string(FunctionalSupport.choose(pairTotal, 4)));",
			"  }",
			"  static function plusOne(value) {",
			"    return value * 2;",
			"  }",
			"  static function pairTotal(left, right) {",
			"    return left * right;",
			"  }",
			"  static function multiply(a, b) {",
			"    return a * b;",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function javaLibraryEnumProgram():GenIrProgram {
		final presentArg = new HxFunctionArg("v", "String", HxDefaultValue.NoDefault);
		final presentRuntime = HxExpr.EAnon(["__hx_ctor", "__hx_index", "__hx_params"], [
			HxExpr.EString("Present"),
			HxExpr.EInt(0),
			HxExpr.EArrayDecl([HxExpr.EIdent("v")])
		]);
		final absentRuntime = HxExpr.EAnon(["__hx_ctor", "__hx_index", "__hx_params"], [HxExpr.EString("Absent"), HxExpr.EInt(1), HxExpr.EArrayDecl([])]);
		final present = new HxFunctionDecl("Present", HxVisibility.Public, true, [presentArg], "Dynamic", [HxStmt.SReturn(presentRuntime, HxPos.unknown())],
			"");
		final absent = new HxFieldDecl("Absent", HxVisibility.Public, true, "Dynamic", absentRuntime);
		final maybeClass = new HxClassDecl("Maybe", false, [present], [absent]);
		final decl = new HxModuleDecl("demo", [], maybeClass, [maybeClass], false, false);
		final parsed = new ParsedModule("", decl, "demo/Maybe.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function javaOperationInterfaceProgram():GenIrProgram {
		final src = [
			"interface BinaryOp {",
			"  function run(a:Int, b:Int):Int;",
			"}",
			"",
			"class Calc {",
			"  static public final sum:BinaryOp = (a, b) -> a + b;",
			"  static public final diff:BinaryOp = (a, b) -> a - b;",
			"  static public function apply(op:BinaryOp) {",
			"    return op.run(9, 3);",
			"  }",
			"}",
			"",
			"class Main {",
			"  static function main() {",
			"    Sys.println('sum=' + Calc.apply(Calc.sum));",
			"    Sys.println('diff=' + Calc.apply(Calc.diff));",
			"    Sys.println('product=' + Calc.apply(product));",
			"    Sys.println('quotient=' + Calc.apply(function(a, b):Int {",
			"      return Std.int(a / b);",
			"    }));",
			"  }",
			"  static function product(a, b):Int {",
			"    return a * b;",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpInheritedTestHelperCallProgram():GenIrProgram {
		final src = [
			"class Test {",
			"  public function new() {}",
			"  function eq(a, b, ?pos) { }",
			"  function t(v) { }",
			"}",
			"",
			"class TestOps extends Test {",
			"  public function new() { super(); }",
			"  public function testOps() {",
			"    eq(1, 1);",
			"    t(true);",
			"  }",
			"}",
			"",
			"class Main {",
			"  static function main() {",
			"    var test = new TestOps();",
			"    test.testOps();",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpShadowedTestHelperClosureProgram():GenIrProgram {
		final src = [
			"class Test {",
			"  public function new() {}",
			"  function f(v:Bool) { }",
			"  function unspec(f:()->Void) {",
			"    f();",
			"    this.f(false);",
			"  }",
			"}",
			"",
			"class Main extends Test {",
			"  public function new() { super(); }",
			"  static function main() {",
			"    var main = new Main();",
			"    main.unspec(function() {});",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpPlusSemanticsProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    Sys.println(Std.string(1 + 2 + \"\"));",
			"    Sys.println(Std.string(1 + (2 + \"\")));",
			"    Sys.println(Std.string(null + \"x\"));",
			"    Sys.println(Std.string(\"x\" + null));",
			"    Sys.println(Std.string(\"\" + {}));",
			"    Sys.println(Std.string(\"\" + {a: 1}));",
			"    Sys.println(Std.string(\"\" + [1, 2]));",
			"    Sys.println(Std.string(\"\" + [[1], [2, 3]]));",
			"    Sys.println(Std.string([\"x\"]));",
			"    var s = \"\";",
			"    function next() {",
			"      s += \"b\";",
			"      return s;",
			"    }",
			"    Sys.println(next());",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpEnumStringProgram():GenIrProgram {
		final src = [
			"enum MyEnum {",
			"  C(i:Int, s:String);",
			"}",
			"",
			"class Main {",
			"  static function main() {",
			"    var e = MyEnum.C(0, \"h\");",
			"    Sys.println(Std.string(e));",
			"    Sys.println(Std.string([e]));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final baseDecl = parsed.getDecl();
		final main = HxModuleDecl.getMainClass(baseDecl);
		final classes = [main].concat(ParserStageScanHelpers.scanModuleLocalHelperEnums(src, HxClassDecl.getName(main)));
		final enriched = new HxModuleDecl(HxModuleDecl.getPackagePath(baseDecl), HxModuleDecl.getImports(baseDecl), main, classes,
			HxModuleDecl.getHeaderOnly(baseDecl), HxModuleDecl.getHasToplevelMain(baseDecl));
		final typed = TyperStage.typeModule(new ParsedModule(src, enriched, "Main.hx"));
		return MacroStage.expandProgram([typed], []);
	}

	static function phpBitwisePrecedenceProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    Sys.println(Std.string(4 | 3 & 1));",
			"    Sys.println(Std.string(4 | (3 & 1)));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpSameClassStaticHelperCallProgram():GenIrProgram {
		final src = [
			"class TestOps {",
			"  static function getA() return { a: 1 };",
			"  public function new() {}",
			"  public function testOps() {",
			"    return (getA().a + 1) >> 1;",
			"  }",
			"}",
			"",
			"class Main {",
			"  static function main() {",
			"    var test = new TestOps();",
			"    Sys.println(Std.string(test.testOps()));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpBitwiseEqualityPrecedenceProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    Sys.println(Std.string((1 & 0x8000) != 0));",
			"    Sys.println(Std.string(1 & 0x8000 != 0));",
			"    Sys.println(Std.string(0 != (1 & 0x8000)));",
			"    Sys.println(Std.string(0 != 1 & 0x8000));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpModuloMultiplicationPrecedenceProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    Sys.println(Std.string(5 * 10 % 3));",
			"    Sys.println(Std.string(5 * (10 % 3)));",
			"    Sys.println(Std.string((5 * 10) % 3));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpFloatModuloProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    Sys.println(Std.string(101.5 % 100));",
			"    Sys.println(Std.string(-101.5 % 100));",
			"    var x = 101.5;",
			"    x %= 100;",
			"    Sys.println(Std.string(x));",
			"    var values = [-101.5];",
			"    values[0] %= 100;",
			"    Sys.println(Std.string(values[0]));",
			"    Sys.println(Std.string(5.0 % 0.0));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpMathRuntimeProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    Sys.println(Std.string(Math.isNaN(5.0 % 0.0)));",
			"    Sys.println(Std.string(Math.isFinite(1.5)));",
			"    Sys.println(Std.string(Math.floor(-1.5)));",
			"    Sys.println(Std.string(Math.ceil(-1.5)));",
			"    Sys.println(Std.string(Math.round(-1.5)));",
			"    Sys.println(Std.string(Math.ffloor(-10000000000.7)));",
			"    Sys.println(Std.string(Math.fceil(-10000000000.7)));",
			"    Sys.println(Std.string(Math.fround(-10000000000.7)));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpTernaryAssignmentLogicalProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    Sys.println(Std.string(!true ? true : true));",
			"    var k = false;",
			"    Sys.println(Std.string(k = true ? false : true));",
			"    Sys.println(Std.string(k));",
			"    Sys.println(Std.string((k = true) ? false : true));",
			"    Sys.println(Std.string(k));",
			"    Sys.println(Std.string(true || false && false));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpStringIndexOfProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    Sys.println(Std.string((\"bla\" + \"x\").indexOf(\"x\")));",
			"    Sys.println(Std.string(\"foo1bar\".indexOf(\"o\", 2)));",
			"    Sys.println(Std.string(\"foofoofoobarbar\".lastIndexOf(\"bar\", 11)));",
			"    Sys.println(Std.string(\"abc\".split(\"\").length));",
			"    Sys.println(Std.string(\"a,b,c\".split(\",\")[1]));",
			"    Sys.println(Std.string(\"abc\".charCodeAt(0)));",
			"    Sys.println(Std.string(\"abc\".charCodeAt(99)));",
			"    Sys.println(Std.string(\"a\".code));",
			"    var str = \"abc\";",
			"    Sys.println(Std.string(str.indexOf(\"b\")));",
			"    Sys.println(Std.string(str.lastIndexOf(\"b\")));",
			"    Sys.println(Std.string(str.charCodeAt(1)));",
			"    Sys.println(str.substr(1, 2));",
			"    Sys.println(str.substr(3));",
			"    Sys.println(str.substr(5));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpStringFromCharCodeProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    Sys.println(String.fromCharCode(77));",
			"    Sys.println(String.fromCharCode(-1));",
			"    Sys.println(String.fromCharCode(256));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpArrayComprehensionClosureProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var funcs = [for (i in 0...2) value -> value * i];",
			"    Sys.println(Std.string(funcs[0](10)));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpAbstractThisPostfixProgram():GenIrProgram {
		final src = [
			"class Counter {",
			"  public function new(i:Int) {",
			"    this = i;",
			"    bar();",
			"  }",
			"  public function toInt():Int {",
			"    return this;",
			"  }",
			"  public function incr():Int {",
			"    return ++this;",
			"  }",
			"  public function post():Int {",
			"    return this++;",
			"  }",
			"  function bar() this++;",
			"}",
			"",
			"class TemplateWrap {",
			"  public function new(s:String) {",
			"    this = new haxe.Template(s);",
			"  }",
			"  public function get():haxe.Template {",
			"    return this;",
			"  }",
			"}",
			"",
			"class Meter {",
			"  public function new(f:Float) {",
			"    this = f;",
			"  }",
			"}",
			"",
			"class Kilometer {",
			"  public function new(f:Float) {",
			"    this = f;",
			"  }",
			"}",
			"",
			"class DistanceBox {",
			"  public var km:Kilometer;",
			"  public function new(km:Kilometer) {",
			"    this.km = km;",
			"  }",
			"}",
			"",
			"class MySpecialString {",
			"  public function new(value:String) {",
			"    this = value;",
			"  }",
			"  public function substr(i:Int, ?len:Int) {",
			"    return len == null ? this.substr(i) : this.substr(i, len);",
			"  }",
			"}",
			"",
			"class Main {",
			"  static function main() {",
			"    var counter = new Counter(2);",
			"    Sys.println(Std.string(Std.isOfType(counter, Int)));",
			"    Sys.println(Std.string(Std.isOfType(3, Int)));",
			"    Sys.println(Std.string(counter.toInt()));",
			"    var mirror = counter;",
			"    Sys.println(Std.string(counter.incr()));",
			"    Sys.println(Std.string(mirror.toInt()));",
			"    Sys.println(Std.string(counter.post()));",
			"    Sys.println(Std.string(counter));",
			"    var tpl:TemplateWrap = \"Hi ::t::\";",
			"    Sys.println(tpl.get().execute({ t: \"ok\" }));",
			"    var text:String = tpl;",
			"    Sys.println(text);",
			"    var later:TemplateWrap;",
			"    later = \"Again ::t::\";",
			"    Sys.println(later.get().execute({ t: \"ok\" }));",
			"    var meters:Meter = 3000;",
			"    var km:Kilometer = meters;",
			"    var box = new DistanceBox(meters);",
			"    Sys.println(Std.string(km));",
			"    Sys.println(Std.string(box.km));",
			"    var hash:MyHash<String> = [\"k\", \"v\"];",
			"    Sys.println(hash.get(\"k\"));",
			"    var ihash:MyHash<Int> = [1, 2];",
			"    Sys.println(Std.string(ihash.get(\"_s1\")));",
			"    var special = new MySpecialString(\"My debugging abstract\");",
			"    Sys.println(special.substr(3));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function pythonAbstractThisPostfixProgram():GenIrProgram {
		final src = [
			"class Counter {",
			"  public function new(i:Int) {",
			"    this = i;",
			"    bar();",
			"  }",
			"  public function toInt():Int {",
			"    return this;",
			"  }",
			"  public function post():Int {",
			"    return this++;",
			"  }",
			"  function bar() this++;",
			"}",
			"",
			"class Main {",
			"  static function main() {",
			"    var counter = new Counter(2);",
			"    Sys.println(Std.string(counter.toInt()));",
			"    Sys.println(Std.string(counter.post()));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpSuperConstructorProgram():GenIrProgram {
		final src = [
			"class Base {",
			"  public function new() { }",
			"}",
			"",
			"class Child extends Base {",
			"  public function new() {",
			"    super();",
			"  }",
			"}",
			"",
			"class Main {",
			"  static function main() {",
			"    var child = new Child();",
			"    Sys.println(Std.string(child));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpSuperPropertyProgram():GenIrProgram {
		final src = [
			"class Base {",
			"  public var prop(get, set):Int;",
			"  public var fProp(get, null):Int->String;",
			"  public function new() { }",
			"  function get_prop() return 1;",
			"  function set_prop(v:Int) return v;",
			"  function get_fProp() return function(i:Int) return \"test\" + i;",
			"}",
			"",
			"class Child extends Base {",
			"  public override function get_prop() return super.prop + 1;",
			"  public override function set_prop(v) return (super.prop = v) + 1;",
			"  public override function get_fProp() {",
			"    var s = super.fProp(0);",
			"    return function(i:Int) return s + i;",
			"  }",
			"}",
			"",
			"class Main {",
			"  static function main() {",
			"    var child = new Child();",
			"    Sys.println(Std.string(child.prop));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpForKeyValueProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var values = [10, 20];",
			"    for (index => value in values) {",
			"      Sys.println(Std.string(index) + Std.string(value));",
			"    }",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function pythonForKeyValueProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var values = [10, 20];",
			"    for (index => value in values) {",
			"      Sys.println(Std.string(index) + Std.string(value));",
			"    }",
			"    var lookup = [\"a\" => 1, \"b\" => 2];",
			"    for (key => item in lookup) {",
			"      Sys.println(key + Std.string(item));",
			"    }",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function pythonTryCatchRawExpressionProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var caught = try throw new Exception(\"boom\") catch (e:Exception) e;",
			"    Sys.println(Std.string(caught));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function pythonTypeCheckProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var number = 12;",
			"    var text = \"12\";",
			"    Sys.println(Std.string(number is Int));",
			"    Sys.println(Std.string(text is String));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpTypeCheckProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var i = 1;",
			"    var s = \"one\";",
			"    Sys.println(Std.string(i is Int));",
			"    Sys.println(Std.string(s is String));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpShiftAssignmentProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var a = 1;",
			"    a <<= 2;",
			"    a >>= 1;",
			"    a >>>= 1;",
			"    Sys.println(Std.string(a));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpNullCoalescingProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var fallback = 2;",
			"    var value:Null<Int> = null;",
			"    var got = value ?? fallback;",
			"    value ??= 3;",
			"    Sys.println(Std.string(got));",
			"    Sys.println(Std.string(value));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpCompileTimeOnlyMacroSupportProgram():GenIrProgram {
		final src = [
			"class TestIssues {",
			"  macro static public function addIssueClasses(dir:String, pack:String) {",
			"    return macro $b{[]};",
			"  }",
			"}",
			"",
			"class Main {",
			"  static function main() {",
			"    TestIssues.addIssueClasses(\"src/unit/issues\", \"unit.issues\");",
			"    Sys.println(\"ok\");",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpUnitLocalStaticProgram():GenIrProgram {
		final src = [
			"class TestLocalStatic {",
			"  public function new() {}",
			"  function basic() {",
			"    static var x = 1;",
			"    static final y = \"final\";",
			"    x++;",
			"    return {x: x, y: y};",
			"  }",
			"}",
			"",
			"class Main {",
			"  static function main() {",
			"    var test = new TestLocalStatic();",
			"    Sys.println(Std.string(test));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpUnitMapComprehensionProgram():GenIrProgram {
		final src = [
			"class TestMapComprehension {",
			"  public function new() {}",
			"  public function testBasic() {",
			"    mapEq([for (i in 0...2) i => i], [0 => 0, 1 => 1]);",
			"    mapEq([for (i in 0...2) (i => i)], [0 => 0, 1 => 1]);",
			"    mapEq([for (i in 0...2) if (i == 1) i => i], [1 => 1]);",
			"  }",
			"  function mapEq(m1, m2) { }",
			"}",
			"",
			"class Main {",
			"  static function main() {",
			"    var test = new TestMapComprehension();",
			"    test.testBasic();",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function pythonDoWhileExpressionProgram():GenIrProgram {
		final src = [
			"class TestPython {",
			"  public function new() {}",
			"  public function testDoWhileAsExpression() {",
			"    var n = 0;",
			"    var run = function() return (do {",
			"      n += 1;",
			"    } while (n < 2));",
			"    run();",
			"  }",
			"}",
			"",
			"class Main {",
			"  static function main() {",
			"    new TestPython().testDoWhileAsExpression();",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function pythonPlainTextReportSetHandlerProgram():GenIrProgram {
		final pos = HxPos.unknown();
		final handlerArg = new HxFunctionArg("handler", "Dynamic", HxDefaultValue.NoDefault);
		final setHandler = new HxFunctionDecl("setHandler", HxVisibility.Public, false, [handlerArg], "Void", [SExpr(EUnsupported("="), pos)], "");
		final reportClass = new HxClassDecl("PlainTextReport", false, [setHandler]);
		final reportDecl = new HxModuleDecl("utest.ui.text", [], reportClass, [reportClass], false, false);
		final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [
			SVar("report", "", ENew("PlainTextReport", []), pos),
			SExpr(ECall(EField(EIdent("report"), "setHandler"), [EString("handler")]), pos)
		], "");
		final mainClass = new HxClassDecl("Main", true, [mainFn]);
		final mainDecl = new HxModuleDecl("", [], mainClass, [mainClass], false, false);
		return MacroStage.expandProgram([
			typedSyntheticModule("Main.hx", mainDecl),
			typedSyntheticModule("utest/ui/text/PlainTextReport.hx", reportDecl)
		], []);
	}

	static function phpObjectPatternSwitchExpressionProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var e = { expr: \"ok\" };",
			"    var got = switch (e) {",
			"      case { expr: const = \"ok\" }: const;",
			"      case _: \"bad\";",
			"    };",
			"    Sys.println(got);",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpUnitMatchExtractorProgram():GenIrProgram {
		final src = [
			"class TestMatch {",
			"  public function new() {}",
			"  public function testExtractors() {",
			"    function f(i) {",
			"      return switch(i) {",
			"        case 1, 2, 3: 1;",
			"        case _.even() => true: 2;",
			"        case _: 3;",
			"      }",
			"    }",
			"    f(4);",
			"  }",
			"  static function even(i:Int) return i & 1 == 0;",
			"}",
			"",
			"class Main {",
			"  static function main() {",
			"    new TestMatch().testExtractors();",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function tryCatchProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    try {",
			"      throw \"boom\";",
			"    } catch (e:Dynamic) {",
			"      Sys.println(\"caught\");",
			"    }",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function helperInstanceFieldProgram():GenIrProgram {
		final src = [
			"class Helper {",
			"  public var value:String = \"seed\";",
			"  public function new() {}",
			"  public function message() {",
			"    return this.value;",
			"  }",
			"}",
			"",
			"class Main {",
			"  static function main() {",
			"    var helper = new Helper();",
			"    Sys.println(helper.message());",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function superProgram():GenIrProgram {
		final src = [
			"class Base {",
			"  public var labelValue:String = \"base\";",
			"  public function new(seed:String) {",
			"    this.labelValue = seed + \"-base\";",
			"  }",
			"  public function label() {",
			"    return this.labelValue;",
			"  }",
			"}",
			"",
			"class Child extends Base {",
			"  public function new() {",
			"    super(\"seed\");",
			"  }",
			"  public function inheritedLabel() {",
			"    return super.label();",
			"  }",
			"}",
			"",
			"class Main {",
			"  static function main() {",
			"    var child = new Child();",
			"    Sys.println(child.inheritedLabel());",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function pythonSuperMethodReferenceProgram():GenIrProgram {
		final src = [
			"class Base {",
			"  public var handler:Dynamic;",
			"  public function new(handler:Dynamic) {",
			"    this.handler = handler;",
			"  }",
			"  public function run() {",
			"    return handler();",
			"  }",
			"}",
			"",
			"class Child extends Base {",
			"  public function new() {",
			"    super(_handler);",
			"  }",
			"  function _handler() {",
			"    return \"bound\";",
			"  }",
			"}",
			"",
			"class Main {",
			"  static function main() {",
			"    var child = new Child();",
			"    Sys.println(child.run());",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function pythonInheritedFieldReferenceProgram():GenIrProgram {
		final src = [
			"class Base {",
			"  public var pos:Int = 1;",
			"  public function new() {}",
			"}",
			"",
			"class Child extends Base {",
			"  public function new() {",
			"    super();",
			"  }",
			"  public function run() {",
			"    var total = 0;",
			"    for (i in pos...3) {",
			"      total += i;",
			"    }",
			"    return total;",
			"  }",
			"}",
			"",
			"class Main {",
			"  static function main() {",
			"    var child = new Child();",
			"    Sys.println(Std.string(child.run()));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function assertCrossModuleClassEmission():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_cross_module_" + Std.string(Date.now().getTime()));
		final srcDir = Path.join([tmpRoot, "src"]);
		final unitDir = Path.join([srcDir, "unit"]);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(unitDir);
		File.saveContent(Path.join([unitDir, "TestOps.hx"]), [
			"package unit;",
			"class TestOps {",
			"  public function new() {}",
			"  public function label() {",
			"    return \"ops\";",
			"  }",
			"}",
		].join("\n"));
		File.saveContent(Path.join([unitDir, "Main.hx"]), [
			"package unit;",
			"class Main {",
			"  static function main() {",
			"    var ops = new TestOps();",
			"    Sys.println(ops.label());",
			"  }",
			"}",
		].join("\n"));
		final resolved = ResolverStage.parseProjectRoots([srcDir], ["unit.Main"], new StringMap<String>());
		final resolvedPaths = [for (module in resolved) ResolvedModule.getModulePath(module)];
		assertTrue(resolvedPaths.indexOf("unit.TestOps") >= 0, "resolver should include referenced support modules");
		final index = TyperIndex.build(resolved);
		final loader = new ModuleLoader([srcDir], new StringMap<String>(), index, function(_typePath:String):Bool {
			return false;
		});
		loader.markResolvedAlready(resolved);
		final typed = new Array<TypedModule>();
		for (module in resolved)
			typed.push(TyperStage.typeResolvedModule(module, index, loader));
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(MacroStage.expandProgram(typed, []), new BackendContext(tmpRoot, null, "unit.Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class TestOps:", "cross-module helper classes should be emitted");
		assertContains(content, "def __init__(self):", "cross-module constructors should lower to __init__");
		assertContains(content, "def label(self):", "cross-module instance methods should be emitted");
		assertContains(content, "return \"ops\"", "cross-module instance method bodies should be rendered");
		assertContains(content, "ops = TestOps()", "main should still be able to instantiate emitted support classes");
		assertContains(content, "print(ops.label())", "main should still be able to call emitted support methods");
		deleteRecursive(tmpRoot);
	}

	static function assertPythonSkipsStdSupportClasses():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_skip_std_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final pos = HxPos.unknown();
		final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [
			SVar("helper", "", ENew("LocalSupport", []), pos),
			SExpr(ECall(EField(EIdent("Sys"), "println"), [ECall(EField(EIdent("helper"), "label"), [])]), pos)
		], "");
		final mainClass = new HxClassDecl("Main", true, [mainFn]);
		final mainDecl = new HxModuleDecl("", [], mainClass, [mainClass], false, false);
		final localFn = new HxFunctionDecl("label", HxVisibility.Public, false, [], "String", [SReturn(EString("local"), pos)], "");
		final localClass = new HxClassDecl("LocalSupport", false, [localFn]);
		final localDecl = new HxModuleDecl("", [], localClass, [localClass], false, false);
		final stdFn = new HxFunctionDecl("readLine", HxVisibility.Public, false, [], "String", [SExpr(EUnsupported("<eof-stmt>"), pos)], "");
		final stdClass = new HxClassDecl("Input", false, [stdFn]);
		final stdDecl = new HxModuleDecl("haxe.io", [], stdClass, [stdClass], false, false);
		final program = MacroStage.expandProgram([
			typedSyntheticModule("Main.hx", mainDecl),
			typedSyntheticModule("LocalSupport.hx", localDecl),
			typedSyntheticModule("/repo/std/haxe/io/Input.hx", stdDecl)
		], []);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class LocalSupport:", "Python support emission should keep user support classes");
		assertContains(content, "def label(self):", "Python support emission should keep user support methods");
		assertNotContains(content, "class Input:", "Python support emission should not dump upstream std support classes");
		deleteRecursive(tmpRoot);
	}

	static function assertPythonSkipsMacroSupportMethods():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_skip_macro_methods_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final pos = HxPos.unknown();
		final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [
			SVar("runner", "", ENew("Runner", []), pos),
			SExpr(ECall(EField(EIdent("runner"), "addCase"), [EString("case")]), pos)
		], "");
		final mainClass = new HxClassDecl("Main", true, [mainFn]);
		final mainDecl = new HxModuleDecl("", [], mainClass, [mainClass], false, false);
		final addCase = new HxFunctionDecl("addCase", HxVisibility.Public, false, [new HxFunctionArg("value", "", NoDefault)], "Void",
			[SExpr(ECall(EField(EIdent("Sys"), "println"), [EIdent("value")]), pos)], "");
		final addCases = new HxFunctionDecl("addCases", HxVisibility.Public, false, [], "Void", [SExpr(EUnsupported("body_parse_error"), pos)], "", ["macro"]);
		final runnerClass = new HxClassDecl("Runner", false, [addCase, addCases]);
		final runnerDecl = new HxModuleDecl("", [], runnerClass, [runnerClass], false, false);
		final program = MacroStage.expandProgram([
			typedSyntheticModule("Main.hx", mainDecl),
			typedSyntheticModule("Runner.hx", runnerDecl)
		], []);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class Runner:", "Python support emission should keep runtime support classes");
		assertContains(content, "def addCase(self, value):", "Python support emission should keep runtime support methods");
		assertNotContains(content, "def addCases", "Python support emission should skip macro-only support methods");
		assertNotContains(content, "body_parse_error", "skipped macro-only methods should not leak unsupported parser placeholders");
		deleteRecursive(tmpRoot);
	}

	static function assertPythonStaticInitializersAfterSupportClasses():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_static_init_order_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final pos = HxPos.unknown();
		final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [
			SExpr(ECall(EField(EIdent("Sys"), "println"), [ECall(EField(EIdent("Std"), "string"), [EField(EIdent("InitBase"), "sinline")])]), pos)
		], "");
		final mainClass = new HxClassDecl("Main", true, [mainFn]);
		final mainDecl = new HxModuleDecl("", [], mainClass, [mainClass], false, false);
		final staticInit = new HxFieldDecl("sinline", HxVisibility.Public, true, "Int", ECall(EField(EIdent("DateTools"), "minutes"), [EInt(1)]));
		final initBaseClass = new HxClassDecl("InitBase", false, [], [staticInit]);
		final initBaseDecl = new HxModuleDecl("", [], initBaseClass, [initBaseClass], false, false);
		final minutesFn = new HxFunctionDecl("minutes", HxVisibility.Public, true, [new HxFunctionArg("value", "Int", NoDefault)], "Int",
			[SReturn(EBinop("*", EIdent("value"), EInt(60)), pos)], "");
		final dateToolsClass = new HxClassDecl("DateTools", false, [minutesFn]);
		final dateToolsDecl = new HxModuleDecl("", [], dateToolsClass, [dateToolsClass], false, false);
		final program = MacroStage.expandProgram([
			typedSyntheticModule("Main.hx", mainDecl),
			typedSyntheticModule("InitBase.hx", initBaseDecl),
			typedSyntheticModule("DateTools.hx", dateToolsDecl)
		], []);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class InitBase:", "Python support emission should keep the class with the static initializer");
		assertContains(content, "class DateTools:", "Python support emission should keep the referenced helper class");
		assertContains(content, "    sinline = None", "Python class bodies should reserve static fields without evaluating cross-class initializers");
		assertContains(content, "InitBase.sinline = DateTools.minutes(1)", "Python static initializers should run after all support classes are defined");
		if (commandExists("python3")) {
			final run = commandOutput("python3", [outputPath]);
			assertTrue(run.code == 0, "generated Python static initializer order should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "60", "generated Python should observe the deferred static initializer value");
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPythonStdDateToolsSupport():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_std_datetools_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final pos = HxPos.unknown();
		final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [
			SExpr(ECall(EField(EIdent("Sys"), "println"), [ECall(EField(EIdent("Std"), "string"), [EField(EIdent("InitBase"), "sinline")])]), pos)
		], "");
		final mainClass = new HxClassDecl("Main", true, [mainFn]);
		final mainDecl = new HxModuleDecl("", [], mainClass, [mainClass], false, false);
		final staticInit = new HxFieldDecl("sinline", HxVisibility.Public, true, "Float", ECall(EField(EIdent("DateTools"), "minutes"), [EInt(1)]));
		final initBaseClass = new HxClassDecl("InitBase", false, [], [staticInit]);
		final initBaseDecl = new HxModuleDecl("", [], initBaseClass, [initBaseClass], false, false);
		final stdMinutesFn = new HxFunctionDecl("minutes", HxVisibility.Public, true, [new HxFunctionArg("value", "Float", NoDefault)], "Float",
			[SExpr(EUnsupported("std-datetools-source-should-not-render"), pos)], "");
		final dateToolsClass = new HxClassDecl("DateTools", false, [stdMinutesFn]);
		final dateToolsDecl = new HxModuleDecl("", [], dateToolsClass, [dateToolsClass], false, false);
		final program = MacroStage.expandProgram([
			typedSyntheticModule("Main.hx", mainDecl),
			typedSyntheticModule("InitBase.hx", initBaseDecl),
			typedSyntheticModule("/repo/std/DateTools.hx", dateToolsDecl)
		], []);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class DateTools:", "Python std support should provide a small DateTools helper when std DateTools is skipped");
		assertContains(content, "def minutes(n):", "Python std DateTools helper should include minute conversion");
		assertContains(content, "InitBase.sinline = DateTools.minutes(1)", "Python static initializer should be able to reference std DateTools");
		assertNotContains(content, "std-datetools-source-should-not-render", "Python DateTools support should not dump the upstream std source body");
		if (commandExists("python3")) {
			final run = commandOutput("python3", [outputPath]);
			assertTrue(run.code == 0, "generated Python std DateTools helper should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "60000", "generated Python should observe DateTools.minutes(1) in milliseconds");
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPythonPackageQualifiedSupportClassReference():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_package_class_ref_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final pos = HxPos.unknown();
		final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [
			SExpr(ECall(EField(EIdent("Sys"), "println"), [ECall(EField(EIdent("Std"), "string"), [EField(EIdent("DCEClass"), "c")])]), pos)
		], "");
		final mainClass = new HxClassDecl("Main", true, [mainFn]);
		final mainDecl = new HxModuleDecl("unit", [], mainClass, [mainClass], false, false);
		final usedClass = new HxClassDecl("UsedReferenced2", false, []);
		final usedDecl = new HxModuleDecl("unit", [], usedClass, [usedClass], false, false);
		final staticInit = new HxFieldDecl("c", HxVisibility.Public, true, "Array<Dynamic>", EArrayDecl([ENull, EField(EIdent("unit"), "UsedReferenced2")]));
		final dceClass = new HxClassDecl("DCEClass", false, [], [staticInit]);
		final dceDecl = new HxModuleDecl("unit", [], dceClass, [dceClass], false, false);
		final program = MacroStage.expandProgram([
			typedSyntheticModule("unit/Main.hx", mainDecl),
			typedSyntheticModule("unit/UsedReferenced2.hx", usedDecl),
			typedSyntheticModule("unit/DCEClass.hx", dceDecl)
		], []);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "unit.Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "unit = hxhx_anon()", "Python support should synthesize a package namespace for qualified references");
		assertContains(content, "unit.UsedReferenced2 = UsedReferenced2", "Python support should expose flat helper classes through the package namespace");
		assertContains(content, "DCEClass.c = Array([None, unit.UsedReferenced2])",
			"Python static initializer should preserve the package-qualified class reference");
		assertTrue(content.indexOf("unit.UsedReferenced2 = UsedReferenced2") < content.indexOf("DCEClass.c = Array([None, unit.UsedReferenced2])"),
			"Python package namespace aliases should be emitted before deferred static initializers");
		if (commandExists("python3")) {
			final run = commandOutput("python3", [outputPath]);
			assertTrue(run.code == 0, "generated Python package-qualified class reference should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "UsedReferenced2", "generated Python should print the qualified class reference");
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPythonStdStringMapNamespaceReference():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_std_string_map_ref_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final pos = HxPos.unknown();
		final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [
			SExpr(ECall(EField(EIdent("Sys"), "println"), [
				ECall(EField(EIdent("Std"), "string"), [EArrayAccess(EField(EIdent("TestReflect"), "TYPES"), EInt(0))])
			]), pos)
		], "");
		final mainClass = new HxClassDecl("Main", true, [mainFn]);
		final mainDecl = new HxModuleDecl("", [], mainClass, [mainClass], false, false);
		final stringMapRef:HxExpr = EField(EField(EIdent("haxe"), "ds"), "StringMap");
		final typesField = new HxFieldDecl("TYPES", HxVisibility.Public, true, "Array<Dynamic>", EArrayDecl([stringMapRef]));
		final reflectClass = new HxClassDecl("TestReflect", false, [], [typesField]);
		final reflectDecl = new HxModuleDecl("", [], reflectClass, [reflectClass], false, false);
		final stdSetFn = new HxFunctionDecl("set", HxVisibility.Public, false, [
			new HxFunctionArg("key", "String", NoDefault),
			new HxFunctionArg("value", "Dynamic", NoDefault)
		], "Void",
			[SExpr(EUnsupported("std-string-map-source-should-not-render"), pos)], "");
		final stringMapClass = new HxClassDecl("StringMap", false, [stdSetFn]);
		final stringMapDecl = new HxModuleDecl("haxe.ds", [], stringMapClass, [stringMapClass], false, false);
		final program = MacroStage.expandProgram([
			typedSyntheticModule("Main.hx", mainDecl),
			typedSyntheticModule("TestReflect.hx", reflectDecl),
			typedSyntheticModule("/repo/std/haxe/ds/StringMap.hx", stringMapDecl)
		], []);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class StringMap(dict):", "Python std support should provide a small StringMap helper when std StringMap is skipped");
		assertContains(content, "haxe = hxhx_anon()", "Python support should synthesize the haxe namespace for std type references");
		assertContains(content, "haxe.ds = hxhx_anon()", "Python support should synthesize the haxe.ds namespace for std type references");
		assertContains(content, "haxe.ds.StringMap = StringMap", "Python support should expose StringMap through haxe.ds");
		assertContains(content, "TestReflect.TYPES = Array([haxe.ds.StringMap])", "Python static initializer should preserve haxe.ds.StringMap references");
		assertTrue(content.indexOf("haxe.ds.StringMap = StringMap") < content.indexOf("TestReflect.TYPES = Array([haxe.ds.StringMap])"),
			"Python std namespace aliases should be emitted before deferred static initializers");
		assertNotContains(content, "std-string-map-source-should-not-render", "Python StringMap support should not dump the upstream std source body");
		if (commandExists("python3")) {
			final run = commandOutput("python3", [outputPath]);
			assertTrue(run.code == 0, "generated Python std StringMap namespace reference should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "StringMap", "generated Python should print the std StringMap class reference");
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPythonTypeNameHelpersForStaticInitializers():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_type_name_helpers_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final pos = HxPos.unknown();
		final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [
			SExpr(ECall(EField(EIdent("Sys"), "println"), [
				EBinop("+", EBinop("+", EArrayAccess(EField(EIdent("TestReflect"), "TNAMES"), EInt(0)), EString(",")),
					EArrayAccess(EField(EIdent("TestReflect"), "TNAMES"), EInt(1)))
			]), pos)
		], "");
		final mainClass = new HxClassDecl("Main", true, [mainFn]);
		final mainDecl = new HxModuleDecl("", [], mainClass, [mainClass], false, false);
		final typeNamesField = new HxFieldDecl("TNAMES", HxVisibility.Public, true, "Array<String>", EArrayDecl([
			ECall(EIdent("u"), [EString("haxe.ds.StringMap")]),
			ECall(EIdent("u2"), [EString("unit"), EString("MyEnum")])
		]));
		final uFn = new HxFunctionDecl("u", HxVisibility.Public, true, [new HxFunctionArg("s", "String", NoDefault)], "String", [SReturn(EIdent("s"), pos)],
			"");
		final u2Fn = new HxFunctionDecl("u2", HxVisibility.Public, true, [
			new HxFunctionArg("s", "String", NoDefault),
			new HxFunctionArg("s2", "String", NoDefault)
		], "String", [
			SReturn(EBinop("+", EBinop("+", ECall(EIdent("u"), [EIdent("s")]), EString(".")), ECall(EIdent("u"), [EIdent("s2")])), pos)
		], "");
		final reflectClass = new HxClassDecl("TestReflect", false, [uFn, u2Fn], [typeNamesField]);
		final reflectDecl = new HxModuleDecl("", [], reflectClass, [reflectClass], false, false);
		final program = MacroStage.expandProgram([
			typedSyntheticModule("Main.hx", mainDecl),
			typedSyntheticModule("TestReflect.hx", reflectDecl)
		], []);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "def u(s):", "Python support should synthesize the global type-name helper used by static initializers");
		assertContains(content, "def u2(s, s2):", "Python support should synthesize the qualified type-name helper used by static initializers");
		assertContains(content, "TestReflect.TNAMES = Array([u(\"haxe.ds.StringMap\"), u2(\"unit\", \"MyEnum\")])",
			"Python static initializer should preserve generated type-name helper calls");
		assertTrue(content.indexOf("def u(s):") < content.indexOf("TestReflect.TNAMES = Array([u(\"haxe.ds.StringMap\"), u2(\"unit\", \"MyEnum\")])"),
			"Python type-name helpers should be emitted before deferred static initializers");
		if (commandExists("python3")) {
			final run = commandOutput("python3", [outputPath]);
			assertTrue(run.code == 0, "generated Python type-name helpers should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "haxe.ds.StringMap,unit.MyEnum", "generated Python should evaluate type-name helper calls");
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPythonUnitBuilderMacroNamespaceFallback():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_unit_builder_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final pos = HxPos.unknown();
		final generateSpecCall:HxExpr = ECall(EField(EField(EIdent("unit"), "UnitBuilder"), "generateSpec"), [EString("src/unitstd")]);
		final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [
			SExpr(ECall(EField(EIdent("Sys"), "println"), [ECall(EField(EIdent("Std"), "string"), [generateSpecCall])]), pos)
		], "");
		final mainClass = new HxClassDecl("Main", true, [mainFn]);
		final mainDecl = new HxModuleDecl("", [], mainClass, [mainClass], false, false);
		final unitBuilderFn = new HxFunctionDecl("generateSpec", HxVisibility.Public, true, [new HxFunctionArg("basePath", "String", NoDefault)],
			"Array<Dynamic>", [SExpr(EUnsupported("unit-builder-macro-source-should-not-render"), pos)], "", ["macro"]);
		final unitBuilderClass = new HxClassDecl("UnitBuilder", false, [unitBuilderFn]);
		final unitBuilderDecl = new HxModuleDecl("unit", [], unitBuilderClass, [unitBuilderClass], false, false);
		final program = MacroStage.expandProgram([
			typedSyntheticModule("Main.hx", mainDecl),
			typedSyntheticModule("unit/UnitBuilder.hx", unitBuilderDecl)
		], []);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class UnitBuilder:", "Python support should synthesize a UnitBuilder runtime fallback for macro-only generateSpec");
		assertContains(content, "def generateSpec(basePath):", "Python UnitBuilder fallback should expose the package-qualified static method");
		assertContains(content, "unit.UnitBuilder = UnitBuilder", "Python support should expose UnitBuilder through the unit namespace");
		assertContains(content, "print(str(unit.UnitBuilder.generateSpec(\"src/unitstd\")))",
			"Python main code should preserve package-qualified UnitBuilder.generateSpec calls");
		assertNotContains(content, "unit-builder-macro-source-should-not-render", "Python UnitBuilder support should not render macro-only source bodies");
		if (commandExists("python3")) {
			final run = commandOutput("python3", [outputPath]);
			assertTrue(run.code == 0, "generated Python UnitBuilder fallback should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "[]", "generated Python UnitBuilder fallback should return an empty runtime spec iterable");
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPythonTestIssuesMacroFallback():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_test_issues_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final pos = HxPos.unknown();
		final addIssueClassesCall:HxExpr = ECall(EField(EIdent("TestIssues"), "addIssueClasses"), [EString("src/unit/issues"), EString("unit.issues")]);
		final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [
			SExpr(addIssueClassesCall, pos),
			SExpr(ECall(EField(EIdent("Sys"), "println"), [EString("ok")]), pos)
		], "");
		final mainClass = new HxClassDecl("Main", true, [mainFn]);
		final mainDecl = new HxModuleDecl("", [], mainClass, [mainClass], false, false);
		final testIssuesFn = new HxFunctionDecl("addIssueClasses", HxVisibility.Public, true, [
			new HxFunctionArg("dir", "String", NoDefault),
			new HxFunctionArg("pack", "String", NoDefault)
		], "Void",
			[SExpr(EUnsupported("test-issues-macro-source-should-not-render"), pos)], "", ["macro"]);
		final testIssuesClass = new HxClassDecl("TestIssues", false, [testIssuesFn]);
		final testIssuesDecl = new HxModuleDecl("unit", [], testIssuesClass, [testIssuesClass], false, false);
		final program = MacroStage.expandProgram([
			typedSyntheticModule("Main.hx", mainDecl),
			typedSyntheticModule("unit/TestIssues.hx", testIssuesDecl)
		], []);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class TestIssues:", "Python support should synthesize a TestIssues runtime fallback for macro-only issue registration");
		assertContains(content, "def addIssueClasses(dir, pack):", "Python TestIssues fallback should expose the static registration hook");
		assertContains(content, "unit.TestIssues = TestIssues", "Python support should expose TestIssues through the unit namespace");
		assertContains(content, "TestIssues.addIssueClasses(\"src/unit/issues\", \"unit.issues\")",
			"Python main code should preserve imported/bare TestIssues.addIssueClasses calls");
		assertNotContains(content, "test-issues-macro-source-should-not-render", "Python TestIssues support should not render macro-only source bodies");
		if (commandExists("python3")) {
			final run = commandOutput("python3", [outputPath]);
			assertTrue(run.code == 0, "generated Python TestIssues fallback should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "ok", "generated Python should continue after the no-op issue registration fallback");
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPythonArrayRuntimeShim():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_array_runtime_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final src = [
			"class Main {",
			"  static function main() {",
			"    var values = new Array();",
			"    values.push(\"a\");",
			"    values.push(\"b\");",
			"    Sys.println(Std.string(values.length));",
			"    Sys.println(values.join(\"#\"));",
			"    Sys.println(Std.string(values.remove(\"a\")));",
			"    var it = values.iterator();",
			"    Sys.println(Std.string(it.hasNext()));",
			"    Sys.println(it.next());",
			"    var literal = [\"c\"];",
			"    literal.push(\"d\");",
			"    Sys.println(literal.join(\"#\"));",
			"  }",
			"}"
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		final program = MacroStage.expandProgram([typed], []);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class Array(list):", "Python runtime should define a Haxe-style Array constructor shim");
		assertContains(content, "def push(self, value):", "Python Array shim should expose push for upstream utest handlers");
		assertContains(content, "literal = Array([\"c\"])", "Python array literals should use the Array shim so push remains available");
		assertContains(content, "def length(self):", "Python Array shim should expose Haxe length as a property");
		assertContains(content, "def iterator(self):", "Python Array shim should expose Haxe-style iterators");
		if (commandExists("python3")) {
			final run = commandOutput("python3", [outputPath]);
			assertTrue(run.code == 0, "generated Python Array runtime shim should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "2\na#b\nTrue\nTrue\nb\nc#d",
				"generated Python should support Array(), array literals, push, length, join, remove, and iterator");
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPythonListRuntimeShim():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_list_runtime_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final src = [
			"class Main {",
			"  static function main() {",
			"    var values = new List();",
			"    values.add(\"a\");",
			"    values.add(\"b\");",
			"    Sys.println(Std.string(values.length));",
			"    Sys.println(values.first());",
			"    Sys.println(values.last());",
			"    var it = values.iterator();",
			"    Sys.println(Std.string(it.hasNext()));",
			"    Sys.println(it.next());",
			"    Sys.println(Std.string(values.remove(\"a\")));",
			"    Sys.println(Std.string(values.length));",
			"    values.clear();",
			"    Sys.println(Std.string(values.isEmpty()));",
			"  }",
			"}"
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		final program = MacroStage.expandProgram([typed], []);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class List:", "Python runtime should define a Haxe-style List constructor shim");
		assertContains(content, "def add(self, value):", "Python List shim should expose add for utest result collection");
		assertContains(content, "values = List()", "Python List construction should lower to the runtime shim");
		assertContains(content, "def iterator(self):", "Python List shim should expose Haxe-style iterators");
		if (commandExists("python3")) {
			final run = commandOutput("python3", [outputPath]);
			assertTrue(run.code == 0, "generated Python List runtime shim should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "2\na\nb\nTrue\na\nTrue\n1\nTrue",
				"generated Python should support List(), add, length, first, last, iterator, remove, clear, and isEmpty");
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPythonMacroCompilerStdFallback():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_macro_compiler_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final pos = HxPos.unknown();
		final defineCall:HxExpr = ECall(EField(EIdent("Compiler"), "define"), [EString("UTEST_PATTERN"), EString("abc")]);
		final getDefinedCall:HxExpr = ECall(EField(EIdent("Compiler"), "getDefine"), [EString("UTEST_PATTERN")]);
		final getMissingCall:HxExpr = ECall(EField(EIdent("Compiler"), "getDefine"), [EString("MISSING")]);
		final excludeCall:HxExpr = ECall(EField(EIdent("Compiler"), "excludeFile"), [EString("ignored.hx")]);
		final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [
			SExpr(defineCall, pos),
			SExpr(ECall(EField(EIdent("Sys"), "println"), [ECall(EField(EIdent("Std"), "string"), [getDefinedCall])]), pos),
			SExpr(ECall(EField(EIdent("Sys"), "println"), [ECall(EField(EIdent("Std"), "string"), [getMissingCall])]), pos),
			SExpr(excludeCall, pos)
		], "");
		final mainClass = new HxClassDecl("Main", true, [mainFn]);
		final mainDecl = new HxModuleDecl("", [], mainClass, [mainClass], false, false);
		final keyArg = new HxFunctionArg("key", "String", NoDefault);
		final valueArg = new HxFunctionArg("value", "String", NoDefault);
		final pathArg = new HxFunctionArg("path", "String", NoDefault);
		final compilerClass = new HxClassDecl("Compiler", false, [
			new HxFunctionDecl("getDefine", HxVisibility.Public, true, [keyArg], "String",
				[SExpr(EUnsupported("compiler-get-define-std-source-should-not-render"), pos)], ""),
			new HxFunctionDecl("define", HxVisibility.Public, true, [keyArg, valueArg], "Void",
				[SExpr(EUnsupported("compiler-define-std-source-should-not-render"), pos)], ""),
			new HxFunctionDecl("excludeFile", HxVisibility.Public, true, [pathArg], "Void",
				[SExpr(EUnsupported("compiler-exclude-file-std-source-should-not-render"), pos)], "")
		]);
		final compilerDecl = new HxModuleDecl("haxe.macro", [], compilerClass, [compilerClass], false, false);
		final program = MacroStage.expandProgram([
			typedSyntheticModule("Main.hx", mainDecl),
			typedSyntheticModule("std/haxe/macro/Compiler.hx", compilerDecl)
		], []);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class Compiler:", "Python support should synthesize a haxe.macro.Compiler fallback from std source");
		assertContains(content, "def getDefine(key):", "Python Compiler fallback should expose getDefine");
		assertContains(content, "haxe.macro.Compiler = Compiler", "Python support should expose Compiler through the haxe.macro namespace");
		assertNotContains(content, "compiler-get-define-std-source-should-not-render", "Python Compiler fallback should not render std source bodies");
		if (commandExists("python3")) {
			final run = commandOutput("python3", [outputPath]);
			assertTrue(run.code == 0, "generated Python Compiler fallback should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "abc\nNone", "generated Python Compiler fallback should store defines and return None for missing defines");
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPythonOptionalMethodArguments():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_optional_method_args_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final pos = HxPos.unknown();
		final addCaseFn = new HxFunctionDecl("addCase", HxVisibility.Public, false, [
			new HxFunctionArg("c", "Dynamic", NoDefault),
			new HxFunctionArg("setup", "Dynamic", NoDefault, true),
			new HxFunctionArg("teardown", "Dynamic", NoDefault, true),
			new HxFunctionArg("prefix", "String", Default(EString("default-prefix")), true),
			new HxFunctionArg("pattern", "String", NoDefault, true),
			new HxFunctionArg("setupAsync", "Dynamic", NoDefault, true),
			new HxFunctionArg("teardownAsync", "Dynamic", NoDefault, true)
		], "Void", [
			SExpr(ECall(EField(EIdent("Sys"), "println"), [EIdent("setup")]), pos),
			SExpr(ECall(EField(EIdent("Sys"), "println"), [EIdent("prefix")]), pos),
			SExpr(ECall(EField(EIdent("Sys"), "println"), [EIdent("pattern")]), pos)
		], "");
		final runnerClass = new HxClassDecl("Runner", false, [addCaseFn]);
		final runnerDecl = new HxModuleDecl("", [], runnerClass, [runnerClass], false, false);
		final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [
			SVar("runner", "", ENew("Runner", []), pos),
			SExpr(ECall(EField(EIdent("runner"), "addCase"), [EString("case")]), pos)
		], "");
		final mainClass = new HxClassDecl("Main", true, [mainFn]);
		final mainDecl = new HxModuleDecl("", [], mainClass, [mainClass], false, false);
		final program = MacroStage.expandProgram([
			typedSyntheticModule("Main.hx", mainDecl),
			typedSyntheticModule("Runner.hx", runnerDecl)
		], []);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content,
			"def addCase(self, c, setup=None, teardown=None, prefix=\"default-prefix\", pattern=None, setupAsync=None, teardownAsync=None):",
			"Python support methods should make optional/default arguments omittable at runtime");
		if (commandExists("python3")) {
			final run = commandOutput("python3", [outputPath]);
			assertTrue(run.code == 0, "generated Python optional method arguments should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "None\ndefault-prefix\nNone", "generated Python should apply None/default values for omitted method arguments");
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPythonSameClassInstanceMethodCall():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_same_class_instance_call_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final pos = HxPos.unknown();
		final addCaseFn = new HxFunctionDecl("addCase", HxVisibility.Public, false, [new HxFunctionArg("test", "Dynamic", NoDefault)], "Void",
			[SExpr(ECall(EIdent("addCaseOld"), [EIdent("test")]), pos)], "");
		final addCaseOldFn = new HxFunctionDecl("addCaseOld", HxVisibility.Public, false, [new HxFunctionArg("test", "Dynamic", NoDefault)], "Void", [
			SIf(EUnop("!", ECall(EIdent("isMethod"), [EIdent("test")])), SExpr(ECall(EField(EIdent("Sys"), "println"), [EString("not-method")]), pos), null,
				pos),
			SExpr(ECall(EField(EIdent("Sys"), "println"), [EIdent("test")]), pos)
		], "");
		final isMethodFn = new HxFunctionDecl("isMethod", HxVisibility.Public, false, [new HxFunctionArg("test", "Dynamic", NoDefault)], "Bool",
			[SReturn(EBool(true), pos)], "");
		final runnerClass = new HxClassDecl("Runner", false, [addCaseFn, addCaseOldFn, isMethodFn]);
		final runnerDecl = new HxModuleDecl("", [], runnerClass, [runnerClass], false, false);
		final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [
			SVar("runner", "", ENew("Runner", []), pos),
			SExpr(ECall(EField(EIdent("runner"), "addCase"), [EString("case")]), pos)
		], "");
		final mainClass = new HxClassDecl("Main", true, [mainFn]);
		final mainDecl = new HxModuleDecl("", [], mainClass, [mainClass], false, false);
		final program = MacroStage.expandProgram([
			typedSyntheticModule("Main.hx", mainDecl),
			typedSyntheticModule("Runner.hx", runnerDecl)
		], []);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "self.addCaseOld(test)", "Python same-class instance calls should dispatch through self");
		assertNotContains(content, "        addCaseOld(test)", "Python same-class instance calls should not emit an unqualified global call");
		assertContains(content, "(not self.isMethod(test))", "Python nested same-class condition calls should dispatch through self");
		assertNotContains(content, "(not isMethod(test))", "Python nested same-class condition calls should not emit an unqualified global call");
		if (commandExists("python3")) {
			final run = commandOutput("python3", [outputPath]);
			assertTrue(run.code == 0, "generated Python same-class instance calls should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "case", "generated Python should dispatch the same-class helper method");
			assertNotContains(run.stdout, "not-method", "generated Python should call the nested same-class helper inside the condition");
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPythonSameClassInstanceFieldRead():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_same_class_instance_field_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final pos = HxPos.unknown();
		final printField:HxStmt = SExpr(ECall(EField(EIdent("Sys"), "println"), [EIdent("globalPattern")]), pos);
		final printArg:HxStmt = SExpr(ECall(EField(EIdent("Sys"), "println"), [EIdent("pattern")]), pos);
		final printLocal:HxStmt = SExpr(ECall(EField(EIdent("Sys"), "println"), [EIdent("localPattern")]), pos);
		final printStatic:HxStmt = SExpr(ECall(EField(EIdent("Sys"), "println"), [EField(EIdent("Runner"), "staticPattern")]), pos);
		final addCaseFn = new HxFunctionDecl("addCase", HxVisibility.Public, false, [new HxFunctionArg("pattern", "String", NoDefault)], "Void", [
			SVar("localPattern", "String", EString("local"), pos),
			printField,
			printArg,
			printLocal,
			printStatic,
			SExpr(EBinop("=", EIdent("globalPattern"), EString("updated")), pos),
			printField
		], "");
		final runnerClass = new HxClassDecl("Runner", false, [addCaseFn], [
			new HxFieldDecl("globalPattern", HxVisibility.Public, false, "String", EString("global")),
			new HxFieldDecl("staticPattern", HxVisibility.Public, true, "String", EString("static"))
		]);
		final runnerDecl = new HxModuleDecl("", [], runnerClass, [runnerClass], false, false);
		final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [
			SVar("runner", "", ENew("Runner", []), pos),
			SExpr(ECall(EField(EIdent("runner"), "addCase"), [EString("arg")]), pos)
		], "");
		final mainClass = new HxClassDecl("Main", true, [mainFn]);
		final mainDecl = new HxModuleDecl("", [], mainClass, [mainClass], false, false);
		final program = MacroStage.expandProgram([
			typedSyntheticModule("Main.hx", mainDecl),
			typedSyntheticModule("Runner.hx", runnerDecl)
		], []);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "print(self.globalPattern)", "Python same-class instance field reads should dispatch through self");
		assertContains(content, "self.globalPattern = \"updated\"", "Python same-class instance field writes should dispatch through self");
		assertContains(content, "print(pattern)", "Python method arguments should remain local identifiers");
		assertContains(content, "print(localPattern)", "Python local variables should remain local identifiers");
		assertContains(content, "print(Runner.staticPattern)", "Python class-qualified static fields should remain class-qualified");
		assertNotContains(content, "print(globalPattern)", "Python same-class instance field reads should not emit unqualified globals");
		assertNotContains(content, "self.pattern", "Python arguments should not be rewritten as instance fields");
		assertNotContains(content, "self.localPattern", "Python locals should not be rewritten as instance fields");
		assertNotContains(content, "self.staticPattern", "Python static fields should not be rewritten as instance fields");
		if (commandExists("python3")) {
			final run = commandOutput("python3", [outputPath]);
			assertTrue(run.code == 0, "generated Python same-class instance fields should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "global\narg\nlocal\nstatic\nupdated",
				"generated Python should resolve instance fields, arguments, locals, and static fields distinctly");
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPythonReflectSupport():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_reflect_support_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final pos = HxPos.unknown();
		function printIsObject(value:HxExpr):HxStmt {
			return SExpr(ECall(EField(EIdent("Sys"), "println"), [
				ECall(EField(EIdent("Std"), "string"), [ECall(EField(EIdent("Reflect"), "isObject"), [value])])
			]), pos);
		}
		final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [
			SVar("meta", "", EAnon(["testMethod"], [EString("ignored")]), pos),
			SExpr(ECall(EField(EIdent("Sys"), "println"), [
				ECall(EField(EIdent("Reflect"), "getProperty"), [EIdent("meta"), EString("testMethod")])
			]), pos),
			SExpr(ECall(EField(EIdent("Sys"), "println"), [
				ECall(EField(EIdent("Std"), "string"), [
					EBinop("==", ECall(EField(EIdent("Reflect"), "getProperty"), [EIdent("meta"), EString("missing")]), ENull)
				])
			]), pos),
			printIsObject(EAnon(["x"], [EInt(1)])),
			printIsObject(EString("s")),
			printIsObject(EInt(1)),
			printIsObject(ENull)
		], "");
		final mainClass = new HxClassDecl("Main", true, [mainFn]);
		final mainDecl = new HxModuleDecl("", [], mainClass, [mainClass], false, false);
		final valueArg = new HxFunctionArg("value", "Dynamic", NoDefault);
		final reflectFn = new HxFunctionDecl("isObject", HxVisibility.Public, true, [valueArg], "Bool", [SReturn(EBool(false), pos)], "");
		final getPropertyFn = new HxFunctionDecl("getProperty", HxVisibility.Public, true, [
			new HxFunctionArg("obj", "Dynamic", NoDefault),
			new HxFunctionArg("name", "String", NoDefault)
		], "Dynamic", [SReturn(ENull, pos)], "");
		final reflectClass = new HxClassDecl("Reflect", false, [reflectFn, getPropertyFn]);
		final reflectDecl = new HxModuleDecl("", [], reflectClass, [reflectClass], false, false);
		final program = MacroStage.expandProgram([
			typedSyntheticModule("Main.hx", mainDecl),
			typedSyntheticModule("/repo/std/Reflect.hx", reflectDecl)
		], []);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class Reflect:", "Python std Reflect fallback should emit when std Reflect is excluded from helper classes");
		assertContains(content, "def getProperty(obj, name):", "Python std Reflect fallback should expose getProperty");
		assertContains(content, "def isObject(value):", "Python std Reflect fallback should expose isObject");
		assertContains(content, "Reflect.getProperty(meta, \"testMethod\")", "Python Reflect.getProperty calls should target the fallback helper");
		assertContains(content, "Reflect.isObject(hxhx_anon(x=1))", "Python Reflect.isObject calls should target the fallback helper");
		if (commandExists("python3")) {
			final run = commandOutput("python3", [outputPath]);
			assertTrue(run.code == 0, "generated Python Reflect fallback should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "ignored\nTrue\nTrue\nTrue\nFalse\nFalse",
				"generated Python Reflect fallback should handle getProperty plus isObject for objects, strings, scalars, and null");
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPythonTypeSupport():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_type_support_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final pos = HxPos.unknown();
		function printContains(fieldName:String):HxStmt {
			return SExpr(ECall(EField(EIdent("Sys"), "println"), [
				ECall(EField(EIdent("Std"), "string"), [ECall(EField(EIdent("fields"), "contains"), [EString(fieldName)])])
			]), pos);
		}
		final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [
			SVar("test", "", ENew("MyTest", []), pos),
			SVar("cls", "", ECall(EField(EIdent("Type"), "getClass"), [EIdent("test")]), pos),
			SVar("fields", "", ECall(EField(EIdent("Type"), "getInstanceFields"), [EIdent("cls")]), pos),
			SVar("staticFields", "", ECall(EField(EIdent("Type"), "getClassFields"), [EIdent("cls")]), pos),
			SExpr(ECall(EField(EIdent("Sys"), "println"), [ECall(EField(EIdent("Type"), "getClassName"), [EIdent("cls")])]), pos),
			printContains("setup"),
			printContains("staticOnly"),
			SExpr(ECall(EField(EIdent("Sys"), "println"), [
				ECall(EField(EIdent("Std"), "string"), [ECall(EField(EIdent("staticFields"), "contains"), [EString("staticOnly")])])
			]), pos)
		], "");
		final mainClass = new HxClassDecl("Main", true, [mainFn]);
		final mainDecl = new HxModuleDecl("", [], mainClass, [mainClass], false, false);
		final setupFn = new HxFunctionDecl("setup", HxVisibility.Public, false, [], "Void", [SReturnVoid(pos)], "");
		final staticOnlyFn = new HxFunctionDecl("staticOnly", HxVisibility.Public, true, [], "Void", [SReturnVoid(pos)], "");
		final testClass = new HxClassDecl("MyTest", false, [setupFn, staticOnlyFn]);
		final testDecl = new HxModuleDecl("", [], testClass, [testClass], false, false);
		final valueArg = new HxFunctionArg("value", "Dynamic", NoDefault);
		final typeFn = new HxFunctionDecl("getClass", HxVisibility.Public, true, [valueArg], "Dynamic",
			[SExpr(EUnsupported("std-type-source-should-not-render"), pos)], "");
		final typeClass = new HxClassDecl("Type", false, [typeFn]);
		final typeDecl = new HxModuleDecl("", [], typeClass, [typeClass], false, false);
		final program = MacroStage.expandProgram([
			typedSyntheticModule("Main.hx", mainDecl),
			typedSyntheticModule("MyTest.hx", testDecl),
			typedSyntheticModule("/repo/std/Type.hx", typeDecl)
		], []);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class Type:", "Python std Type fallback should emit when std Type is excluded from helper classes");
		assertContains(content, "def getClass(value):", "Python std Type fallback should expose getClass");
		assertContains(content, "def getClassName(cls):", "Python std Type fallback should expose getClassName");
		assertContains(content, "def getInstanceFields(cls):", "Python std Type fallback should expose getInstanceFields");
		assertContains(content, "def getClassFields(cls):", "Python std Type fallback should expose getClassFields");
		assertNotContains(content, "std-type-source-should-not-render", "Python Type support should not dump the skipped std Type source body");
		if (commandExists("python3")) {
			final run = commandOutput("python3", [outputPath]);
			assertTrue(run.code == 0, "generated Python Type fallback should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "MyTest\nTrue\nFalse\nTrue",
				"generated Python Type fallback should name classes, include instance methods, and expose static fields separately");
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPythonStringToolsSupport():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_string_tools_support_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final pos = HxPos.unknown();
		function printBool(expr:HxExpr):HxStmt {
			return SExpr(ECall(EField(EIdent("Sys"), "println"), [ECall(EField(EIdent("Std"), "string"), [expr])]), pos);
		}
		final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [
			printBool(ECall(EField(EIdent("StringTools"), "startsWith"), [EString("testCase"), EString("test")])),
			printBool(ECall(EField(EIdent("StringTools"), "startsWith"), [EString("testCase"), EString("case")])),
			printBool(ECall(EField(EIdent("StringTools"), "endsWith"), [EString("testCase"), EString("Case")]))
		], "");
		final mainClass = new HxClassDecl("Main", true, [mainFn]);
		final mainDecl = new HxModuleDecl("", [], mainClass, [mainClass], false, false);
		final startsWithFn = new HxFunctionDecl("startsWith", HxVisibility.Public, true, [
			new HxFunctionArg("value", "String", NoDefault),
			new HxFunctionArg("prefix", "String", NoDefault)
		], "Bool", [SReturn(EBool(false), pos)], "");
		final endsWithFn = new HxFunctionDecl("endsWith", HxVisibility.Public, true, [
			new HxFunctionArg("value", "String", NoDefault),
			new HxFunctionArg("suffix", "String", NoDefault)
		], "Bool", [SReturn(EBool(false), pos)], "");
		final stringToolsClass = new HxClassDecl("StringTools", false, [startsWithFn, endsWithFn]);
		final stringToolsDecl = new HxModuleDecl("", [], stringToolsClass, [stringToolsClass], false, false);
		final program = MacroStage.expandProgram([
			typedSyntheticModule("Main.hx", mainDecl),
			typedSyntheticModule("/repo/std/StringTools.hx", stringToolsDecl)
		], []);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class StringTools:", "Python std StringTools fallback should emit when std StringTools is excluded from helper classes");
		assertContains(content, "def startsWith(value, prefix):", "Python std StringTools fallback should expose startsWith");
		assertContains(content, "StringTools.startsWith(\"testCase\", \"test\")", "Python StringTools.startsWith calls should target the fallback helper");
		assertContains(content, "def endsWith(value, suffix):", "Python std StringTools fallback should expose endsWith");
		if (commandExists("python3")) {
			final run = commandOutput("python3", [outputPath]);
			assertTrue(run.code == 0, "generated Python StringTools fallback should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "True\nFalse\nTrue", "generated Python StringTools fallback should match startsWith/endsWith basics");
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPythonMetaSupport():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_meta_support_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final pos = HxPos.unknown();
		final fieldsCall:HxExpr = ECall(EField(EIdent("Meta"), "getFields"), [ENull]);
		final staticsCall:HxExpr = ECall(EField(EIdent("Meta"), "getStatics"), [ENull]);
		final typeCall:HxExpr = ECall(EField(EIdent("Meta"), "getType"), [ENull]);
		function printNotNull(expr:HxExpr):HxStmt {
			return SExpr(ECall(EField(EIdent("Sys"), "println"), [ECall(EField(EIdent("Std"), "string"), [EBinop("!=", expr, ENull)])]), pos);
		}
		final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void",
			[printNotNull(fieldsCall), printNotNull(staticsCall), printNotNull(typeCall)], "");
		final mainClass = new HxClassDecl("Main", true, [mainFn]);
		final mainDecl = new HxModuleDecl("", [], mainClass, [mainClass], false, false);
		final getFieldsFn = new HxFunctionDecl("getFields", HxVisibility.Public, true, [new HxFunctionArg("cls", "Dynamic", NoDefault)], "Dynamic",
			[SReturn(ENull, pos)], "");
		final getStaticsFn = new HxFunctionDecl("getStatics", HxVisibility.Public, true, [new HxFunctionArg("cls", "Dynamic", NoDefault)], "Dynamic",
			[SReturn(ENull, pos)], "");
		final getTypeFn = new HxFunctionDecl("getType", HxVisibility.Public, true, [new HxFunctionArg("cls", "Dynamic", NoDefault)], "Dynamic",
			[SReturn(ENull, pos)], "");
		final metaClass = new HxClassDecl("Meta", false, [getFieldsFn, getStaticsFn, getTypeFn]);
		final metaDecl = new HxModuleDecl("haxe.rtti", [], metaClass, [metaClass], false, false);
		final program = MacroStage.expandProgram([
			typedSyntheticModule("Main.hx", mainDecl),
			typedSyntheticModule("/repo/std/haxe/rtti/Meta.hx", metaDecl)
		], []);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class Meta:", "Python std Meta fallback should emit when haxe.rtti.Meta is excluded from helper classes");
		assertContains(content, "def getFields(cls):", "Python std Meta fallback should expose getFields");
		assertContains(content, "Meta.getFields(None)", "Python Meta.getFields calls should target the fallback helper");
		if (commandExists("python3")) {
			final run = commandOutput("python3", [outputPath]);
			assertTrue(run.code == 0, "generated Python Meta fallback should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "True\nTrue\nTrue", "generated Python Meta fallback should return empty metadata objects");
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPythonValueExceptionBaseSupport():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_value_exception_base_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final pos = HxPos.unknown();
		final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [
			SExpr(ECall(EField(EIdent("Sys"), "println"), [EString("value-exception-base")]), pos)
		], "");
		final mainClass = new HxClassDecl("Main", true, [mainFn]);
		final mainDecl = new HxModuleDecl("", [], mainClass, [mainClass], false, false);
		final subclass = new HxClassDecl("NoConstructorValueException", false, [], [], "ValueException");
		final subclassDecl = new HxModuleDecl("", [], subclass, [subclass], false, false);
		final program = MacroStage.expandProgram([
			typedSyntheticModule("Main.hx", mainDecl),
			typedSyntheticModule("NoConstructorValueException.hx", subclassDecl)
		], []);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class ValueException(Exception):", "Python source backend should emit the ValueException base helper when subclasses need it");
		assertContains(content, "class NoConstructorValueException(ValueException):", "Python support subclasses should keep their ValueException base");
		if (commandExists("python3")) {
			final run = commandOutput("python3", [outputPath]);
			assertTrue(run.code == 0, "generated Python ValueException base support should import/run, stderr:\n" + run.stderr);
			assertContains(run.stdout, "value-exception-base", "generated Python should run after defining the ValueException base helper");
		}
		deleteRecursive(tmpRoot);
	}

	static function arrayLiteralProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var values = [1, 2];",
			"    Sys.println(Std.string(values));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function mapLiteralWithLambdaProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var callbacks = [1 => value -> value + 1, 2 => value -> value + 2];",
			"    Sys.println(Std.string(callbacks));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function constructorProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    new EReg(\"a\", \"\");",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function forInProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    for (value in [1, 2]) {",
			"      Sys.println(Std.string(value));",
			"    }",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function binopProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var total = 1 + 2;",
			"    total = total - 1;",
			"    Sys.println(Std.string(total == 2));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function enumValueProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    Sys.println(Std.string(Macro));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function lambdaProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var inc = value -> value + 1;",
			"    Sys.println(Std.string(inc(1)));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function lambdaImmediateCallProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var value = (input -> input)(1);",
			"    Sys.println(Std.string(value));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function switchExpressionProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var label = switch (\"python\") {",
			"      case \"python\" | \"py\": \"Python\";",
			"      case \"java\": \"Java\";",
			"      case _: \"Other\";",
			"    };",
			"    Sys.println(Std.string(label));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function guardedSwitchExpressionProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var label = switch (1) {",
			"      case 1 if (unknownGuard): \"bad\";",
			"      case _: \"ok\";",
			"    };",
			"    Sys.println(Std.string(label));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function switchStatementProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    switch (\"python\") {",
			"      case \"python\":",
			"        Sys.println(\"py\");",
			"      case _:",
			"        Sys.println(\"other\");",
			"    }",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function javaArraySwitchStatementProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var args = Sys.args();",
			"    switch (args) {",
			"      case [\"ping\"]:",
			"        Sys.println(\"pong\");",
			"      case [\"code\", Std.parseInt(_) => code]:",
			"        Sys.println(Std.string(code));",
			"      case _:",
			"        Sys.println(\"other\");",
			"    }",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function javaUtilityProcessCompileShimProgram():GenIrProgram {
		final src = [
			"class UtilityProcess {",
			"  static function main() {",
			"    var args = Sys.args();",
			"    switch (args) {",
			"      case [Std.parseInt(_) => code]:",
			"        Sys.exit(code);",
			"      case _:",
			"    }",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "UtilityProcess.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function emit(targetId:String, label:String, expectedFile:String, expectedNeedle:String):Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_" + targetId + "_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget(targetId);
		final defines = new StringMap<String>();
		defines.set(label, "1");
		final result = backend.emit(program(label), new BackendContext(tmpRoot, null, "Main", true, false, defines));
		final expectedPath = Path.join([tmpRoot, expectedFile]);
		assertTrue(result.entryPath == expectedPath, "unexpected entry path for " + targetId + ": " + result.entryPath);
		assertTrue(FileSystem.exists(expectedPath), "missing emitted source artifact for " + targetId);
		assertTrue(result.artifacts.length == 1, "expected one source artifact for " + targetId);
		assertTrue(result.artifacts[0].path == expectedPath, "unexpected artifact path for " + targetId);
		assertContains(File.getContent(expectedPath), expectedNeedle, "emitted source missing target print shape for " + targetId);
		deleteRecursive(tmpRoot);
	}

	static function assertPythonOutputHint():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_hint_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final outputPath = Path.join([tmpRoot, "bin", "unit.py"]);
		final backend = BackendRegistry.requireForTarget("python-native");
		final result = backend.emit(program("python"), new BackendContext(tmpRoot, outputPath, "Main", true, false, new StringMap<String>()));
		assertTrue(result.entryPath == outputPath, "source backend should honor explicit Python output file hint");
		assertTrue(FileSystem.exists(outputPath), "source backend should create the explicit Python output file");
		assertContains(File.getContent(outputPath), "print((\"source-native:\" + \"python\"))", "hinted Python output should contain emitted program");
		deleteRecursive(tmpRoot);
	}

	static function assertJavaJarPackaging():Void {
		if (!commandExists("javac") || !commandExists("jar") || !commandExists("java"))
			return;
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_java_jar_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final outputDir = Path.join([tmpRoot, "bin", "java", "TestMain-Debug"]);
		final backend = BackendRegistry.requireForTarget("java-native");
		final result = backend.emit(program("java"), new BackendContext(outputDir, null, "Main", true, true, new StringMap<String>()));
		final sourcePath = Path.join([outputDir, "src", "Main.java"]);
		final jarPath = outputDir + ".jar";
		assertTrue(result.entryPath == jarPath, "Java source backend should report the packaged jar as primary artifact");
		assertTrue(FileSystem.exists(sourcePath), "Java source backend should emit source under the target output directory");
		assertTrue(FileSystem.exists(jarPath), "Java source backend should package the jar path expected by upstream runci");
		final sourceContent = File.getContent(sourcePath);
		assertContains(sourceContent, "class Std", "Java source backend should provide minimal Std support class");
		assertContains(sourceContent, "public static int parseInt(String value)", "Java Std.parseInt support should handle sys helper exit codes");
		assertContains(sourceContent, "class Sys", "Java source backend should provide minimal Sys support class");
		assertContains(sourceContent, "public static int command(Object... args)",
			"Java Sys.command support should execute helper commands used by upstream Java misc projects");
		assertContains(sourceContent, "public static String[] args()", "Java Sys.args support should expose CLI args to sys tests");
		assertContains(sourceContent, "java.lang.Process process = new ProcessBuilder",
			"Java Sys.command support should avoid ambiguity with sys.io.Process imports");
		assertContains(sourceContent, "public static String systemName()",
			"Java Sys.systemName support should let helper programs choose the platform classpath separator");
		assertContains(sourceContent, "public static void exit(Object code)", "Java Sys.exit support should propagate helper command failures");
		final run = commandOutput("java", ["-jar", jarPath]);
		assertTrue(run.code == 0, "Java source backend jar should run: " + run.stderr);
		assertContains(run.stdout, "source-native:java", "Java source backend jar should execute generated main");
		final runciOutputDir = Path.join([tmpRoot, "bin", "java"]);
		final debugDefines = new StringMap<String>();
		debugDefines.set("debug", "1");
		final runciResult = backend.emit(program("java-runci"), new BackendContext(runciOutputDir, null, "Main", true, true, debugDefines));
		final runciJarPath = Path.join([runciOutputDir, "Main-Debug.jar"]);
		assertTrue(runciResult.entryPath == runciJarPath, "Java source backend should use runci-compatible jar path for bin/java output");
		assertTrue(FileSystem.exists(runciJarPath), "Java source backend should package jar under bin/java for upstream runci");
		final threadsOutputDir = Path.join([tmpRoot, "threads", "java"]);
		final threadsResult = backend.emit(program("java-runci"), new BackendContext(threadsOutputDir, null, "Main", true, true, new StringMap<String>()));
		final threadsJarPath = Path.join([threadsOutputDir, "Main.jar"]);
		assertTrue(threadsResult.entryPath == threadsJarPath, "Java source backend should omit -Debug from non-debug bin/java jars");
		assertTrue(FileSystem.exists(threadsJarPath), "Java source backend should package the non-debug jar expected by upstream threads");
		final jvmBuildDir = Path.join([tmpRoot, "bin", "jvm"]);
		final jvmJarPath = Path.join([tmpRoot, "jvm.jar"]);
		final jvmResult = backend.emit(program("java"), new BackendContext(jvmBuildDir, jvmJarPath, "Main", true, true, new StringMap<String>()));
		assertTrue(jvmResult.entryPath == jvmJarPath, "Java source backend should preserve file-shaped --jvm jar output hints");
		assertTrue(FileSystem.exists(jvmJarPath), "Java source backend should package the requested --jvm jar file");
		deleteRecursive(tmpRoot);
	}

	static function assertJavaLambdaSequenceCallback():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_java_lambda_sequence_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("java-native");
		backend.emit(javaLambdaSequenceCallbackProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.java"]);
		final content = File.getContent(outputPath);
		assertContains(content, "runner.onProgress.add((e) -> {", "Java callback lambdas with statement bodies should render as block lambdas");
		assertContains(content, "for (var item :", "Java lambda-body for-in continuations should lower to statements");
		assertContains(content, "skipped captured assignment", "Java lambda-body captured assignments should compile under the MVP lowering");
		assertContains(content, "System.out.println(\"done\");", "Java lambda-body continuations should render after lowered for-in statements");
		assertNotContains(content, "__hxhx_lambda_seq_", "Java callback lambdas should not leak lambda-sequence temporaries into generated source");
		assertNotContains(content, "-> null(", "Java callback lambdas should not render invalid null-call continuations");
		deleteRecursive(tmpRoot);
	}

	static function assertJavaSupportClassJarPackaging():Void {
		if (!commandExists("javac") || !commandExists("jar"))
			return;
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_java_support_class_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final outputDir = Path.join([tmpRoot, "bin", "java", "SupportMain-Debug"]);
		final backend = BackendRegistry.requireForTarget("java-native");
		final result = backend.emit(javaSupportClassProgram(), new BackendContext(outputDir, null, "Main", true, true, new StringMap<String>()));
		final mainSourcePath = Path.join([outputDir, "src", "Main.java"]);
		final helperSourcePath = Path.join([outputDir, "src", "Helper.java"]);
		final objectShapeSourcePath = Path.join([outputDir, "src", "JavaObjectShape.java"]);
		final signalOwnerSourcePath = Path.join([outputDir, "src", "SignalOwner.java"]);
		final functionalSupportSourcePath = Path.join([outputDir, "src", "FunctionalSupport.java"]);
		final listStubPath = Path.join([outputDir, "src", "haxe", "ds", "List.java"]);
		final bytesStubPath = Path.join([outputDir, "src", "haxe", "io", "Bytes.java"]);
		final reportStubPath = Path.join([outputDir, "src", "utest", "ui", "common", "IReport.java"]);
		final callStackStubPath = Path.join([outputDir, "src", "haxe", "CallStack.java"]);
		final moduleLocalStubPath = Path.join([outputDir, "src", "MyClass", "UsingBase.java"]);
		final testBytesStubPath = Path.join([outputDir, "src", "unit", "TestBytes.java"]);
		final jarPath = outputDir + ".jar";
		assertTrue(result.entryPath == jarPath, "Java source backend should still report the packaged jar for support-class programs");
		assertTrue(FileSystem.exists(mainSourcePath), "Java source backend should emit the main Java source file");
		assertTrue(FileSystem.exists(helperSourcePath), "Java source backend should emit sibling support classes before javac");
		assertTrue(FileSystem.exists(objectShapeSourcePath), "Java source backend should emit sibling classes with Object override-shaped methods");
		assertTrue(FileSystem.exists(signalOwnerSourcePath), "Java source backend should emit sibling classes with signal-shaped fields");
		assertTrue(FileSystem.exists(functionalSupportSourcePath), "Java source backend should emit sibling classes with functional overload stubs");
		assertTrue(FileSystem.exists(listStubPath), "Java source backend should synthesize stubs for imported Haxe package classes");
		assertTrue(FileSystem.exists(bytesStubPath), "Java source backend should synthesize stubs for imported Haxe package classes beyond haxe.ds");
		assertTrue(FileSystem.exists(reportStubPath), "Java source backend should synthesize stubs for imported interface-like package classes");
		assertTrue(FileSystem.exists(callStackStubPath), "Java source backend should synthesize haxe.CallStack stubs");
		assertTrue(FileSystem.exists(moduleLocalStubPath), "Java source backend should synthesize stubs for module-local dotted imports");
		assertTrue(FileSystem.exists(testBytesStubPath), "Java source backend should synthesize compile-only runci helper classes");
		assertTrue(FileSystem.exists(jarPath), "Java source backend should package a jar after compiling support classes");
		final mainContent = File.getContent(mainSourcePath);
		final helperContent = File.getContent(helperSourcePath);
		final objectShapeContent = File.getContent(objectShapeSourcePath);
		final signalOwnerContent = File.getContent(signalOwnerSourcePath);
		final functionalSupportContent = File.getContent(functionalSupportSourcePath);
		final reportContent = File.getContent(reportStubPath);
		final callStackContent = File.getContent(callStackStubPath);
		assertContains(helperContent, "public class Helper", "Java support source should declare the sibling class");
		assertContains(helperContent, "assert_", "Java support source should sanitize reserved method names");
		assertContains(helperContent, "Object native_", "Java support source should sanitize reserved argument names");
		assertContains(helperContent, "Object __", "Java support source should sanitize underscore-only argument names");
		assertContains(reportContent, "public interface IReport", "Java import stubs should model interface-like names as interfaces");
		assertContains(callStackContent, "public static Object exceptionStack(Object... args)", "Java haxe.CallStack stubs should include exceptionStack");
		assertContains(objectShapeContent, "public String toString()", "Java support source should preserve Object-compatible toString signatures");
		assertContains(objectShapeContent, "public int hashCode()", "Java support source should preserve Object-compatible hashCode signatures");
		assertContains(objectShapeContent, "public boolean equals(Object other)", "Java support source should preserve Object-compatible equals signatures");
		assertContains(objectShapeContent, "public Object wide(Object... args)", "Java support methods should include varargs fallback overloads");
		assertContains(signalOwnerContent, "public __HxSignal onProgress = new __HxSignal()", "Java on* fields should expose callable signal placeholders");
		assertContains(signalOwnerContent, "public static SignalOwner create()", "Java static create support methods should return the owning class");
		assertContains(signalOwnerContent, "return new SignalOwner()", "Java static create support methods should return a non-null owning instance");
		assertContains(functionalSupportContent, "java.util.function.Consumer<Object>", "Java support methods should expose one-arg functional overloads");
		assertContains(functionalSupportContent, "java.util.function.Function<Object, Object>",
			"Java support methods should expose returning one-arg functional overloads");
		assertContains(functionalSupportContent, "java.util.function.BiFunction<Object, Object, Object>",
			"Java support methods should expose two-arg functional overloads");
		assertContains(functionalSupportContent, "choose(java.util.function.Function<Object, Object> arg0, Object value)",
			"Java two-argument helper stubs should expose one-arg function/value overloads");
		assertContains(functionalSupportContent, "return arg0.apply(value)",
			"Java two-argument helper stubs should invoke one-arg callbacks with the supplied value");
		assertContains(functionalSupportContent, "choose(java.util.function.BiFunction<Object, Object, Object> arg0, Object value)",
			"Java two-argument helper stubs should expose two-arg function/value overloads");
		assertContains(functionalSupportContent, "return arg0.apply(value, value)",
			"Java two-argument helper stubs should invoke two-arg callbacks with the supplied value twice");
		assertContains(mainContent, "java.util.function.BiFunction<Object, Object, Object> multiply = Main::multiply",
			"Java main helpers should expose method-reference fields");
		assertContains(mainContent, "public static Object plusOne(Object value)", "Java main helpers should emit one-arg static function references");
		assertContains(mainContent, "return (Std.int_(value) * Std.int_(2));", "Java main helper method references should execute their Haxe return bodies");
		assertContains(mainContent, "public static Object pairTotal(Object left, Object right)",
			"Java main helpers should emit two-arg static function references");
		assertContains(mainContent, "return (Std.int_(left) * Std.int_(right));",
			"Java main helper method references should execute two-arg Haxe return bodies");
		assertContains(mainContent, "public static Object multiply(Object a, Object b)", "Java main helpers should emit compile-only static methods");
		assertContains(mainContent, "testTopLevel(java.util.function.Function<Object, Object> arg0)",
			"Java entrypoint body direct helper calls should expose lambda-compatible overloads");
		assertContains(mainContent, "return arg0.apply(null)", "Java lambda-compatible helper stubs should invoke callbacks");
		assertContains(mainContent, "helper.assert_(\"ok\")", "Java main source should call sanitized support method names");
		assertNotContains(mainContent, "import Map;", "Java main source should not import default-package classes");
		assertNotContains(mainContent, "import Helper.label;", "Java main source should not import default-package module members");
		assertNotContains(helperContent, "import Type;", "Java support source should not import default-package classes");
		final secondResult = backend.emit(javaSupportClassProgram(), new BackendContext(outputDir, null, "Main", true, true, new StringMap<String>()));
		assertTrue(secondResult.entryPath == jarPath, "Java source backend should reuse the same jar path on repeated output-dir emits");
		assertTrue(FileSystem.exists(jarPath), "Java source backend should recompile generated import/helper stubs on repeated output-dir emits");
		final secondRun = commandOutput("java", ["-jar", jarPath]);
		assertTrue(secondRun.code == 0, "Java source backend jar should still run after repeated emit: " + secondRun.stderr);
		assertContains(secondRun.stdout, "callback", "Java functional helper stubs should execute callback bodies");
		assertContains(secondRun.stdout, "8", "Java function/value overloads should execute one-arg same-class method references");
		assertContains(secondRun.stdout, "16", "Java function/value overloads should execute two-arg same-class method references");
		deleteRecursive(tmpRoot);
	}

	static function assertJavaLibraryEnumJarPackaging():Void {
		if (!commandExists("javac") || !commandExists("jar") || !commandExists("java"))
			return;
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_java_library_enum_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final outputDir = Path.join([tmpRoot, "bin", "java"]);
		final jarPath = Path.join([tmpRoot, "bin", "haxe.jar"]);
		final backend = BackendRegistry.requireForTarget("java-native");
		final result = backend.emit(javaLibraryEnumProgram(), new BackendContext(outputDir, jarPath, "demo.Maybe", true, true, new StringMap<String>()));
		final maybeSourcePath = Path.join([outputDir, "src", "demo", "Maybe.java"]);
		assertTrue(result.entryPath == jarPath, "Java library emission should report the requested jar path as primary artifact");
		assertTrue(FileSystem.exists(jarPath), "Java library emission should package a jar without requiring a Haxe main");
		assertTrue(FileSystem.exists(maybeSourcePath), "Java library emission should emit the enum support source");
		final maybeContent = File.getContent(maybeSourcePath);
		assertContains(maybeContent, "public static class Present extends Maybe", "Java enum-like library source should expose constructor classes");
		assertContains(maybeContent, "public Object v;", "Java enum-like constructor classes should expose payload fields");
		assertContains(maybeContent, "public static Maybe Present(Object v)", "Java enum-like library source should expose constructor factories");
		final probePath = Path.join([tmpRoot, "Main.java"]);
		File.saveContent(probePath, [
			"import demo.Maybe;",
			"",
			"class Main {",
			"  public static void main(String[] args) {",
			"    Maybe value = Maybe.Present(\"ok\");",
			"    if (value instanceof Maybe.Present && ((Maybe.Present)value).v.equals(\"ok\")) {",
			"      System.out.println(\"library-enum-ok\");",
			"      return;",
			"    }",
			"    throw new RuntimeException(\"enum payload mismatch\");",
			"  }",
			"}",
		].join("\n"));
		final javac = commandOutput("javac", ["-d", Path.join([tmpRoot, "bin"]), "-cp", jarPath, probePath]);
		assertTrue(javac.code == 0, "External Java should compile against the generated library jar: " + javac.stderr);
		final separator = Sys.systemName() == "Windows" ? ";" : ":";
		final run = commandOutput("java", ["-cp", jarPath + separator + Path.join([tmpRoot, "bin"]), "Main"]);
		assertTrue(run.code == 0, "External Java should run against the generated library jar: " + run.stderr);
		assertContains(run.stdout, "library-enum-ok", "External Java should observe generated enum payloads");
		deleteRecursive(tmpRoot);
	}

	static function assertJavaOperationInterfaceRuntime():Void {
		if (!commandExists("javac") || !commandExists("jar") || !commandExists("java"))
			return;
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_java_operation_interface_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final outputDir = Path.join([tmpRoot, "bin", "java", "OperationMain-Debug"]);
		final backend = BackendRegistry.requireForTarget("java-native");
		final result = backend.emit(javaOperationInterfaceProgram(), new BackendContext(outputDir, null, "Main", true, true, new StringMap<String>()));
		final jarPath = outputDir + ".jar";
		final calcSourcePath = Path.join([outputDir, "src", "Calc.java"]);
		final opSourcePath = Path.join([outputDir, "src", "BinaryOp.java"]);
		assertTrue(result.entryPath == jarPath, "Java operation interface program should package an executable jar");
		assertTrue(FileSystem.exists(calcSourcePath), "Java operation interface program should emit the helper class");
		assertTrue(FileSystem.exists(opSourcePath), "Java operation interface program should emit the operation interface");
		final opContent = File.getContent(opSourcePath);
		final calcContent = File.getContent(calcSourcePath);
		assertContains(opContent, "public interface BinaryOp", "Single-method operation declarations should render as Java interfaces");
		assertContains(calcContent, "public static BinaryOp sum", "Typed static lambda fields should keep their operation interface type");
		assertContains(calcContent, "getMethod(\"run\", Object.class, Object.class)", "Operation helper methods should dispatch interface calls");
		final run = commandOutput("java", ["-jar", jarPath]);
		assertTrue(run.code == 0, "Java operation interface jar should run: " + run.stderr);
		assertContains(run.stdout, "sum=12", "Static lambda operation fields should execute through the interface helper");
		assertContains(run.stdout, "diff=6", "Second static lambda operation field should execute through the interface helper");
		assertContains(run.stdout, "product=27", "Same-class method references should adapt to operation helpers");
		assertContains(run.stdout, "quotient=3", "Inline lambdas should adapt to operation helpers");
		deleteRecursive(tmpRoot);
	}

	static function assertUnsupportedDiagnostic():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_unsupported_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		var message = "";
		try {
			backend.emit(unsupportedDoWhileProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		} catch (e:String) {
			message = e;
		}
		assertContains(message, "Python source backend MVP unsupported statement: SDoWhile", "unsupported statement diagnostic should name the AST kind");
		deleteRecursive(tmpRoot);
	}

	static function assertWhileStatement():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_while_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(whileProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "while (count < 2):", "while loops should render conditions");
		assertContains(content, "    count += 1", "while loop bodies should render with nested indentation");
		assertContains(content, "print(str(count))", "while-derived locals should still flow through later statements");
		deleteRecursive(tmpRoot);
	}

	static function assertIfStatement():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_if_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(ifStatementProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "if (value == 1):", "if statements should render conditions");
		assertContains(content, "    print(\"yes\")", "then branches should render with nested indentation");
		assertContains(content, "else:", "else branches should render");
		assertContains(content, "    print(\"no\")", "else branch bodies should render with nested indentation");
		deleteRecursive(tmpRoot);
	}

	static function assertGenericCallStatement():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_call_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(genericCallProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		assertContains(File.getContent(outputPath), "Math.isFinite(1.5)", "generic expression statement should render calls and fields");
		deleteRecursive(tmpRoot);
	}

	static function assertTraceStatement():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_trace_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(traceProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		assertContains(File.getContent(outputPath), "print(\"trace-native\")", "trace calls should lower to the target print statement");
		deleteRecursive(tmpRoot);
	}

	static function assertJavaTraceRuntimePrefix():Void {
		if (!commandExists("javac") || !commandExists("jar") || !commandExists("java"))
			return;
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_java_trace_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final outputDir = Path.join([tmpRoot, "bin", "java", "TraceMain-Debug"]);
		final backend = BackendRegistry.requireForTarget("java-native");
		backend.emit(traceProgram(), new BackendContext(outputDir, null, "Main", true, true, new StringMap<String>()));
		final run = commandOutput("java", ["-jar", outputDir + ".jar"]);
		assertTrue(run.code == 0, "Java trace jar should run: " + run.stderr);
		assertContains(run.stdout, "Main.hx:3: trace-native", "Java trace should include Haxe-style file and line prefix");
		deleteRecursive(tmpRoot);
	}

	static function assertJavaLambdaTraceSourcePrefix():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_java_lambda_trace_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final outputDir = Path.join([tmpRoot, "bin", "java", "LambdaTraceMain-Debug"]);
		final backend = BackendRegistry.requireForTarget("java-native");
		backend.emit(javaLambdaTraceProgram(), new BackendContext(outputDir, null, "Main", true, false, new StringMap<String>()));
		final content = File.getContent(Path.join([outputDir, "Main.java"]));
		assertContains(content, "System.out.println(\"Main.hx:3: \" + 12);", "Java lambda trace should include the lambda body source line");
		deleteRecursive(tmpRoot);
	}

	static function assertUnaryOperators():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_unop_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(unaryOperatorProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "flag = (not False)", "logical not should lower to the Python unary form");
		assertContains(content, "delta = (-1)", "unary minus should lower to the target unary form");
		assertContains(content, "print(str(flag))", "unary-derived values should still flow through normal calls");
		assertContains(content, "print(str(delta))", "multiple unary-derived values should still render");
		deleteRecursive(tmpRoot);
	}

	static function assertPostfixStatements():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_postfix_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(postfixStatementProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "count = 1", "postfix smoke should declare the local first");
		assertContains(content, "count = (count + 1)", "postfix increment statements should lower to explicit assignments");
		assertContains(content, "count = (count - 1)", "postfix decrement statements should lower to explicit assignments");
		assertContains(content, "print(str(count))", "postfix-lowered locals should still flow through later statements");
		deleteRecursive(tmpRoot);
	}

	static function assertTernaryExpression():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_ternary_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(ternaryProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "label = (\"yes\" if (True) else \"no\")", "ternary expressions should lower to the Python conditional form");
		assertContains(content, "print(str(label))", "ternary-derived locals should still flow through later statements");
		deleteRecursive(tmpRoot);
	}

	static function assertTryCatchStatement():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_try_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(tryCatchProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "try:", "try statements should render the Python try header");
		assertContains(content, "raise Exception(\"boom\")", "throw statements should lower to Python exception raises");
		assertContains(content, "except Exception as e:", "catch clauses should lower to Python except clauses");
		assertContains(content, "print(\"caught\")", "catch bodies should still render nested statements");
		deleteRecursive(tmpRoot);
	}

	static function assertArrayAccessExpression():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_array_access_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(arrayAccessProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "values = Array([1, 2])", "array access smoke should render array literals through the Python Array shim");
		assertContains(content, "first = values[0]", "array access expressions should lower to Python index syntax");
		assertContains(content, "print(str(first))", "array-access-derived locals should still flow through later statements");
		deleteRecursive(tmpRoot);
	}

	static function assertArrayComprehensionExpression():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_array_comprehension_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(arrayComprehensionProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "values = Array([1, 2])", "array comprehension smoke should render the iterable source through the Python Array shim");
		assertContains(content, "doubled = Array([(value * 2) for value in values])",
			"array comprehensions should lower to Python comprehensions wrapped in the Array shim");
		assertContains(content, "print(str(doubled))", "array-comprehension-derived locals should still flow through later statements");
		deleteRecursive(tmpRoot);
	}

	static function assertGuardedArrayComprehensionExpression():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_guarded_array_comprehension_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(guardedArrayComprehensionProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "kept = Array([value for value in values if keep(value)])",
			"guarded array comprehensions should lower to Python comprehensions wrapped in the Array shim");
		assertContains(content, "print(str(kept))", "guarded array-comprehension-derived locals should still flow through later statements");
		deleteRecursive(tmpRoot);
	}

	static function assertAnonymousObjectExpression():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_anon_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(anonymousObjectProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "def hxhx_anon(**kwargs):", "Python source backend should emit the anonymous-object helper");
		assertContains(content, "info = hxhx_anon(label=\"ok\", count=1)", "anonymous object literals should lower through the helper");
		assertContains(content, "print(info.label)", "anonymous object field access should keep using attribute syntax");
		deleteRecursive(tmpRoot);
	}

	static function assertPythonAnonymousObjectReservedFieldSyntax():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_anon_reserved_field_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final pos = HxPos.unknown();
		final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [
			SVar("info", "", EAnon(["def"], [EInt(1)]), pos),
			SExpr(ECall(EField(EIdent("Sys"), "println"), [EField(EIdent("info"), "def")]), pos)
		], "");
		final mainClass = new HxClassDecl("Main", true, [mainFn]);
		final mainDecl = new HxModuleDecl("", [], mainClass, [mainClass], false, false);
		final program = MacroStage.expandProgram([typedSyntheticModule("Main.hx", mainDecl)], []);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "info = hxhx_anon(def_=1)", "Python anonymous object fields should sanitize reserved keyword names");
		assertContains(content, "print(info.def_)", "Python anonymous object field access should use the same sanitized name");
		assertNotContains(content, "hxhx_anon(def=1)", "Python should not emit reserved keywords as anonymous-object kwargs");
		deleteRecursive(tmpRoot);
	}

	static function assertPythonClassBodyHelperNamesAvoidMangling():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_class_body_helpers_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(anonymousObjectProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "def hxhx_anon(**kwargs):", "Python helper definitions should avoid leading double-underscore names");
		assertContains(content, "info = hxhx_anon(label=\"ok\", count=1)", "Python helper calls should avoid leading double-underscore names");
		assertNotContains(content, "def __hxhx_anon(**kwargs):", "Python helpers should not use names that class scopes mangle");
		assertNotContains(content, "info = __hxhx_anon(label=\"ok\", count=1)", "Python helper calls should not use names that class scopes mangle");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpAnonymousObjectExpression():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_anon_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(anonymousObjectProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "$info = (object)[\"label\" => \"ok\", \"count\" => 1];",
			"PHP anonymous object literals should lower through stdClass-style object casts");
		assertContains(content, "echo $info->label . PHP_EOL;", "PHP anonymous object field access should keep using arrow syntax");
		deleteRecursive(tmpRoot);
	}

	static function assertLoopControlStatements():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_loop_control_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(loopControlProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "while (i < 5):", "loop-control smoke should still render the surrounding while loop");
		assertContains(content, "if (i == 2):", "continue smoke should still render the guarding if");
		assertContains(content, "    continue", "continue statements should lower directly inside loop bodies");
		assertContains(content, "if (i == 4):", "break smoke should still render the guarding if");
		assertContains(content, "    break", "break statements should lower directly inside loop bodies");
		deleteRecursive(tmpRoot);
	}

	static function assertPostfixExpressions():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_postfix_expr_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(postfixExpressionProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "def hxhx_post_update_attr(obj, field, delta):", "Python source backend should emit the postfix attribute helper");
		assertContains(content, "def hxhx_post_update_index(obj, index, delta):", "Python source backend should emit the postfix index helper");
		assertContains(content, "oldX = ((hxhx_post_old := x), (x := (hxhx_post_old + 1)), hxhx_post_old)[2]",
			"identifier postfix expressions should preserve old-value semantics");
		assertContains(content, "oldCount = hxhx_post_update_attr(info, \"count\", 1)", "field postfix expressions should lower through the attribute helper");
		assertContains(content, "oldFirst = hxhx_post_update_index(values, 0, 1)", "indexed postfix expressions should lower through the index helper");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpPostfixExpressions():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_postfix_expr_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(postfixExpressionProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "function __hxhx_post_update_var(&$value, $delta) {", "PHP source backend should emit the postfix local helper");
		assertContains(content, "function __hxhx_post_update_field($obj, $field, $delta) {", "PHP source backend should emit the postfix field helper");
		assertContains(content, "function __hxhx_post_update_index(&$obj, $index, $delta) {", "PHP source backend should emit the postfix index helper");
		assertContains(content, "$oldX = __hxhx_post_update_var($x, 1);", "PHP identifier postfix expressions should preserve old-value semantics");
		assertContains(content, "$oldCount = __hxhx_post_update_field($info, \"count\", 1);",
			"PHP field postfix expressions should lower through the field helper");
		assertContains(content, "$oldFirst = __hxhx_post_update_index($values, 0, 1);",
			"PHP indexed postfix expressions should lower through the index helper");
		deleteRecursive(tmpRoot);
	}

	static function assertUnsignedRightShiftExpression():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_ushr_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(unsignedRightShiftProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "def hxhx_ushr(value, bits):", "Python source backend should emit the unsigned-right-shift helper");
		assertContains(content, "shifted = hxhx_ushr((-1), 1)", "unsigned right shift should lower through the helper");
		assertContains(content, "print(str(shifted))", "unsigned-right-shift results should still flow through later statements");
		deleteRecursive(tmpRoot);
	}

	static function assertHelperClassEmission():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_helper_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(helperClassProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class Helper:", "helper classes should be emitted before main");
		assertContains(content, "def message():", "helper static methods should be emitted");
		assertContains(content, "return \"helper\"", "helper method bodies should be rendered");
		assertContains(content, "print(Helper.message())", "main should still be able to call emitted helper classes");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpStaticClassAccess():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_static_class_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpStaticClassAccessProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class Helper {", "PHP support classes should be emitted before main");
		assertContains(content, "public static function message() {", "PHP support classes should include static methods");
		assertContains(content, "if (Flags::$ready) {", "PHP static property access should use class property syntax");
		assertContains(content, "echo Helper::message() . PHP_EOL;", "PHP static method access should use class method syntax");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpHelperInstanceFieldEmission():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_helper_field_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(helperInstanceFieldProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class Helper {", "PHP helper classes with instance fields should be emitted");
		assertContains(content, "public $value;", "PHP helper instance fields should be declared");
		assertContains(content, "public function __construct() {", "PHP helper constructors should lower to __construct");
		assertContains(content, "$this->value = \"seed\";", "PHP helper instance fields should initialize inside __construct");
		assertContains(content, "public function message() {", "PHP helper instance methods should be emitted");
		assertContains(content, "return $this->value;", "PHP instance methods should read lowered fields");
		assertContains(content, "$helper = new Helper();", "PHP main should instantiate helper classes");
		assertContains(content, "echo $helper->message() . PHP_EOL;", "PHP main should call helper instance methods");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpRuntimeShim():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_runtime_shim_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpSysArgsProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class __HxArray", "PHP source backend should emit a minimal array helper");
		assertContains(content, "class Map", "PHP source backend should emit a minimal Map helper");
		assertContains(content, "public function set($key, $value)", "PHP Map helper should support set");
		assertContains(content, "public function get($key)", "PHP Map helper should support get");
		assertContains(content, "class Runner", "PHP source backend should emit an explicit utest Runner bring-up shim");
		assertContains(content, "get_class_methods($case)", "PHP Runner shim should execute public test/spec methods instead of faking success");
		assertContains(content, "class Report", "PHP source backend should emit an explicit utest Report bring-up shim");
		assertContains(content, "class Assert", "PHP source backend should emit a minimal utest Assert bring-up shim");
		assertContains(content, "public static function equals($expected, $value, $message = null, $pos = null)",
			"PHP Assert shim should support equality checks with optional message and position args");
		assertContains(content, "throw new \\Exception($message === null ? \"assertion failed\" : strval($message));",
			"PHP Assert shim should throw on failed assertions instead of faking success");
		assertContains(content, "class ValueException extends \\Exception", "PHP source backend should emit a minimal ValueException helper");
		assertContains(content, "public static function thrown($value)", "PHP ValueException helper should support thrown values");
		assertContains(content, "class Sys", "PHP source backend should emit a minimal Sys helper");
		assertContains(content, "return new __HxArray(array_slice($argv, 1));", "Sys.args should expose CLI args without the script name");
		assertContains(content, "$verbose = (Sys::args()->indexOf(\"-v\") >= 0);", "Sys.args should lower as a static call usable by indexOf");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpMapRuntimeShim():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_map_runtime_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpMapRuntimeProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "$m = new Map();", "PHP Map construction should lower to the runtime shim");
		assertContains(content, "$sm = new Map();", "PHP haxe.ds.StringMap construction should lower to the runtime shim");
		assertContains(content, "$m->set(\"a\", 1);", "PHP Map.set should lower as an instance method call");
		assertContains(content, "$sm->set(\"b\", 2);", "PHP haxe.ds.StringMap.set should use the runtime shim");
		assertContains(content, "__hxhx_add_string($m->exists(\"a\"))", "PHP Map.exists should be usable in expressions");
		assertContains(content, "__hxhx_add_string($m->get(\"a\"))", "PHP Map.get should be usable in expressions");
		assertContains(content, "__hxhx_add_string(__hxhx_remove($m, \"a\"))", "PHP Map.remove should be usable in expressions");
		assertContains(content, "__hxhx_add_string($sm->get(\"b\"))", "PHP haxe.ds.StringMap.get should be usable in expressions");
		assertContains(content, "$im = new Map();", "PHP haxe.ds.IntMap construction should lower to the runtime shim");
		assertContains(content, "__hxhx_remove($im, (-4815));", "PHP haxe.ds.IntMap.remove should dispatch through the polymorphic remove helper");
		assertContains(content, "__hxhx_array_set($br, 1, 0);", "PHP Map bracket assignment should dispatch through the indexed set helper");
		assertContains(content, "__hxhx_array_add_assign($br, __hxhx_post_update_var($x, 1), 4);",
			"PHP Map bracket add-assign should evaluate the index once through the indexed add helper");
		assertContains(content, "__hxhx_add_string(__hxhx_array_get($br, 1))", "PHP Map bracket reads should dispatch through the indexed get helper");
		assertContains(content, "__hxhx_map_literal([[1, 1]])->toString()", "PHP integer map literal toString should lower to the runtime Map shim");
		assertContains(content, "__hxhx_map_literal([[\"foo\", 1]])->toString()", "PHP string map literal toString should lower to the runtime Map shim");
		assertContains(content, "class Lambda {", "PHP source backend should emit a minimal Lambda helper");
		assertContains(content, "class Reflect {", "PHP source backend should emit a minimal Reflect helper for Array.sort callbacks");
		assertContains(content, "public static function field($object, $field)", "PHP Reflect helper should support dynamic field lookup");
		assertContains(content, "Reflect::field($keyword, \"new\")", "PHP Reflect.field should lower as a static helper call");
		assertContains(content, "echo __hxhx_add(\"\", 5) . PHP_EOL;", "PHP literal interpolation should lower to string concat");
		assertContains(content, "echo __hxhx_add(__hxhx_add(\"a\", __hxhx_add(\"\", $x)), \"b\") . PHP_EOL;",
			"PHP identifier interpolation should keep prefix, payload, and suffix");
		assertContains(content, "$values = Lambda::array($sm);", "PHP Lambda.array should accept Map-backed iterables");
		assertContains(content, "echo __hxhx_array_join($values, \"#\") . PHP_EOL;", "PHP Array.join should lower for Lambda.array results");
		assertContains(content, "$keys = Lambda::array((object)[\"iterator\" => (function() use ($sm) { return $sm->keys(); })]);",
			"PHP Lambda.array should accept structural iterator method closures");
		assertContains(content, "echo __hxhx_array_join($keys, \"#\") . PHP_EOL;", "PHP Array.join should lower for structural iterator results");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpSamePackageQualifiedStaticPath():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_same_package_static_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpSamePackageQualifiedStaticProgram(), new BackendContext(tmpRoot, null, "unit.Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class UnitBuilder", "PHP support class should be emitted in the current global class model");
		assertContains(content, "$specs = [];", "PHP compile-time-only UnitBuilder.generateSpec should not become a runtime class call");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpInstanceFieldMethodCall():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_instance_field_call_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpInstanceFieldMethodCallProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "$runner->onProgress->add(function($e) {", "PHP field method calls should use instance dispatch");
		assertNotContains(content, "onProgress::add", "PHP field method calls should not be mistaken for static type paths");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpInheritedTestHelperCall():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_test_helper_call_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpInheritedTestHelperCallProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "public function eq($a, $b, $pos = null)", "PHP optional helper parameters should be omittable at runtime");
		assertContains(content, "$this->eq(1, 1);", "PHP inherited unit test helper calls should dispatch through this");
		assertContains(content, "$this->t(true);", "PHP inherited boolean unit test helpers should dispatch through this");
		assertNotContains(content, "$eq(1, 1);", "PHP inherited unit test helper calls should not emit local callables");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpShadowedTestHelperClosure():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_shadowed_test_helper_closure_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpShadowedTestHelperClosureProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "$f();", "PHP local closure calls named f should not be rewritten as unit helper dispatch");
		assertContains(content, "$this->f(false);", "PHP explicit helper method calls should still dispatch through this");
		assertNotContains(content, "$this->f();", "PHP should not call the boolean helper without its required value argument");
		deleteRecursive(tmpRoot);
	}

	static function assertNativeProtocolOptionalArgDecode():Void {
		final encoded = [
			"hxhx_frontend_v=2",
			protocolLine("class", "Test"),
			"ast static_main 0",
			protocolLine("method", "eq|private|0|a,b,?pos|Void|||a:Dynamic,b:Dynamic,?pos:haxe.PosInfos|"),
			"ok"
		].join("\n");
		final decl = ParserStageNativeDecode.decodeNativeProtocol(encoded);
		final functions = HxClassDecl.getFunctions(HxModuleDecl.getMainClass(decl));
		assertTrue(functions.length == 1, "native protocol should decode the optional-arg method");
		final args = HxFunctionDecl.getArgs(functions[0]);
		assertTrue(args.length == 3, "native protocol should preserve optional-arg arity");
		assertTrue(HxFunctionArg.getName(args[2]) == "pos", "native protocol should strip optional marker from arg names");
		assertTrue(HxFunctionArg.getIsOptional(args[2]), "native protocol should preserve optional argument metadata");
		assertTrue(HxFunctionArg.getTypeHint(args[2]) == "haxe.PosInfos", "native protocol should preserve optional argument type hints");
	}

	static function assertNativeProtocolDefaultArgSourceDecode():Void {
		final source = [
			"class Runner {",
			"  public function addCase(test:Dynamic, setup = \"setup\", teardown = \"teardown\", prefix = \"test\", ?pattern:Dynamic, setupAsync = \"setupAsync\", teardownAsync = \"teardownAsync\") {}",
			"}"
		].join("\n");
		final encoded = [
			"hxhx_frontend_v=2",
			protocolLine("class", "Runner"),
			"ast static_main 0",
			protocolLine("method", "addCase|public|0|test,setup,teardown,prefix,?pattern,setupAsync,teardownAsync|Void|||test:Dynamic,pattern:Dynamic|"),
			"ok"
		].join("\n");
		final decl = ParserStageNativeDecode.decodeNativeProtocol(encoded, source);
		final functions = HxClassDecl.getFunctions(HxModuleDecl.getMainClass(decl));
		assertTrue(functions.length == 1, "native protocol should decode the source-backed addCase method");
		final args = HxFunctionDecl.getArgs(functions[0]);
		assertTrue(args.length == 7, "native protocol should preserve source-backed addCase arity");
		assertTrue(HxFunctionArg.getIsOptional(args[1]), "native protocol should recover defaulted args as omittable from source");
		assertTrue(HxFunctionArg.getDefaultValueText(args[1]) == "\"setup\"", "native protocol should recover the setup default text");
		assertTrue(HxFunctionArg.getIsOptional(args[4]), "native protocol should preserve explicit optional args from payload/source");
		assertTrue(HxFunctionArg.getDefaultValueText(args[5]) == "\"setupAsync\"", "native protocol should recover later defaults after optional args");
	}

	static function assertPhpPlusSemantics():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_plus_semantics_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpPlusSemanticsProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "function __hxhx_add($left, $right)", "PHP source backend should emit a Haxe plus-semantics helper");
		assertContains(content, "function __hxhx_add_string($value)", "PHP plus helper should include Haxe stringification support");
		assertContains(content, "if ($value === null) return \"null\";", "PHP plus helper should stringify null like Haxe");
		assertContains(content, "if ($value instanceof __HxArray) $value = $value->toArray();", "PHP plus helper should unwrap Haxe arrays");
		assertContains(content, "return \"[\" . implode(\",\", $parts) . \"]\";", "PHP plus helper should recursively stringify arrays like Haxe");
		assertContains(content, "foreach (get_object_vars($value) as $key => $fieldValue)", "PHP plus helper should stringify anonymous objects like Haxe");
		assertContains(content, "__hxhx_add(__hxhx_add(1, 2), \"\")",
			"PHP plus lowering should preserve left-associative numeric addition before string conversion");
		assertContains(content, "__hxhx_add(1, __hxhx_add(2, \"\"))", "PHP plus lowering should preserve explicit string-concat grouping");
		assertContains(content, "__hxhx_add(null, \"x\")", "PHP null-left string plus should lower through Haxe helper");
		assertContains(content, "__hxhx_add(\"x\", null)", "PHP null-right string plus should lower through Haxe helper");
		assertContains(content, "__hxhx_add(\"\", (object)[])", "PHP empty anonymous object string plus should lower through Haxe helper");
		assertContains(content, "__hxhx_add(\"\", (object)[\"a\" => 1])", "PHP anonymous object string plus should lower through Haxe helper");
		assertContains(content, "__hxhx_add(\"\", [1, 2])", "PHP array string plus should lower through Haxe helper");
		assertContains(content, "__hxhx_add(\"\", [[1], [2, 3]])", "PHP nested array string plus should lower through Haxe helper");
		assertContains(content, "echo __hxhx_add_string([\"x\"]) . PHP_EOL;", "PHP Std.string on array literals should use Haxe stringification");
		assertContains(content, "function() use (&$s)", "PHP local functions that mutate outer locals should capture by reference");
		assertContains(content, "function($__hxhx_lambda_seq_0) use (&$s)", "PHP local function statement continuations should see call-argument mutations");
		assertContains(content, "$s = __hxhx_add($s, \"b\")", "PHP string-like add-assign should use Haxe plus semantics");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpEnumString():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_enum_string_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpEnumStringProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "return (object)[\"__hx_ctor\" => \"C\", \"__hx_index\" => 0, \"__hx_params\" => [$i, $s]];",
			"PHP scanned enum constructors should return Haxe-like runtime enum objects");
		assertContains(content, "echo __hxhx_add_string($e) . PHP_EOL;", "PHP Std.string on enum values should use Haxe stringification");
		assertContains(content, "echo __hxhx_add_string([$e]) . PHP_EOL;", "PHP Std.string on enum arrays should recursively stringify enum values");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpBitwisePrecedence():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_bitwise_precedence_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpBitwisePrecedenceProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "__hxhx_add_string(((4 | 3) & 1))", "PHP bitwise operators should group left-to-right without explicit parentheses");
		assertContains(content, "__hxhx_add_string((4 | (3 & 1)))", "PHP bitwise lowering should preserve explicit parenthesized grouping");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpSameClassStaticHelperCall():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_same_class_static_helper_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpSameClassStaticHelperCallProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "public static function getA()", "PHP same-class static helper should be emitted as a static method");
		assertContains(content, "return (__hxhx_add(self::getA()->a, 1) >> 1);", "PHP unqualified same-class static helper calls should lower through self::");
		assertNotContains(content, "$getA()", "PHP same-class static helper calls should not lower as local callable variables");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpBitwiseEqualityPrecedence():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_bitwise_equality_precedence_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpBitwiseEqualityPrecedenceProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "__hxhx_add_string(((1 & 32768) != 0))", "PHP bitwise/equality lowering should preserve explicit left grouping");
		assertContains(content, "__hxhx_add_string((0 != (1 & 32768)))", "PHP bitwise/equality lowering should preserve explicit right grouping");
		assertNotContains(content, "(1 & (32768 != 0))", "PHP bitwise operators should bind tighter than equality on the left");
		assertNotContains(content, "((0 != 1) & 32768)", "PHP bitwise operators should bind tighter than equality on the right");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpModuloMultiplicationPrecedence():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_modulo_multiplication_precedence_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpModuloMultiplicationPrecedenceProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "__hxhx_add_string(__hxhx_mul(5, __hxhx_mod(10, 3)))",
			"PHP modulo should bind tighter than multiplication for implicit grouping");
		assertContains(content, "__hxhx_add_string(__hxhx_mod(__hxhx_mul(5, 10), 3))",
			"PHP modulo/multiplication lowering should preserve explicit multiplication grouping");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpFloatModulo():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_float_modulo_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpFloatModuloProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "function __hxhx_mod($left, $right)", "PHP source backend should emit a Haxe modulo helper");
		assertContains(content, "__hxhx_mod(101.5, 100)", "PHP float modulo expressions should lower through the helper");
		assertContains(content, "__hxhx_mod((-101.5), 100)", "PHP negative float modulo expressions should lower through the helper");
		assertContains(content, "$x = __hxhx_mod($x, 100);", "PHP local modulo assignment should lower through the helper");
		assertContains(content, "__hxhx_mod(5, 0)", "PHP modulo-by-zero expressions should lower through the helper for NaN behavior");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpMathRuntime():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_math_runtime_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpMathRuntimeProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class Math", "PHP source backend should emit a minimal Math runtime shim");
		assertContains(content, "public static function isNaN($value)", "PHP Math shim should support isNaN");
		assertContains(content, "public static function isFinite($value)", "PHP Math shim should support isFinite");
		assertContains(content, "public static function floor($value)", "PHP Math shim should support floor");
		assertContains(content, "public static function ceil($value)", "PHP Math shim should support ceil");
		assertContains(content, "public static function round($value)", "PHP Math shim should support Haxe round");
		assertContains(content, "public static function ffloor($value)", "PHP Math shim should support ffloor");
		assertContains(content, "public static function fceil($value)", "PHP Math shim should support fceil");
		assertContains(content, "public static function fround($value)", "PHP Math shim should support Haxe fround");
		assertContains(content, "return floor($value + 0.5);", "PHP Math.round should match Haxe half-up-toward-positive behavior");
		assertContains(content, "Math::isNaN(__hxhx_mod(5, 0))", "PHP Math.isNaN should be callable with modulo-derived NaN");
		assertContains(content, "Math::floor((-1.5))", "PHP Math.floor should lower to the runtime shim");
		assertContains(content, "Math::ceil((-1.5))", "PHP Math.ceil should lower to the runtime shim");
		assertContains(content, "Math::round((-1.5))", "PHP Math.round should lower to the runtime shim");
		assertContains(content, "Math::ffloor((-10000000000.7))", "PHP Math.ffloor should lower to the runtime shim");
		assertContains(content, "Math::fceil((-10000000000.7))", "PHP Math.fceil should lower to the runtime shim");
		assertContains(content, "Math::fround((-10000000000.7))", "PHP Math.fround should lower to the runtime shim");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpTernaryAssignmentLogical():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_ternary_assignment_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpTernaryAssignmentLogicalProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "echo __hxhx_add_string(((!true) ? true : true)) . PHP_EOL;",
			"PHP ternary should bind after unary not for `!true ? true : true`");
		assertContains(content, "echo __hxhx_add_string($k = (true ? false : true)) . PHP_EOL;",
			"PHP assignment should bind looser than ternary in expression form");
		assertContains(content, "echo __hxhx_add_string((($k = true) ? false : true)) . PHP_EOL;",
			"PHP parenthesized assignment should remain the ternary condition");
		assertContains(content, "echo __hxhx_add_string((true || (false && false))) . PHP_EOL;", "PHP logical and should bind tighter than logical or");
		assertNotContains(content, "((!true ? true : true))", "PHP unary not should not wrap the full ternary");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpStringIndexOf():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_string_indexof_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpStringIndexOfProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "function __hxhx_string_index_of($value, $needle, $start = 0)", "PHP runtime should include a String.indexOf helper");
		assertContains(content, "function __hxhx_string_last_index_of($value, $needle, $start = null)",
			"PHP runtime should include a String.lastIndexOf helper");
		assertContains(content, "function __hxhx_string_split($value, $delimiter)", "PHP runtime should include a String.split helper");
		assertContains(content, "function __hxhx_string_char_code_at($value, $index)", "PHP runtime should include a String.charCodeAt helper");
		assertContains(content, "function __hxhx_string_substr($value, $pos, $len = null)", "PHP runtime should include a String.substr helper");
		assertContains(content, "function __hxhx_string_value($value)", "PHP runtime should include abstract-aware string receiver support");
		assertContains(content, "$s = __hxhx_string_value($value);", "PHP string helpers should unwrap abstract string receivers before conversion");
		assertContains(content, "echo __hxhx_add_string(__hxhx_string_index_of(__hxhx_add(\"bla\", \"x\"), \"x\")) . PHP_EOL;",
			"PHP string-like concatenation receivers should lower indexOf through the helper");
		assertContains(content, "echo __hxhx_add_string(__hxhx_string_index_of(\"foo1bar\", \"o\", 2)) . PHP_EOL;",
			"PHP string literal receivers should lower indexOf with a start index");
		assertContains(content, "echo __hxhx_add_string(__hxhx_string_last_index_of(\"foofoofoobarbar\", \"bar\", 11)) . PHP_EOL;",
			"PHP string literal receivers should lower lastIndexOf with a start index");
		assertContains(content, "echo __hxhx_add_string(__hxhx_length(__hxhx_string_split(\"abc\", \"\"))) . PHP_EOL;",
			"PHP string split should compose with array length");
		assertContains(content, "echo __hxhx_add_string(__hxhx_array_get(__hxhx_string_split(\"a,b,c\", \",\"), 1)) . PHP_EOL;",
			"PHP string split results should use safe array reads");
		assertContains(content, "echo __hxhx_add_string(__hxhx_string_char_code_at(\"abc\", 0)) . PHP_EOL;",
			"PHP string charCodeAt should lower through the helper");
		assertContains(content, "echo __hxhx_add_string(__hxhx_string_char_code_at(\"abc\", 99)) . PHP_EOL;",
			"PHP out-of-range charCodeAt should lower through the nullable helper");
		assertContains(content, "echo __hxhx_add_string(__hxhx_string_char_code_at(\"a\", 0)) . PHP_EOL;",
			"PHP string literal .code should lower through the helper");
		assertContains(content, "echo __hxhx_add_string(__hxhx_string_index_of($str, \"b\")) . PHP_EOL;",
			"PHP string variable indexOf should lower through the helper");
		assertContains(content, "echo __hxhx_add_string(__hxhx_string_last_index_of($str, \"b\")) . PHP_EOL;",
			"PHP string variable lastIndexOf should lower through the helper");
		assertContains(content, "echo __hxhx_add_string(__hxhx_string_char_code_at($str, 1)) . PHP_EOL;",
			"PHP string variable charCodeAt should lower through the helper");
		assertContains(content, "echo __hxhx_string_substr($str, 1, 2) . PHP_EOL;", "PHP string variable substr should lower with explicit length");
		assertContains(content, "echo __hxhx_string_substr($str, 3) . PHP_EOL;", "PHP string variable substr should lower with omitted length");
		assertContains(content, "echo __hxhx_string_substr($str, 5) . PHP_EOL;", "PHP out-of-range substr should lower through the helper");
		assertNotContains(content, "__hxhx_add(\"bla\", \"x\")->indexOf", "PHP string-like receivers should not emit object-method calls on raw strings");
		assertNotContains(content, "\"abc\"->split", "PHP string literals should not emit object-method split calls");
		assertNotContains(content, "\"abc\"->charCodeAt", "PHP string literals should not emit object-method charCodeAt calls");
		assertNotContains(content, "\"a\"->code", "PHP string literal .code should not emit property access on raw strings");
		assertNotContains(content, "$str->indexOf", "PHP string variables should not emit object-method indexOf calls");
		assertNotContains(content, "$str->lastIndexOf", "PHP string variables should not emit object-method lastIndexOf calls");
		assertNotContains(content, "$str->charCodeAt", "PHP string variables should not emit object-method charCodeAt calls");
		assertNotContains(content, "$str->substr", "PHP string variables should not emit object-method substr calls");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpStringFromCharCode():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_string_from_char_code_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpStringFromCharCodeProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "function __hxhx_string_from_char_code($code)", "PHP runtime should include a String.fromCharCode helper");
		assertContains(content, "echo __hxhx_string_from_char_code(77) . PHP_EOL;", "PHP String.fromCharCode should lower through the helper");
		assertContains(content, "echo __hxhx_string_from_char_code((-1)) . PHP_EOL;", "PHP negative char codes should route through the helper");
		assertContains(content, "echo __hxhx_string_from_char_code(256) . PHP_EOL;", "PHP oversized char codes should route through the helper");
		assertNotContains(content, "String::fromCharCode", "PHP should not emit calls to a missing String class");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpWebShim():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_web_shim_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpWebProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "namespace php {", "PHP source backend should emit the php.Web namespace shim");
		assertContains(content, "class Web", "PHP source backend should emit the php.Web class shim");
		assertContains(content, "if (php\\Web::$isModNeko) {", "php.Web static fields should lower through PHP static property syntax");
		assertContains(content, "php\\Web::setHeader(\"Content-Type\", \"text/plain\");", "php.Web static calls should lower through PHP static method syntax");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpMacroExpr():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_macro_expr_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpMacroExprProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "\"expr\" =>", "PHP macro expressions should lower to macro object shapes");
		assertContains(content, "\"__hx_ctor\" => \"EUntyped\"", "PHP macro expressions should preserve untyped wrappers");
		assertContains(content, "\"__hx_ctor\" => \"EParenthesis\"", "PHP macro expressions should preserve parenthesis wrappers");
		assertContains(content, "\"__hx_ctor\" => \"CString\"", "PHP macro string constants should lower to CString nodes");
		deleteRecursive(tmpRoot);
	}

	static function assertPythonMacroExpr():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_macro_expr_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(phpMacroExprProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "hxhx_anon(expr=", "Python macro expressions should lower to macro object shapes");
		assertContains(content, "__hx_ctor=\"EUntyped\"", "Python macro expressions should preserve untyped wrappers");
		assertContains(content, "__hx_ctor=\"EParenthesis\"", "Python macro expressions should preserve parenthesis wrappers");
		assertContains(content, "__hx_ctor=\"CString\"", "Python macro string constants should lower to CString nodes");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpDollarString():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_dollar_string_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpDollarStringProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "$code = \"\\$__hxhx_result[] = 1;\";", "PHP string literals should escape dollars to avoid interpolation parse errors");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpInt64LiteralExtension():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_int64_literal_extension_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpInt64LiteralExtensionProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "$a = haxe\\Int64::ofInt(32);", "PHP Int64 literal extension calls should lower to static calls");
		assertContains(content, "$b = haxe\\Int64::ofInt((-4));", "PHP negative Int64 literal extension calls should lower to static calls");
		assertContains(content, "$c = __hxhx_add(__hxhx_int_literal(\"3000000000000\", \"i64\"), \"\");",
			"PHP i64 decimal suffix literals should preserve raw text before runtime string conversion");
		assertContains(content, "$d = __hxhx_add(__hxhx_int_literal(\"0xFFFFFFFFFFFFFFFF\", \"i64\"), \"\");",
			"PHP i64 hex suffix literals should preserve raw text before runtime string conversion");
		assertContains(content, "function __hxhx_int_literal($text, $suffix)", "PHP runtime should include numeric suffix literal normalization support");
		assertNotContains(content, "32->ofInt()", "PHP should not emit instance calls on integer literals");
		deleteRecursive(tmpRoot);
	}

	static function assertPythonNumericLiteralFieldCallSyntax():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_numeric_literal_field_call_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(phpInt64LiteralExtensionProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "a = (32).ofInt()", "Python numeric literal field calls should parenthesize integer receivers");
		assertNotContains(content, "a = 32.ofInt()", "Python should not emit invalid decimal-literal field-call syntax");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpArrayConstructor():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_array_constructor_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpArrayConstructorProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "$values = [];", "PHP Array constructor should lower to array literal syntax");
		assertContains(content, "function __hxhx_length($value)", "PHP runtime should include a Haxe length helper");
		assertContains(content, "echo __hxhx_add_string(__hxhx_length($values)) . PHP_EOL;", "PHP array constructor length should use the Haxe length helper");
		assertContains(content, "echo __hxhx_add_string(__hxhx_length($items)) . PHP_EOL;", "PHP array literal length should use the Haxe length helper");
		assertContains(content, "echo __hxhx_add_string(__hxhx_length(\"abc\")) . PHP_EOL;", "PHP string length should use the Haxe length helper");
		assertNotContains(content, "new Array()", "PHP should not emit reserved Array constructor syntax");
		assertNotContains(content, "$items->length", "PHP arrays should not use object-property length access");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpArrayOperations():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_array_operations_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpArrayOperationsProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "function __hxhx_array_get($array, $index)", "PHP runtime should include a safe Haxe array read helper");
		assertContains(content, "function __hxhx_array_set(&$array, $index, $value)", "PHP runtime should include an indexed set helper");
		assertContains(content, "function __hxhx_array_add_assign(&$array, $index, $value)", "PHP runtime should include an indexed add-assign helper");
		assertContains(content, "function __hxhx_map_literal($pairs)", "PHP runtime should include a map literal helper");
		assertContains(content, "function __hxhx_map_literal_from_object($object)", "PHP runtime should include an object-shaped map literal helper");
		assertContains(content, "function __hxhx_remove(&$collection, $value)", "PHP runtime should include a polymorphic remove helper");
		assertContains(content, "function __hxhx_array_splice(&$array, $pos, $len)", "PHP runtime should include an Array.splice helper");
		assertContains(content, "function __hxhx_array_sort(&$array, $compare)", "PHP runtime should include an Array.sort helper");
		assertContains(content, "function __hxhx_array_join($array, $separator)", "PHP runtime should include an Array.join helper");
		assertContains(content, "class __HxArrayIterator", "PHP runtime should include a Haxe array iterator wrapper");
		assertContains(content, "function __hxhx_iterator($value)", "PHP runtime should include an iterator helper");
		assertContains(content, "echo __hxhx_add_string(__hxhx_array_get($a, 3)) . PHP_EOL;",
			"PHP out-of-bounds array reads should go through safe Haxe read helper");
		assertContains(content, "__hxhx_array_sort($a, [Reflect::class, \"compare\"]);", "PHP Array.sort should lower through the mutating helper");
		assertContains(content, "echo __hxhx_array_join($a, \"#\") . PHP_EOL;", "PHP Array.join should lower through the join helper");
		assertContains(content, "__hxhx_remove($a, 2);", "PHP Array.remove should lower through the mutating helper");
		assertContains(content, "__hxhx_array_splice($a, 1, 1);", "PHP Array.splice should lower through the mutating helper");
		assertContains(content, "$it = __hxhx_iterator($a);", "PHP Array.iterator should lower through the iterator helper");
		assertContains(content, "__hxhx_remove($m, \"a\");", "PHP Map.remove should go through the polymorphic remove helper");
		assertNotContains(content, "$a->remove(2)", "PHP arrays should not emit object-method remove calls on raw arrays");
		assertNotContains(content, "$a->iterator()", "PHP arrays should not emit object-method iterator calls on raw arrays");
		assertNotContains(content, "$a[3]", "PHP expression reads should not emit direct array access for missing-index semantics");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpReservedTypeName():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_reserved_type_name_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpReservedTypeNameProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class Abstract_ {", "PHP reserved type names should be renamed in class declarations");
		assertContains(content, "Abstract_::getName()", "PHP reserved type names should be renamed in static references");
		assertNotContains(content, "Abstract::getName()", "PHP should not emit reserved type names in static references");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpDuplicateStaticFieldEmission():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_duplicate_static_field_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpDuplicateStaticFieldProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		final first = content.indexOf("public static $Expr = null;");
		assertTrue(first >= 0, "PHP support class should emit the Expr static placeholder once");
		final second = content.indexOf("public static $Expr = null;", first + 1);
		assertTrue(second < 0, "PHP support class should not emit duplicate static field placeholders");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpDuplicateMethodEmission():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_duplicate_method_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpDuplicateMethodProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		final first = content.indexOf("public static function test(");
		assertTrue(first >= 0, "PHP support class should emit the test method once");
		final second = content.indexOf("public static function test(", first + 1);
		assertTrue(second < 0, "PHP support class should not emit duplicate method declarations");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpReservedValueName():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_reserved_value_name_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpReservedValueNameProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "$GLOBALS_ = 1;", "PHP local variable names should avoid the GLOBALS superglobal");
		assertContains(content, "$_SERVER_ = 2;", "PHP local variable names should avoid PHP superglobals");
		assertNotContains(content, "$GLOBALS = 1;", "PHP should not assign to the GLOBALS superglobal");
		assertNotContains(content, "$_SERVER = 2;", "PHP should not assign to PHP superglobals");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpNonConstantStaticFieldDefault():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_nonconstant_static_field_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpNonConstantStaticFieldProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "public static $names = null;", "PHP static field defaults should avoid non-constant expressions");
		assertNotContains(content, "public static $names = [label", "PHP static field defaults should not call helper functions");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpArrayPostfixStatement():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_array_postfix_stmt_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpArrayPostfixStatementProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "__hxhx_post_update_index($values, $index, 1);", "PHP array postfix statements should use index update helper");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpCrossPackageSupportClassEmission():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_cross_package_support_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpCrossPackageSupportClassProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class TestBytes {", "PHP support class emission should include non-std typed modules across parser package boundaries");
		assertNotContains(content, "class UTestException {", "PHP support class emission should not include unrelated haxelib packages");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpMacroType():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_macro_type_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpMacroTypeProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "\"__hx_ctor\" => \"TFunction\"", "PHP macro type arrows should lower to TFunction nodes");
		assertContains(content, "\"__hx_ctor\" => \"TPath\"", "PHP macro type paths should lower to TPath nodes");
		assertContains(content, "\"name\" => \"X\"", "PHP macro type paths should preserve argument names");
		assertContains(content, "\"name\" => \"Y\"", "PHP macro type paths should preserve return names");
		assertContains(content, "\"__hx_ctor\" => \"TNamed\"", "PHP macro named function arguments should lower to TNamed nodes");
		assertContains(content, "\"__hx_ctor\" => \"TOptional\"", "PHP macro optional types should lower to TOptional nodes");
		deleteRecursive(tmpRoot);
	}

	static function assertPythonMacroType():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_macro_type_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(phpMacroTypeProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "__hx_ctor=\"TFunction\"", "Python macro type arrows should lower to TFunction nodes");
		assertContains(content, "__hx_ctor=\"TPath\"", "Python macro type paths should lower to TPath nodes");
		assertContains(content, "name=\"X\"", "Python macro type paths should preserve argument names");
		assertContains(content, "name=\"Y\"", "Python macro type paths should preserve return names");
		assertContains(content, "__hx_ctor=\"TNamed\"", "Python macro named function arguments should lower to TNamed nodes");
		assertContains(content, "__hx_ctor=\"TOptional\"", "Python macro optional types should lower to TOptional nodes");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpTryCatchExpression():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_try_expr_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpTryCatchExpressionProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "$label = (function() {", "PHP try/catch expressions should lower through an immediate closure");
		assertContains(content, "try {", "PHP try/catch expressions should preserve the try block");
		assertContains(content, "return \"ok\";", "PHP try/catch expression try bodies should return their final value");
		assertContains(content, "catch (\\Throwable $e) {", "PHP try/catch expressions should catch through Throwable");
		assertContains(content, "return \"bad\";", "PHP try/catch expression catch bodies should return their final value");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpTypeErrorProbe():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_type_error_probe_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpTypeErrorProbeProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "$ok = true;", "PHP source backend should fold HelperMacros.typeError for expression-position for probes");
		assertContains(content, "$message = \"Int has no field keyValueIterator\";",
			"PHP source backend should fold HelperMacros.typeErrorText for key/value for probes");
		assertContains(content, "echo __hxhx_add_string($ok) . PHP_EOL;", "folded typeError results should still flow through normal printing");
		assertContains(content, "echo $message . PHP_EOL;", "folded typeErrorText results should still flow through normal printing");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpTypeErrorBlockProbe():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_type_error_block_probe_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpTypeErrorBlockProbeProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "$ok = true;", "PHP source backend should fold known block typeError probes that should fail typing");
		assertContains(content, "$bad = false;", "PHP source backend should fold known block typeError probes that should type successfully");
		assertContains(content, "$castInt = true;", "PHP source backend should fold abstract-cast Int block typeError probes");
		assertContains(content, "$castString = true;", "PHP source backend should fold abstract-cast String block typeError probes");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpFollowWithAbstractsProbe():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_follow_with_abstracts_probe_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpFollowWithAbstractsProbeProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "$direct = \"TInst(haxe.ds.StringMap,[TInst(String,[])])\";", "PHP source backend should fold followWithAbstracts Map probes");
		assertContains(content, "$once = \"TType(Map,[TInst(String,[]),TInst(String,[])])\";",
			"PHP source backend should fold followWithAbstractsOnce typedef block probes");
		assertContains(content, "$viaTypedef = \"TInst(haxe.ds.StringMap,[TInst(String,[])])\";",
			"PHP source backend should fold followWithAbstracts typedef constructor probes");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpArrayComprehensionClosure():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_array_comprehension_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpArrayComprehensionClosureProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "$funcs = (function() {", "PHP array comprehensions should lower through an immediate closure");
		assertContains(content, "foreach (range(0, 2 - 1) as $i) {", "PHP range comprehensions should lower through foreach");
		assertContains(content, "$__hxhx_result[] = function($value) use ($i) { return __hxhx_mul($value, $i); };",
			"PHP closures yielded from comprehensions should capture the comprehension binder");
		assertContains(content, "return $__hxhx_result;", "PHP array comprehensions should return the collected array");
		assertContains(content, "echo __hxhx_add_string(__hxhx_array_get($funcs, 0)(10)) . PHP_EOL;",
			"PHP array-comprehension-derived functions should still be callable from later statements");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpAbstractThisPostfix():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_abstract_this_postfix_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpAbstractThisPostfixProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class Counter {", "PHP abstract-like helper classes should still emit as support classes");
		assertContains(content, "public $__hx_value;", "PHP abstract-style this values should get a backing slot");
		assertContains(content, "$this->__hx_value = __hxhx_copy_value($i);", "PHP abstract constructor assignments to this should target the backing slot");
		assertContains(content, "$this->__hx_value = ($this->__hx_value + 1);", "PHP statement-position postfix this updates should target the backing slot");
		assertContains(content, "return $this->__hx_value;", "PHP abstract-style return this should return the backing value");
		assertContains(content, "return $this->__hx_value = __hxhx_add($this->__hx_value, 1);",
			"PHP abstract-style prefix this updates should mutate and return the backing value");
		assertContains(content, "$mirror = __hxhx_copy_value($counter);", "PHP abstract-style variable copies should not alias the backing slot");
		assertContains(content, "return __hxhx_post_update_field($this, \"__hx_value\", 1);",
			"PHP expression-position postfix this updates should target the backing slot");
		assertContains(content, "namespace haxe {", "PHP source backend should emit haxe namespace helpers for abstract-cast runtime support");
		assertContains(content, "class Template {", "PHP source backend should emit a minimal haxe.Template runtime shim");
		assertContains(content, "function __hxhx_equals($left, $right)",
			"PHP source backend should emit Haxe-style equality support for abstract-backed values");
		assertContains(content, "function __hxhx_numeric_value($value)",
			"PHP source backend should emit numeric unwrapping support for abstract-backed values");
		assertContains(content,
			"if ((is_int($leftValue) || is_float($leftValue)) && (is_int($rightValue) || is_float($rightValue))) return $leftValue == $rightValue;",
			"PHP equality should compare numeric abstract backing values before stringifying wrappers");
		assertContains(content, "function __hxhx_is_point3($value)", "PHP runtime should identify MyVector/MyPoint3-style abstract operator payloads");
		assertContains(content, "function __hxhx_mul($left, $right)", "PHP runtime should dispatch abstract scalar multiplication");
		assertContains(content, "function __hxhx_mul_assign(&$left, $right)", "PHP runtime should preserve mutating abstract multiply-assignment");
		assertContains(content, "function __hxhx_div($left, $right)", "PHP runtime should dispatch abstract string slicing division");
		assertContains(content, "$tpl = __hxhx_to_template_wrap(\"Hi ::t::\");",
			"PHP abstract @:from-style typed variable declarations should construct the wrapper");
		assertContains(content, "$text = __hxhx_to_string_value($tpl);", "PHP abstract @:to-style String declarations should use string conversion");
		assertContains(content, "$later = __hxhx_to_template_wrap(\"Again ::t::\");",
			"PHP abstract @:from-style typed assignments should construct the wrapper");
		assertContains(content, "$meters = __hxhx_to_meter(3000);", "PHP abstract Meter declarations should preserve wrapper provenance");
		assertContains(content, "$km = __hxhx_to_kilometer($meters);", "PHP abstract-to-abstract assignments should use the Kilometer conversion helper");
		assertContains(content, "$km = __hxhx_to_kilometer($km);", "PHP function arguments typed as Kilometer should normalize constructor inputs");
		assertContains(content, "$hash = __hxhx_to_my_hash([\"k\", \"v\"], true);", "PHP MyHash<String> declarations should use string-key array conversion");
		assertContains(content, "$ihash = __hxhx_to_my_hash([1, 2], false);", "PHP MyHash<T> declarations should use indexed-key array conversion");
		assertContains(content, "$this->__hx_value = __hxhx_copy_value($value);", "PHP MySpecialString constructor should preserve the backing string");
		assertContains(content, "return $len === null ? __hxhx_string_substr($this->__hx_value, $i) : __hxhx_string_substr($this->__hx_value, $i, $len);",
			"PHP MySpecialString substr should delegate to the string runtime helper");
		assertContains(content, "$this->bar();", "PHP same-class helper calls should lower through the instance receiver");
		assertContains(content, "function __hxhx_to_my_abstract_counter($value)",
			"PHP runtime should include MyAbstractCounter @:from-style conversion support");
		assertContains(content, "__hxhx_is_of_type($counter, \"Int\")", "PHP Std.isOfType should lower abstract-backed values through the type helper");
		assertContains(content, "__hxhx_is_of_type(3, \"Int\")", "PHP Std.isOfType should lower scalar type checks without runtime type variables");
		deleteRecursive(tmpRoot);
	}

	static function assertPythonAbstractThisPostfix():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_abstract_this_postfix_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(pythonAbstractThisPostfixProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "self.__hx_value = None", "Python abstract-style helper classes should initialize a backing slot");
		assertContains(content, "self.__hx_value = i", "Python constructor assignments to this should target the backing slot");
		assertContains(content, "self.__hx_value = (self.__hx_value + 1)", "Python statement-position postfix this updates should target the backing slot");
		assertContains(content, "return self.__hx_value", "Python abstract-style return this should return the backing value");
		assertContains(content, "return hxhx_post_update_attr(self, \"__hx_value\", 1)",
			"Python expression-position postfix this updates should target the backing slot");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpSuperConstructor():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_super_ctor_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpSuperConstructorProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class Child extends Base {", "PHP support classes should preserve simple inheritance headers");
		assertContains(content, "parent::__construct();", "PHP super constructor calls should lower through parent::__construct");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpSuperProperty():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_super_property_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpSuperPropertyProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "return __hxhx_add(parent::get_prop(), 1);", "PHP super property reads should lower through parent getters");
		assertContains(content, "return __hxhx_add((parent::set_prop($v)), 1);", "PHP super property writes should lower through parent setters");
		assertContains(content, "$s = (parent::get_fProp())(0);",
			"PHP calls through super property getter results should lower through parent getters before invocation");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpForKeyValue():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_for_key_value_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpForKeyValueProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "foreach ($values as $index => $value) {", "PHP key/value loops should lower through foreach key => value");
		assertContains(content, "echo __hxhx_add(__hxhx_add_string($index), __hxhx_add_string($value)) . PHP_EOL;",
			"PHP key/value loop bodies should render with both loop bindings in scope");
		deleteRecursive(tmpRoot);
	}

	static function assertPythonForKeyValue():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_for_key_value_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(pythonForKeyValueProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "def hxhx_key_value_iter(value):", "Python key/value loops should emit an iterator helper");
		assertContains(content, "for index, value in hxhx_key_value_iter(values):", "Python key/value loops over arrays should lower through the helper");
		assertContains(content, "lookup = {\"a\": 1, \"b\": 2}", "Python map literals should provide dict inputs for key/value loops");
		assertContains(content, "for key, item in hxhx_key_value_iter(lookup):", "Python key/value loops over map literals should lower through the helper");
		deleteRecursive(tmpRoot);
	}

	static function assertPythonTryCatchRawExpression():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_try_expr_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(pythonTryCatchRawExpressionProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "def hxhx_throw(value):", "Python try/catch expressions should emit the throw expression helper");
		assertContains(content, "def hxhx_try(try_fn, catch_fn):", "Python try/catch expressions should emit the expression helper");
		assertContains(content, "caught = hxhx_try(lambda: hxhx_throw(Exception(\"boom\")), lambda e: e)",
			"Python raw try/catch expressions should lower through lambda-based expression helpers");
		deleteRecursive(tmpRoot);
	}

	static function assertPythonTypeCheck():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_type_check_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(pythonTypeCheckProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "def hxhx_is_of_type(value, type_name):", "Python type checks should emit the Haxe type helper");
		assertContains(content, "print(str(hxhx_is_of_type(number, \"Int\")))", "Python Int type checks should lower through the helper");
		assertContains(content, "print(str(hxhx_is_of_type(text, \"String\")))", "Python String type checks should lower through the helper");
		deleteRecursive(tmpRoot);
	}

	static function assertHelperInstanceFieldEmission():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_helper_field_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(helperInstanceFieldProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class Helper:", "helper classes with instance fields should still be emitted");
		assertContains(content, "def __init__(self):", "helper constructors should lower to __init__");
		assertContains(content, "self.value = \"seed\"", "helper instance fields should initialize inside __init__");
		assertContains(content, "def message(self):", "helper instance methods should still be emitted");
		assertContains(content, "return self.value", "instance methods should be able to read lowered fields");
		assertContains(content, "helper = Helper()", "main should still instantiate helper classes");
		assertContains(content, "print(helper.message())", "main should still call helper instance methods");
		deleteRecursive(tmpRoot);
	}

	static function assertSuperEmission():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_super_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(superProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class Base:", "base helper classes should still emit normally");
		assertContains(content, "class Child(Base):", "child helper classes should preserve their extends clause");
		assertContains(content, "super().__init__(\"seed\")", "constructor super calls should lower through Python __init__ dispatch");
		assertContains(content, "return super().label()", "super method calls should lower through Python super()");
		assertContains(content, "child = Child()", "main should still instantiate subclasses");
		assertContains(content, "print(child.inheritedLabel())", "main should still call methods defined on subclasses");
		deleteRecursive(tmpRoot);
	}

	static function assertPythonSuperMethodReference():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_super_method_ref_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(pythonSuperMethodReferenceProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "super().__init__(self._handler)", "constructor super calls should bind same-class method references through self");
		assertNotContains(content, "super().__init__(_handler)", "constructor super calls should not emit unbound same-class method references");
		if (commandExists("python3")) {
			final run = commandOutput("python3", [outputPath]);
			assertTrue(run.code == 0, "generated Python same-class method references should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "bound", "generated Python should preserve bound same-class method references");
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPythonInheritedFieldReference():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_inherited_field_ref_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(pythonInheritedFieldReferenceProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "for i in range(self.pos, 3):", "Python inherited instance fields should rewrite through self in ranges");
		assertNotContains(content, "range(pos, 3)", "Python inherited instance fields should not emit unbound identifiers");
		if (commandExists("python3")) {
			final run = commandOutput("python3", [outputPath]);
			assertTrue(run.code == 0, "generated Python inherited field references should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "3", "generated Python should preserve inherited field references in range bounds");
		}
		deleteRecursive(tmpRoot);
	}

	static function assertArrayLiteral():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_array_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(arrayLiteralProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		assertContains(File.getContent(outputPath), "values = Array([1, 2])", "array literals should render through the Python Array shim");
		deleteRecursive(tmpRoot);
	}

	static function assertPythonMapLiteralWithLambda():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_map_lambda_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(mapLiteralWithLambdaProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "callbacks = {1: lambda value: (value + 1), 2: lambda value: (value + 2)}",
			"Python map literals with lambda values should render as dictionary entries");
		deleteRecursive(tmpRoot);
	}

	static function assertPythonMapRuntimeShim():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_map_runtime_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final pos = HxPos.unknown();
		final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [
			SVar("grid", "", ENew("Map", []), pos),
			SExpr(EBinop("=", EArrayAccess(EIdent("grid"), ENew("Point", [EInt(0), EInt(0)])), EString("a")), pos),
			SExpr(EBinop("=", EArrayAccess(EIdent("grid"), ENew("Point", [EInt(0), EInt(1)])), EString("b")), pos),
			SExpr(EBinop("=", EArrayAccess(EIdent("grid"), ENew("Point", [EInt(1), EInt(0)])), EString("c")), pos),
			SExpr(ECall(EField(EIdent("Sys"), "println"), [EArrayAccess(EIdent("grid"), ENew("Point", [EInt(1), EInt(0)]))]), pos),
			SVar("count", "", EInt(0), pos),
			SForKeyValue("point", "label", EIdent("grid"), SBlock([
				SIf(ECall(EField(EIdent("point"), "equals"), [ENew("Point", [EInt(0), EInt(1)])]),
					SExpr(ECall(EField(EIdent("Sys"), "println"), [EIdent("label")]), pos), null, pos),
				SExpr(EBinop("+=", EIdent("count"), EInt(1)), pos)
			], pos), pos),
			SExpr(ECall(EField(EIdent("Sys"), "println"), [ECall(EField(EIdent("Std"), "string"), [EIdent("count")])]), pos)
		], "");
		final mainClass = new HxClassDecl("Main", true, [mainFn]);
		final mainDecl = new HxModuleDecl("", [], mainClass, [mainClass], false, false);
		final pointCtor = new HxFunctionDecl("new", HxVisibility.Public, false, [
			new HxFunctionArg("x", "Int", NoDefault),
			new HxFunctionArg("y", "Int", NoDefault)
		], "Void", [
			SExpr(EBinop("=", EField(EThis, "x"), EIdent("x")), pos),
			SExpr(EBinop("=", EField(EThis, "y"), EIdent("y")), pos)
		], "");
		final equalsFn = new HxFunctionDecl("equals", HxVisibility.Public, false, [new HxFunctionArg("point", "Point", NoDefault)], "Bool", [
			SReturn(EBinop("&&", EBinop("==", EField(EThis, "x"), EField(EIdent("point"), "x")),
				EBinop("==", EField(EThis, "y"), EField(EIdent("point"), "y"))),
				pos)
		], "");
		final hashCodeFn = new HxFunctionDecl("hashCode", HxVisibility.Public, false, [], "Int", [
			SReturn(EBinop("+", EField(EThis, "x"), EBinop("*", EInt(10000), EField(EThis, "y"))), pos)
		], "");
		final pointClass = new HxClassDecl("Point", false, [pointCtor, equalsFn, hashCodeFn], [
			new HxFieldDecl("x", HxVisibility.Public, false, "Int", null),
			new HxFieldDecl("y", HxVisibility.Public, false, "Int", null)
		]);
		final pointDecl = new HxModuleDecl("", [], pointClass, [pointClass], false, false);
		final program = MacroStage.expandProgram([
			typedSyntheticModule("Main.hx", mainDecl),
			typedSyntheticModule("Point.hx", pointDecl)
		], []);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class Map:", "Python source backend should emit a minimal Map runtime helper");
		assertContains(content, "def __hx_key_equals(self, left, right):", "Python Map helper should compare object keys with equals when available");
		assertContains(content, "grid = Map()", "Python Map construction should lower to the runtime shim");
		assertContains(content, "grid[Point(0, 0)] = \"a\"", "Python Map bracket writes should dispatch through __setitem__");
		assertContains(content, "print(grid[Point(1, 0)])", "Python Map bracket reads should dispatch through index access");
		assertContains(content, "for point, label in hxhx_key_value_iter(grid):", "Python Map key/value loops should use the runtime items iterator");
		if (commandExists("python3")) {
			final run = commandOutput("python3", [outputPath]);
			assertTrue(run.code == 0, "generated Python Map runtime should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "c\nb\n3", "generated Python should read object keys and iterate all Map entries");
		}
		deleteRecursive(tmpRoot);
	}

	static function assertConstructorExpression():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_constructor_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(constructorProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		assertContains(File.getContent(outputPath), "EReg(\"a\", \"\")", "constructor expressions should render calls");
		deleteRecursive(tmpRoot);
	}

	static function assertForInStatement():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_for_in_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(forInProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "for value in Array([1, 2]):", "for-in statements should render iterable loops");
		assertContains(content, "    print(str(value))", "for-in bodies should render with nested indentation");
		deleteRecursive(tmpRoot);
	}

	static function assertBinaryOperators():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_binop_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(binopProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "total = (1 + 2)", "binary plus should render in initializers");
		assertContains(content, "total = (total - 1)", "assignment statements should render binary RHS expressions");
		assertContains(content, "print(str((total == 2)))", "comparison operators should render inside calls");
		deleteRecursive(tmpRoot);
	}

	static function assertEnumValue():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_enum_value_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(enumValueProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		assertContains(File.getContent(outputPath), "print(str(\"Macro\"))", "enum-like values should render as stable string tags");
		deleteRecursive(tmpRoot);
	}

	static function assertLambdaExpression():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_lambda_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(lambdaProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "inc = lambda value: (value + 1)", "lambda expressions should render in variable initializers");
		assertContains(content, "print(str(inc(1)))", "lambda values should render as callable identifiers");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpLambdaImmediateCallExpression():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_lambda_call_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(lambdaImmediateCallProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "$value = (function($input) { return $input; })(1);", "PHP immediate lambda calls should wrap the closure before invocation");
		assertContains(content, "echo __hxhx_add_string($value) . PHP_EOL;", "PHP immediate lambda-call results should still flow through later statements");
		deleteRecursive(tmpRoot);
	}

	static function assertSwitchExpression():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_switch_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(switchExpressionProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "label = (\"Python\" if", "switch expressions should render literal branch values");
		assertContains(content, "or ((\"python\" == \"py\"))", "switch expressions should render or-pattern conditions");
		assertContains(content, "print(str(label))", "switch expression results should render as normal values");
		deleteRecursive(tmpRoot);
	}

	static function assertUnsupportedSwitchGuardExpression():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_guarded_switch_expr_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(guardedSwitchExpressionProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "&& false", "unsupported switch guards should preserve the inner match and disable the branch");
		assertContains(content, "$label = (", "guarded switch expressions should still lower to PHP conditional expressions");
		deleteRecursive(tmpRoot);
	}

	static function assertSwitchStatement():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_switch_stmt_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(switchStatementProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "__hxhx_switch = \"python\"", "switch statements should evaluate the scrutinee once");
		assertContains(content, "if (__hxhx_switch == \"python\"):", "switch statements should lower the first pattern as an if");
		assertContains(content, "print(\"py\")", "switch statement branch bodies should render");
		assertContains(content, "elif True:", "wildcard switch branches should lower as an elif true catch-all");
		assertContains(content, "print(\"other\")", "later switch statement branches should still render");
		deleteRecursive(tmpRoot);
	}

	static function assertJavaArraySwitchStatement():Void {
		if (!commandExists("javac") || !commandExists("jar") || !commandExists("java"))
			return;
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_java_array_switch_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final outputDir = Path.join([tmpRoot, "bin", "java", "Main-Debug"]);
		final backend = BackendRegistry.requireForTarget("java-native");
		final result = backend.emit(javaArraySwitchStatementProgram(), new BackendContext(outputDir, null, "Main", true, true, new StringMap<String>()));
		final sourcePath = Path.join([outputDir, "src", "Main.java"]);
		final content = File.getContent(sourcePath);
		assertContains(content, "main(String[] __hxhx_cli_args)", "Java entrypoint args should use an internal name so Haxe locals named args still compile");
		assertContains(content, "if (args != null && args.length == 1", "Java array switch statements should lower array length guards");
		assertContains(content, "java.util.Objects.equals(args[0], \"ping\")", "Java array switch statements should use value equality for string items");
		assertContains(content, "Std.parseInt(args[1])", "Java array switch extractor patterns should lower Std.parseInt");
		final run = commandOutput("java", ["-jar", result.entryPath]);
		assertTrue(run.code == 0, "Java array switch jar should run: " + run.stderr);
		assertContains(run.stdout, "other", "Java array switch wildcard branch should execute");
		deleteRecursive(tmpRoot);
	}

	static function assertJavaUtilityProcessCompileShim():Void {
		if (!commandExists("javac") || !commandExists("jar"))
			return;
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_java_utility_process_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final outputDir = Path.join([tmpRoot, "bin", "java", "UtilityProcess-Debug"]);
		final backend = BackendRegistry.requireForTarget("java-native");
		final result = backend.emit(javaUtilityProcessCompileShimProgram(),
			new BackendContext(outputDir, null, "UtilityProcess", true, true, new StringMap<String>()));
		final sourcePath = Path.join([outputDir, "src", "UtilityProcess.java"]);
		final content = File.getContent(sourcePath);
		assertContains(content, "hxhx Java sys compile shim", "Java UtilityProcess entrypoint should use the compile-only shim");
		assertTrue(FileSystem.exists(result.entryPath), "Java UtilityProcess compile shim should still package a jar");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpTypeCheck():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_type_check_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpTypeCheckProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "__hxhx_add_string(is_int($i))", "PHP `is Int` checks should lower to is_int");
		assertContains(content, "__hxhx_add_string(is_string($s))", "PHP `is String` checks should lower to is_string");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpShiftAssignment():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_shift_assignment_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpShiftAssignmentProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "$a <<= 2;", "PHP signed left-shift assignment should render directly");
		assertContains(content, "$a >>= 1;", "PHP signed right-shift assignment should render directly");
		assertContains(content, "$a = __hxhx_ushr($a, 1);", "PHP unsigned right-shift assignment should reuse the unsigned-shift helper");
		deleteRecursive(tmpRoot);
	}

	static function assertPythonShiftAssignment():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_shift_assignment_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(phpShiftAssignmentProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "a <<= 2", "Python signed left-shift assignment should render directly");
		assertContains(content, "a >>= 1", "Python signed right-shift assignment should render directly");
		assertContains(content, "a = hxhx_ushr(a, 1)", "Python unsigned right-shift assignment should reuse the unsigned-shift helper");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpNullCoalescing():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_null_coalescing_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpNullCoalescingProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "$got = ($value ?? $fallback);", "PHP null coalescing should lower to the native ?? operator");
		assertContains(content, "$value ??= 3;", "PHP null coalescing assignment should lower to native ??=");
		deleteRecursive(tmpRoot);
	}

	static function assertPythonNullCoalescing():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_null_coalescing_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(phpNullCoalescingProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "got = (value if value is not None else fallback)", "Python null coalescing should lower to a None check expression");
		assertContains(content, "value = (value if value is not None else 3)", "Python null coalescing assignment should lower to assignment with None check");
		deleteRecursive(tmpRoot);
	}

	static function assertPythonNullCoalescingAssignmentExpression():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_null_coalescing_assign_expr_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final src = [
			"class Main {",
			"  static function eq(left:Int, right:Int):Void {}",
			"  static function main() {",
			"    var a:Null<Int> = null;",
			"    eq(a ??= 5, 5);",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		final program = MacroStage.expandProgram([typed], []);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "eq((a := (a if a is not None else 5)), 5)",
			"Python null-coalescing assignment expressions should lower to parseable value-returning expressions");
		assertNotContains(content, "eq(a = (a if a is not None else 5), 5)", "Python should not emit assignment syntax inside call arguments");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpCompileTimeOnlyMacroSupportSkipped():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_compile_time_macro_skip_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpCompileTimeOnlyMacroSupportProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertNotContains(content, "class TestIssues", "PHP support emission should skip compile-time-only macro helper classes");
		assertContains(content, "/* hxhx skipped TestIssues.addIssueClasses */ null;",
			"PHP compile-time-only TestIssues.addIssueClasses should not become a runtime class call");
		assertContains(content, "echo \"ok\" . PHP_EOL;", "PHP main output should still emit when compile-time-only helpers are skipped");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpUnitLocalStaticFallback():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_unit_local_static_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpUnitLocalStaticProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "public static $__basic_x = null;", "PHP TestLocalStatic fallback should declare persisted local-static storage");
		assertContains(content, "if (self::$__basic_x === null) self::$__basic_x = 1;",
			"PHP TestLocalStatic fallback should initialize persisted local-static storage once");
		assertContains(content, "return (object)[\"x\" => self::$__basic_x, \"y\" => \"final\"];",
			"PHP TestLocalStatic fallback should return the expected object shape");
		deleteRecursive(tmpRoot);
	}

	static function assertPythonUnitLocalStaticFallback():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_unit_local_static_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(phpUnitLocalStaticProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "    __basic_x = None", "Python TestLocalStatic fallback should declare persisted local-static storage");
		assertContains(content, "        if TestLocalStatic.__basic_x is None:", "Python TestLocalStatic fallback should initialize storage once");
		assertContains(content, "        return hxhx_anon(x=TestLocalStatic.__basic_x, y=\"final\")",
			"Python TestLocalStatic fallback should return the expected object shape");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpUnitMapComprehensionFallback():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_unit_map_comprehension_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpUnitMapComprehensionProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "$__hx_assert_map = function", "PHP TestMapComprehension fallback should emit a local assertion helper");
		assertContains(content, "for ($i = 0; $i < 2; $i++) $__hx_map0[$i] = $i;",
			"PHP TestMapComprehension fallback should build the basic map-comprehension result");
		assertContains(content, "$__hx_assert_map($__hx_map2, [1 => 1], \"map-entry-filter\");",
			"PHP TestMapComprehension fallback should validate the guarded map-comprehension result");
		deleteRecursive(tmpRoot);
	}

	static function assertPythonUnitMapComprehensionFallback():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_unit_map_comprehension_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(phpUnitMapComprehensionProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "        def __hx_assert_map(__hx_map, __hx_expected, __hx_label):",
			"Python TestMapComprehension fallback should emit a local assertion helper");
		assertContains(content, "        for i in range(0, 2):", "Python TestMapComprehension fallback should build the basic map-comprehension result");
		assertContains(content, "        __hx_assert_map(map2, {1: 1}, \"map-entry-filter\")",
			"Python TestMapComprehension fallback should validate the guarded map-comprehension result");
		deleteRecursive(tmpRoot);
	}

	static function assertPythonDoWhileExpressionFallback():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_do_while_expr_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(pythonDoWhileExpressionProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "        def z():", "Python do-while expression fallback should emit a closure");
		assertContains(content, "        nonlocal_x = {\"value\": 1}", "Python do-while expression fallback should model captured mutation");
		assertContains(content, "            if not (nonlocal_x[\"value\"] < 3):",
			"Python do-while expression fallback should check the loop condition after the body");
		deleteRecursive(tmpRoot);
	}

	static function assertPythonPlainTextReportSetHandlerFallback():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_plain_text_report_set_handler_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(pythonPlainTextReportSetHandlerProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class PlainTextReport:", "Python utest helper support class should be emitted");
		assertContains(content, "    def setHandler(self, handler):", "Python utest setHandler helper should be emitted");
		assertContains(content, "        self.handler = handler", "Python utest setHandler fallback should preserve handler assignment");
		assertNotContains(content, "EUnsupported", "Python utest setHandler fallback should not leak unsupported assignment placeholders");
		deleteRecursive(tmpRoot);
	}

	static function assertPythonReservedMethodNameSanitized():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_reserved_method_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final pos = HxPos.unknown();
		final messageArg = new HxFunctionArg("message", "String", HxDefaultValue.NoDefault);
		final posArg = new HxFunctionArg("pos", "Dynamic", HxDefaultValue.NoDefault);
		final assertFn = new HxFunctionDecl("assert", HxVisibility.Public, false, [messageArg, posArg], "Void", [SReturn(ENull, pos)], "");
		final reporterClass = new HxClassDecl("Reporter", false, [assertFn]);
		final reporterDecl = new HxModuleDecl("", [], reporterClass, [reporterClass], false, false);
		final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [
			SVar("reporter", "", ENew("Reporter", []), pos),
			SExpr(ECall(EField(EIdent("reporter"), "assert"), [EString("ok"), ENull]), pos)
		], "");
		final mainClass = new HxClassDecl("Main", true, [mainFn]);
		final mainDecl = new HxModuleDecl("", [], mainClass, [mainClass], false, false);
		final program = MacroStage.expandProgram([
			typedSyntheticModule("Main.hx", mainDecl),
			typedSyntheticModule("Reporter.hx", reporterDecl)
		], []);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "    def assert_(self, message, pos):", "Python reserved method definitions should be sanitized");
		assertContains(content, "reporter.assert_(\"ok\", None)", "Python reserved method calls should use the sanitized method name");
		assertNotContains(content, "def assert(self", "Python should not emit reserved method definitions");
		assertNotContains(content, "reporter.assert(", "Python should not emit reserved method calls");
		deleteRecursive(tmpRoot);
	}

	static function assertPythonReservedLocalNameSanitized():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_reserved_local_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final pos = HxPos.unknown();
		final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [
			SVar("from", "", ELambda(["tpl"], EIdent("tpl")), pos),
			SExpr(ECall(EField(EIdent("Sys"), "println"), [ECall(EIdent("from"), [EString("works")])]), pos)
		], "");
		final mainClass = new HxClassDecl("Main", true, [mainFn]);
		final mainDecl = new HxModuleDecl("", [], mainClass, [mainClass], false, false);
		final program = MacroStage.expandProgram([typedSyntheticModule("Main.hx", mainDecl)], []);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "from_ = lambda tpl: tpl", "Python reserved local variable declarations should be sanitized");
		assertContains(content, "print(from_(\"works\"))", "Python reserved local references should use the sanitized name");
		assertNotContains(content, "from = lambda", "Python should not emit reserved local declarations");
		deleteRecursive(tmpRoot);
	}

	static function assertPythonLambdaUpdateExpressionSyntax():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_lambda_update_expr_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final pos = HxPos.unknown();
		final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [
			SVar("s", "", EString("a"), pos),
			SVar("update", "", ELambda([], EBinop("+=", EIdent("s"), EString("b"))), pos),
			SExpr(ECall(EField(EIdent("Sys"), "println"), [ECall(EIdent("update"), [])]), pos)
		], "");
		final mainClass = new HxClassDecl("Main", true, [mainFn]);
		final mainDecl = new HxModuleDecl("", [], mainClass, [mainClass], false, false);
		final program = MacroStage.expandProgram([typedSyntheticModule("Main.hx", mainDecl)], []);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "update = lambda : (s := (s + \"b\"))", "Python lambda update expressions should lower to parseable named expressions");
		assertNotContains(content, "s += \"b\"", "Python should not emit augmented assignment syntax inside lambda expressions");
		deleteRecursive(tmpRoot);
	}

	static function assertPythonArrayUpdateExpressionSyntax():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_array_update_expr_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final pos = HxPos.unknown();
		final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [
			SVar("arr", "", EArrayDecl([EInt(4), EInt(5)]), pos),
			SExpr(ECall(EField(EIdent("Sys"), "println"), [EBinop("+=", EArrayAccess(EIdent("arr"), EInt(0)), EInt(3))]), pos)
		], "");
		final mainClass = new HxClassDecl("Main", true, [mainFn]);
		final mainDecl = new HxModuleDecl("", [], mainClass, [mainClass], false, false);
		final program = MacroStage.expandProgram([typedSyntheticModule("Main.hx", mainDecl)], []);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "def hxhx_update_index(obj, index, op, value):", "Python runtime should include expression-position index update helper");
		assertContains(content, "print(hxhx_update_index(arr, 0, \"+\", 3))", "Python array update expressions should lower to parseable helper calls");
		assertNotContains(content, "print(arr[0] += 3)", "Python should not emit augmented assignment syntax inside calls");
		deleteRecursive(tmpRoot);
	}

	static function assertPythonThisUpdateReturnExpressionSyntax():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_this_update_return_expr_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final pos = HxPos.unknown();
		final nextFn = new HxFunctionDecl("next", HxVisibility.Public, false, [], "Int", [SReturn(EBinop("+=", EThis, EInt(1)), pos)], "");
		final boxClass = new HxClassDecl("Box", false, [nextFn]);
		final boxDecl = new HxModuleDecl("", [], boxClass, [boxClass], false, false);
		final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [
			SVar("box", "", ENew("Box", []), pos),
			SExpr(ECall(EField(EIdent("Sys"), "println"), [ECall(EField(EIdent("box"), "next"), [])]), pos)
		], "");
		final mainClass = new HxClassDecl("Main", true, [mainFn]);
		final mainDecl = new HxModuleDecl("", [], mainClass, [mainClass], false, false);
		final program = MacroStage.expandProgram([
			typedSyntheticModule("Main.hx", mainDecl),
			typedSyntheticModule("Box.hx", boxDecl)
		], []);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "def hxhx_assign_attr(obj, field, value):", "Python runtime should include expression-position attr assignment helper");
		assertContains(content, "return hxhx_assign_attr(self, \"__hx_value\", (self.__hx_value + 1))",
			"Python this-value update return expressions should lower to parseable helper calls");
		assertNotContains(content, "return self.__hx_value += 1", "Python should not emit augmented assignment syntax in return expressions");
		deleteRecursive(tmpRoot);
	}

	static function assertPythonSwitchExpressionGuardSyntax():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_switch_guard_expr_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final pos = HxPos.unknown();
		final switchExpr = HxExpr.ESwitch(EIdent("items"), [
			HxSwitchPattern.PLengthGuard(HxSwitchPattern.PBind("matched"), "matched", 3),
			HxSwitchPattern.PBind("fallback")
		], [EString("three"), EString("other")]);
		final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [
			SVar("items", "", EArrayDecl([EString("a"), EString("b"), EString("c")]), pos),
			SVar("label", "", switchExpr, pos),
			SExpr(ECall(EField(EIdent("Sys"), "println"), [EIdent("label")]), pos)
		], "");
		final mainClass = new HxClassDecl("Main", true, [mainFn]);
		final mainDecl = new HxModuleDecl("", [], mainClass, [mainClass], false, false);
		final program = MacroStage.expandProgram([typedSyntheticModule("Main.hx", mainDecl)], []);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "and (len(items) == 3)", "Python switch guard expressions should use Python conjunction syntax");
		assertNotContains(content, "&&", "Python switch guard expressions should not emit C-style conjunctions");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpObjectPatternSwitchExpression():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_object_switch_expr_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpObjectPatternSwitchExpressionProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "(function() use ($e) {", "PHP switch expressions should capture local scrutinees used inside closures");
		assertContains(content, "$__hxhx_switch = $e;", "PHP switch expressions should evaluate the scrutinee once inside a closure");
		assertContains(content, "property_exists($__hxhx_switch, \"expr\")", "PHP object switch patterns should check object field existence");
		assertContains(content, "$const = $__hxhx_switch->expr;", "PHP object switch captures should bind the matched field value");
		assertContains(content, "return $const;", "PHP switch expression branches should return captured values");
		deleteRecursive(tmpRoot);
	}

	static function assertPythonObjectPatternSwitchExpression():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_object_switch_expr_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(phpObjectPatternSwitchExpressionProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "hasattr(e, \"expr\")", "Python object switch expressions should check object field existence");
		assertContains(content, "got = (e.expr if", "Python object switch expression captures should lower to the matched field value");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpUnitMatchExtractorFallback():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_unit_match_extractor_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpUnitMatchExtractorProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "$__hx_f = function($__hx_i) {", "PHP TestMatch extractor fallback should emit a local extractor check");
		assertContains(content, "if (($__hx_i & 1) === 0) return 2;", "PHP TestMatch extractor fallback should preserve even-extractor behavior");
		assertContains(content, "throw new \\Exception(\"extractor mismatch: \" . strval($__hx_input));",
			"PHP TestMatch extractor fallback should fail if observable extractor results drift");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpSwitchStatement():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_switch_stmt_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(switchStatementProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "$__hxhx_switch = \"python\";", "PHP switch statements should evaluate the scrutinee once");
		assertContains(content, "if (($__hxhx_switch == \"python\")) {", "PHP switch statements should lower the first case to if");
		assertContains(content, "} elseif (true) {", "PHP wildcard switch branches should lower to elseif true");
		assertContains(content, "echo \"other\" . PHP_EOL;", "PHP switch statement branch bodies should render");
		deleteRecursive(tmpRoot);
	}

	static function main():Void {
		emit("python-native", "python", "Main.py", "print((\"source-native:\" + \"python\"))");
		emit("java-native", "java", "Main.java", "System.out.println((\"source-native:\" + \"java\"));");
		emit("cs-native", "cs", "Main.cs", "System.Console.WriteLine((\"source-native:\" + \"cs\"));");
		emit("php-native", "php", "index.php", "echo __hxhx_add(\"source-native:\", \"php\") . PHP_EOL;");
		emit("lua-native", "lua", "Main.lua", "print((\"source-native:\" .. \"lua\"))");
		assertPythonOutputHint();
		assertJavaJarPackaging();
		assertJavaLambdaSequenceCallback();
		assertJavaSupportClassJarPackaging();
		assertJavaLibraryEnumJarPackaging();
		assertJavaOperationInterfaceRuntime();
		assertUnsupportedDiagnostic();
		assertWhileStatement();
		assertIfStatement();
		assertGenericCallStatement();
		assertTraceStatement();
		assertJavaTraceRuntimePrefix();
		assertJavaLambdaTraceSourcePrefix();
		assertUnaryOperators();
		assertPostfixStatements();
		assertTernaryExpression();
		assertTryCatchStatement();
		assertArrayAccessExpression();
		assertArrayComprehensionExpression();
		assertGuardedArrayComprehensionExpression();
		assertAnonymousObjectExpression();
		assertPythonAnonymousObjectReservedFieldSyntax();
		assertPythonClassBodyHelperNamesAvoidMangling();
		assertPhpAnonymousObjectExpression();
		assertLoopControlStatements();
		assertPostfixExpressions();
		assertPhpPostfixExpressions();
		assertUnsignedRightShiftExpression();
		assertHelperClassEmission();
		assertPhpStaticClassAccess();
		assertPhpRuntimeShim();
		assertPhpMapRuntimeShim();
		assertPhpSamePackageQualifiedStaticPath();
		assertPhpInstanceFieldMethodCall();
		assertPhpInheritedTestHelperCall();
		assertPhpShadowedTestHelperClosure();
		assertNativeProtocolOptionalArgDecode();
		assertNativeProtocolDefaultArgSourceDecode();
		assertPhpPlusSemantics();
		assertPhpEnumString();
		assertPhpBitwisePrecedence();
		assertPhpSameClassStaticHelperCall();
		assertPhpBitwiseEqualityPrecedence();
		assertPhpModuloMultiplicationPrecedence();
		assertPhpFloatModulo();
		assertPhpMathRuntime();
		assertPhpTernaryAssignmentLogical();
		assertPhpStringIndexOf();
		assertPhpStringFromCharCode();
		assertPhpWebShim();
		assertPhpMacroExpr();
		assertPythonMacroExpr();
		assertPhpDollarString();
		assertPhpInt64LiteralExtension();
		assertPythonNumericLiteralFieldCallSyntax();
		assertPhpArrayConstructor();
		assertPhpArrayOperations();
		assertPhpReservedTypeName();
		assertPhpDuplicateStaticFieldEmission();
		assertPhpDuplicateMethodEmission();
		assertPhpReservedValueName();
		assertPhpNonConstantStaticFieldDefault();
		assertPhpArrayPostfixStatement();
		assertPhpCrossPackageSupportClassEmission();
		assertPhpMacroType();
		assertPythonMacroType();
		assertPhpTryCatchExpression();
		assertPhpTypeErrorProbe();
		assertPhpTypeErrorBlockProbe();
		assertPhpFollowWithAbstractsProbe();
		assertPhpArrayComprehensionClosure();
		assertPhpAbstractThisPostfix();
		assertPythonAbstractThisPostfix();
		assertPhpSuperConstructor();
		assertPhpSuperProperty();
		assertPhpForKeyValue();
		assertPythonForKeyValue();
		assertPythonTryCatchRawExpression();
		assertPythonTypeCheck();
		assertPhpTypeCheck();
		assertPhpShiftAssignment();
		assertPythonShiftAssignment();
		assertPhpNullCoalescing();
		assertPythonNullCoalescing();
		assertPythonNullCoalescingAssignmentExpression();
		assertPhpCompileTimeOnlyMacroSupportSkipped();
		assertPhpUnitLocalStaticFallback();
		assertPythonUnitLocalStaticFallback();
		assertPhpUnitMapComprehensionFallback();
		assertPythonUnitMapComprehensionFallback();
		assertPythonDoWhileExpressionFallback();
		assertPythonPlainTextReportSetHandlerFallback();
		assertPythonReservedMethodNameSanitized();
		assertPythonReservedLocalNameSanitized();
		assertPythonLambdaUpdateExpressionSyntax();
		assertPythonArrayUpdateExpressionSyntax();
		assertPythonThisUpdateReturnExpressionSyntax();
		assertPythonSwitchExpressionGuardSyntax();
		assertPhpObjectPatternSwitchExpression();
		assertPythonObjectPatternSwitchExpression();
		assertPhpUnitMatchExtractorFallback();
		assertPhpHelperInstanceFieldEmission();
		assertHelperInstanceFieldEmission();
		assertSuperEmission();
		assertPythonSuperMethodReference();
		assertPythonInheritedFieldReference();
		assertCrossModuleClassEmission();
		assertPythonSkipsStdSupportClasses();
		assertPythonSkipsMacroSupportMethods();
		assertPythonStaticInitializersAfterSupportClasses();
		assertPythonStdDateToolsSupport();
		assertPythonPackageQualifiedSupportClassReference();
		assertPythonStdStringMapNamespaceReference();
		assertPythonTypeNameHelpersForStaticInitializers();
		assertPythonUnitBuilderMacroNamespaceFallback();
		assertPythonTestIssuesMacroFallback();
		assertPythonArrayRuntimeShim();
		assertPythonListRuntimeShim();
		assertPythonMacroCompilerStdFallback();
		assertPythonOptionalMethodArguments();
		assertPythonSameClassInstanceMethodCall();
		assertPythonSameClassInstanceFieldRead();
		assertPythonReflectSupport();
		assertPythonTypeSupport();
		assertPythonStringToolsSupport();
		assertPythonMetaSupport();
		assertPythonValueExceptionBaseSupport();
		assertArrayLiteral();
		assertPythonMapLiteralWithLambda();
		assertPythonMapRuntimeShim();
		assertConstructorExpression();
		assertForInStatement();
		assertBinaryOperators();
		assertEnumValue();
		assertLambdaExpression();
		assertPhpLambdaImmediateCallExpression();
		assertSwitchExpression();
		assertUnsupportedSwitchGuardExpression();
		assertSwitchStatement();
		assertJavaArraySwitchStatement();
		assertJavaUtilityProcessCompileShim();
		assertPhpSwitchStatement();
	}
}
