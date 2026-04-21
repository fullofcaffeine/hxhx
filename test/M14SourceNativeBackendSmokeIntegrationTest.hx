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
			"import haxe.ds.List;",
			"import haxe.io.Bytes;",
			"import utest.ui.common.IReport;",
			"import MyClass.UsingBase;",
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
			"class Main {",
			"  static function main() {",
			"    var helper = new Helper();",
			"    Sys.println(Std.string(helper.label()));",
			"    helper.assert(\"ok\");",
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
		final run = commandOutput("java", ["-jar", jarPath]);
		assertTrue(run.code == 0, "Java source backend jar should run: " + run.stderr);
		assertContains(run.stdout, "source-native:java", "Java source backend jar should execute generated main");
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
		assertContains(content, "success = false;", "Java lambda-body switch side effects should lower to statements");
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
		final listStubPath = Path.join([outputDir, "src", "haxe", "ds", "List.java"]);
		final bytesStubPath = Path.join([outputDir, "src", "haxe", "io", "Bytes.java"]);
		final reportStubPath = Path.join([outputDir, "src", "utest", "ui", "common", "IReport.java"]);
		final moduleLocalStubPath = Path.join([outputDir, "src", "MyClass", "UsingBase.java"]);
		final jarPath = outputDir + ".jar";
		assertTrue(result.entryPath == jarPath, "Java source backend should still report the packaged jar for support-class programs");
		assertTrue(FileSystem.exists(mainSourcePath), "Java source backend should emit the main Java source file");
		assertTrue(FileSystem.exists(helperSourcePath), "Java source backend should emit sibling support classes before javac");
		assertTrue(FileSystem.exists(objectShapeSourcePath), "Java source backend should emit sibling classes with Object override-shaped methods");
		assertTrue(FileSystem.exists(listStubPath), "Java source backend should synthesize stubs for imported Haxe package classes");
		assertTrue(FileSystem.exists(bytesStubPath), "Java source backend should synthesize stubs for imported Haxe package classes beyond haxe.ds");
		assertTrue(FileSystem.exists(reportStubPath), "Java source backend should synthesize stubs for imported interface-like package classes");
		assertTrue(FileSystem.exists(moduleLocalStubPath), "Java source backend should synthesize stubs for module-local dotted imports");
		assertTrue(FileSystem.exists(jarPath), "Java source backend should package a jar after compiling support classes");
		final mainContent = File.getContent(mainSourcePath);
		final helperContent = File.getContent(helperSourcePath);
		final objectShapeContent = File.getContent(objectShapeSourcePath);
		final reportContent = File.getContent(reportStubPath);
		assertContains(helperContent, "public class Helper", "Java support source should declare the sibling class");
		assertContains(helperContent, "assert_", "Java support source should sanitize reserved method names");
		assertContains(helperContent, "Object native_", "Java support source should sanitize reserved argument names");
		assertContains(helperContent, "Object __", "Java support source should sanitize underscore-only argument names");
		assertContains(reportContent, "public interface IReport", "Java import stubs should model interface-like names as interfaces");
		assertContains(objectShapeContent, "public String toString()", "Java support source should preserve Object-compatible toString signatures");
		assertContains(objectShapeContent, "public int hashCode()", "Java support source should preserve Object-compatible hashCode signatures");
		assertContains(objectShapeContent, "public boolean equals(Object other)", "Java support source should preserve Object-compatible equals signatures");
		assertContains(objectShapeContent, "public Object wide(Object... args)", "Java support methods should include varargs fallback overloads");
		assertContains(mainContent, "helper.assert_(\"ok\")", "Java main source should call sanitized support method names");
		assertNotContains(mainContent, "import Map;", "Java main source should not import default-package classes");
		assertNotContains(helperContent, "import Type;", "Java support source should not import default-package classes");
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
		assertContains(content, "values = [1, 2]", "array access smoke should still render array literals");
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
		assertContains(content, "values = [1, 2]", "array comprehension smoke should still render the iterable source");
		assertContains(content, "doubled = [(value * 2) for value in values]", "array comprehensions should lower to Python list comprehensions");
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
		assertContains(content, "kept = [value for value in values if keep(value)]",
			"guarded array comprehensions should lower to Python list comprehensions with trailing if");
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
		assertContains(content, "def __hxhx_anon(**kwargs):", "Python source backend should emit the anonymous-object helper");
		assertContains(content, "info = __hxhx_anon(label=\"ok\", count=1)", "anonymous object literals should lower through the helper");
		assertContains(content, "print(info.label)", "anonymous object field access should keep using attribute syntax");
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
		assertContains(content, "def __hxhx_post_update_attr(obj, field, delta):", "Python source backend should emit the postfix attribute helper");
		assertContains(content, "def __hxhx_post_update_index(obj, index, delta):", "Python source backend should emit the postfix index helper");
		assertContains(content, "oldX = ((__hxhx_post_old := x), (x := (__hxhx_post_old + 1)), __hxhx_post_old)[2]",
			"identifier postfix expressions should preserve old-value semantics");
		assertContains(content, "oldCount = __hxhx_post_update_attr(info, \"count\", 1)",
			"field postfix expressions should lower through the attribute helper");
		assertContains(content, "oldFirst = __hxhx_post_update_index(values, 0, 1)", "indexed postfix expressions should lower through the index helper");
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
		assertContains(content, "def __hxhx_ushr(value, bits):", "Python source backend should emit the unsigned-right-shift helper");
		assertContains(content, "shifted = __hxhx_ushr((-1), 1)", "unsigned right shift should lower through the helper");
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

	static function assertArrayLiteral():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_array_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(arrayLiteralProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		assertContains(File.getContent(outputPath), "values = [1, 2]", "array literals should render in variable initializers");
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
		assertContains(content, "for value in [1, 2]:", "for-in statements should render iterable loops");
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
		assertContains(content, "if (\"python\" == \"python\"):", "switch statements should lower the first pattern as an if");
		assertContains(content, "print(\"py\")", "switch statement branch bodies should render");
		assertContains(content, "elif True:", "wildcard switch branches should lower as an elif true catch-all");
		assertContains(content, "print(\"other\")", "later switch statement branches should still render");
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
		assertUnsupportedDiagnostic();
		assertWhileStatement();
		assertIfStatement();
		assertGenericCallStatement();
		assertTraceStatement();
		assertUnaryOperators();
		assertPostfixStatements();
		assertTernaryExpression();
		assertTryCatchStatement();
		assertArrayAccessExpression();
		assertArrayComprehensionExpression();
		assertGuardedArrayComprehensionExpression();
		assertAnonymousObjectExpression();
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
		assertPhpDollarString();
		assertPhpInt64LiteralExtension();
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
		assertPhpTryCatchExpression();
		assertPhpTypeErrorProbe();
		assertPhpTypeErrorBlockProbe();
		assertPhpFollowWithAbstractsProbe();
		assertPhpArrayComprehensionClosure();
		assertPhpAbstractThisPostfix();
		assertPhpSuperConstructor();
		assertPhpSuperProperty();
		assertPhpForKeyValue();
		assertPhpTypeCheck();
		assertPhpShiftAssignment();
		assertPhpNullCoalescing();
		assertPhpCompileTimeOnlyMacroSupportSkipped();
		assertPhpUnitLocalStaticFallback();
		assertPhpUnitMapComprehensionFallback();
		assertPhpObjectPatternSwitchExpression();
		assertPhpUnitMatchExtractorFallback();
		assertPhpHelperInstanceFieldEmission();
		assertHelperInstanceFieldEmission();
		assertSuperEmission();
		assertCrossModuleClassEmission();
		assertArrayLiteral();
		assertConstructorExpression();
		assertForInStatement();
		assertBinaryOperators();
		assertEnumValue();
		assertLambdaExpression();
		assertPhpLambdaImmediateCallExpression();
		assertSwitchExpression();
		assertUnsupportedSwitchGuardExpression();
		assertSwitchStatement();
		assertPhpSwitchStatement();
	}
}
