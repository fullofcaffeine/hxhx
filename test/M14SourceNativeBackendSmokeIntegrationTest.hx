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

	static function commandOutputWithInput(command:String, args:Array<String>, input:String):{code:Int, stdout:String, stderr:String} {
		final process = new sys.io.Process(command, args);
		process.stdin.writeString(input);
		process.stdin.flush();
		process.stdin.close();
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

	static function phpSameClassStaticInlineCallProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static inline function foo(x) return x + 5;",
			"  static function main() {",
			"    var x = 3;",
			"    Sys.println(Std.string(2 * foo(x)));",
			"    Sys.println(Std.string(-foo(x)));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpStaticFunctionFieldCallProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static var add = function(x, y) return x + y;",
			"  static function main() {",
			"    Sys.println(Std.string(add(2, 3)));",
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
			"    var mapExpr = macro [1 => \"one\"];",
			"    Sys.println(Std.string(expr));",
			"    Sys.println(Std.string(mapExpr));",
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
			"    var e = 0xFFFFFFFFu32;",
			"    var f = (0xFFFFFFFF : UInt);",
			"    var g = 0xFFFFFFFFi32;",
			"    var h = 0xA0FFEEDD;",
			"    var i = cast(-1, UInt);",
			"    Sys.println(Std.string(a));",
			"    Sys.println(Std.string(b));",
			"    Sys.println(c);",
			"    Sys.println(d);",
			"    Sys.println(Std.string(e));",
			"    Sys.println(Std.string(f));",
			"    Sys.println(Std.string(g));",
			"    Sys.println(Std.string(h));",
			"    Sys.println(Std.string(i));",
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
			"    var base:Array<Int> = [1, 2, 3];",
			"    var mapped = base.map(v -> v * 2);",
			"    Sys.println(mapped.join(\",\"));",
			"    var m = new Map();",
			"    m.remove(\"a\");",
			"    var x = 0;",
			"    var records:Dynamic = [{ v: 3 }];",
			"    Sys.println(Std.string(records[x++].v++));",
			"    Sys.println(Std.string(x));",
			"    Sys.println(Std.string(records[0].v));",
			"    x = 0;",
			"    Sys.println(Std.string(records[x++].v += 3));",
			"    Sys.println(Std.string(x));",
			"    Sys.println(Std.string(records[0].v));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpSameClassArrayFieldMapProgram():GenIrProgram {
		final src = [
			"class Holder {",
			"  var callbacks:Array<Int->Int> = [];",
			"  public function new() {}",
			"  public function run() {",
			"    callbacks = [a -> a + a, b -> b * 3];",
			"    var values = callbacks.map(f -> f(2));",
			"    Sys.println(values.join(\",\"));",
			"  }",
			"}",
			"class Main {",
			"  static function main() {",
			"    new Holder().run();",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpObjectArrayAccessProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var record:Dynamic = { foo: 12, bar: \"test\" };",
			"    Sys.println(Std.string(record[\"foo\"]));",
			"    record[\"foo\"] = 11;",
			"    record[\"foo\"] += 99;",
			"    Sys.println(Std.string(record[\"foo\"]));",
			"    record[\"baz\"] = record[\"bar\"] += record[\"foo\"];",
			"    Sys.println(record[\"baz\"]);",
			"    Sys.println(record[\"bar\"]);",
			"    var key = \"hh\";",
			"    record[key] = 1;",
			"    record[key += \"h\"] = 2;",
			"    Sys.println(Std.string(record[\"hhh\"]));",
			"    Sys.println(key);",
			"    record[\"101\"] = function(x) return 9 + x;",
			"    Sys.println(Std.string(record[\"101\"](1)));",
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

	static function phpImportedHaxelibEnumSupportProgram():GenIrProgram {
		final mainSrc = [
			"package unit;",
			"import utest.ui.common.HeaderDisplayMode;",
			"class Main {",
			"  static function main() {",
			"    Sys.println(Std.string(HeaderDisplayMode.AlwaysShowHeader));",
			"    Sys.println(Std.string(SuccessResultsDisplayMode.NeverShowSuccessResults));",
			"  }",
			"}",
		].join("\n");
		final enumSrc = [
			"package utest.ui.common;",
			"enum HeaderDisplayMode {",
			"  AlwaysShowHeader;",
			"  NeverShowHeader;",
			"}",
			"enum SuccessResultsDisplayMode {",
			"  AlwaysShowSuccessResults;",
			"  NeverShowSuccessResults;",
			"}",
		].join("\n");
		final typedMain = TyperStage.typeModule(ParserStage.parse(mainSrc, "tests/unit/src/unit/Main.hx"));
		final typedEnum = TyperStage.typeModule(ParserStage.parse(enumSrc, "tests/.haxelib/utest/git/src/utest/ui/common/HeaderDisplayMode.hx"));
		return MacroStage.expandProgram([typedMain, typedEnum], []);
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

	static function phpExceptionCatchProgram():GenIrProgram {
		final src = [
			"import haxe.Exception;",
			"class Main {",
			"  static function main() {",
			"    try {",
			"      throw 123;",
			"    } catch (e:Exception) {",
			"      Sys.println(e.message);",
			"    }",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpCustomExceptionCatchProgram():GenIrProgram {
		final src = [
			"import haxe.Exception;",
			"class CustomHaxeException extends Exception { }",
			"class Main {",
			"  static function main() {",
			"    try {",
			"      throw new CustomHaxeException(\"boom\");",
			"    } catch (e:CustomHaxeException) {",
			"      Sys.println(e);",
			"    }",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpCustomExceptionValueExceptionGuardProgram():GenIrProgram {
		final src = [
			"import haxe.Exception;",
			"import haxe.ValueException;",
			"class CustomHaxeException extends Exception { }",
			"class Main {",
			"  static function main() {",
			"    try {",
			"      throw new CustomHaxeException(\"boom\");",
			"    } catch (e:ValueException) {",
			"      Sys.println(\"bad\");",
			"    } catch (e:Dynamic) {",
			"      Sys.println(\"ok\");",
			"    }",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpValueExceptionCatchProgram():GenIrProgram {
		final src = [
			"import haxe.ValueException;",
			"class Main {",
			"  static function main() {",
			"    try {",
			"      throw 123;",
			"    } catch (e:ValueException) {",
			"      Sys.println(e.value);",
			"    }",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpAbstractCatchProgram():GenIrProgram {
		final src = [
			"import haxe.Exception;",
			"private abstract AbstrString(String) from String { }",
			"private class CustomHaxeException extends Exception { }",
			"private abstract AbstrException(CustomHaxeException) from CustomHaxeException { }",
			"class Main {",
			"  static function main() {",
			"    try {",
			"      throw \"hello\";",
			"    } catch (e:AbstrString) {",
			"      Sys.println(e);",
			"    }",
			"    try {",
			"      throw new CustomHaxeException(\"boom\");",
			"    } catch (e:AbstrException) {",
			"      Sys.println(e);",
			"    }",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpEnumCatchProgram():GenIrProgram {
		final src = [
			"private enum EnumError {",
			"  EError;",
			"}",
			"class Main {",
			"  static function main() {",
			"    try {",
			"      throw EError;",
			"    } catch (e:EnumError) {",
			"      Sys.println(Std.string(e));",
			"      Sys.println(Type.enumEq(e, EError));",
			"    }",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final baseDecl = parsed.getDecl();
		final main = HxModuleDecl.getMainClass(baseDecl);
		final classes = [main].concat(ParserStageScanHelpers.scanModuleLocalHelperClasses(src, HxClassDecl.getName(main)))
			.concat(ParserStageScanHelpers.scanModuleLocalHelperEnums(src, HxClassDecl.getName(main)));
		final enriched = new HxModuleDecl(HxModuleDecl.getPackagePath(baseDecl), HxModuleDecl.getImports(baseDecl), main, classes,
			HxModuleDecl.getHeaderOnly(baseDecl), HxModuleDecl.getHasToplevelMain(baseDecl));
		final typed = TyperStage.typeModule(new ParsedModule(src, enriched, "Main.hx"));
		return MacroStage.expandProgram([typed], []);
	}

	static function phpCatchLocalShadowsEnumConstructorProgram():GenIrProgram {
		final src = [
			"private enum Expr {",
			"  e2;",
			"}",
			"private enum CatchError {",
			"  OutsideBounds;",
			"}",
			"class Main {",
			"  static function excv(f:Void->Void, e:Dynamic) {",
			"    try {",
			"      f();",
			"    } catch (e2:Dynamic) {",
			"      Sys.println(Std.string(e2));",
			"      Sys.println(Type.enumEq(e2, e));",
			"    }",
			"  }",
			"  static function main() {",
			"    excv(function() throw OutsideBounds, OutsideBounds);",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final baseDecl = parsed.getDecl();
		final main = HxModuleDecl.getMainClass(baseDecl);
		final classes = [main].concat(ParserStageScanHelpers.scanModuleLocalHelperClasses(src, HxClassDecl.getName(main)))
			.concat(ParserStageScanHelpers.scanModuleLocalHelperEnums(src, HxClassDecl.getName(main)));
		final enriched = new HxModuleDecl(HxModuleDecl.getPackagePath(baseDecl), HxModuleDecl.getImports(baseDecl), main, classes,
			HxModuleDecl.getHeaderOnly(baseDecl), HxModuleDecl.getHasToplevelMain(baseDecl));
		final typed = TyperStage.typeModule(new ParsedModule(src, enriched, "Main.hx"));
		return MacroStage.expandProgram([typed], []);
	}

	static function phpInstanceMethodCallProgram():GenIrProgram {
		final src = [
			"class Worker {",
			"  public function new() { }",
			"  public function outer() {",
			"    return inner();",
			"  }",
			"  public function inner() {",
			"    return \"ok\";",
			"  }",
			"}",
			"class Main {",
			"  static function main() {",
			"    Sys.println(new Worker().outer());",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpArrayPushProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var values:Array<String> = [];",
			"    var length = values.push(\"ok\");",
			"    Sys.println(length);",
			"    Sys.println(values[0]);",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpCallStackProgram():GenIrProgram {
		final src = [
			"import haxe.CallStack;",
			"import haxe.Exception;",
			"import haxe.ValueException;",
			"class Main {",
			"  static function main() {",
			"    Sys.println(CallStack.callStack().length);",
			"    Sys.println(new Exception(\"boom\").stack.length);",
			"    Sys.println(new ValueException(\"boom\").stack.length);",
			"    Sys.println(@:privateAccess new ValueException(\"boom\").get_stack().length);",
			"    Sys.println(@:privateAccess (Exception.thrown(\"boom\"):Exception).stack.length);",
			"    Sys.println(Std.downcast(new Exception(\"boom\"), Exception) != null);",
			"    try {",
			"      throw \"boom\";",
			"    } catch (e:ValueException) {",
			"      Sys.println(@:privateAccess e.get_stack().length);",
			"    }",
			"    try {",
			"      throw new Exception(\"boom\");",
			"    } catch (e) {",
			"      Sys.println(Std.downcast(e, Exception) != null);",
			"    }",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpHelperMacroFoldProgram():GenIrProgram {
		final src = [
			"import haxe.Exception;",
			"class HelperMacros {",
			"  public static function parseAndPrint(s:String) { }",
			"  public static function typeString(e) { return \"\"; }",
			"}",
			"class Main {",
			"  static function main() {",
			"    HelperMacros.parseAndPrint(\"try { } catch(e) { }\");",
			"    Sys.println(HelperMacros.typeString(try throw new Exception(\"\") catch(e) e));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpTypedAsHelperProbeProgram():GenIrProgram {
		final pos = HxPos.unknown();
		final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [
			SExpr(ECall(EIdent("typedAs"), [EString("actual"), EString("expected")]), pos),
			SExpr(ECall(EField(EIdent("HelperMacros"), "typedAs"), [EInt(1), EInt(1)]), pos),
			SExpr(ECall(EField(EField(EIdent("unit"), "HelperMacros"), "typedAs"), [EBool(true), EBool(true)]), pos),
			SExpr(ECall(EField(EIdent("Sys"), "println"), [EString("typedAs-ok")]), pos)
		], "");
		final mainClass = new HxClassDecl("Main", true, [mainFn]);
		final mainDecl = new HxModuleDecl("", [], mainClass, [mainClass], false, false);
		return MacroStage.expandProgram([typedSyntheticModule("Main.hx", mainDecl)], []);
	}

	static function phpNotImplementedExceptionProgram():GenIrProgram {
		final src = [
			"import haxe.exceptions.NotImplementedException;",
			"class Main {",
			"  static function main() {",
			"    try {",
			"      throw new NotImplementedException();",
			"    } catch (e:NotImplementedException) {",
			"      Sys.println(\"not-implemented\");",
			"    }",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpThrowExpressionLambdaProgram():GenIrProgram {
		final src = [
			"import haxe.exceptions.ArgumentException;",
			"class Main {",
			"  static function main() {",
			"    function negativeOnly(i:Int) {",
			"      if (i >= 0) throw new ArgumentException(\"i\");",
			"    }",
			"    try {",
			"      negativeOnly(1);",
			"    } catch (e:ArgumentException) {",
			"      Sys.println(\"lambda-throw\");",
			"      Sys.println(e.argument);",
			"    }",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpBytesRuntimeProgram():GenIrProgram {
		final src = [
			"import haxe.io.Bytes.fastGet as fget;",
			"class Main {",
			"  static function main() {",
			"    var b = haxe.io.Bytes.alloc(4);",
			"    b.set(1, 0xF756);",
			"    var read = function() return b.get(1);",
			"    Sys.println(b.length);",
			"    Sys.println(read());",
			"    var text = haxe.io.Bytes.ofString(\"ABé\");",
			"    Sys.println(text.length);",
			"    Sys.println(text.getString(2, 2));",
			"    var shared = haxe.io.Bytes.ofData(text.getData());",
			"    shared.set(0, \"C\".code);",
			"    Sys.println(text.getString(0, 2));",
			"    Sys.println(haxe.io.Bytes.fastGet(text.getData(), 0));",
			"    Sys.println(fget(text.getData(), 0));",
			"    Sys.println(haxe.io.Bytes.ofHex(text.toHex()).toString());",
			"    Sys.println(new haxe.io.BytesInput(text).readAll().toString());",
			"    var out = new haxe.io.BytesOutput();",
			"    out.bigEndian = true;",
			"    out.writeByte(\"A\".code);",
			"    out.writeInt16(-2);",
			"    out.writeString(\"Z\");",
			"    var input = new haxe.io.BytesInput(out.getBytes());",
			"    input.bigEndian = true;",
			"    Sys.println(out.length);",
			"    Sys.println(input.position);",
			"    input.position = 1;",
			"    Sys.println(input.position);",
			"    input.position = -5;",
			"    Sys.println(input.position);",
			"    input.position = 999;",
			"    Sys.println(input.position);",
			"    input.position = 0;",
			"    Sys.println(input.readByte());",
			"    Sys.println(input.readInt16());",
			"    Sys.println(input.readString(1));",
			"    var cmpA = haxe.io.Bytes.ofString(\"ABCD\");",
			"    var cmpB = haxe.io.Bytes.ofString(\"ABDC\");",
			"    Sys.println(cmpA.compare(cmpB));",
			"    Sys.println(cmpB.compare(cmpA));",
			"    Sys.println(cmpA.compare(haxe.io.Bytes.ofString(\"ABCD\")));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpMd5MakeProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var bytes = haxe.io.Bytes.ofString(\"héllo\");",
			"    Sys.println(bytes.toHex());",
			"    Sys.println(haxe.crypto.Md5.make(bytes).toHex());",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpSha1Program():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var bytes = haxe.io.Bytes.ofString(\"héllo\");",
			"    Sys.println(haxe.crypto.Sha1.encode(\"hello\"));",
			"    Sys.println(haxe.crypto.Sha1.make(bytes).toHex());",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpBase64Program():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var bytes = haxe.io.Bytes.ofString(\"Héllow\");",
			"    Sys.println(haxe.crypto.Base64.encode(bytes));",
			"    Sys.println(haxe.crypto.Base64.encode(bytes, false));",
			"    Sys.println(haxe.crypto.Base64.decode(\"SMOpbGxvdw==\").toString());",
			"    Sys.println(haxe.crypto.Base64.decode(\"SMOpbGxvdw\", false).toString());",
			"    try { haxe.crypto.Base64.decode(\"invalid string\"); Sys.println(\"bad\"); } catch (e:Dynamic) Sys.println(\"exc\");",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpBaseCodeProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var alt = new haxe.crypto.BaseCode(haxe.io.Bytes.ofString(\"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_-\"));",
			"    Sys.println(alt.encodeString(\"Héllow\"));",
			"    Sys.println(alt.decodeString(\"iceFr6NLtM\"));",
			"    var base32 = new haxe.crypto.BaseCode(haxe.io.Bytes.ofString(\"0123456789ABCDEFGHIJKLMNOPQRSTUV\"));",
			"    Sys.println(base32.encodeString(\"foo\"));",
			"    Sys.println(base32.decodeString(\"CPNMU\"));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpStringToolsUrlProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    Sys.println(StringTools.urlEncode(\"é\"));",
			"    Sys.println(StringTools.urlDecode(\"%C3%A9\"));",
			"    Sys.println(StringTools.urlEncode(\"a/b+c\"));",
			"    Sys.println(StringTools.urlDecode(\"a%2Fb%2Bc\"));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpOptionalStringNullProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  public function new() {}",
			"  public function optString(?value:String) {",
			"    return { value: value };",
			"  }",
			"  public function optTyped(?x:Int, ?y:String) {",
			"    return { x: x, y: y };",
			"  }",
			"  public function optDefaults(?x = 5, ?y = \"hello\") {",
			"    return { x: x, y: y };",
			"  }",
			"  public function optNullableDefaults(?x:Null<Int> = 5, ?y:Null<Float> = 6) {",
			"    return { x: x, y: y };",
			"  }",
			"  public function optNullableDefaultsSpaced(?x : Null<Int> = 5, ?y : Null<Float> = 6) {",
			"    return { x: x, y: y };",
			"  }",
			"  public function run() {",
			"    Sys.println(Std.string(optString().value == null));",
			"    Sys.println(optString(\"hello\").value);",
			"    Sys.println(Std.string(optTyped(\"str\").x == null));",
			"    Sys.println(optTyped(\"str\").y);",
			"    Sys.println(Std.string(optTyped(55).x));",
			"    Sys.println(Std.string(optTyped(55).y == null));",
			"    Sys.println(Std.string(optDefaults(null, null).x));",
			"    Sys.println(optDefaults(0, null).y);",
			"    Sys.println(Std.string(optNullableDefaults(null, null).x));",
			"    Sys.println(Std.string(optNullableDefaults(null, null).y));",
			"    Sys.println(Std.string(optNullableDefaults(7.4).x));",
			"    Sys.println(Std.string(optNullableDefaults(7.4).y));",
			"    Sys.println(Std.string(optNullableDefaultsSpaced(7.4).x));",
			"    Sys.println(Std.string(optNullableDefaultsSpaced(7.4).y));",
			"    var optClosure = function(a:Int, ?b = 2) return a + b;",
			"    Sys.println(Std.string(optClosure(1)));",
			"    Sys.println(Std.string(optClosure(1, 2)));",
			"    Sys.println(Std.string(optClosure(1, null)));",
			"  }",
			"  static function main() {",
			"    new Main().run();",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpXmlRuntimeProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var x = Xml.parse('<a href=\"hello\">World<b/></a>');",
			"    Sys.println(Std.string(x.firstChild() == x.firstChild()));",
			"    Sys.println(Std.string(x.nodeType == Xml.Document));",
			"    try { x.nodeName; Sys.println('bad'); } catch (e:Dynamic) Sys.println('exc');",
			"    try { x.nodeValue; Sys.println('bad'); } catch (e:Dynamic) Sys.println('exc');",
			"    try { x.attributes(); Sys.println('bad'); } catch (e:Dynamic) Sys.println('exc');",
			"    try { x.get('att'); Sys.println('bad'); } catch (e:Dynamic) Sys.println('exc');",
			"    try { x.exists('att'); Sys.println('bad'); } catch (e:Dynamic) Sys.println('exc');",
			"    x = x.firstChild();",
			"    Sys.println(Std.string(x.nodeType == Xml.Element));",
			"    Sys.println(x.nodeName);",
			"    x.nodeName = 'b';",
			"    Sys.println(x.toString());",
			"    Sys.println(x.get('href'));",
			"    Sys.println(Std.string(x.exists('other')));",
			"    Sys.println(Lambda.array({ iterator: x.attributes }).join('#'));",
			"    x.remove('href');",
			"    Sys.println(Lambda.array({ iterator: x.attributes }).join('#'));",
			"    Sys.println(x.toString());",
			"    Sys.println(x.firstChild().nodeValue);",
			"    Sys.println(x.firstElement().nodeName);",
			"    Sys.println(Std.string(Lambda.count({ iterator: x.elementsNamed.bind('b') })));",
			"    var y = Xml.parse('<a><b><c/> <d/> \\n <e/><![CDATA[<x>]]></b></a>');",
			"    Sys.println(y.toString().split('\\n').join('\\\\n'));",
			"    Sys.println(Xml.parse('\"').toString());",
			"    var whitespace = Xml.parse('<b></b><c/>');",
			"    var whitespaceElements = whitespace.elements();",
			"    var emptyExplicit = whitespaceElements.next();",
			"    var emptySelfClosing = whitespaceElements.next();",
			"    Sys.println(Std.string(emptyExplicit.firstChild().nodeValue == ''));",
			"    Sys.println(Std.string(emptySelfClosing.firstChild() == null));",
			"    Sys.println(Xml.createComment('Hello').toString());",
			"    Sys.println(Xml.parse('<!--Hello-->').firstChild().nodeValue);",
			"    Sys.println(Xml.createCData('<x>').toString());",
			"    Sys.println(Xml.parse('<![CDATA[Hello]]>').firstChild().nodeValue);",
			"    Sys.println(Xml.createProcessingInstruction('XHTML').toString());",
			"    Sys.println(Xml.createDocType('XHTML').toString());",
			"    var scalar = Xml.createPCData('x');",
			"    try { scalar.firstChild(); Sys.println('bad'); } catch (e:Dynamic) Sys.println('exc');",
			"    try { scalar.firstElement(); Sys.println('bad'); } catch (e:Dynamic) Sys.println('exc');",
			"    try { scalar.elements(); Sys.println('bad'); } catch (e:Dynamic) Sys.println('exc');",
			"    try { scalar.elementsNamed('x'); Sys.println('bad'); } catch (e:Dynamic) Sys.println('exc');",
			"    try { scalar.addChild(Xml.createElement('x')); Sys.println('bad'); } catch (e:Dynamic) Sys.println('exc');",
			"    try { scalar.removeChild(Xml.createElement('x')); Sys.println('bad'); } catch (e:Dynamic) Sys.println('exc');",
			"    try { scalar.insertChild(Xml.createElement('x'), 0); Sys.println('bad'); } catch (e:Dynamic) Sys.println('exc');",
			"    try { for (child in scalar) { } Sys.println('bad'); } catch (e:Dynamic) Sys.println('exc');",
			"    var closureFor = function() { for (child in scalar) { } };",
			"    try { closureFor(); Sys.println('bad'); } catch (e:Dynamic) Sys.println('exc');",
			"    Sys.println(haxe.xml.Parser.parse('&lt;', false).firstChild().nodeValue);",
			"    Sys.println(haxe.xml.Parser.parse('&#64;', false).firstChild().nodeValue);",
			"    Sys.println(haxe.xml.Parser.parse('&#244;', false).firstChild().nodeValue);",
			"    Sys.println(haxe.xml.Parser.parse('&#x3F;', false).firstChild().nodeValue);",
			"    Sys.println(haxe.xml.Parser.parse('&#xFF;', false).firstChild().nodeValue);",
			"    var custom = '<a>&gt;<b>&lt;</b>&lt;&gt;<b>&gt;&lt;</b>\"</a>';",
			"    Sys.println(haxe.xml.Parser.parse(custom).toString());",
			"    var doc = Xml.parse('<a>A</a><i>I</i>');",
			"    var aElement = doc.elementsNamed('a').next();",
			"    var iElement = doc.elementsNamed('i').next();",
			"    iElement.addChild(aElement);",
			"    Sys.println(doc.toString());",
			"    var attrQuote = Xml.createElement('node');",
			"    attrQuote.set('key', 'a\"b\\'&c>d<e');",
			"    Sys.println(attrQuote.toString());",
			"    try { haxe.xml.Parser.parse('<node attribute=\"<\"/>', true); Sys.println('bad'); } catch (e:Dynamic) Sys.println('exc');",
			"    try { haxe.xml.Parser.parse('<node attribute=\">\"/>', true); Sys.println('bad'); } catch (e:Dynamic) Sys.println('exc');",
			"    var escapedAttr = haxe.xml.Parser.parse('<node attribute=\"something with &lt; &amp; &quot; &apos; special characters &gt;\"/>');",
			"    Sys.println(escapedAttr.firstChild().get('attribute'));",
			"    try { haxe.xml.Parser.parse('<flow>x'); Sys.println('bad'); } catch (e:Exception) Sys.println(Std.string(e.message.indexOf('Unclosed node <flow>') != -1));",
			"    try { haxe.xml.Parser.parse('<f><f/></f></f>'); Sys.println('bad'); } catch (e:Exception) Sys.println(Std.string(e.message.indexOf('Unexpected </f>, tag is not open') != -1));",
			"    try { haxe.xml.Parser.parse('<f><f></f>'); Sys.println('bad'); } catch (e:Exception) Sys.println(Std.string(e.message.indexOf('Unclosed node <f>') != -1));",
			"    try { Xml.parse('<node>'); Sys.println('bad'); } catch (e:Dynamic) Sys.println('exc');",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpScopedLocalShadowProgram():GenIrProgram {
		final pos = HxPos.unknown();
		function println(expr:HxExpr):HxStmt {
			return SExpr(ECall(EField(EIdent("Sys"), "println"), [expr]), pos);
		}
		final body:Array<HxStmt> = [
			SVar("x", "", EInt(0), pos),
			SBlock([
				SVar("x", "", EString("hello"), pos),
				println(EIdent("x")),
				SBlock([SVar("x", "", EString(""), pos), println(EIdent("x"))], pos),
				println(EIdent("x"))
			],
				pos),
			println(EIdent("x")),
			SIf(EBool(true), SBlock([SVar("x", "", EString("branch"), pos), println(EIdent("x"))], pos), null, pos),
			println(EIdent("x")),
			SForIn("x", EArrayDecl([EString("loop")]), SBlock([println(EIdent("x"))], pos), pos),
			println(EIdent("x")),
			SSwitch(EAnon(["value"], [EString("matched")]), [HxSwitchPattern.PObject(["value"], [HxSwitchPattern.PBind("x")])],
				[SBlock([println(EIdent("x"))], pos)], pos),
			println(EIdent("x")),
			STry(SBlock([SThrow(EString("caught"), pos)], pos), [
				{
					name: "x",
					typeHint: "Dynamic",
					body: SBlock([println(EIdent("x"))], pos)
				}
			], pos),
			println(EIdent("x"))
		];
		final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", body, "");
		final mainClass = new HxClassDecl("Main", true, [mainFn]);
		final mainDecl = new HxModuleDecl("", [], mainClass, [mainClass], false, false);
		return MacroStage.expandProgram([typedSyntheticModule("Main.hx", mainDecl)], []);
	}

	static function phpLoopCaptureProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var funs = [];",
			"    var sum = 0;",
			"    for (i in 0...3) {",
			"      var k = 0;",
			"      funs.push(function() {",
			"        k++;",
			"        sum++;",
			"        return k;",
			"      });",
			"    }",
			"    Sys.println(Std.string(funs[0]()));",
			"    Sys.println(Std.string(funs[1]()));",
			"    Sys.println(Std.string(funs[2]()));",
			"    Sys.println(Std.string(sum));",
			"    var incs = [];",
			"    var decs = [];",
			"    var total = 0;",
			"    for (i in 0...3) {",
			"      var j = i;",
			"      incs.push(function() {",
			"          total += j;",
			"          j++;",
			"          return j;",
			"      });",
			"      decs.push(function() {",
			"          j--;",
			"          total -= j;",
			"          return j;",
			"      });",
			"    }",
			"    for (i in 0...3) {",
			"      Sys.println(Std.string(incs[i]()));",
			"      Sys.println(Std.string(total));",
			"      Sys.println(Std.string(decs[i]()));",
			"      Sys.println(Std.string(total));",
			"    }",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpSubCaptureProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var funs = new Array();",
			"    for( i in 0...5 )",
			"      funs.push(function() {",
			"        var tmp = new Array();",
			"        for( j in 0...5 )",
			"          tmp.push(function() return i + j);",
			"        var sum = 0;",
			"        for( j in 0...5 )",
			"          sum += tmp[j]();",
			"        return sum;",
			"      });",
			"    for( i in 0...5 )",
			"      Sys.println(Std.string(funs[i]()));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpAnonCallableFieldProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var count = 1;",
			"    var ops = {",
			"      inc: function() {",
			"        count++;",
			"        return count;",
			"      }",
			"    };",
			"    Sys.println(Std.string(ops.inc()));",
			"    Sys.println(Std.string(count));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpERegProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var groups = ~/a+(b)?(c*)a+/;",
			"    Sys.println(\"m1=\" + Std.string(groups.match(\"xxaabcayyy\")));",
			"    Sys.println(\"g0=\" + groups.matched(0));",
			"    Sys.println(\"g1=\" + Std.string(groups.matched(1)));",
			"    Sys.println(\"g2=\" + Std.string(groups.matched(2)));",
			"    Sys.println(\"left=\" + groups.matchedLeft());",
			"    Sys.println(\"right=\" + groups.matchedRight());",
			"    var pos = groups.matchedPos();",
			"    Sys.println(\"pos=\" + Std.string(pos.pos) + \",len=\" + Std.string(pos.len));",
			"    var digits = new EReg(\"\\\\d+\", \"g\");",
			"    Sys.println(\"m2=\" + Std.string(digits.match(\"ab12cd\")));",
			"    Sys.println(\"dg0=\" + digits.matched(0));",
			"    Sys.println(\"dleft=\" + digits.matchedLeft());",
			"    Sys.println(\"dright=\" + digits.matchedRight());",
			"    Sys.println(\"rep=\" + digits.replace(\"a1b22c\", \"#\"));",
			"    Sys.println(\"parts=\" + digits.split(\"a1b22c\").join(\"|\"));",
			"    Sys.println(\"map=\" + digits.map(\"a1b22c\", function(e) return \"[\" + e.matched(0) + \"]\"));",
			"    Sys.println(\"mapsub=\" + ~/a+/g.map(\"aaabacx\", function(r) return \"[\" + r.matched(0).substr(1) + \"]\"));",
			"    Sys.println(\"mapzero=\" + ~/x?/g.map(\"aaabacx\", function(r) return \"[\" + r.matched(0) + \"]\"));",
			"    var sub = ~/a+/;",
			"    Sys.println(\"sub0=\" + Std.string(sub.matchSub(\"abab\", 0)));",
			"    Sys.println(\"sub0right=\" + sub.matchedRight());",
			"    Sys.println(\"sub1=\" + Std.string(sub.matchSub(\"abab\", 1)));",
			"    Sys.println(\"sub1left=\" + sub.matchedLeft());",
			"    Sys.println(\"sub1right=\" + sub.matchedRight());",
			"    Sys.println(\"esc=\" + EReg.escape(\"a+b\"));",
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

	static function phpTypeErrorExpressionProbeProgram():GenIrProgram {
		final src = [
			"class MyInt2 {",
			"  public function new(v:Int) {",
			"    this = v;",
			"  }",
			"  public function get():Int {",
			"    return this;",
			"  }",
			"  public function invert():MyInt2 {",
			"    return new MyInt2(-this);",
			"  }",
			"  public function incr():Int {",
			"    return ++this;",
			"  }",
			"}",
			"",
			"class Main {",
			"  static function main() {",
			"    var accepts = function(label:String, ?point:{x:Float, y:Int}, ?size:{w:Float, h:Int}) { };",
			"    var item:{v:Int};",
			"    var badFloat = typeError(item = {v: 1.2});",
			"    var okInt = typeError(item = {v: 1});",
			"    var badString = typeError(item = {v: \"oops\"});",
			"    var badExtra = typeError(item = {v: 1, w: \"extra\"});",
			"    var okPointCall = typeError(accepts(\"shape\", {x: 1.2, y: 2}));",
			"    var okSizeCall = typeError(accepts(\"shape\", {w: 1.2, h: 2}));",
			"    var duplicateMapKey = typeError([1 => 2, 1 => 3]);",
			"    var mixedMapKey = typeError([1 => 2, \"1\" => 2]);",
			"    var mixedMapValue = typeError([1 => 2, 3 => \"2\"]);",
			"    var okMapLiteral = typeError([1 => 2, 3 => 4]);",
			"    var ms1:MyString = cast \"foo\";",
			"    var ms2:MyString = cast \"bar\";",
			"    var badAbstractAdd = typeError(ms1 + true);",
			"    var badAbstractSub = typeError(ms1 - ms2);",
			"    var my = new MyInt2(12);",
			"    var badAbstractNot = typeError(!my);",
			"    var badAbstractPostfix = typeError(my++);",
			"    function choose(a:Choice, ?flag:Bool, ?tail:Choice) {",
			"      return \"\";",
			"    }",
			"    var badOptionalSkip = typeError(choose(A, A, false));",
			"    Sys.println(Std.string(badFloat));",
			"    Sys.println(Std.string(okInt));",
			"    Sys.println(Std.string(badString));",
			"    Sys.println(Std.string(badExtra));",
			"    Sys.println(Std.string(okPointCall));",
			"    Sys.println(Std.string(okSizeCall));",
			"    Sys.println(Std.string(duplicateMapKey));",
			"    Sys.println(Std.string(mixedMapKey));",
			"    Sys.println(Std.string(mixedMapValue));",
			"    Sys.println(Std.string(okMapLiteral));",
			"    Sys.println(Std.string(badAbstractAdd));",
			"    Sys.println(Std.string(badAbstractSub));",
			"    Sys.println(Std.string(badAbstractNot));",
			"    Sys.println(Std.string(badAbstractPostfix));",
			"    Sys.println(Std.string(badOptionalSkip));",
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

	static function phpAbstractCastConstraintProgram():GenIrProgram {
		final src = [
			"class AbstractBase<T> {",
			"  public var value:T;",
			"  public function new(value:T) {",
			"    this.value = value;",
			"  }",
			"}",
			"",
			"class AbstractZ<T> { }",
			"",
			"class Helper {",
			"  public static function t(value:Bool) { }",
			"}",
			"",
			"class Main {",
			"  static function main() {",
			"    var z:AbstractZ<String> = new AbstractBase(\"foo\");",
			"    var s:String = z;",
			"    Sys.println(s);",
			"    var zi:AbstractZ<Int> = new AbstractBase(12);",
			"    var i:Int = zi;",
			"    Sys.println(Std.string(i + 1));",
			"    var badInt = typeError({ var i:Int = z; });",
			"    var badString = typeError({ var z:AbstractZ<Int> = new AbstractBase(12); var s:String = z; });",
			"    Sys.println(Std.string(badInt));",
			"    Sys.println(Std.string(badString));",
			"    Helper.t(typeError({ var z:AbstractZ<Int> = new AbstractBase(12); var s:String = z; }));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpLoweredAbstractCastTypeErrorProbeProgram():GenIrProgram {
		final pos = HxPos.unknown();
		final badIntProbe:HxExpr = ECall(EIdent("typeError"), [ECall(ELambda([], ECall(ELambda(["i"], ENull), [EIdent("z")])), [])]);
		final badStringProbe:HxExpr = ECall(EIdent("typeError"), [
			ECall(ELambda(["z"], ECall(ELambda(["s"], ENull), [EIdent("z")])), [ENew("AbstractBase", [EInt(12)])])
		]);
		final badScopedStringProbe:HxExpr = ECall(EIdent("typeError"), [
			ECall(ELambda([], ECall(ELambda(["s"], ENull), [ECall(EIdent("__hxhx_copy_value"), [EIdent("z__hx_scope_1")])])), [])
		]);
		final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [
			SVar("z", "", ENull, pos),
			SVar("z__hx_scope_1", "", ENull, pos),
			SVar("badInt", "", badIntProbe, pos),
			SVar("badString", "", badStringProbe, pos),
			SVar("badScopedString", "", badScopedStringProbe, pos),
			SVar("tester", "", ENew("TestHarness", []), pos),
			SExpr(ECall(EField(EIdent("Sys"), "println"), [ECall(EField(EIdent("Std"), "string"), [EIdent("badInt")])]), pos),
			SExpr(ECall(EField(EIdent("Sys"), "println"), [ECall(EField(EIdent("Std"), "string"), [EIdent("badString")])]), pos),
			SExpr(ECall(EField(EIdent("Sys"), "println"), [ECall(EField(EIdent("Std"), "string"), [EIdent("badScopedString")])]), pos),
			SExpr(ECall(EField(EIdent("tester"), "t"), [badScopedStringProbe]), pos)
		], "");
		final mainClass = new HxClassDecl("Main", true, [mainFn]);
		final harnessFn = new HxFunctionDecl("t", HxVisibility.Public, false, [new HxFunctionArg("value", "Bool", NoDefault)], "Void", [], "");
		final harnessClass = new HxClassDecl("TestHarness", false, [harnessFn]);
		final mainDecl = new HxModuleDecl("", [], mainClass, [mainClass, harnessClass], false, false);
		return MacroStage.expandProgram([typedSyntheticModule("Main.hx", mainDecl)], []);
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

	static function phpMapLiteralTypeTagProgram():GenIrProgram {
		final src = [
			"class Box {",
			"  public var id:Int;",
			"  public function new(id:Int) {",
			"    this.id = id;",
			"  }",
			"}",
			"",
			"class Main {",
			"  static function main() {",
			"    var intMap = [1 => 2, 3 => 4];",
			"    Sys.println(Std.string(Std.isOfType(intMap, haxe.ds.IntMap)));",
			"    Sys.println(Std.string(intMap.get(1)));",
			"    var stringMap = [\"1\" => 2, \"3\" => 4];",
			"    Sys.println(Std.string(Std.isOfType(stringMap, haxe.ds.StringMap)));",
			"    Sys.println(Std.string(stringMap.get(\"3\")));",
			"    var box = new Box(1);",
			"    var objectMap = [box => 5];",
			"    Sys.println(Std.string(Std.isOfType(objectMap, haxe.ds.ObjectMap)));",
			"    Sys.println(Std.string(objectMap.get(box)));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpMapSetTypeTagProgram():GenIrProgram {
		final src = [
			"class Box {",
			"  public function new() {}",
			"}",
			"",
			"class Main {",
			"  static function mapMe(map:Map<Int,String>) {",
			"  }",
			"  static function main() {",
			"    var stringMap = new Map<String,Int>();",
			"    stringMap.set(\"foo\", 1);",
			"    Sys.println(Std.string(Std.isOfType(stringMap, haxe.ds.StringMap)));",
			"    var intMap = new Map<Int,Int>();",
			"    intMap.set(7, 1);",
			"    Sys.println(Std.string(Std.isOfType(intMap, haxe.ds.IntMap)));",
			"    var box = new Box();",
			"    var objectMap = new Map<Box,Int>();",
			"    objectMap.set(box, 1);",
			"    Sys.println(Std.string(Std.isOfType(objectMap, haxe.ds.ObjectMap)));",
			"    var inferred = new Map();",
			"    mapMe(inferred);",
			"    Sys.println(Std.string(Std.isOfType(inferred, haxe.ds.IntMap)));",
			"    var neutral = new Map();",
			"    Sys.println(Std.string(Std.isOfType(neutral, haxe.ds.IntMap)));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpHaxeSerializerRuntimeProgram():GenIrProgram {
		final src = [
			"class Box {",
			"  public var count:Int = 0;",
			"  public var label:String = \"\";",
			"  public function new(count:Int, label:String) {",
			"    this.count = count;",
			"    this.label = label;",
			"  }",
			"}",
			"class Main {",
			"  static function main() {",
			"    Sys.println(haxe.Serializer.run(0));",
			"    Sys.println(haxe.Serializer.run(\"éé\"));",
			"    var values = [1, 2, null, null, 4];",
			"    var values2:Array<Dynamic> = haxe.Unserializer.run(haxe.Serializer.run(values));",
			"    Sys.println(Std.string(values2.length));",
			"    Sys.println(Std.string(values2[3] == null));",
			"    var anon:Dynamic = haxe.Unserializer.run(haxe.Serializer.run({name: \"hxhx\", count: 3}));",
			"    Sys.println(Std.string(Reflect.field(anon, \"name\")));",
			"    var original = new Box(7, \"seven\");",
			"    var box:Box = haxe.Unserializer.run(haxe.Serializer.run(original));",
			"    Sys.println(Std.string(original == box));",
			"    Sys.println(box.label + \":\" + Std.string(box.count));",
			"    var map = new haxe.ds.StringMap<Int>();",
			"    map.set(\"kéy\", 42);",
			"    var map2:haxe.ds.StringMap<Int> = haxe.Unserializer.run(haxe.Serializer.run(map));",
			"    Sys.println(Std.string(map2.get(\"kéy\")));",
			"    var intMap = new haxe.ds.IntMap<Int>();",
			"    intMap.set(7, 9);",
			"    var intMap2:haxe.ds.IntMap<Int> = haxe.Unserializer.run(haxe.Serializer.run(intMap));",
			"    Sys.println(Std.string(Std.isOfType(intMap2, haxe.ds.IntMap)));",
			"    Sys.println(Std.string(intMap2.get(7)));",
			"    var objectKey = new Box(1, \"one\");",
			"    var objectMap = new haxe.ds.ObjectMap<Box, Int>();",
			"    objectMap.set(objectKey, 11);",
			"    var objectMap2:haxe.ds.ObjectMap<Box, Int> = haxe.Unserializer.run(haxe.Serializer.run(objectMap));",
			"    Sys.println(Std.string(Std.isOfType(objectMap2, haxe.ds.ObjectMap)));",
			"    var list = Lambda.list([4, 5]);",
			"    var list2:haxe.ds.List<Int> = haxe.Unserializer.run(haxe.Serializer.run(list));",
			"    Sys.println(Std.string(list2.length));",
			"    Sys.println(Std.string(list2.first()));",
			"    Sys.println(Std.string(list2.last()));",
			"    var bytes = haxe.io.Bytes.ofString(\"ABC\");",
			"    Sys.println(haxe.Serializer.run(bytes));",
			"    var bytes2:haxe.io.Bytes = haxe.Unserializer.run(haxe.Serializer.run(bytes));",
			"    Sys.println(bytes2.toString());",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpPoint3StringEqualityRuntimeProgram():GenIrProgram {
		final src = [
			"class MyPoint3 {",
			"  public var x:Int;",
			"  public var y:Int;",
			"  public var z:Int;",
			"  public function new(x:Int, y:Int, z:Int) {",
			"    this.x = x;",
			"    this.y = y;",
			"    this.z = z;",
			"  }",
			"}",
			"class Main {",
			"  static function main() {",
			"    var point = new MyPoint3(2, 3, 4);",
			"    var other = new MyPoint3(2, 3, 4);",
			"    Sys.println(Std.string(\"(2,3,4)\" == point));",
			"    Sys.println(Std.string(point == \"(2,3,4)\"));",
			"    Sys.println(Std.string(point == other));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpPoint3UnaryScaleRuntimeProgram():GenIrProgram {
		final src = [
			"class MyPoint3 {",
			"  public var x:Int;",
			"  public var y:Int;",
			"  public var z:Int;",
			"  public function new(x:Int, y:Int, z:Int) {",
			"    this.x = x;",
			"    this.y = y;",
			"    this.z = z;",
			"  }",
			"}",
			"class MyVector {",
			"  public var x(get, set):Int;",
			"  public var y:Int;",
			"  public var z:Int;",
			"  public function new() {",
			"    y = 0;",
			"    z = 0;",
			"  }",
			"  public function get_x():Int return 0;",
			"  public function get_y():Int return y;",
			"  public function set_x(value:Int):Int return value;",
			"  public function set_y(value:Int):Int return y = value;",
			"  public function set_z(value:Int):Int return z = value;",
			"}",
			"class Main {",
			"  static function main() {",
			"    var point = new MyPoint3(1, 2, 3);",
			"    var neg = -point;",
			"    Sys.println(Std.string(neg != point));",
			"    Sys.println(Std.string(point));",
			"    Sys.println(neg.toString());",
			"    var fields = Type.getInstanceFields(MyPoint3);",
			"    fields.sort(Reflect.compare);",
			"    Sys.println(fields.join(\"|\"));",
			"    var vectorFields = Type.getInstanceFields(MyVector);",
			"    vectorFields.sort(Reflect.compare);",
			"    Sys.println(vectorFields.join(\"|\"));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpLambdaListRuntimeProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var list = Lambda.list([\"a\", \"b\", \"c\"]);",
			"    Sys.println(Std.string(list.length));",
			"    Sys.println(list.first());",
			"    Sys.println(list.last());",
			"    var manual = new haxe.ds.List();",
			"    manual.push(\"b\");",
			"    manual.push(\"a\");",
			"    manual.add(\"c\");",
			"    Sys.println(manual.join(\"#\"));",
			"    Sys.println(Std.string(manual.length));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpGenericStackRuntimeProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var stack = new haxe.ds.GenericStack<Int>();",
			"    Sys.println(Std.string(stack.isEmpty()));",
			"    stack.add(1);",
			"    stack.add(2);",
			"    Sys.println(Std.string(stack.first()));",
			"    Sys.println(stack.toString());",
			"    Sys.println(Std.string(stack.pop()));",
			"    Sys.println(Std.string(stack.first()));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpReflectMakeVarArgsProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var f = function(a:Array<Dynamic>) {",
			"      return a.length + a[0] + a[1];",
			"    };",
			"    var g = Reflect.makeVarArgs(f);",
			"    Sys.println(Std.string(g(1, 2)));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpReflectPropertyAccessProgram():GenIrProgram {
		final src = [
			"package unit;",
			"",
			"interface IPropBox {",
			"  public var x(get, set) : Int;",
			"}",
			"class PropBox {",
			"  public var x(get, set):Int;",
			"  var _x:Int;",
			"  public static var STAT_X(default, set):Int;",
			"  public function new() {",
			"    _x = 5;",
			"  }",
			"  function get_x() {",
			"    return _x;",
			"  }",
			"  function set_x(v:Int) {",
			"    _x = v;",
			"    return v;",
			"  }",
			"  static function set_STAT_X(v:Int) {",
			"    STAT_X = v * 2;",
			"    return v;",
			"  }",
			"  static function __init__() {",
			"    STAT_X = 3;",
			"  }",
			"}",
			"class PropHarness {",
			"  public function new() {}",
			"  public function run() {",
			"    var box = new PropBox();",
			"    Sys.println(Std.string(box.x));",
			"    Reflect.setProperty(box, \"x\", 16);",
			"    Sys.println(Std.string(box.x));",
			"  }",
			"}",
			"class Main {",
			"  static function main() {",
			"    var box = new PropBox();",
			"    Sys.println(Std.string(box.x));",
			"    Sys.println(Std.string(Reflect.getProperty(box, \"x\")));",
			"    box.x = 10;",
			"    Sys.println(Std.string(box.x));",
			"    Reflect.setProperty(box, \"x\", 12);",
			"    Sys.println(Std.string(box.x));",
			"    var iface : IPropBox = new PropBox();",
			"    Sys.println(Std.string(iface.x));",
			"    iface.x = 13;",
			"    Sys.println(Std.string(iface.x));",
			"    Reflect.setProperty(iface, \"x\", 14);",
			"    Sys.println(Std.string(iface.x));",
			"    var dup = new PropBox();",
			"    Sys.println(Std.string(dup.x));",
			"    var dup : IPropBox = new PropBox();",
			"    Sys.println(Std.string(dup.x));",
			"    Sys.println(Std.string(PropBox.STAT_X));",
			"    Sys.println(Std.string(Reflect.getProperty(PropBox, \"STAT_X\")));",
			"    PropBox.STAT_X = 4;",
			"    Sys.println(Std.string(PropBox.STAT_X));",
			"    Reflect.setProperty(PropBox, \"STAT_X\", 9);",
			"    Sys.println(Std.string(Reflect.getProperty(PropBox, \"STAT_X\")));",
			"    new PropHarness().run();",
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
			"enum LowerEnum {",
			"  id(i:Int);",
			"}",
			"enum MultiEnum {",
			"  A;",
			"  B;",
			"  With(i:Int);",
			"}",
			"enum A {",
			"  A;",
			"  D(e:A);",
			"}",
			"enum EOlder {",
			"  Same;",
			"}",
			"enum ELatest {",
			"  Same;",
			"}",
			"enum ConstantBox<T> {",
			"  CFloatBox(s:String):ConstantBox<Float>;",
			"}",
			"enum BinopBox<S, T> {",
			"  OpAddBox:BinopBox<Float, Float>;",
			"}",
			"enum OlderExprBox {",
			"  EConst;",
			"}",
			"enum ExprBox<T> {",
			"  EConst(c:ConstantBox<T>):ExprBox<T>;",
			"  EBinop<C>(op:BinopBox<C, T>, left:ExprBox<C>, right:ExprBox<C>):ExprBox<T>;",
			"}",
			"",
			"class EnumSwitchHolder {",
			"  public function new() {}",
			"  function id(e:MyEnum) return e;",
			"  public function run():String {",
			"    var c = MyEnum.C(4, \"z\");",
			"    return switch (id(c)) {",
			"      case C(i, s): Std.string(i) + s;",
			"      default: \"bad\";",
			"    }",
			"  }",
			"}",
			"",
			"class BoxEval {",
			"  public static function eval(e:ExprBox<Float>):Float {",
			"    return switch (e) {",
			"      case EConst(CFloatBox(s)): Std.parseFloat(s);",
			"      case EBinop(op, left, right): evalBinop(op, left, right);",
			"    }",
			"  }",
			"  public static function evalBinop(op:BinopBox<Float, Float>, left:ExprBox<Float>, right:ExprBox<Float>):Float {",
			"    return switch (op) {",
			"      case OpAddBox: eval(left) + eval(right);",
			"    }",
			"  }",
			"}",
			"",
			"class Main {",
			"  static function main() {",
			"    var e = MyEnum.C(0, \"h\");",
			"    var c = MyEnum.C;",
			"    var e2 = c(1, \"x\");",
			"    var id = MyEnum.C;",
			"    var later = function(i:Int, s:String) return id(i, s);",
			"    var e3 = later(2, \"y\");",
			"    var lowerId = LowerEnum.id;",
			"    var lower = lowerId(3);",
			"    var holder = new EnumSwitchHolder();",
			"    Sys.println(Std.string(e));",
			"    Sys.println(Std.string([e]));",
			"    Sys.println(Std.string(e2));",
			"    Sys.println(Type.enumEq(e2, MyEnum.C(1, \"x\")));",
			"    Sys.println(Std.string(e3));",
			"    Sys.println(Type.enumEq(e3, MyEnum.C(2, \"y\")));",
			"    Sys.println(Std.string(lower));",
			"    Sys.println(Type.enumEq(lower, LowerEnum.id(3)));",
			"    Sys.println(holder.run());",
			"    Sys.println(Std.string(SimpleEnum.SE_A));",
			"    Sys.println(Type.enumEq(SimpleEnum.SE_A, SimpleEnum.SE_A));",
			"    haxe.Serializer.USE_ENUM_INDEX = true;",
			"    var indexed:Dynamic = haxe.Unserializer.run(haxe.Serializer.run(MultiEnum.With(9)));",
			"    var indexedA:Dynamic = haxe.Unserializer.run(haxe.Serializer.run(MultiEnum.A));",
			"    var indexedSimple:Dynamic = haxe.Unserializer.run(haxe.Serializer.run(SimpleEnum.SE_A));",
			"    haxe.Serializer.USE_ENUM_INDEX = false;",
			"    Sys.println(Std.string(indexed));",
			"    Sys.println(Type.enumEq(indexed, MultiEnum.With(9)));",
			"    Sys.println(Std.string(indexedA));",
			"    Sys.println(Type.enumEq(indexedA, MultiEnum.A));",
			"    Sys.println(Std.string(indexedSimple));",
			"    Sys.println(Type.enumEq(indexedSimple, SimpleEnum.SE_A));",
			"    var unqualifiedNested = D(A);",
			"    Sys.println(Std.string(unqualifiedNested));",
			"    Sys.println(Type.enumEq(unqualifiedNested, D(A)));",
			"    var latest:ELatest = ELatest.Same;",
			"    Sys.println(Std.string(latest));",
			"    Sys.println(Type.enumEq(latest, Same));",
			"    var box = EConst(CFloatBox(\"12\"));",
			"    Sys.println(Std.string(box));",
			"    Sys.println(Std.string(BoxEval.eval(EBinop(OpAddBox, box, EConst(CFloatBox(\"8\"))))));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final baseDecl = parsed.getDecl();
		final main = HxModuleDecl.getMainClass(baseDecl);
		final classes = [main].concat(ParserStageScanHelpers.scanModuleLocalHelperClasses(src, HxClassDecl.getName(main)))
			.concat(ParserStageScanHelpers.scanModuleLocalHelperEnums(src, HxClassDecl.getName(main)));
		final enriched = new HxModuleDecl(HxModuleDecl.getPackagePath(baseDecl), HxModuleDecl.getImports(baseDecl), main, classes,
			HxModuleDecl.getHeaderOnly(baseDecl), HxModuleDecl.getHasToplevelMain(baseDecl));
		final typed = TyperStage.typeModule(new ParsedModule(src, enriched, "Main.hx"));
		return MacroStage.expandProgram([typed], []);
	}

	static function phpStdEnumAbstractSupportProgram():GenIrProgram {
		final mainSrc = [
			"import haxe.display.KeywordKind;",
			"class Main {",
			"  static function main() {",
			"    Sys.println(Std.string(KeywordKind.Implements));",
			"  }",
			"}",
		].join("\n");
		final stdSrc = [
			"package haxe.display;",
			"class Display {}",
			"enum abstract KeywordKind(String) to String {",
			"  var Implements = \"implements\";",
			"  var Extends = \"extends\";",
			"}",
		].join("\n");
		final typedMain = TyperStage.typeModule(ParserStage.parse(mainSrc, "Main.hx"));
		final parsedStd = ParserStage.parse(stdSrc, "std/haxe/display/Display.hx");
		final stdBaseDecl = parsedStd.getDecl();
		final stdMain = HxModuleDecl.getMainClass(stdBaseDecl);
		final stdClasses = [stdMain].concat(ParserStageScanHelpers.scanModuleLocalHelperEnums(stdSrc, HxClassDecl.getName(stdMain)));
		final stdDecl = new HxModuleDecl(HxModuleDecl.getPackagePath(stdBaseDecl), HxModuleDecl.getImports(stdBaseDecl), stdMain, stdClasses,
			HxModuleDecl.getHeaderOnly(stdBaseDecl), HxModuleDecl.getHasToplevelMain(stdBaseDecl));
		final typedStd = typedSyntheticModule("std/haxe/display/Display.hx", stdDecl);
		return MacroStage.expandProgram([typedMain, typedStd], []);
	}

	static function phpStdIoErrorEnumSupportProgram():GenIrProgram {
		final mainSrc = [
			"import haxe.io.Error;",
			"class Main {",
			"  static function main() {",
			"    Sys.println(Std.string(Error.OutsideBounds));",
			"    Sys.println(Type.enumEq(Error.OutsideBounds, Error.OutsideBounds));",
			"    Sys.println(Std.string(Error.Custom(\"disk\")));",
			"  }",
			"}",
		].join("\n");
		final typedMain = TyperStage.typeModule(ParserStage.parse(mainSrc, "Main.hx"));
		return MacroStage.expandProgram([typedMain, phpStdIoErrorTypedModule()], []);
	}

	static function phpStdIoErrorRuntimeExceptionProgram():GenIrProgram {
		final mainSrc = [
			"import haxe.io.Error;",
			"class Main {",
			"  static function check(label:String, fn:Void->Void, expected:Error) {",
			"    try {",
			"      fn();",
			"      Sys.println(label + \":bad\");",
			"    } catch (caught:Dynamic) {",
			"      Sys.println(label + \":\" + Std.string(caught));",
			"      Sys.println(Type.enumEq(caught, expected));",
			"    }",
			"  }",
			"  static function main() {",
			"    var bytes = haxe.io.Bytes.ofString(\"abc\");",
			"    var out = new haxe.io.BytesOutput();",
			"    check(\"write-bounds\", function() out.writeBytes(bytes, -1, 1), Error.OutsideBounds);",
			"    check(\"write-overflow\", function() out.writeInt8(128), Error.Overflow);",
			"    var input = new haxe.io.BytesInput(bytes);",
			"    var buf = haxe.io.Bytes.alloc(2);",
			"    check(\"read-bounds\", function() input.readBytes(buf, 1, 2), Error.OutsideBounds);",
			"  }",
			"}",
		].join("\n");
		final typedMain = TyperStage.typeModule(ParserStage.parse(mainSrc, "Main.hx"));
		return MacroStage.expandProgram([typedMain, phpStdIoErrorTypedModule()], []);
	}

	static function phpStdIoErrorTypedModule():TypedModule {
		final errorSrc = [
			"package haxe.io;",
			"enum Error {",
			"  Blocked;",
			"  Overflow;",
			"  OutsideBounds;",
			"  Custom(e:Dynamic);",
			"}",
		].join("\n");
		return TyperStage.typeModule(ParserStage.parse(errorSrc, "std/haxe/io/Error.hx"));
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

	static function phpMathRandomRuntimeProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var value = Math.random();",
			"    Sys.println(Std.string(value >= 0.0 && value < 1.0));",
			"    Sys.println(Std.string(Math.isFinite(value)));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpStdRandomRuntimeProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    Sys.println(Std.random(0));",
			"    var value = Std.random(3);",
			"    Sys.println(Std.string(value >= 0 && value < 3));",
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
			"    try { throw new Exception('Unclosed node <flow>'); } catch (exc:Exception) {",
			"      Sys.println(Std.string(exc.message.indexOf('Unclosed node <flow>') != -1));",
			"    }",
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
			"class MyInt2 {",
			"  public function new(v:Int) {",
			"    this = v;",
			"  }",
			"  public function get():Int {",
			"    return this;",
			"  }",
			"  public function invert():MyInt2 {",
			"    return new MyInt2(-this);",
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
			"    var my = new MyInt2(12);",
			"    Sys.println(Std.string((-my).get()));",
			"    my = my + 1;",
			"    Sys.println(Std.string(my.get()));",
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

	static function phpAbstractThisClosureCaptureProgram():GenIrProgram {
		final src = [
			"class ClosureBox {",
			"  public function new(value:String) {",
			"    this = value;",
			"  }",
			"  public function make() {",
			"    var fn = function() {",
			"      return this;",
			"    };",
			"    return fn;",
			"  }",
			"  public inline function setVal(value:String) {",
			"    this = value;",
			"  }",
			"}",
			"",
			"class Main {",
			"  static function main() {",
			"    var box = new ClosureBox(\"foo\");",
			"    var first = box.make();",
			"    Sys.println(first());",
			"    box.setVal(\"bar\");",
			"    Sys.println(first());",
			"    Sys.println(box.make()());",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpExposingAbstractArrayProgram():GenIrProgram {
		final src = [
			"class ExposingArray {",
			"  public function new() {",
			"    this = [];",
			"  }",
			"}",
			"",
			"class Main {",
			"  static function main() {",
			"    var exposing = new ExposingArray();",
			"    Sys.println(Std.string(exposing.push(12)));",
			"    Sys.println(Std.string(exposing.pop()));",
			"    Sys.println(Std.string(exposing.pop()));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpInlineCastSelfReturnProgram():GenIrProgram {
		final src = [
			"class InlineBase {",
			"  public function new() {}",
			"  public function self():InlineBase {",
			"    return this;",
			"  }",
			"}",
			"",
			"class InlineChild extends InlineBase {",
			"  public function new() {",
			"    super();",
			"  }",
			"  public inline function test():InlineChild {",
			"    return cast self();",
			"  }",
			"  public function quote():String {",
			"    return \"quoted\";",
			"  }",
			"}",
			"",
			"class Main {",
			"  static function main() {",
			"    Sys.println(new InlineChild().test().quote());",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpConstrainedParameterScannerFlowProgram():GenIrProgram {
		final src = [
			"class Base {",
			"  public function new() {}",
			"}",
			"",
			"class ConstraintHelper {",
			"  static public function staticSingle<A:Base>(a:A):A {",
			"    return a;",
			"  }",
			"  public function memberAnon<A:{ x : Int } & { y : Float }>(v:A) {",
			"    return v.x + v.y;",
			"  }",
			"}",
			"",
			"class Main {",
			"  static function main() {",
			"    var b = new Base();",
			"    Sys.println(Std.string(ConstraintHelper.staticSingle(b) == b));",
			"    Sys.println(Std.string(new ConstraintHelper().memberAnon({ x: 1, y: 3. }) == 4));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final baseDecl = parsed.getDecl();
		final main = HxModuleDecl.getMainClass(baseDecl);
		final classes = [main].concat(ParserStageScanHelpers.scanModuleLocalHelperClasses(src, HxClassDecl.getName(main)));
		final enriched = new HxModuleDecl(HxModuleDecl.getPackagePath(baseDecl), HxModuleDecl.getImports(baseDecl), main, classes,
			HxModuleDecl.getHeaderOnly(baseDecl), HxModuleDecl.getHasToplevelMain(baseDecl));
		final typed = TyperStage.typeModule(new ParsedModule(src, enriched, "Main.hx"));
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
			"  public function test() return super.fProp(2);",
			"}",
			"",
			"class Main {",
			"  static function main() {",
			"    var child = new Child();",
			"    Sys.println(Std.string(child.prop));",
			"    Sys.println(Std.string(child.prop = 4));",
			"    Sys.println(child.test());",
			"    Sys.println(child.fProp(9));",
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
			"enum KeywordKind { Dynamic; }",
			"enum MyTypeEnum { A; }",
			"interface MyTypeInterface {}",
			"class MyTypeClass implements MyTypeInterface { public function new() {} }",
			"class MyTypeSubClass extends MyTypeClass { public function new() { super(); } }",
			"class Main {",
			"  static function main() {",
			"    var i = 1;",
			"    var s = \"one\";",
			"    Sys.println(Std.string(i is Int));",
			"    Sys.println(Std.string(s is String));",
			"    Sys.println(Std.string(i is Float));",
			"    Sys.println(Std.string(1.5 is Float));",
			"    Sys.println(Std.string(Std.isOfType(i, Float)));",
			"    Sys.println(Std.string(Std.isOfType(1.5, Float)));",
			"    var c:Dynamic = Float;",
			"    Sys.println(Std.string(Std.isOfType(i, c)));",
			"    c = String;",
			"    Sys.println(Std.string(Std.isOfType(i, c)));",
			"    Sys.println(Std.string(2.0 is Int));",
			"    Sys.println(Std.string(1.2 is Int));",
			"    Sys.println(Std.string(Std.isOfType(2.0, Int)));",
			"    Sys.println(Std.string(Std.isOfType(1.2, Int)));",
			"    Sys.println(Std.string(Std.isOfType(1e10, Int)));",
			"    Sys.println(Std.string(Std.isOfType(1e10, Float)));",
			"    var dynamicTypes:Array<Dynamic> = [String, Bool, Int, Float, Class, Enum, Dynamic];",
			"    for (t in dynamicTypes) Sys.println(Std.string(Std.isOfType(0, t)));",
			"    Sys.println(Std.string(loopCheck(0, Int, Float)));",
			"    Sys.println(Std.string(fullLoopCheck(0, Int, Float)));",
			"  }",
			"  static function loopCheck(value:Dynamic, t1:Dynamic, ?t2:Dynamic):Bool {",
			"    var dynamicTypes:Array<Dynamic> = [String, Bool, Int, Float, Class, Enum, Dynamic];",
			"    for (c in dynamicTypes) {",
			"      var actual = Std.isOfType(value, c);",
			"      var expected = c != null && (c == t1 || c == t2) || c == Dynamic;",
			"      if (actual != expected) return false;",
			"    }",
			"    return true;",
			"  }",
			"  static function fullLoopCheck(value:Dynamic, t1:Dynamic, ?t2:Dynamic):Bool {",
			"    var dynamicTypes:Array<Dynamic> = [null, String, Bool, Int, Float, Array, List, haxe.ds.StringMap, MyTypeEnum, MyTypeClass, MyTypeSubClass, Class, Enum, Dynamic, MyTypeInterface];",
			"    for (c in dynamicTypes) {",
			"      var actual = Std.isOfType(value, c);",
			"      var expected = c != null && (c == t1 || c == t2) || c == Dynamic;",
			"      if (actual != expected) return false;",
			"    }",
			"    return true;",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpInterfaceCastProgram():GenIrProgram {
		final src = [
			"interface CapA {}",
			"interface CapB extends CapA {}",
			"class OnlyA implements CapA { public function new() {} }",
			"class Both implements CapB { public function new() {} }",
			"class Main {",
			"  static function main() {",
			"    var a = new OnlyA();",
			"    Sys.println(Std.string(cast(a, CapA) == a));",
			"    try {",
			"      cast(a, CapB);",
			"      Sys.println(\"missing\");",
			"    } catch (e:Dynamic) {",
			"      Sys.println(\"raised\");",
			"    }",
			"    var b = new Both();",
			"    Sys.println(Std.string(cast(b, CapA) == b));",
			"    Sys.println(Std.string(cast(b, CapB) == b));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpArrayDynamicCastProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var values:Dynamic = [1, 2, 3];",
			"    var casted = cast(values, Array<Dynamic>);",
			"    Sys.println(Std.string(casted.length));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpAbstractValueCastProgram():GenIrProgram {
		final src = [
			"abstract Wrap(Int) from Int {}",
			"class Main {",
			"  static function main() {",
			"    var value = cast(1, Wrap);",
			"    Sys.println(Std.string(value));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpSyntaxIntrinsicProgram():GenIrProgram {
		final src = [
			"import php.Syntax;",
			"class Main {",
			"  static function main() {",
			"    var one = 1;",
			"    var two = 2;",
			"    Sys.println(Std.string(Syntax.code(\"{0} + {1}\", one, two)));",
			"    var anon = {field: \"ok\"};",
			"    Sys.println(Std.string(Syntax.field(anon, \"field\")));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpNullEqualityProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var value:Null<Int> = null;",
			"    Sys.println(Std.string(value == 0));",
			"    Sys.println(Std.string(0 == value));",
			"    Sys.println(Std.string(value == null));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpUserSyntaxClassProgram():GenIrProgram {
		final src = [
			"class Syntax {",
			"  public static function code(value:String):String { return \"user:\" + value; }",
			"}",
			"class Main {",
			"  static function main() {",
			"    Sys.println(Syntax.code(\"ok\"));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpUserClassTypeCheckProgram():GenIrProgram {
		final src = [
			"package unit;",
			"enum MyEnum { A; }",
			"interface MyInterface {}",
			"class MyClass implements MyInterface {",
			"  public var intValue:Null<Int> = 55;",
			"  var value:Null<Int>;",
			"  public function new(value:Int) { this.value = value; }",
			"  public function get():Null<Int> return value;",
			"}",
			"class MySubClass extends MyClass { public function new(value:Int) { super(value); } }",
			"class Main {",
			"  static var types:Array<Dynamic> = [null, String, unit.MyClass, Class, Dynamic];",
			"  static function main() {",
			"    var value = new MyClass(0);",
			"    var child = new MySubClass(1);",
			"    var c:Dynamic = MyClass;",
			"    Sys.println(Std.string(value is MyClass));",
			"    Sys.println(Std.string(Std.isOfType(value, MyClass)));",
			"    Sys.println(Std.string(child is MyClass));",
			"    Sys.println(Std.string(Std.isOfType(child, MyClass)));",
			"    Sys.println(Std.string(value is c));",
			"    Sys.println(Std.string(check(value, c)));",
			"    c = MySubClass;",
			"    Sys.println(Std.string(value is c));",
			"    Sys.println(Std.string(check(value, c)));",
			"    c = null;",
			"    Sys.println(Std.string(Std.isOfType(value, c)));",
			"    var anon:Dynamic = { x: 0 };",
			"    Sys.println(Std.string(Std.isOfType(anon, c)));",
			"    var fn:Dynamic = function() {};",
			"    Sys.println(Std.string(Std.isOfType(fn, c)));",
			"    Sys.println(Std.string(reflectLoopCheck(value, MyClass)));",
			"    Sys.println(Std.string(reflectLoopCheck(MyClass, Class)));",
			"    Sys.println(Std.string(Std.isOfType(MyClass, Class)));",
			"    Sys.println(Std.string(Std.isOfType(MyClass, String)));",
			"    Sys.println(Std.string(Type.resolveClass(\"unit.MyClass\") == MyClass));",
			"    Sys.println(Type.getClassName(Type.resolveClass(\"unit.MyClass\")));",
			"    Sys.println(Type.getClassName(Type.getClass(value)));",
			"    var made = Type.createInstance(MyClass, [33]);",
			"    Sys.println(Std.string(made is MyClass));",
			"    Sys.println(made.get());",
			"    Sys.println(made.intValue);",
			"    var empty = Type.createEmptyInstance(MyClass);",
			"    Sys.println(Std.string(empty is MyClass));",
			"    Sys.println(Std.string(empty.get() == null));",
			"    Sys.println(Std.string(empty.intValue == null));",
			"    Sys.println(Std.string(fullLoopCheck(0, Int, Float)));",
			"  }",
			"  static function check(value:Dynamic, c:Dynamic):Bool return value is c;",
			"  static function reflectLoopCheck(value:Dynamic, t1:Dynamic):Bool {",
			"    for (i in 0...types.length) {",
			"      var c:Dynamic = types[i];",
			"      var actual = Std.isOfType(value, c);",
			"      var expected = c != null && c == t1 || c == Dynamic;",
			"      if (actual != expected) return false;",
			"    }",
			"    return true;",
			"  }",
			"  static function fullLoopCheck(value:Dynamic, t1:Dynamic, ?t2:Dynamic):Bool {",
			"    var dynamicTypes:Array<Dynamic> = [null, String, Bool, Int, Float, Array, List, haxe.ds.StringMap, unit.MyEnum, unit.MyClass, unit.MySubClass, Class, Enum, Dynamic, unit.MyInterface];",
			"    for (c in dynamicTypes) {",
			"      var actual = Std.isOfType(value, c);",
			"      var expected = c != null && (c == t1 || c == t2) || c == Dynamic;",
			"      if (actual != expected) return false;",
			"    }",
			"    return true;",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "unit/Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpEnumTypeCheckProgram():GenIrProgram {
		final enumSrc = ["package unit;", "enum MyEnum {", "  A;", "  B(value:Int);", "}",].join("\n");
		final mainSrc = [
			"package unit;",
			"class Main {",
			"  static var types:Array<Dynamic> = [null, unit.MyEnum, Dynamic];",
			"  static function main() {",
			"    var value:Dynamic = MyEnum.A;",
			"    var other:Dynamic = MyEnum.B(1);",
			"    var c:Dynamic = MyEnum;",
			"    Sys.println(Std.string(Std.isOfType(value, MyEnum)));",
			"    Sys.println(Std.string(value is MyEnum));",
			"    Sys.println(Std.string(Std.isOfType(other, c)));",
			"    Sys.println(Std.string(check(other, c)));",
			"    Sys.println(Std.string(reflectLoopCheck(value, MyEnum)));",
			"    Sys.println(Std.string(Std.isOfType(value, Enum)));",
			"    Sys.println(Std.string(Std.isOfType(MyEnum, Enum)));",
			"    c = null;",
			"    Sys.println(Std.string(Std.isOfType(value, c)));",
			"    var anon:Dynamic = { x: 0 };",
			"    Sys.println(Std.string(Std.isOfType(anon, c)));",
			"    var fn:Dynamic = function() {};",
			"    Sys.println(Std.string(Std.isOfType(fn, c)));",
			"    Sys.println(Type.getEnumName(MyEnum));",
			"    var constructors = Type.getEnumConstructs(MyEnum);",
			"    Sys.println(constructors.join(\"|\"));",
			"    var oldConstructor = constructors[0];",
			"    constructors[0] = \"Modified\";",
			"    Sys.println(Std.string(Type.getEnumConstructs(MyEnum).contains(oldConstructor)));",
			"    var all = Type.allEnums(MyEnum);",
			"    Sys.println(all.join(\"|\"));",
			"    Sys.println(Std.string(Type.enumEq(all[0], MyEnum.A)));",
			"    Sys.println(Std.string(all.length));",
			"    var madeA = Type.createEnum(MyEnum, untyped __unprotect__(\"A\"));",
			"    Sys.println(Std.string(Type.enumEq(madeA, MyEnum.A)));",
			"    var madeB:MyEnum = Type.createEnum(MyEnum, \"B\", [55]);",
			"    switch (madeB) {",
			"      case B(value): Sys.println(value);",
			"      default: Sys.println(\"bad\");",
			"    }",
			"    try { Type.createEnum(MyEnum, untyped __unprotect__(\"A\"), [0]); Sys.println(\"bad\"); } catch (e:Dynamic) Sys.println(\"exc\");",
			"    try { Type.createEnum(MyEnum, \"B\"); Sys.println(\"bad\"); } catch (e:Dynamic) Sys.println(\"exc\");",
			"    try { Type.createEnum(MyEnum, \"Z\", []); Sys.println(\"bad\"); } catch (e:Dynamic) Sys.println(\"exc\");",
			"  }",
			"  static function check(value:Dynamic, c:Dynamic):Bool return value is c;",
			"  static function reflectLoopCheck(value:Dynamic, t1:Dynamic):Bool {",
			"    for (i in 0...types.length) {",
			"      var c:Dynamic = types[i];",
			"      var actual = Std.isOfType(value, c);",
			"      var expected = c == t1 || c == Dynamic;",
			"      if (actual != expected) return false;",
			"    }",
			"    return true;",
			"  }",
			"}",
		].join("\n");
		final typedEnum = TyperStage.typeModule(ParserStage.parse(enumSrc, "unit/MyEnum.hx"));
		final typedMain = TyperStage.typeModule(ParserStage.parse(mainSrc, "unit/Main.hx"));
		return MacroStage.expandProgram([typedMain, typedEnum], []);
	}

	static function phpTypeReflectionProgram():GenIrProgram {
		final src = [
			"import haxe.ds.List;",
			"import haxe.ds.StringMap;",
			"enum MyReflectEnum { C; }",
			"class ReflectThing {",
			"  public var value:Int = 1;",
			"  public function new() {}",
			"  public function method():Void {}",
			"  public static var stat:Int = 2;",
			"  public static function helper():Void {}",
			"}",
			"class PropertyThing {",
			"  public var x(get, set):Int;",
			"  public var y(default, set):Int = 0;",
			"  public static var sx(get, set):Int;",
			"  public static var sy(default, set):Int = 0;",
			"  public function new() {}",
			"  function get_x():Int return 1;",
			"  function set_x(value:Int):Int return value;",
			"  function set_y(value:Int):Int return value;",
			"  static function get_sx():Int return 1;",
			"  static function set_sx(value:Int):Int return value;",
			"  static function set_sy(value:Int):Int return value;",
			"}",
			"class Main {",
			"  static function main() {",
			"    var types:Array<Dynamic> = [String, Array, List, ReflectThing, MyReflectEnum];",
			"    var cls:Dynamic = types[3];",
			"    var en:Dynamic = types[4];",
			"    var values = new List();",
			"    values.add('a');",
			"    values.add('b');",
			"    var stringMap = new StringMap();",
			"    stringMap.set('x', 1);",
			"    Sys.println(Type.getClassName(types[0]));",
			"    Sys.println(Type.getClassName(types[1]));",
			"    Sys.println(Std.string(types[1] == \"Array\"));",
			"    Sys.println(Std.string(\"Array\" == types[1]));",
			"    Sys.println(Std.string(Type.resolveClass(\"Array\") == types[1]));",
			"    Sys.println(Type.getClassName(types[2]));",
			"    Sys.println(Std.string(Type.resolveClass(\"haxe.ds.List\") == types[2]));",
			"    Sys.println(Type.getClassName(cls));",
			"    Sys.println(Std.string(Type.resolveClass(\"ReflectThing\") == cls));",
			"    var instanceFields = Type.getInstanceFields(cls);",
			"    instanceFields.sort(Reflect.compare);",
			"    Sys.println(instanceFields.join(\"#\"));",
			"    var classFields = Type.getClassFields(cls);",
			"    classFields.sort(Reflect.compare);",
			"    Sys.println(classFields.join(\"#\"));",
			"    var propertyFields = Type.getInstanceFields(PropertyThing);",
			"    propertyFields.sort(Reflect.compare);",
			"    Sys.println(propertyFields.join(\"#\"));",
			"    var staticPropertyFields = Type.getClassFields(PropertyThing);",
			"    staticPropertyFields.sort(Reflect.compare);",
			"    Sys.println(staticPropertyFields.join(\"#\"));",
			"    Sys.println(Type.getEnumName(en));",
			"    Sys.println(Std.string(Type.resolveEnum(\"MyReflectEnum\") == en));",
			"    Sys.println(Type.getClassName(Type.getClass(\"hello\")));",
			"    Sys.println(Std.string(values is List));",
			"    Sys.println(Std.string(Std.isOfType(values, List)));",
			"    Sys.println(Type.getClassName(Type.getClass(values)));",
			"    Sys.println(Std.string(values.length));",
			"    Sys.println(values.first());",
			"    Sys.println(values.last());",
			"    Sys.println(Std.string(stringMap is StringMap));",
			"    Sys.println(Std.string(Std.isOfType(stringMap, StringMap)));",
			"    Sys.println(Type.getClassName(Type.getClass(stringMap)));",
			"    Sys.println(Std.string(checkType(null, TNull)));",
			"    Sys.println(Std.string(checkType(0, TInt)));",
			"    Sys.println(Std.string(checkType(1.2, TFloat)));",
			"    Sys.println(Std.string(checkType(true, TBool)));",
			"    Sys.println(Std.string(checkType('hello', TClass(String))));",
			"    Sys.println(Std.string(checkType([], TClass(Array))));",
			"    Sys.println(Std.string(checkType(values, TClass(List))));",
			"    Sys.println(Std.string(checkType(stringMap, TClass(StringMap))));",
			"    Sys.println(Std.string(checkType(new ReflectThing(), TClass(ReflectThing))));",
			"    Sys.println(Std.string(checkType(MyReflectEnum.C, TEnum(MyReflectEnum))));",
			"    Sys.println(Std.string(checkType({ x: 0 }, TObject)));",
			"    Sys.println(Std.string(checkType(function() {}, TFunction)));",
			"    Sys.println(Std.string(checkType(ReflectThing, TObject)));",
			"    Sys.println(Std.string(checkType(MyReflectEnum, TObject)));",
			"  }",
			"  static function checkType(value:Dynamic, expected:ValueType):Bool return Type.enumEq(Type.typeof(value), expected);",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpGenericStaticReflectionProgram():GenIrProgram {
		final src = [
			"class GenericBox {",
			"  public var value:String;",
			"  public function new(value:String) this.value = value;",
			"}",
			"class GenericReflect {",
			"  @:generic public static function gf1<T>(value:T):T return value;",
			"  @:generic public static function gf2<A, B>(label:A, values:Array<B>):String return Std.string(label) + Std.string(values);",
			"  @:generic public static function gf3<A, B>(seed:A, values:B):B return values;",
			"  @:generic static function overloadFake<A>(value:A):A return value;",
			"  static function overloadFake_String(value:String):String return value + \"foo\";",
			"  public function new() {}",
			"  public function runOverloadInt():Int return overloadFake(1);",
			"  public function runOverloadString():String return overloadFake(\"bar\");",
			"}",
			"class Main {",
			"  static function main() {",
			"    GenericReflect.gf1(1);",
			"    GenericReflect.gf1(\"foo\");",
			"    GenericReflect.gf1(true);",
			"    GenericReflect.gf1(new haxe.ds.GenericStack<Int>());",
			"    GenericReflect.gf1({foo: 1});",
			"    GenericReflect.gf1(function(i:Int):String return Std.string(i));",
			"    GenericReflect.gf2(\"foo\", [1, 2]);",
			"    GenericReflect.gf2(\"foo\", [[1, 2]]);",
			"    var box = new GenericBox(\"box\");",
			"    GenericReflect.gf3(box, []);",
			"    var fields = Type.getClassFields(GenericReflect);",
			"    fields.sort(Reflect.compare);",
			"    Sys.println(fields.join(\"#\"));",
			"    Sys.println(Std.string(Lambda.has(fields, \"gf1_Int\")));",
			"    Sys.println(Std.string(Lambda.has(fields, \"gf1_String\")));",
			"    Sys.println(Std.string(Lambda.has(fields, \"gf1_Bool\")));",
			"    Sys.println(Std.string(Lambda.has(fields, \"gf1_haxe_ds_GenericStack_Int\")));",
			"    Sys.println(Std.string(Lambda.has(fields, \"gf1_anon_foo_Int\")));",
			"    Sys.println(Std.string(Lambda.has(fields, \"gf1_func_Int_String\")));",
			"    Sys.println(Std.string(Lambda.has(fields, \"gf2_String_Int\")));",
			"    Sys.println(Std.string(Lambda.has(fields, \"gf2_String_Array_Int\")));",
			"    Sys.println(Std.string(Lambda.has(fields, \"gf3_GenericBox_Array_GenericBox\")));",
			"    var reflect = new GenericReflect();",
			"    Sys.println(reflect.runOverloadInt());",
			"    Sys.println(reflect.runOverloadString());",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpGenericStaticReflectionTextFallbackProgram():GenIrProgram {
		final pos = HxPos.unknown();
		final gf2 = new HxFunctionDecl("gf2", HxVisibility.Public, true, [
			new HxFunctionArg("label", "A", HxDefaultValue.NoDefault),
			new HxFunctionArg("values", "Array<B>", HxDefaultValue.NoDefault)
		], "String", [SReturn(EString("ok"), pos)], "", ["generic"], pos, pos);
		final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [], "", [], pos, pos,
			'GenericReflect.gf2("foo", [1, 2]);\nGenericReflect.gf2("foo", [[1, 2]]);');
		final mainClass = new HxClassDecl("Main", true, [mainFn], []);
		final genericClass = new HxClassDecl("GenericReflect", false, [gf2], []);
		final decl = new HxModuleDecl("", [], mainClass, [mainClass, genericClass], false, false);
		return new MacroExpandedProgram([typedSyntheticModule("Main.hx", decl)], false, []);
	}

	static function phpGenericConstructibleProgram():GenIrProgram {
		final src = [
			"class A {",
			"  public var value:String;",
			"  public function new(value:String) this.value = value;",
			"  public function toString():String return value;",
			"}",
			"class MyGeneric<T> {",
			"  public var t:T;",
			"  public function new(t:T) this.t = t;",
			"}",
			"class GenericConstruct {",
			"  @:generic public static function append<A>(seed:A, values:Array<A>):Array<A> {",
			"    var clone = new A(\"tail\");",
			"    values.push(clone);",
			"    return values;",
			"  }",
			"}",
			"class Main {",
			"  static function main() {",
			"    var strings = GenericConstruct.append(\"seed\", [\"head\"]);",
			"    Sys.println(strings[1]);",
			"    var box = new A(\"first\");",
			"    var boxes = GenericConstruct.append(box, []);",
			"    Sys.println(Std.string(boxes[0] == box));",
			"    Sys.println(boxes[0].value);",
			"    var fnBox = new MyGeneric<Int->Int>(function(i:Int):Int return i * i);",
			"    Sys.println(fnBox.t(2));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpTypeErrorGenericNullProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  @:generic static function gf1<T>(value:T):T return value;",
			"  static function main() {",
			"    Sys.println(Std.string(typeError(gf1(null))));",
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

	static function phpMapComprehensionRuntimeProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {",
			"    var m = [for (x in [\"a\", \"b\"]) x => x.toUpperCase()];",
			"    Sys.println(Std.string(m.exists(\"a\")));",
			"    Sys.println(m.get(\"b\"));",
			"    var wrapped = [for (x in [1, 2]) (x => x + 10)];",
			"    Sys.println(wrapped.get(2));",
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

	static function assertPythonUtestRunnerAddCasesMacroStub():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_utest_add_cases_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final pos = HxPos.unknown();
		final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [
			SVar("runner", "", ENew("Runner", []), pos),
			SExpr(ECall(EField(EIdent("runner"), "addCases"), [EString("cases")]), pos),
			SExpr(ECall(EField(EIdent("Sys"), "println"), [EString("after-addCases")]), pos)
		], "");
		final mainClass = new HxClassDecl("Main", true, [mainFn]);
		final mainDecl = new HxModuleDecl("", [], mainClass, [mainClass], false, false);
		final addCase = new HxFunctionDecl("addCase", HxVisibility.Public, false, [new HxFunctionArg("value", "", NoDefault)], "Void",
			[SExpr(ECall(EField(EIdent("Sys"), "println"), [EIdent("value")]), pos)], "");
		final addCases = new HxFunctionDecl("addCases", HxVisibility.Public, false, [
			new HxFunctionArg("eThis", "Dynamic", NoDefault),
			new HxFunctionArg("path", "String", NoDefault),
			new HxFunctionArg("recursive", "Bool", Default(EBool(true)), true)
		], "Void", [SExpr(EUnsupported("body_parse_error"), pos)], "", ["macro"]);
		final runnerClass = new HxClassDecl("Runner", false, [addCase, addCases]);
		final runnerDecl = new HxModuleDecl("utest", [], runnerClass, [runnerClass], false, false);
		final program = MacroStage.expandProgram([
			typedSyntheticModule("Main.hx", mainDecl),
			typedSyntheticModule("tests/.haxelib/utest/git/src/utest/Runner.hx", runnerDecl)
		], []);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class Runner:", "Python utest Runner should still emit runtime support");
		assertContains(content, "def addCases(self, path, recursive=True):", "Python utest Runner addCases should omit macro eThis and keep callable defaults");
		assertContains(content, "return None", "Python utest Runner addCases macro body should lower to a neutral runtime stub");
		assertContains(content, "utest.Runner = Runner", "Python utest Runner should remain package-addressable");
		assertNotContains(content, "body_parse_error", "Python utest Runner addCases should not leak its macro-only source body");
		if (commandExists("python3")) {
			final run = commandOutput("python3", [outputPath]);
			assertTrue(run.code == 0, "generated Python utest Runner addCases stub should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "after-addCases", "generated Python should continue after the addCases runtime stub");
		}
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

	static function assertPythonTimerRuntimeShim():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_std_timer_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final pos = HxPos.unknown();
		final stampCall:HxExpr = ECall(EField(EIdent("Timer"), "stamp"), []);
		final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [
			SVar("before", "Float", stampCall, pos),
			SVar("after", "Float", stampCall, pos),
			SExpr(ECall(EField(EIdent("Sys"), "println"), [
				ECall(EField(EIdent("Std"), "string"), [EBinop(">=", EIdent("after"), EIdent("before"))])
			]), pos)
		], "");
		final mainClass = new HxClassDecl("Main", true, [mainFn]);
		final mainDecl = new HxModuleDecl("", [], mainClass, [mainClass], false, false);
		final stdStampFn = new HxFunctionDecl("stamp", HxVisibility.Public, true, [], "Float",
			[SExpr(EUnsupported("std-timer-source-should-not-render"), pos)], "");
		final timerClass = new HxClassDecl("Timer", false, [stdStampFn]);
		final timerDecl = new HxModuleDecl("", [], timerClass, [timerClass], false, false);
		final program = MacroStage.expandProgram([
			typedSyntheticModule("Main.hx", mainDecl),
			typedSyntheticModule("/repo/std/Timer.hx", timerDecl)
		], []);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class Timer:", "Python runtime should provide a small Timer helper for upstream utest handlers");
		assertContains(content, "def stamp():", "Python Timer helper should expose stamp for upstream utest handlers");
		assertContains(content, "before = Timer.stamp()", "Python code should preserve Timer.stamp calls against the helper");
		assertNotContains(content, "std-timer-source-should-not-render", "Python Timer support should not dump the upstream std source body");
		if (commandExists("python3")) {
			final run = commandOutput("python3", [outputPath]);
			assertTrue(run.code == 0, "generated Python Timer runtime shim should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "True", "generated Python should observe monotonic Timer.stamp readings");
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
			printBool(ECall(EField(EIdent("StringTools"), "endsWith"), [EString("testCase"), EString("Case")])),
			SExpr(ECall(EField(EIdent("Sys"), "println"), [ECall(EField(EIdent("StringTools"), "hex"), [EInt(1), EInt(6)])]), pos)
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
		assertContains(content, "def hex(value, digits=None):", "Python std StringTools fallback should expose hex");
		if (commandExists("python3")) {
			final run = commandOutput("python3", [outputPath]);
			assertTrue(run.code == 0, "generated Python StringTools fallback should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "True\nFalse\nTrue\n000001", "generated Python StringTools fallback should match startsWith/endsWith/hex basics");
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPythonStdVectorNamespaceSupport():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_std_vector_namespace_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final pos = HxPos.unknown();
		final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [
			SExpr(ECall(EField(EIdent("Sys"), "println"), [EArrayAccess(ENew("haxe.ds.Vector", [EInt(1)]), EInt(0))]), pos)
		], "");
		final mainClass = new HxClassDecl("Main", true, [mainFn]);
		final mainDecl = new HxModuleDecl("", [], mainClass, [mainClass], false, false);
		final vectorClass = new HxClassDecl("Vector", false, []);
		final vectorDecl = new HxModuleDecl("haxe.ds", [], vectorClass, [vectorClass], false, false);
		final program = MacroStage.expandProgram([
			typedSyntheticModule("Main.hx", mainDecl),
			typedSyntheticModule("/repo/std/haxe/ds/Vector.hx", vectorDecl)
		], []);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class Vector(Array):", "Python std Vector fallback should emit when std Vector is excluded from helper classes");
		assertContains(content, "haxe.ds.Vector = Vector", "Python std Vector fallback should be reachable through haxe.ds namespace");
		if (commandExists("python3")) {
			final run = commandOutput("python3", [outputPath]);
			assertTrue(run.code == 0, "generated Python Vector fallback should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "None", "new haxe.ds.Vector(1)[0] should read the default null slot");
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPythonMainClassConstructedAtRuntime():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_main_class_constructed_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final pos = HxPos.unknown();
		final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [
			SVar("fixture", "", ENew("Main", []), pos),
			SExpr(ECall(EField(EIdent("fixture"), "testExtern"), []), pos)
		], "");
		final testFn = new HxFunctionDecl("testExtern", HxVisibility.Public, false, [], "Void",
			[SExpr(ECall(EField(EIdent("Sys"), "println"), [EString("case")]), pos)], "");
		final mainClass = new HxClassDecl("Main", true, [mainFn, testFn]);
		final mainDecl = new HxModuleDecl("", [], mainClass, [mainClass], false, false);
		final program = MacroStage.expandProgram([typedSyntheticModule("Main.hx", mainDecl)], []);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class Main:", "Python backend should emit a runtime main class when main constructs Main()");
		assertContains(content, "fixture = Main()", "Python backend should preserve Main construction inside the entrypoint");
		assertContains(content, "def testExtern(self):", "Python backend should keep instance test methods on the emitted main class");
		if (commandExists("python3")) {
			final run = commandOutput("python3", [outputPath]);
			assertTrue(run.code == 0, "generated Python main-class construction should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "case", "generated Python should run the constructed main-class instance method");
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

	static function phpTypedMapLiteralWithLambdaFieldProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  var callbacks:Map<Int, Int->Int> = new Map();",
			"  public function new() {}",
			"  public function run() {",
			"    callbacks = [1 => value -> value + 1, 2 => value -> value + 2];",
			"    Sys.println(callbacks.get(2)(40));",
			"  }",
			"  static function main() {",
			"    new Main().run();",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function phpOptionalBeforeRequiredFunctionFieldProgram():GenIrProgram {
		final src = [
			"class Holder {",
			"  var combine:?Int->String->Int;",
			"  public function new() {}",
			"  public function run() {",
			"    combine = (a:Int = 1, b:String) -> a + b.length;",
			"    Sys.println(combine(\"--\"));",
			"  }",
			"}",
			"class Main {",
			"  static function main() {",
			"    new Holder().run();",
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

	static function javaUtilityProcessRuntimeProgram():GenIrProgram {
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

	static function javaFileSystemFullPathProgram(linkPath:String):GenIrProgram {
		final escapedLink = StringTools.replace(linkPath, "\\", "\\\\");
		final src = [
			"import sys.FileSystem;",
			"",
			"class Main {",
			"  static function main() {",
			"    Sys.println(FileSystem.fullPath(\"" + escapedLink + "\"));",
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
		final sourceContent = File.getContent(sourcePath);
		assertContains(sourceContent, "class Std", "Java source backend should provide minimal Std support class");
		assertContains(sourceContent, "public static int parseInt(String value)", "Java Std.parseInt support should handle sys helper exit codes");
		assertContains(sourceContent, "class Sys", "Java source backend should provide minimal Sys support class");
		assertContains(sourceContent, "public static int command(Object... args)",
			"Java Sys.command support should execute helper commands used by upstream Java misc projects");
		assertContains(sourceContent, "public static String[] args()", "Java Sys.args support should expose CLI args to sys tests");
		assertContains(sourceContent, "java.lang.Process process = builder.start()",
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
		assertContains(content, "class __HxAnon {", "PHP anonymous object literals should emit the anonymous-object runtime helper");
		assertContains(content, "$info = new __HxAnon([\"label\" => \"ok\", \"count\" => 1]);",
			"PHP anonymous object literals should lower through the helper-backed object runtime");
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
		assertContains(content, "$sm = new Map(null, \"haxe.ds.StringMap\");", "PHP haxe.ds.StringMap construction should lower to a tagged runtime shim");
		assertContains(content, "$m->set(\"a\", 1);", "PHP Map.set should lower as an instance method call");
		assertContains(content, "$sm->set(\"b\", 2);", "PHP haxe.ds.StringMap.set should use the runtime shim");
		assertContains(content, "__hxhx_add_string($m->exists(\"a\"))", "PHP Map.exists should be usable in expressions");
		assertContains(content, "__hxhx_add_string($m->get(\"a\"))", "PHP Map.get should be usable in expressions");
		assertContains(content, "__hxhx_add_string(__hxhx_remove($m, \"a\"))", "PHP Map.remove should be usable in expressions");
		assertContains(content, "__hxhx_add_string($sm->get(\"b\"))", "PHP haxe.ds.StringMap.get should be usable in expressions");
		assertContains(content, "$im = new Map(null, \"haxe.ds.IntMap\");", "PHP haxe.ds.IntMap construction should lower to a tagged runtime shim");
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
		assertContains(content, "echo __hxhx_add(__hxhx_add(\"a\", __hxhx_add(\"\", $x",
			"PHP identifier interpolation should keep prefix, payload, and suffix");
		assertContains(content, "$values = Lambda::array($sm);", "PHP Lambda.array should accept Map-backed iterables");
		assertContains(content, "echo __hxhx_array_join($values, \"#\") . PHP_EOL;", "PHP Array.join should lower for Lambda.array results");
		assertContains(content, "$keys = Lambda::array(new __HxAnon([\"iterator\" => (function() use ($sm) { return $sm->keys(); })]));",
			"PHP Lambda.array should accept structural iterator method closures");
		assertContains(content, "echo __hxhx_array_join($keys, \"#\") . PHP_EOL;", "PHP Array.join should lower for structural iterator results");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpMapLiteralTypeTags():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_map_literal_type_tags_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpMapLiteralTypeTagProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "__hxhx_map_literal([[1, 2], [3, 4]])", "PHP int-key map literals should lower through the map literal helper");
		assertContains(content, "__hxhx_map_literal([[\"1\", 2], [\"3\", 4]])", "PHP string-key map literals should lower through the map literal helper");
		assertContains(content, "__hxhx_is_of_type($intMap, \"haxe.ds.IntMap\")", "PHP map literal type tags should support IntMap type checks");
		assertContains(content, "__hxhx_is_of_type($stringMap, \"haxe.ds.StringMap\")", "PHP map literal type tags should support StringMap type checks");
		assertContains(content, "__hxhx_is_of_type($objectMap, \"haxe.ds.ObjectMap\")", "PHP map literal type tags should support ObjectMap type checks");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP map literal type tags should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "true\n2\ntrue\n4\ntrue\n5\n", "generated PHP map literal type tag output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpMapSetTypeTags():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_map_set_type_tags_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpMapSetTypeTagProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "if ($this->__hx_type === \"Map\")", "PHP Map.set should infer a concrete runtime map tag for generic Map values");
		assertContains(content, "$stringMap = new Map();", "PHP generic Map<String,Int> construction should start with the neutral Map runtime shim");
		assertContains(content, "__hxhx_is_of_type($stringMap, \"haxe.ds.StringMap\")",
			"PHP generic Map<String,Int> values should be checkable as haxe.ds.StringMap after set");
		assertContains(content, "__hxhx_is_of_type($intMap, \"haxe.ds.IntMap\")",
			"PHP generic Map<Int,Int> values should be checkable as haxe.ds.IntMap after set");
		assertContains(content, "__hxhx_is_of_type($objectMap, \"haxe.ds.ObjectMap\")",
			"PHP generic Map<object,Int> values should be checkable as haxe.ds.ObjectMap after set");
		assertContains(content, "__hxhx_tag_map($map, \"haxe.ds.IntMap\")", "PHP typed Map<Int,V> function arguments should tag neutral Map values");
		assertContains(content, "__hxhx_is_of_type($inferred, \"haxe.ds.IntMap\")",
			"PHP function-call inferred Map<Int,V> values should be checkable as haxe.ds.IntMap");
		assertContains(content, "$value->__hx_type === \"haxe.ds.IntMap\" || $value->__hx_type === \"Map\"",
			"PHP neutral Map values should remain compatible with inferred concrete map checks");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP Map.set type tags should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "true\ntrue\ntrue\ntrue\ntrue\n", "generated PHP Map.set type tag output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpHaxeSerializerRuntimeSupport():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_haxe_serializer_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpHaxeSerializerRuntimeProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class Serializer {", "PHP source backend should emit haxe.Serializer support");
		assertContains(content, "class Unserializer {", "PHP source backend should emit haxe.Unserializer support");
		assertContains(content, "haxe\\Serializer::run(0)", "PHP haxe.Serializer.run calls should lower to the haxe namespace shim");
		assertContains(content, "haxe\\Unserializer::run(haxe\\Serializer::run($values))",
			"PHP haxe.Unserializer.run should consume haxe.Serializer output through namespace shims");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP haxe.Serializer/Unserializer support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "z\ny12:%C3%A9%C3%A9\n5\ntrue\nhxhx\nfalse\nseven:7\n42\ntrue\n9\ntrue\n2\n4\n5\ns4:QUJD\nABC\n",
				"generated PHP haxe.Serializer/Unserializer output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpHaxeSerializerImportRuntimeSupport():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_haxe_serializer_import_" + Std.string(Date.now().getTime()));
		final srcDir = Path.join([tmpRoot, "src"]);
		final haxeDir = Path.join([srcDir, "haxe"]);
		final unitDir = Path.join([srcDir, "unit"]);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(haxeDir);
		FileSystem.createDirectory(unitDir);
		final src = [
			"package unit;",
			"",
			"import haxe.Serializer;",
			"import haxe.Unserializer;",
			"",
			"class Main {",
			"  static function main() {",
			"    var encoded = Serializer.run({name: \"hx\", count: 3});",
			"    var decoded:Dynamic = Unserializer.run(encoded);",
			"    Sys.println(decoded.name + \":\" + decoded.count);",
			"  }",
			"}",
		].join("\n");
		File.saveContent(Path.join([haxeDir, "Serializer.hx"]), [
			"package haxe;",
			"extern class Serializer {",
			"  static function run(value:Dynamic):String;",
			"}",
		].join("\n"));
		File.saveContent(Path.join([haxeDir, "Unserializer.hx"]), [
			"package haxe;",
			"extern class Unserializer {",
			"  static function run(value:String):Dynamic;",
			"}",
		].join("\n"));
		File.saveContent(Path.join([unitDir, "Main.hx"]), src);
		final resolved = ResolverStage.parseProjectRoots([srcDir], ["unit.Main"], new StringMap<String>());
		final index = TyperIndex.build(resolved);
		final loader = new ModuleLoader([srcDir], new StringMap<String>(), index, function(_typePath:String):Bool {
			return false;
		});
		loader.markResolvedAlready(resolved);
		final typed = new Array<TypedModule>();
		for (module in resolved)
			typed.push(TyperStage.typeResolvedModule(module, index, loader));
		final program = MacroStage.expandProgram(typed, []);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "unit.Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "\\haxe\\Serializer::run", "PHP imported haxe.Serializer calls should target the namespaced runtime class");
		assertContains(content, "\\haxe\\Unserializer::run", "PHP imported haxe.Unserializer calls should target the namespaced runtime class");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP imported haxe.Serializer/Unserializer support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "hx:3\n", "generated PHP imported haxe.Serializer/Unserializer output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpPoint3StringEqualityRuntimeSupport():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_point3_string_equality_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpPoint3StringEqualityRuntimeProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "__hxhx_equals(\"(2,3,4)\", $point)", "PHP string-to-Point3 equality should lower through the equality helper");
		assertContains(content, "__hxhx_equals($point, \"(2,3,4)\")", "PHP Point3-to-string equality should lower through the equality helper");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP Point3/string equality support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "true\ntrue\nfalse\n", "generated PHP Point3/string equality output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpPoint3UnaryScaleRuntimeSupport():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_point3_unary_scale_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpPoint3UnaryScaleRuntimeProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "public function toString() {", "PHP Point3 payload classes should expose abstract-style toString");
		assertContains(content, "$neg = __hxhx_neg($point);", "PHP Point3 unary minus should lower through the abstract-aware negation helper");
		assertContains(content, "__hxhx_to_string_value($neg)",
			"PHP Point3-style toString calls should lower through the abstract-aware string conversion helper");
		assertContains(content, "if (__hxhx_is_point3($value)) return __hxhx_mul($value, -1);",
			"PHP negation helper should dispatch Point3-style abstract payloads through scalar multiplication");
		assertContains(content, "return -__hxhx_numeric_value($value);", "PHP negation fallback should unwrap non-Point3 abstract payloads");
		assertContains(content, "\"MyPoint3\" => [\"toString\" => true]", "PHP reflection policy should expose synthesized Point3-style toString fields");
		assertContains(content, "\"MyVector\" => [\"toString\" => true]", "PHP reflection policy should expose abstract-view MyVector toString fields");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP Point3 unary scale support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "true\n(1,2,3)\n(-1,-2,-3)\ntoString|x|y|z\nget_x|get_y|set_x|set_y|set_z|toString|y|z\n",
				"generated PHP Point3 unary scale output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpLambdaListRuntimeSupport():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_lambda_list_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpLambdaListRuntimeProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "public static function list($value)", "PHP Lambda helper should expose list");
		assertContains(content, "$list = Lambda::list([\"a\", \"b\", \"c\"]);", "PHP Lambda.list calls should lower as static helper calls");
		assertContains(content, "$manual->push(\"b\")", "PHP List.push should call the List runtime method");
		assertNotContains(content, "__hxhx_array_push($manual", "PHP List.push should not route through the Array.push helper");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP Lambda.list support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "3\na\nc\na#b#c\n3\n", "generated PHP Lambda.list should preserve list order and length, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpGenericStackRuntimeSupport():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_generic_stack_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpGenericStackRuntimeProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class GenericStack", "PHP source backend should emit haxe.ds.GenericStack runtime support");
		assertContains(content, "$stack = new haxe\\ds\\GenericStack();", "PHP haxe.ds.GenericStack construction should target the namespace shim");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP GenericStack support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "true\n2\n{2,1}\n2\n1\n", "generated PHP GenericStack output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpMapKeysIteratorRuntimeSupport():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_map_keys_iterator_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final src = [
			"class Main {",
			"  static function main() {",
			"    var sm = new haxe.ds.StringMap<Int>();",
			"    sm.set(\"b\", 2);",
			"    var keyIt = sm.keys();",
			"    Sys.println(Std.string(keyIt.hasNext()));",
			"    Sys.println(keyIt.next());",
			"    Sys.println(Std.string(keyIt.hasNext()));",
			"    sm.set(\"a\", 1);",
			"    var keys = Lambda.array(sm.keys());",
			"    keys.sort(Reflect.compare);",
			"    Sys.println(keys.join(\"#\"));",
			"    var values = Lambda.array(sm);",
			"    values.sort(Reflect.compare);",
			"    Sys.println(values.join(\"#\"));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		final program = MacroStage.expandProgram([typed], []);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class __HxArrayIterator implements \\IteratorAggregate", "PHP array iterator should also be foreach-compatible");
		assertContains(content, "return new __HxArrayIterator(array_values($this->keys));", "PHP Map.keys should return an iterator-compatible wrapper");
		assertContains(content, "$keyIt = $sm->keys();", "PHP Map.keys calls should keep the map iterator shape");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP Map.keys iterator support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "true\nb\nfalse\na#b\n1#2\n", "generated PHP Map.keys iterator output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpMetaRuntimeSupport():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_meta_support_" + Std.string(Date.now().getTime()));
		final srcDir = Path.join([tmpRoot, "src"]);
		final haxeDir = Path.join([srcDir, "haxe"]);
		final rttiDir = Path.join([haxeDir, "rtti"]);
		final unitDir = Path.join([srcDir, "unit"]);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(rttiDir);
		FileSystem.createDirectory(unitDir);
		File.saveContent(Path.join([rttiDir, "Meta.hx"]), [
			"package haxe.rtti;",
			"extern class Meta {",
			"  static function getFields(cls:Dynamic):Dynamic;",
			"  static function getStatics(cls:Dynamic):Dynamic;",
			"  static function getType(cls:Dynamic):Dynamic;",
			"}",
		].join("\n"));
		File.saveContent(Path.join([unitDir, "Main.hx"]), [
			"package unit;",
			"",
			"import haxe.rtti.Meta;",
			"",
			"@enumMeta private enum E {",
			"  @:a A;",
			"  @:b(0) B;",
			"}",
			"",
			"@:typeMeta(\"classArg\")",
			"class Tagged {",
			"  @:instanceMeta(\"fieldArg\") public var value:Int;",
			"  @:methodMeta public function method():Void {}",
			"  @:staticMeta(7) public static var count:Int = 0;",
			"  @:empty() @:_int(-45) @:complex([{ x: 0, y: \"hello\", z: -1.48, b: true, k: null }]) public static var foo:Int = 0;",
			"  @:staticMethodMeta public static function helper():Void {}",
			"  @:new public function new() {}",
			"}",
			"",
			"class Main {",
			"  static function sortedNames(value:Dynamic):String {",
			"    var fields = Reflect.fields(value);",
			"    fields.sort(Reflect.compare);",
			"    return fields.join(\"#\");",
			"  }",
			"  static function main() {",
			"    Sys.println(Std.string(Meta.getFields(null) != null));",
			"    Sys.println(Std.string(Meta.getStatics(null) != null));",
			"    Sys.println(Std.string(Meta.getType(null) != null));",
			"    var a = 1;",
			"    var exprMetaA:Dynamic = getMeta(@foo a);",
			"    Sys.println(exprMetaA.name);",
			"    Sys.println(exprMetaA.args.length);",
			"    var exprMetaB:Dynamic = getMeta(@bar(\"1\", \"foo\") null);",
			"    Sys.println(exprMetaB.name);",
			"    Sys.println(exprMetaB.args[0]);",
			"    Sys.println(exprMetaB.args[1]);",
			"    var exprMetaC:Dynamic = getMeta(@foo (\"1\"));",
			"    Sys.println(exprMetaC.args.length);",
			"    var exprMetaD:Dynamic = getMeta(@foo(\"1\") \"2\");",
			"    Sys.println(exprMetaD.args.length);",
			"    var cls = Type.resolveClass(\"unit.Tagged\");",
			"    var typeMeta:Dynamic = Meta.getType(cls);",
			"    Sys.println(typeMeta.typeMeta[0]);",
			"    var statics:Dynamic = Meta.getStatics(cls);",
			"    Sys.println(sortedNames(statics));",
			"    Sys.println(statics.count.staticMeta[0]);",
			"    Sys.println(sortedNames(statics.foo));",
			"    Sys.println(Std.string(statics.foo.empty == null));",
			"    Sys.println(Std.string(statics.foo._int));",
			"    var complex:Dynamic = statics.foo.complex[0][0];",
			"    Sys.println(sortedNames(complex));",
			"    Sys.println(Std.string(complex.x));",
			"    Sys.println(complex.y);",
			"    Sys.println(Std.string(complex.z));",
			"    Sys.println(Std.string(complex.b));",
			"    Sys.println(Std.string(complex.k == null));",
			"    var fields:Dynamic = Meta.getFields(cls);",
			"    Sys.println(sortedNames(fields));",
			"    Sys.println(fields.value.instanceMeta[0]);",
			"    Sys.println(sortedNames(fields._));",
			"    var enumCls = Type.resolveEnum(\"unit.E\");",
			"    var enumTypeMeta:Dynamic = Meta.getType(enumCls);",
			"    Sys.println(sortedNames(enumTypeMeta));",
			"    Sys.println(Std.string(enumTypeMeta.enumMeta == null));",
			"    var enumFields:Dynamic = Meta.getFields(enumCls);",
			"    Sys.println(sortedNames(enumFields));",
			"    Sys.println(sortedNames(enumFields.A));",
			"    Sys.println(Std.string(enumFields.A.a == null));",
			"    Sys.println(enumFields.B.b[0]);",
			"  }",
			"}",
		].join("\n"));
		final resolved = ResolverStage.parseProjectRoots([srcDir], ["unit.Main"], new StringMap<String>());
		final index = TyperIndex.build(resolved);
		final loader = new ModuleLoader([srcDir], new StringMap<String>(), index, function(_typePath:String):Bool {
			return false;
		});
		loader.markResolvedAlready(resolved);
		final typed = new Array<TypedModule>();
		for (module in resolved)
			typed.push(TyperStage.typeResolvedModule(module, index, loader));
		final program = MacroStage.expandProgram(typed, []);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "unit.Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "namespace haxe\\rtti", "PHP source backend should emit haxe.rtti namespace runtime support");
		assertContains(content, "class Meta {", "PHP source backend should emit haxe.rtti.Meta runtime support");
		assertContains(content, "function __hxhx_meta_type($cls)", "PHP source backend should emit metadata payload tables");
		assertContains(content, "\"unit.Tagged\" => [\"typeMeta\" => [\"classArg\"]]", "PHP metadata table should include class metadata");
		assertContains(content, "\"unit.Main.E\" => [\"enumMeta\" => null]", "PHP metadata table should include module-private enum metadata aliases");
		assertContains(content, "\\haxe\\rtti\\Meta::getFields", "PHP imported haxe.rtti.Meta calls should target the namespaced runtime class");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP haxe.rtti.Meta support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "true\ntrue\ntrue\nfoo\n0\nbar\n1\nfoo\n0\n1\nclassArg\ncount#foo#helper\n7\n_int#complex#empty\ntrue\n[-45]\nb#k#x#y#z\n0\nhello\n-1.48\ntrue\ntrue\n_#method#value\nfieldArg\nnew\nenumMeta\ntrue\nA#B\na\ntrue\n0\n",
				"generated PHP haxe.rtti.Meta output mismatch, got:\n"
				+ run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpReflectMakeVarArgs():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_reflect_make_var_args_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpReflectMakeVarArgsProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "public static function makeVarArgs($f)", "PHP Reflect helper should support makeVarArgs");
		assertContains(content, "return function(...$args) use ($f) { return $f($args); };",
			"PHP Reflect.makeVarArgs should pass variadic arguments as one Haxe array argument");
		assertContains(content, "$g = Reflect::makeVarArgs($f);", "PHP Reflect.makeVarArgs should lower as a static helper call");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP Reflect.makeVarArgs support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "5\n", "generated PHP Reflect.makeVarArgs should preserve varargs semantics, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpReflectFields():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_reflect_fields_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final src = [
			"class Main {",
			"  static function sortedNames(value:Dynamic):String {",
			"    var fields = Reflect.fields(value);",
			"    fields.sort(Reflect.compare);",
			"    return fields.join(\",\");",
			"  }",
			"  static function main() {",
			"    Sys.println(sortedNames({name: \"hx\", count: 2}));",
			"    var parsed = haxe.Json.parse(\"{\\\"z\\\":1,\\\"a\\\":2}\");",
			"    Sys.println(sortedNames(parsed));",
			"    Sys.println(Reflect.fields(null).length);",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		final program = MacroStage.expandProgram([typed], []);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "public static function fields($object)", "PHP Reflect helper should expose fields");
		assertContains(content, "get_object_vars($object)", "PHP Reflect.fields should enumerate dynamic object fields");
		assertContains(content, "Reflect::fields($value)", "PHP Reflect.fields should lower as a static helper call");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP Reflect.fields support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "count,name\na,z\n0\n", "generated PHP Reflect.fields output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpReflectCallMethod():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_reflect_call_method_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final src = [
			"class Helper {",
			"  final prefix:String;",
			"  public function new(prefix:String) this.prefix = prefix;",
			"  public function join(left:String, right:String):String return prefix + left + right;",
			"}",
			"class Main {",
			"  static function main() {",
			"    var helper = new Helper(\"h\");",
			"    var method = Reflect.field(helper, \"join\");",
			"    Sys.println(Reflect.callMethod(helper, method, [\"x\", \"y\"]));",
			"    var add = function(a:Int, b:Int) return a + b;",
			"    Sys.println(Reflect.callMethod(null, add, [4, 5]));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		final program = MacroStage.expandProgram([typed], []);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "public static function callMethod($object, $method, $args)", "PHP Reflect helper should expose callMethod");
		assertContains(content, "return $method(...array_values($args));", "PHP Reflect.callMethod should splat Haxe array arguments");
		assertContains(content, "Reflect::callMethod($helper, $method, [\"x\", \"y\"])", "PHP Reflect.callMethod should lower as a static helper call");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP Reflect.callMethod support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "hxy\n9\n", "generated PHP Reflect.callMethod output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpReflectPropertyAccess():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_reflect_property_access_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpReflectPropertyAccessProgram(), new BackendContext(tmpRoot, null, "unit.Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "public static function getProperty($object, $field)", "PHP Reflect helper should expose getProperty");
		assertContains(content, "public static function setProperty($object, $field, $value)", "PHP Reflect helper should expose setProperty");
		assertContains(content, "$box->get_x()", "PHP instance property reads should call generated getters");
		assertContains(content, "$box->set_x(10);", "PHP instance property writes should call generated setters");
		assertContains(content, "$iface->get_x()", "PHP interface-typed property reads should call generated getters");
		assertContains(content, "$iface->set_x(13);", "PHP interface-typed property writes should call generated setters");
		assertContains(content, "$dup__hx_scope_1->get_x()", "PHP redeclared interface-typed property reads should keep getter lowering");
		assertContains(content, "public function run()", "PHP support class method should be emitted for instance-property coverage");
		assertContains(content, "PropBox::__init__();", "PHP static __init__ should run before generated main code");
		assertContains(content, "PropBox::set_STAT_X(3);", "PHP static __init__ fallback should preserve setter assignments");
		assertContains(content, "PropBox::set_STAT_X(4);", "PHP static property writes should call generated setters");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP Reflect property support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "5\n5\n10\n12\n5\n13\n14\n5\n5\n6\n6\n8\n18\n5\n16\n",
				"generated PHP Reflect property support output mismatch, got:\n" + run.stdout);
		}
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
			"  public function addCase(test:Dynamic, setup = \"setup\", teardown = \"teardown\", prefix = \"test\", ?pattern:Dynamic, setupAsync = \"setupAsync\", teardownAsync = \"teardownAsync\", ?nullableInt:Null<Int> = 5, ?nullableFloat:Null<Float> = 6) {}",
			"}"
		].join("\n");
		final encoded = [
			"hxhx_frontend_v=2",
			protocolLine("class", "Runner"),
			"ast static_main 0",
			protocolLine("method",
				"addCase|public|0|test,setup,teardown,prefix,?pattern,setupAsync,teardownAsync,nullableInt,nullableFloat|Void|||test:Dynamic,pattern:Dynamic,nullableInt:Null,nullableFloat:Null|"),
			"ok"
		].join("\n");
		final decl = ParserStageNativeDecode.decodeNativeProtocol(encoded, source);
		final functions = HxClassDecl.getFunctions(HxModuleDecl.getMainClass(decl));
		assertTrue(functions.length == 1, "native protocol should decode the source-backed addCase method");
		final args = HxFunctionDecl.getArgs(functions[0]);
		assertTrue(args.length == 9, "native protocol should preserve source-backed addCase arity");
		assertTrue(HxFunctionArg.getIsOptional(args[1]), "native protocol should recover defaulted args as omittable from source");
		assertTrue(HxFunctionArg.getDefaultValueText(args[1]) == "\"setup\"", "native protocol should recover the setup default text");
		assertTrue(HxFunctionArg.getIsOptional(args[4]), "native protocol should preserve explicit optional args from payload/source");
		assertTrue(HxFunctionArg.getDefaultValueText(args[5]) == "\"setupAsync\"", "native protocol should recover later defaults after optional args");
		assertTrue(HxFunctionArg.getTypeHint(args[7]) == "Null<Int>", "native protocol should recover source generic Null<Int> over erased payload Null");
		assertTrue(HxFunctionArg.getTypeHint(args[8]) == "Null<Float>", "native protocol should recover source generic Null<Float> over erased payload Null");
	}

	static function assertNativeProtocolConstructorDefaultArgSourceDecode():Void {
		final source = [
			"class Earlier {",
			"  public function new() {}",
			"}",
			"class BaseConstrOpt {",
			"  public function new(s:String = \"test\", i:Int = -5, b:Bool = true) {}",
			"}"
		].join("\n");
		final encoded = [
			"hxhx_frontend_v=2",
			protocolLine("class", "BaseConstrOpt"),
			"ast static_main 0",
			protocolLine("method", "new|public|0|s,i,b|Void|||s:String,i:Int,b:Bool|"),
			"ok"
		].join("\n");
		final decl = ParserStageNativeDecode.decodeNativeProtocol(encoded, source);
		final functions = HxClassDecl.getFunctions(HxModuleDecl.getMainClass(decl));
		assertTrue(functions.length == 1, "native protocol should decode the source-backed constructor");
		final args = HxFunctionDecl.getArgs(functions[0]);
		assertTrue(args.length == 3, "native protocol should preserve constructor arity");
		assertTrue(HxFunctionArg.getDefaultValueText(args[0]) == "\"test\"",
			"native protocol should recover the matching constructor string default instead of the first constructor in the source");
		assertTrue(HxFunctionArg.getDefaultValueText(args[1]) == "-5", "native protocol should recover the matching constructor int default");
		assertTrue(HxFunctionArg.getDefaultValueText(args[2]) == "true", "native protocol should recover the matching constructor bool default");
		final scannedClasses = ParserStageScanHelpers.scanModuleLocalHelperClasses(source, "Earlier");
		var sawScannedStringDefault = false;
		for (cls in scannedClasses) {
			if (HxClassDecl.getName(cls) != "BaseConstrOpt")
				continue;
			for (fn in HxClassDecl.getFunctions(cls)) {
				if (HxFunctionDecl.getName(fn) != "new")
					continue;
				final scannedArgs = HxFunctionDecl.getArgs(fn);
				sawScannedStringDefault = scannedArgs.length == 3 && HxFunctionArg.getDefaultValueText(scannedArgs[0]) == "\"test\"";
			}
		}
		assertTrue(sawScannedStringDefault, "source helper scanner should preserve string defaults on constructors");
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
		assertContains(content, "function __hxhx_add_string($value, $seen = null)", "PHP plus helper should include Haxe stringification support");
		assertContains(content, "if ($value === null) return \"null\";", "PHP plus helper should stringify null like Haxe");
		assertContains(content, "if ($value instanceof __HxArray) $value = $value->toArray();", "PHP plus helper should unwrap Haxe arrays");
		assertContains(content, "return \"[\" . implode(\",\", $parts) . \"]\";", "PHP plus helper should recursively stringify arrays like Haxe");
		assertContains(content, "foreach (get_object_vars($value) as $key => $fieldValue)", "PHP plus helper should stringify anonymous objects like Haxe");
		assertContains(content, "__hxhx_add(__hxhx_add(1, 2), \"\")",
			"PHP plus lowering should preserve left-associative numeric addition before string conversion");
		assertContains(content, "__hxhx_add(1, __hxhx_add(2, \"\"))", "PHP plus lowering should preserve explicit string-concat grouping");
		assertContains(content, "__hxhx_add(null, \"x\")", "PHP null-left string plus should lower through Haxe helper");
		assertContains(content, "__hxhx_add(\"x\", null)", "PHP null-right string plus should lower through Haxe helper");
		assertContains(content, "__hxhx_add(\"\", new __HxAnon([]))", "PHP empty anonymous object string plus should lower through Haxe helper");
		assertContains(content, "__hxhx_add(\"\", new __HxAnon([\"a\" => 1]))", "PHP anonymous object string plus should lower through Haxe helper");
		assertContains(content, "__hxhx_add(\"\", [1, 2])", "PHP array string plus should lower through Haxe helper");
		assertContains(content, "__hxhx_add(\"\", [[1], [2, 3]])", "PHP nested array string plus should lower through Haxe helper");
		assertContains(content, "echo __hxhx_add_string([\"x\"]) . PHP_EOL;", "PHP Std.string on array literals should use Haxe stringification");
		assertContains(content, "function() use (&$s)", "PHP local functions that mutate outer locals should capture by reference");
		assertContains(content, "function($__hxhx_lambda_seq_0) use (&$s)", "PHP local function statement continuations should see call-argument mutations");
		assertContains(content, "$s = __hxhx_add($s, \"b\")", "PHP string-like add-assign should use Haxe plus semantics");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpAnonymousToStringField():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_anon_to_string_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final src = [
			"class Main {",
			"  static function main() {",
			"    var x = { toString: function() return \"foo\" };",
			"    Sys.println(Std.string(x));",
			"    Sys.println(x.toString());",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		final program = MacroStage.expandProgram([typed], []);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "$toString = $value->toString;", "PHP Haxe stringification should inspect anonymous toString fields");
		assertContains(content, "$result = __hxhx_add_string($toString(), $seen);", "PHP Haxe stringification should call anonymous callable toString fields");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP anonymous toString field fixture should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "foo\nfoo\n", "generated PHP anonymous toString field output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpCyclicObjectStringification():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_cyclic_string_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final src = ["class Main {", "  static function main() {", "  }", "}",].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		final program = MacroStage.expandProgram([typed], []);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "function __hxhx_add_string($value, $seen = null)", "PHP Haxe stringification should carry recursion state");
		assertContains(content, "if ($seen->contains($value)) return \"{...}\";", "PHP Haxe stringification should stop cyclic object recursion");
		assertContains(content, "__hxhx_add_string($fieldValue, $seen)", "PHP Haxe stringification should pass recursion state through object fields");
		if (commandExists("php")) {
			File.saveContent(outputPath, content + [
				"",
				"namespace {",
				"  $node = new \\stdClass();",
				"  $node->name = \"root\";",
				"  $node->next = $node;",
				"  echo \\__hxhx_add_string($node) . PHP_EOL;",
				"}",
				"",
			].join("\n"));
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP cyclic object stringification fixture should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "{name: root, next: {...}}\n", "generated PHP cyclic object stringification output mismatch, got:\n" + run.stdout);
		}
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
		assertContains(content,
			"return new __HxAnon([\"__hx_enum\" => \"MyEnum\", \"__hx_ctor\" => \"C\", \"__hx_index\" => 0, \"__hx_params\" => [$i, $s]]);",
			"PHP scanned enum constructors should return Haxe-like runtime enum objects");
		assertContains(content, "public static $__hx_enum_ctors = [\"A\", \"B\", \"With\"];",
			"PHP scanned enums should retain constructor order for indexed unserialization");
		assertContains(content,
			"return new __HxAnon([\"__hx_enum\" => \"MultiEnum\", \"__hx_ctor\" => \"With\", \"__hx_index\" => 2, \"__hx_params\" => [$i]]);",
			"PHP scanned enum constructors should retain their constructor index");
		assertContains(content, "return MyEnum::C(...$__hxhx_args);", "PHP enum constructor values should lower to callable closures");
		assertContains(content, "$unqualifiedNested = A::D(A::$A);", "PHP unqualified enum constructor calls should resolve through the owning enum helper");
		assertContains(content, "Type::enumEq($latest, ELatest::$Same)",
			"PHP duplicate unqualified enum constructors should use peer enum type context when available");
		assertContains(content, "$box = ExprBox::EConst(ConstantBox::CFloatBox(\"12\"));",
			"PHP bare enum constructor calls should prefer current-module constructors over imported ambiguous names");
		assertContains(content, "public static function EBinop($op, $left, $right)",
			"PHP scanned generic enum constructors should remain payload constructors");
		assertContains(content, "property_exists($__hxhx_switch->__hx_params[0], \"__hx_ctor\")",
			"PHP no-arg enum patterns should inspect Haxe enum objects instead of comparing against raw strings");
		assertContains(content, "function() use ($op, $left, $right)",
			"PHP switch-expression closures should capture branch-only values referenced outside the scrutinee");
		assertContains(content, "Type::enumEq($e2, MyEnum::C(1, \"x\"))", "PHP Type.enumEq should remain a static runtime call");
		assertContains(content, "echo __hxhx_add_string($e) . PHP_EOL;", "PHP Std.string on enum values should use Haxe stringification");
		assertContains(content, "echo __hxhx_add_string([$e]) . PHP_EOL;", "PHP Std.string on enum arrays should recursively stringify enum values");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP enum constructor values should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "C(0,h)\n[C(0,h)]\nC(1,x)\n1\nC(2,y)\n1\nid(3)\n1\n4z\nSE_A\n1\nWith(9)\n1\nA\n1\nSE_A\n1\nD(A)\n1\nSame\n1\nEConst(CFloatBox(12))\n20\n",
				"generated PHP enum constructor values should stringify correctly, got:\n"
				+ run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpStdEnumAbstractSupport():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_std_enum_abstract_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpStdEnumAbstractSupportProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class KeywordKind {", "PHP std enum abstract helpers referenced by generated code should be emitted");
		assertContains(content, "public static $Implements = \"implements\";", "PHP std enum abstract helper fields should preserve their literal values");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP std enum abstract helper should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "implements\n", "generated PHP std enum abstract helper output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpStdIoErrorEnumSupport():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_std_io_error_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpStdIoErrorEnumSupportProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class Error_ {", "PHP haxe.io.Error support should avoid the built-in PHP Error class");
		assertContains(content, "public static $OutsideBounds = null;", "PHP haxe.io.Error should emit the OutsideBounds carrier slot");
		assertContains(content, "Error_::$OutsideBounds = new __HxAnon", "PHP haxe.io.Error should initialize the OutsideBounds enum value");
		assertContains(content, "Error_::$OutsideBounds", "PHP haxe.io.Error references should use the safe support carrier name");
		assertNotContains(content, "Error::$OutsideBounds", "PHP haxe.io.Error references should not target PHP's built-in Error class");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP haxe.io.Error support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "OutsideBounds\n1\nCustom(disk)\n", "generated PHP haxe.io.Error output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpStdIoErrorRuntimeExceptions():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_std_io_error_runtime_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpStdIoErrorRuntimeExceptionProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "function __hxhx_io_error($name)", "PHP runtime should expose haxe.io.Error resolution for IO failures");
		assertContains(content, "\\ValueException::thrown(__hxhx_io_error($name))", "PHP IO runtime failures should route through haxe.io.Error values");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP haxe.io.Error runtime failures should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "write-bounds:OutsideBounds\n1\nwrite-overflow:Overflow\n1\nread-bounds:OutsideBounds\n1\n",
				"generated PHP haxe.io.Error runtime failure output mismatch, got:\n" + run.stdout);
		}
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
		assertContains(content, "return (__hxhx_add(TestOps::getA()->a, 1) >> 1);",
			"PHP unqualified same-class static helper calls should lower through a class-qualified static call");
		assertNotContains(content, "$getA()", "PHP same-class static helper calls should not lower as local callable variables");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpSameClassStaticInlineCall():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_same_class_static_inline_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpSameClassStaticInlineCallProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "public static function foo($x)", "PHP should emit the same-class static helper method");
		assertContains(content, "__hxhx_mul(2, Main::foo($x))", "PHP same-class static helper calls should not lower as local variable calls");
		assertContains(content, "__hxhx_neg(Main::foo($x))", "PHP unary expressions should preserve same-class static helper calls");
		assertNotContains(content, "$foo($x)", "PHP same-class static helper calls should not emit undefined local callable variables");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP same-class static inline helper should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "16\n-8\n", "generated PHP same-class static inline helper output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpStaticFunctionFieldCall():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_static_function_field_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpStaticFunctionFieldCallProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "public static $add = null;", "PHP static function fields should use a legal class property default");
		assertContains(content, "Main::$add = function($x, $y)", "PHP static function fields should initialize after class declaration");
		assertContains(content, "(Main::$add)(2, 3)", "PHP static function field calls should dispatch through the property callable");
		assertNotContains(content, "Main::add(2, 3)", "PHP static function field calls should not use static method syntax");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP static function field call should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "5\n", "generated PHP static function field output mismatch, got:\n" + run.stdout);
		}
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
		assertContains(content, "__hxhx_add_string((!__hxhx_equals((1 & 32768), 0)))", "PHP bitwise/equality lowering should preserve explicit left grouping");
		assertContains(content, "__hxhx_add_string((!__hxhx_equals(0, (1 & 32768))))", "PHP bitwise/equality lowering should preserve explicit right grouping");
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
		assertContains(content, "__hxhx_mod(5.0, 0.0)", "PHP modulo-by-zero expressions should lower through the helper for NaN behavior");
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
		assertContains(content, "public static function random()", "PHP Math shim should support random");
		assertContains(content, "return floor($value + 0.5);", "PHP Math.round should match Haxe half-up-toward-positive behavior");
		assertContains(content, "Math::isNaN(__hxhx_mod(5.0, 0.0))", "PHP Math.isNaN should be callable with modulo-derived NaN");
		assertContains(content, "Math::floor((-1.5))", "PHP Math.floor should lower to the runtime shim");
		assertContains(content, "Math::ceil((-1.5))", "PHP Math.ceil should lower to the runtime shim");
		assertContains(content, "Math::round((-1.5))", "PHP Math.round should lower to the runtime shim");
		assertContains(content, "Math::ffloor((-10000000000.7))", "PHP Math.ffloor should lower to the runtime shim");
		assertContains(content, "Math::fceil((-10000000000.7))", "PHP Math.fceil should lower to the runtime shim");
		assertContains(content, "Math::fround((-10000000000.7))", "PHP Math.fround should lower to the runtime shim");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpMathRandomRuntime():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_math_random_runtime_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpMathRandomRuntimeProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "Math::random()", "PHP Math.random should lower to the runtime shim");
		assertContains(content, "return mt_rand() / (mt_getrandmax() + 1.0);", "PHP Math.random should return a Float in the half-open [0, 1) range");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP Math.random should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "true\ntrue\n", "generated PHP Math.random output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpStdRandomRuntime():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_std_random_runtime_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpStdRandomRuntimeProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "public static function random($x)", "PHP Std shim should support random");
		assertContains(content, "return $limit <= 0 ? 0 : mt_rand(0, $limit - 1);", "PHP Std.random should preserve zero and positive bounds");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP Std.random should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "0\ntrue\n", "generated PHP Std.random output mismatch, got:\n" + run.stdout);
		}
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
		assertContains(content, "__hxhx_string_index_of(__hxhx_message_field($exc), \"Unclosed node <flow>\")",
			"PHP exception message indexOf should lower through the string helper");
		assertNotContains(content, "__hxhx_add(\"bla\", \"x\")->indexOf", "PHP string-like receivers should not emit object-method calls on raw strings");
		assertNotContains(content, "\"abc\"->split", "PHP string literals should not emit object-method split calls");
		assertNotContains(content, "\"abc\"->charCodeAt", "PHP string literals should not emit object-method charCodeAt calls");
		assertNotContains(content, "\"a\"->code", "PHP string literal .code should not emit property access on raw strings");
		assertNotContains(content, "$str->indexOf", "PHP string variables should not emit object-method indexOf calls");
		assertNotContains(content, "$str->lastIndexOf", "PHP string variables should not emit object-method lastIndexOf calls");
		assertNotContains(content, "$str->charCodeAt", "PHP string variables should not emit object-method charCodeAt calls");
		assertNotContains(content, "$str->substr", "PHP string variables should not emit object-method substr calls");
		assertNotContains(content, "__hxhx_message_field($exc)->indexOf", "PHP exception message indexOf should not emit object-method calls on strings");
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
		assertContains(content, "\"__hx_ctor\" => \"OpArrow\"", "PHP macro map entries should lower to OpArrow nodes");
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
		assertContains(content, "__hx_ctor=\"OpArrow\"", "Python macro map entries should lower to OpArrow nodes");
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
		assertContains(content, "$a = \\haxe\\Int64::ofInt(32);", "PHP Int64 literal extension calls should lower to qualified static calls");
		assertContains(content, "$b = \\haxe\\Int64::ofInt((-4));", "PHP negative Int64 literal extension calls should lower to qualified static calls");
		assertContains(content, "$c = __hxhx_add(__hxhx_int_literal(\"3000000000000\", \"i64\"), \"\");",
			"PHP i64 decimal suffix literals should preserve raw text before runtime string conversion");
		assertContains(content, "$d = __hxhx_add(__hxhx_int_literal(\"0xFFFFFFFFFFFFFFFF\", \"i64\"), \"\");",
			"PHP i64 hex suffix literals should preserve raw text before runtime string conversion");
		assertContains(content, "$e = __hxhx_int_literal(\"0xFFFFFFFF\", \"u32\");", "PHP u32 hex suffix literals should preserve raw text");
		assertContains(content, "$f = 4294967295;", "PHP UInt casts of signed hex literals should render as unsigned 32-bit values");
		assertContains(content, "$g = __hxhx_int_literal(\"0xFFFFFFFF\", \"i32\");", "PHP i32 hex suffix literals should preserve raw text");
		assertContains(content, "$h = -1593839907;", "PHP unsuffixed large hex literals should emit signed Haxe Int values");
		assertNotContains(content, "__hxhx_cast(-1, \"UInt\")", "PHP UInt casts should not lower through nominal runtime casts");
		assertContains(content, "if ($suffix === \"\" || $suffix === \"i32\")", "PHP runtime should normalize signed Int/i32 literals");
		assertContains(content, "function __hxhx_int32_value($value)", "PHP runtime should normalize high-bit integer equality as Haxe Int");
		assertContains(content, "function __hxhx_int_literal($text, $suffix)", "PHP runtime should include numeric suffix literal normalization support");
		assertContains(content, "function __hxhx_int64_literal($text, $suffix)", "PHP runtime should include typed Int64 literal construction support");
		assertNotContains(content, "32->ofInt()", "PHP should not emit instance calls on integer literals");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpHaxeInt64RuntimeSupport():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_haxe_int64_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final src = [
			"import haxe.Int64.*;",
			"using haxe.Int64;",
			"class Main {",
			"  static function main() {",
			"    var a = haxe.Int64.make(10, 0xFFFFFFFF);",
			"    Sys.println(a.high);",
			"    Sys.println(a.low);",
			"    var c = Int64.make(2, 3);",
			"    Sys.println(c.high);",
			"    Sys.println(c.low);",
			"    var capturedMake = Int64.make;",
			"    var captured = capturedMake(3, 4);",
			"    Sys.println(captured.high);",
			"    Sys.println(captured.low);",
			"    var imported = make(4, 5);",
			"    Sys.println(imported.high);",
			"    Sys.println(imported.low);",
			"    var importedMake = make;",
			"    var importedCapture = importedMake(5, 6);",
			"    Sys.println(importedCapture.high);",
			"    Sys.println(importedCapture.low);",
			"    Sys.println(compare(captured, imported));",
			"    var capturedOfInt = haxe.Int64.ofInt;",
			"    Sys.println(haxe.Int64.toStr(capturedOfInt(-5)));",
			"    Sys.println(haxe.Int64.toStr(neg(ofInt(6))));",
			"    var capturedNeg = neg;",
			"    Sys.println(haxe.Int64.toStr(capturedNeg(ofInt(7))));",
			"    Sys.println(Std.parseInt(\"65\"));",
			"    Sys.println(Std.parseInt(\"65.3\"));",
			"    Sys.println(Std.parseInt(\"0xFF\"));",
			"    Sys.println(Std.parseFloat(\"12.5\"));",
			"    Sys.println(haxe.Int64.toStr(fromFloat(12.0)));",
			"    var capturedFromFloat = fromFloat;",
			"    Sys.println(haxe.Int64.toStr(capturedFromFloat(-13.0)));",
			"    Sys.println(StringTools.hex(-8));",
			"    Sys.println(StringTools.hex(0x21));",
			"    Sys.println(StringTools.hex(0x54, 4));",
			"    Sys.println((ofInt(3).add(ofInt(2))).compare(ofInt(5)));",
			"    Sys.println(haxe.Int64.toStr((ofInt(3).add(ofInt(2))).sub(ofInt(1))));",
			"    var dynInt64:Dynamic = ofInt(3);",
			"    Sys.println(dynInt64.compare(ofInt(3)));",
			"    Sys.println(dynInt64.add(ofInt(2)).compare(ofInt(5)));",
			"    var b = haxe.Int64.ofInt(-1);",
			"    Sys.println(b.high);",
			"    Sys.println(b.low);",
			"    Sys.println(b.toInt());",
			"    var d:haxe.Int64 = 1;",
			"    Sys.println(d.toInt());",
			"    var boxed:Array<haxe.Int64> = [];",
			"    boxed.push(1);",
			"    Sys.println(boxed[0].high);",
			"    Sys.println(boxed[0].low);",
			"    var inc:haxe.Int64 = 0;",
			"    inc++;",
			"    Sys.println(haxe.Int64.toStr(inc));",
			"    ++inc;",
			"    Sys.println(haxe.Int64.toStr(inc));",
			"    var oldInc = inc++;",
			"    Sys.println(haxe.Int64.toStr(oldInc));",
			"    Sys.println(haxe.Int64.toStr(inc));",
			"    inc--;",
			"    Sys.println(haxe.Int64.toStr(inc));",
			"    --inc;",
			"    Sys.println(haxe.Int64.toStr(inc));",
			"    var oldDec = inc--;",
			"    Sys.println(haxe.Int64.toStr(oldDec));",
			"    Sys.println(haxe.Int64.toStr(inc));",
			"    var e:haxe.Int64 = 47244640255i64;",
			"    Sys.println(e.high);",
			"    Sys.println(e.low);",
			"    var f:haxe.Int64 = 0x7FFFFFFFFFFFFFFFi64;",
			"    Sys.println(f.high);",
			"    Sys.println(f.low);",
			"    var g = haxe.Int64.parseString(\"  -23 \");",
			"    Sys.println(g.high);",
			"    Sys.println(g.low);",
			"    var h = haxe.Int64.parseString(\"9223372036854775807\");",
			"    Sys.println(h.high);",
			"    Sys.println(h.low);",
			"    Sys.println(haxe.Int64.toStr(h));",
			"    Sys.println(h.toStr());",
			"    var hdyn:Dynamic = h;",
			"    Sys.println(hdyn.toStr());",
			"    Sys.println(Std.string(h));",
			"    Sys.println('$h');",
			"    try {",
			"      haxe.Int64.parseString(\"9223372036854775808\");",
			"      Sys.println(\"missing-parse-overflow\");",
			"    } catch (_:Dynamic) {",
			"      Sys.println(\"parse-overflow\");",
			"    }",
			"    Sys.println(haxe.Int64.compare(haxe.Int64.ofInt(1), haxe.Int64.ofInt(2)));",
			"    Sys.println(haxe.Int64.compare(haxe.Int64.ofInt(2), haxe.Int64.ofInt(1)));",
			"    Sys.println(haxe.Int64.compare(haxe.Int64.ofInt(2), haxe.Int64.ofInt(2)));",
			"    Sys.println(h.compare(haxe.Int64.ofInt(0)));",
			"    Sys.println(haxe.Int64.ucompare(haxe.Int64.ofInt(-1), haxe.Int64.ofInt(0)));",
			"    Sys.println(haxe.Int64.ofInt(-1).ucompare(haxe.Int64.ofInt(0)));",
			"    int64eq(haxe.Int64.add(haxe.Int64.ofInt(5), haxe.Int64.ofInt(-5)), 0);",
			"    var i = haxe.Int64.ofInt(7) * 6;",
			"    Sys.println(i.high);",
			"    Sys.println(i.low);",
			"    var j = haxe.Int64.add(haxe.Int64.ofInt(5), haxe.Int64.ofInt(9));",
			"    Sys.println(j.high);",
			"    Sys.println(j.low);",
			"    var k = haxe.Int64.sub(haxe.Int64.ofInt(5), haxe.Int64.ofInt(9));",
			"    Sys.println(k.high);",
			"    Sys.println(k.low);",
			"    var ks = haxe.Int64.ofInt(5) - haxe.Int64.ofInt(9);",
			"    Sys.println(ks.high);",
			"    Sys.println(ks.low);",
			"    var m = haxe.Int64.mul(haxe.Int64.ofInt(7), 6);",
			"    Sys.println(m.high);",
			"    Sys.println(m.low);",
			"    var dv = haxe.Int64.ofInt(23) / haxe.Int64.ofInt(5);",
			"    Sys.println(haxe.Int64.toStr(dv));",
			"    var md = haxe.Int64.ofInt(23) % haxe.Int64.ofInt(5);",
			"    Sys.println(haxe.Int64.toStr(md));",
			"    var bwAnd = haxe.Int64.ofInt(6) & haxe.Int64.ofInt(3);",
			"    Sys.println(haxe.Int64.toStr(bwAnd));",
			"    var bwOr = haxe.Int64.ofInt(6) | haxe.Int64.ofInt(3);",
			"    Sys.println(haxe.Int64.toStr(bwOr));",
			"    var bwXor = haxe.Int64.ofInt(6) ^ haxe.Int64.ofInt(3);",
			"    Sys.println(haxe.Int64.toStr(bwXor));",
			"    var bwNot = ~haxe.Int64.ofInt(6);",
			"    Sys.println(haxe.Int64.toStr(bwNot));",
			"    var shl = haxe.Int64.ofInt(1) << 33;",
			"    Sys.println(haxe.Int64.toStr(shl));",
			"    var shr = haxe.Int64.parseString(\"-8\") >> 1;",
			"    Sys.println(haxe.Int64.toStr(shr));",
			"    var ushr = haxe.Int64.parseString(\"-8\") >>> 1;",
			"    Sys.println(haxe.Int64.toStr(ushr));",
			"    var shiftAssign:haxe.Int64 = 1;",
			"    shiftAssign <<= 33;",
			"    Sys.println(haxe.Int64.toStr(shiftAssign));",
			"    shiftAssign >>= 32;",
			"    Sys.println(haxe.Int64.toStr(shiftAssign));",
			"    shiftAssign >>>= 1;",
			"    Sys.println(haxe.Int64.toStr(shiftAssign));",
			"    var compatA = haxe.Int64.ofInt(32);",
			"    var compatB = haxe.Int64.ofInt(-4);",
			"    Sys.println(Std.string(compatA.eq(compatB)));",
			"    Sys.println(Std.string(compatA.neq(compatB)));",
			"    Sys.println(haxe.Int64.toStr(compatA.add(compatB)));",
			"    Sys.println(haxe.Int64.toStr(compatA.sub(compatB)));",
			"    Sys.println(haxe.Int64.toStr(compatA.div(compatB)));",
			"    Sys.println(haxe.Int64.toStr(compatA.mod(compatB)));",
			"    Sys.println(haxe.Int64.toStr(compatB.shl(1)));",
			"    Sys.println(haxe.Int64.toStr(compatB.shr(1)));",
			"    Sys.println(haxe.Int64.toStr(compatB.ushr(1)));",
			"    Sys.println(haxe.Int64.toStr(compatA.and(compatB)));",
			"    Sys.println(haxe.Int64.toStr(compatA.or(compatB)));",
			"    Sys.println(haxe.Int64.toStr(compatA.xor(compatB)));",
			"    Sys.println(haxe.Int64.toStr(compatA.neg()));",
			"    Sys.println(Std.string(compatA.isNeg()));",
			"    Sys.println(Std.string(compatB.isNeg()));",
			"    Sys.println(Std.string(compatA.isZero()));",
			"    var q = haxe.Int64.divMod(haxe.Int64.ofInt(23), haxe.Int64.ofInt(5));",
			"    Sys.println(haxe.Int64.toStr(q.quotient));",
			"    Sys.println(haxe.Int64.toStr(q.modulus));",
			"    var qi = haxe.Int64.ofInt(23).divMod(haxe.Int64.ofInt(5));",
			"    Sys.println(haxe.Int64.toStr(qi.quotient));",
			"    Sys.println(haxe.Int64.toStr(qi.modulus));",
			"    var r = haxe.Int64.divMod(haxe.Int64.ofInt(-23), haxe.Int64.ofInt(5));",
			"    Sys.println(haxe.Int64.toStr(r.quotient));",
			"    Sys.println(haxe.Int64.toStr(r.modulus));",
			"    var lmin = haxe.Int64.parseString(\"-9223372036854775808\");",
			"    var l = -lmin;",
			"    Sys.println(l.high);",
			"    Sys.println(l.low);",
			"    Sys.println(Std.string(lmin == l));",
			"    Sys.println(Std.string(lmin != haxe.Int64.ofInt(0)));",
			"    var min = haxe.Int64.parseString(\"-9223372036854775808\");",
			"    Sys.println(haxe.Int64.toStr(min));",
			"    Sys.println(haxe.Int64.toStr(k));",
			"    var minDiv = haxe.Int64.divMod(min, haxe.Int64.ofInt(10));",
			"    Sys.println(haxe.Int64.toStr(minDiv.quotient));",
			"    Sys.println(haxe.Int64.toStr(minDiv.modulus));",
			"    Sys.println(Std.string(min == (-min)));",
			"    try {",
			"      haxe.Int64.make(0, 0x80000000).toInt();",
			"      Sys.println(\"missing-overflow\");",
			"    } catch (_:Dynamic) {",
			"      Sys.println(\"overflow\");",
			"    }",
			"  }",
			"  static function int64eq(v:haxe.Int64, v2:haxe.Int64) {",
			"    Sys.println(Std.string(v == v2));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		final program = MacroStage.expandProgram([typed], []);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class Int64 {", "PHP runtime should expose haxe.Int64");
		assertContains(content, "public static function make($high, $low)", "PHP haxe.Int64 should expose make");
		assertContains(content, "public static function ofInt($value)", "PHP haxe.Int64 should expose ofInt");
		assertContains(content, "public static function add($left, $right)", "PHP haxe.Int64 should expose add");
		assertContains(content, "public static function sub($left, $right)", "PHP haxe.Int64 should expose sub");
		assertContains(content, "public static function mul($left, $right)", "PHP haxe.Int64 should expose mul");
		assertContains(content, "public static function divMod($dividend, $divisor)", "PHP haxe.Int64 should expose divMod");
		assertContains(content, "public static function parseString($value)", "PHP haxe.Int64 should expose parseString");
		assertContains(content, "public static function toStr($value)", "PHP haxe.Int64 should expose toStr");
		assertContains(content, "public static function compare($left, $right)", "PHP haxe.Int64 should expose compare");
		assertContains(content, "public static function ucompare($left, $right)", "PHP haxe.Int64 should expose ucompare");
		assertContains(content, "public function get_high()", "PHP haxe.Int64 should expose typed high getter");
		assertContains(content, "public function get_low()", "PHP haxe.Int64 should expose typed low getter");
		assertContains(content, "public function toInt()", "PHP haxe.Int64 should expose instance toInt");
		assertContains(content, "public function toString()", "PHP haxe.Int64 should expose instance toString");
		assertContains(content, "__hxhx_to_str($h)", "PHP Int64 instance toStr should lower through the runtime helper");
		assertContains(content, "__hxhx_to_str($hdyn)", "PHP dynamic Int64 toStr should lower through the runtime helper");
		assertContains(content, "if (__hxhx_is_int64($obj) && $name === \"toStr\")", "PHP dynamic Int64 toStr should bind the receiver");
		assertContains(content, "if (__hxhx_is_int64($value)) return __hxhx_int64_to_string($value);", "PHP string conversion should format Int64 as decimal");
		assertContains(content, "$e = __hxhx_int64_literal(\"47244640255\", \"i64\");", "PHP typed Int64 decimal literals should construct Int64 values");
		assertContains(content, "$f = __hxhx_int64_literal(\"0x7FFFFFFFFFFFFFFF\", \"i64\");", "PHP typed Int64 hex literals should construct Int64 values");
		assertContains(content, "$c = \\haxe\\Int64::make(2, 3);", "PHP imported Int64 calls should lower to qualified haxe.Int64 calls");
		assertContains(content, "$capturedMake = function(...$__hxhx_args) { return \\haxe\\Int64::make(...$__hxhx_args); };",
			"PHP captured Int64.make should lower to a qualified callable");
		assertContains(content, "$imported = \\haxe\\Int64::make(4, 5);", "PHP imported haxe.Int64.* make calls should lower to qualified static calls");
		assertContains(content, "$importedMake = __hxhx_copy_value(function(...$__hxhx_args) { return \\haxe\\Int64::make(...$__hxhx_args); });",
			"PHP captured imported haxe.Int64.* make should lower to a qualified callable");
		assertContains(content, "\\haxe\\Int64::compare($captured, $imported)",
			"PHP imported haxe.Int64.* compare calls should lower to qualified static calls");
		assertContains(content, "$capturedOfInt = function(...$__hxhx_args) { return \\haxe\\Int64::ofInt(...$__hxhx_args); };",
			"PHP captured haxe.Int64.ofInt should lower to a qualified callable");
		assertContains(content, "\\haxe\\Int64::neg(\\haxe\\Int64::ofInt(6))", "PHP imported haxe.Int64.* neg calls should lower to qualified static calls");
		assertContains(content, "$capturedNeg = __hxhx_copy_value(function(...$__hxhx_args) { return \\haxe\\Int64::neg(...$__hxhx_args); });",
			"PHP captured imported haxe.Int64.* neg should lower to a qualified callable");
		assertContains(content, "public static function parseInt($value)", "PHP Std should expose parseInt");
		assertContains(content, "Std::parseInt(\"65.3\")", "PHP Std.parseInt calls should lower to the Std support class");
		assertContains(content, "public static function parseFloat($value)", "PHP Std should expose parseFloat");
		assertContains(content, "Std::parseFloat(\"12.5\")", "PHP Std.parseFloat calls should lower to the Std support class");
		assertContains(content, "\\haxe\\Int64::fromFloat(12.0)", "PHP imported haxe.Int64.* fromFloat calls should lower to qualified static calls");
		assertContains(content, "$capturedFromFloat = __hxhx_copy_value(function(...$__hxhx_args) { return \\haxe\\Int64::fromFloat(...$__hxhx_args); });",
			"PHP captured imported haxe.Int64.* fromFloat should lower to a qualified callable");
		assertContains(content, "public static function hex($value, $digits = null)", "PHP StringTools should expose hex");
		assertContains(content, "StringTools::hex((-8))", "PHP StringTools.hex calls should lower to the StringTools support class");
		assertContains(content, "__hxhx_int64_compare(__hxhx_int64_add(\\haxe\\Int64::ofInt(3), \\haxe\\Int64::ofInt(2)), \\haxe\\Int64::ofInt(5))",
			"PHP chained Int64 instance arithmetic result compare should lower through the runtime helper");
		assertContains(content, "__hxhx_int64_sub(__hxhx_int64_add(\\haxe\\Int64::ofInt(3), \\haxe\\Int64::ofInt(2)), \\haxe\\Int64::ofInt(1))",
			"PHP chained Int64 instance arithmetic should preserve Int64 result typing");
		assertContains(content, "__hxhx_int64_compare($dynInt64, \\haxe\\Int64::ofInt(3))",
			"PHP Int64-looking instance compare calls should use helpers when an argument is known Int64");
		assertContains(content, "__hxhx_int64_compare(__hxhx_int64_add($dynInt64, \\haxe\\Int64::ofInt(2)), \\haxe\\Int64::ofInt(5))",
			"PHP Int64-looking instance arithmetic calls should use helpers when an argument is known Int64");
		assertContains(content, "__hxhx_array_push($boxed, \\haxe\\Int64::ofInt(1))", "PHP Array<Int64>.push should box Int literals");
		assertContains(content, "$inc = __hxhx_add($inc, 1);", "PHP Int64 postfix increment statements should route through Int64 addition");
		assertContains(content, "$inc = __hxhx_sub($inc, 1);", "PHP Int64 postfix decrement statements should route through Int64 subtraction");
		assertContains(content, "__hxhx_post_update_var($inc, 1)", "PHP Int64 postfix expressions should preserve old-value semantics through the helper");
		assertContains(content, "$i = __hxhx_mul(\\haxe\\Int64::ofInt(7), 6);", "PHP Int64 multiplication should lower through the runtime helper");
		assertContains(content, "$ks = __hxhx_sub(\\haxe\\Int64::ofInt(5), \\haxe\\Int64::ofInt(9));",
			"PHP typed Int64 binary subtraction should lower through the runtime helper");
		assertContains(content, "$dv = __hxhx_div(\\haxe\\Int64::ofInt(23), \\haxe\\Int64::ofInt(5));",
			"PHP typed Int64 binary division should lower through the runtime helper");
		assertContains(content, "$md = __hxhx_mod(\\haxe\\Int64::ofInt(23), \\haxe\\Int64::ofInt(5));",
			"PHP typed Int64 modulo should lower through the runtime helper");
		assertContains(content, "$bwAnd = __hxhx_int64_and(\\haxe\\Int64::ofInt(6), \\haxe\\Int64::ofInt(3));",
			"PHP typed Int64 bitwise and should lower through the runtime helper");
		assertContains(content, "$bwOr = __hxhx_int64_or(\\haxe\\Int64::ofInt(6), \\haxe\\Int64::ofInt(3));",
			"PHP typed Int64 bitwise or should lower through the runtime helper");
		assertContains(content, "$bwXor = __hxhx_int64_xor(\\haxe\\Int64::ofInt(6), \\haxe\\Int64::ofInt(3));",
			"PHP typed Int64 bitwise xor should lower through the runtime helper");
		assertContains(content, "$bwNot = __hxhx_int64_not(\\haxe\\Int64::ofInt(6));", "PHP typed Int64 bitwise not should lower through the runtime helper");
		assertContains(content, "$shl = __hxhx_int64_shl(\\haxe\\Int64::ofInt(1), 33);", "PHP typed Int64 left shift should lower through the runtime helper");
		assertContains(content, "$shr = __hxhx_int64_shr(\\haxe\\Int64::parseString(\"-8\"), 1);",
			"PHP typed Int64 signed right shift should lower through the runtime helper");
		assertContains(content, "$ushr = __hxhx_int64_ushr(\\haxe\\Int64::parseString(\"-8\"), 1);",
			"PHP typed Int64 unsigned right shift should lower through the runtime helper");
		assertContains(content, "$shiftAssign = __hxhx_int64_shl($shiftAssign, 33);",
			"PHP typed Int64 left-shift assignment should lower through the runtime helper");
		assertContains(content, "$shiftAssign = __hxhx_int64_shr($shiftAssign, 32);",
			"PHP typed Int64 signed right-shift assignment should lower through the runtime helper");
		assertContains(content, "$shiftAssign = __hxhx_int64_ushr($shiftAssign, 1);",
			"PHP typed Int64 unsigned right-shift assignment should lower through the runtime helper");
		assertContains(content, "__hxhx_equals($compatA, $compatB)", "PHP Int64 eq/neq methods should lower through equality helper calls");
		assertContains(content, "__hxhx_int64_add($compatA, $compatB)", "PHP Int64 add method should lower through the runtime helper");
		assertContains(content, "__hxhx_int64_div_mod($compatA, $compatB)->quotient", "PHP Int64 div method should return the divMod quotient");
		assertContains(content, "__hxhx_int64_ushr($compatB, 1)", "PHP Int64 ushr method should lower through the runtime helper");
		assertContains(content, "__hxhx_int64_is_zero($compatA)", "PHP Int64 isZero method should lower through the runtime helper");
		assertContains(content, "$qi = __hxhx_int64_div_mod(\\haxe\\Int64::ofInt(23), \\haxe\\Int64::ofInt(5));",
			"PHP Int64 instance divMod should bind the receiver as the first argument");
		assertContains(content, "$result = __hxhx_int64_div_mod($left, $right);", "PHP runtime division should dispatch Int64 operands through divMod");
		assertContains(content, "return $result->modulus;", "PHP runtime modulo should return the Int64 divMod modulus");
		assertContains(content, "$l = __hxhx_int64_neg($lmin);", "PHP typed Int64 locals should route unary minus through the runtime helper");
		assertContains(content, "__hxhx_equals($lmin, $l)", "PHP typed Int64 equality should lower through high/low word comparison");
		assertContains(content, "$v2 = __hxhx_int64_value($v2);", "PHP Int64 function parameters should coerce Int literals at the boundary");
		assertContains(content, "__hxhx_equals($v, $v2)", "PHP typed Int64 parameter equality should lower through high/low word comparison");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP haxe.Int64 runtime support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "10\n-1\n2\n3\n3\n4\n4\n5\n5\n6\n-1\n-5\n-6\n-7\n65\n65\n255\n12.5\n12\n-13\nFFFFFFF8\n21\n0054\n0\n4\n0\n0\n-1\n-1\n-1\n1\n0\n1\n1\n2\n2\n3\n2\n1\n1\n0\n10\n-1\n2147483647\n-1\n-1\n-23\n2147483647\n-1\n9223372036854775807\n9223372036854775807\n9223372036854775807\n9223372036854775807\n9223372036854775807\nparse-overflow\n-1\n1\n0\n1\n1\n1\ntrue\n0\n42\n0\n14\n-1\n-4\n-1\n-4\n0\n42\n4\n3\n2\n7\n5\n-7\n8589934592\n-4\n9223372036854775804\n8589934592\n2\n1\nfalse\ntrue\n28\n36\n-8\n0\n-8\n-2\n9223372036854775806\n32\n-4\n-36\n-32\nfalse\ntrue\nfalse\n4\n3\n4\n3\n-4\n-3\n-2147483648\n0\ntrue\ntrue\n-9223372036854775808\n-4\n-922337203685477580\n-8\ntrue\noverflow\n",
				"generated PHP haxe.Int64 output mismatch, got:\n"
				+ run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpInt64GlobalClassDoesNotCollide():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_int64_shadow_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final src = [
			"class Main {",
			"  static function main() {",
			"    var x:haxe.Int64 = 1;",
			"    Sys.println(haxe.Int64.toStr(x));",
			"    Sys.println(Int64.label());",
			"  }",
			"}",
			"class Int64 {",
			"  public static function label() {",
			"    return \"shadow\";",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		final program = MacroStage.expandProgram([typed], []);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class Int64 {", "PHP should preserve user top-level Int64 support classes");
		assertContains(content, "$x = \\haxe\\Int64::ofInt(1);", "PHP haxe.Int64 assignments should not rely on the global Int64 alias");
		assertNotContains(content, "class Int64 extends \\haxe\\Int64", "PHP should not emit the global Int64 alias when a user Int64 class exists");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP should not redeclare Int64, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "1\nshadow\n", "generated PHP Int64 shadow output mismatch, got:\n" + run.stdout);
		}
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
		assertContains(content, "function __hxhx_field_add_assign($object, $field, $value)", "PHP runtime should include a field add-assign helper");
		assertContains(content, "function __hxhx_map_literal($pairs)", "PHP runtime should include a map literal helper");
		assertContains(content, "function __hxhx_map_literal_from_object($object)", "PHP runtime should include an object-shaped map literal helper");
		assertContains(content, "function __hxhx_remove(&$collection, $value)", "PHP runtime should include a polymorphic remove helper");
		assertContains(content, "function __hxhx_array_splice(&$array, $pos, $len)", "PHP runtime should include an Array.splice helper");
		assertContains(content, "function __hxhx_array_sort(&$array, $compare)", "PHP runtime should include an Array.sort helper");
		assertContains(content, "function __hxhx_array_join($array, $separator)", "PHP runtime should include an Array.join helper");
		assertContains(content, "function __hxhx_array_map($array, $callback)", "PHP runtime should include an Array.map helper");
		assertContains(content, "class __HxArrayIterator", "PHP runtime should include a Haxe array iterator wrapper");
		assertContains(content, "function __hxhx_iterator($value)", "PHP runtime should include an iterator helper");
		assertContains(content, "echo __hxhx_add_string(__hxhx_array_get($a, 3)) . PHP_EOL;",
			"PHP out-of-bounds array reads should go through safe Haxe read helper");
		assertContains(content, "__hxhx_array_sort($a, [Reflect::class, \"compare\"]);", "PHP Array.sort should lower through the mutating helper");
		assertContains(content, "echo __hxhx_array_join($a, \"#\") . PHP_EOL;", "PHP Array.join should lower through the join helper");
		assertContains(content, "__hxhx_remove($a, 2);", "PHP Array.remove should lower through the mutating helper");
		assertContains(content, "__hxhx_array_splice($a, 1, 1);", "PHP Array.splice should lower through the mutating helper");
		assertContains(content, "$mapped = __hxhx_array_map($base,", "PHP Array.map should lower through the array map helper");
		assertContains(content, "$it = __hxhx_iterator($a);", "PHP Array.iterator should lower through the iterator helper");
		assertContains(content, "__hxhx_remove($m, \"a\");", "PHP Map.remove should go through the polymorphic remove helper");
		assertContains(content, "__hxhx_field_add_assign(__hxhx_array_get($records, __hxhx_post_update_var($x, 1)), \"v\", 3)",
			"PHP field add-assign should evaluate side-effecting receivers once");
		assertNotContains(content, "$a->remove(2)", "PHP arrays should not emit object-method remove calls on raw arrays");
		assertNotContains(content, "$base->map", "PHP arrays should not emit object-method map calls on raw arrays");
		assertNotContains(content, "$a->iterator()", "PHP arrays should not emit object-method iterator calls on raw arrays");
		assertNotContains(content, "$a[3]", "PHP expression reads should not emit direct array access for missing-index semantics");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP array operations should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "1#2#3\nnull\n2\n3\n1\ntrue\n1\n2,4,6\n3\n1\n4\n7\n1\n7\n",
				"generated PHP array operations should preserve field add-assign receiver evaluation, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpSameClassArrayFieldMap():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_same_class_array_field_map_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpSameClassArrayFieldMapProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "$values = __hxhx_array_map($this->callbacks,",
			"PHP same-class Array.map field calls should lower through the array map helper");
		assertNotContains(content, "$this->callbacks->map", "PHP same-class array fields should not emit object-method map calls on raw arrays");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP same-class Array.map field call should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "4,6\n", "generated PHP same-class Array.map field call output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpObjectArrayAccess():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_object_array_access_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpObjectArrayAccessProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "function __hxhx_array_get($array, $index)", "PHP runtime should include object-aware custom array-access reads");
		assertContains(content, "if (is_object($array)) {", "PHP custom array-access helpers should handle object-backed abstracts");
		assertContains(content, "__hxhx_array_set($record, \"foo\", 11)", "PHP object array-access writes should lower through the shared indexed setter");
		assertContains(content, "__hxhx_array_add_assign($record, \"foo\", 99)",
			"PHP object array-access add-assign should lower through the shared indexed update helper");
		assertContains(content, "__hxhx_array_get($record, \"101\")(1)",
			"PHP object array-access reads should remain callable when the stored field is a function");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP object array-access support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "12\n110\ntest110\ntest110\n2\nhhh\n10\n", "generated PHP object array-access output mismatch, got:\n" + run.stdout);
		}
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

	static function assertPhpImportedHaxelibEnumSupportClassEmission():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_imported_haxelib_enum_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpImportedHaxelibEnumSupportProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class HeaderDisplayMode {",
			"PHP support class emission should include imported haxelib enum carriers referenced by generated code");
		assertContains(content, "class SuccessResultsDisplayMode {",
			"PHP support class emission should include sibling enum carriers from imported haxelib modules");
		assertContains(content, "HeaderDisplayMode::$AlwaysShowHeader", "PHP generated code should reference the imported enum carrier");
		assertContains(content, "SuccessResultsDisplayMode::$NeverShowSuccessResults", "PHP generated code should reference the sibling enum carrier");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP imported haxelib enum support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "AlwaysShowHeader\nNeverShowSuccessResults\n", "generated PHP imported haxelib enum output mismatch, got:\n"
				+ run.stdout);
		}
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

	static function assertPhpMacroRestProbe():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_macro_rest_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final src = [
			"class Main {",
			"  static function main() {",
			"    var one = MyMacro.MyRestMacro.testRest1(1, 2, [3]);",
			"    var two = MyMacro.MyRestMacro.testRest2(1, 2, 3, 4);",
			"    Sys.println(Std.string(one.length) + ':' + Std.string(one[0]) + ':' + Std.string(one[2][0]));",
			"    Sys.println(Std.string(two.length) + ':' + Std.string(two[2]) + ':' + Std.string(two[3]));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		final program = MacroStage.expandProgram([typed], []);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertNotContains(content, "MyRestMacro::testRest", "PHP macro-rest probes should fold before runtime emission");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP macro-rest probe should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "3:1:3\n4:3:4\n", "generated PHP macro-rest output mismatch, got:\n" + run.stdout);
		}
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
		assertContains(content, "catch (\\Throwable $__hxhx_caught) {", "PHP try/catch expressions should catch through Throwable");
		assertContains(content, "$e = __hxhx_unwrap_thrown_value($__hxhx_caught);", "PHP try/catch expressions should bind the original Haxe thrown value");
		assertContains(content, "return \"bad\";", "PHP try/catch expression catch bodies should return their final value");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpThrownValueCatch():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_thrown_value_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(tryCatchProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "throw ValueException::thrown(\"boom\");", "PHP throw statements should preserve Haxe thrown values");
		assertContains(content, "catch (\\Exception $__hxhx_caught) {", "PHP try statements should catch through PHP exceptions");
		assertContains(content, "$e = __hxhx_unwrap_thrown_value($__hxhx_caught);", "PHP catch variables should receive the original Haxe thrown value");
		assertContains(content, "if ($value instanceof ValueException) return $value;", "PHP thrown-value wrapping should be idempotent for rethrows");
		assertContains(content, "function __hxhx_unwrap_thrown_value($value)", "PHP runtime should expose thrown-value unwrapping");
		deleteRecursive(tmpRoot);

		final exceptionTmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_exception_catch_" + Std.string(Date.now().getTime()));
		deleteRecursive(exceptionTmpRoot);
		FileSystem.createDirectory(exceptionTmpRoot);
		backend.emit(phpExceptionCatchProgram(), new BackendContext(exceptionTmpRoot, null, "Main", true, false, new StringMap<String>()));
		final exceptionContent = File.getContent(Path.join([exceptionTmpRoot, "index.php"]));
		assertContains(exceptionContent, "throw ValueException::thrown(123);", "PHP primitive throws should use the ValueException wrapper");
		assertContains(exceptionContent, "catch (\\Exception $__hxhx_caught) {", "PHP Exception catches should catch the wrapper object");
		assertNotContains(exceptionContent, "$e = __hxhx_unwrap_thrown_value($__hxhx_caught);",
			"PHP Exception catches should preserve the ValueException object");
		assertContains(exceptionContent, "echo __hxhx_message_field($e) . PHP_EOL;", "PHP Exception catch bodies should be able to read message");
		assertContains(exceptionContent, "function __hxhx_message_field($value)", "PHP runtime should expose throwable-safe message reads");
		deleteRecursive(exceptionTmpRoot);

		final customTmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_custom_exception_catch_" + Std.string(Date.now().getTime()));
		deleteRecursive(customTmpRoot);
		FileSystem.createDirectory(customTmpRoot);
		backend.emit(phpCustomExceptionCatchProgram(), new BackendContext(customTmpRoot, null, "Main", true, false, new StringMap<String>()));
		final customContent = File.getContent(Path.join([customTmpRoot, "index.php"]));
		assertContains(customContent, "throw ValueException::thrown(new CustomHaxeException(\"boom\"));",
			"PHP custom Haxe exception throws should use the ValueException wrapper");
		assertContains(customContent, "$e = __hxhx_unwrap_thrown_value($__hxhx_caught);",
			"PHP custom Haxe exception catches should receive the original payload");
		deleteRecursive(customTmpRoot);

		final customGuardTmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_custom_exception_value_guard_" + Std.string(Date.now().getTime()));
		deleteRecursive(customGuardTmpRoot);
		FileSystem.createDirectory(customGuardTmpRoot);
		backend.emit(phpCustomExceptionValueExceptionGuardProgram(),
			new BackendContext(customGuardTmpRoot, null, "Main", true, false, new StringMap<String>()));
		final customGuardContent = File.getContent(Path.join([customGuardTmpRoot, "index.php"]));
		assertContains(customGuardContent,
			"if ($type === \"ValueException\" || $type === \"haxe.ValueException\") return $caught instanceof ValueException && !($caught->value instanceof \\Throwable);",
			"PHP ValueException catches should not match wrapped Throwable payloads");
		if (commandExists("php")) {
			final run = commandOutput("php", [Path.join([customGuardTmpRoot, "index.php"])]);
			assertTrue(run.code == 0, "generated PHP ValueException guard should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "ok", "generated PHP ValueException catch should skip custom Haxe exceptions");
			assertNotContains(run.stdout, "bad", "generated PHP ValueException catch should not catch custom Haxe exceptions");
		}
		deleteRecursive(customGuardTmpRoot);

		final valueTmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_value_exception_catch_" + Std.string(Date.now().getTime()));
		deleteRecursive(valueTmpRoot);
		FileSystem.createDirectory(valueTmpRoot);
		backend.emit(phpValueExceptionCatchProgram(), new BackendContext(valueTmpRoot, null, "Main", true, false, new StringMap<String>()));
		final valueContent = File.getContent(Path.join([valueTmpRoot, "index.php"]));
		assertContains(valueContent, "throw ValueException::thrown(123);", "PHP primitive throws should still wrap values for ValueException catches");
		assertNotContains(valueContent, "$e = __hxhx_unwrap_thrown_value($__hxhx_caught);", "PHP ValueException catches should preserve the wrapper object");
		assertContains(valueContent, "echo $e->value . PHP_EOL;", "PHP ValueException catch bodies should be able to read value");
		deleteRecursive(valueTmpRoot);

		final abstractTmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_abstract_exception_catch_" + Std.string(Date.now().getTime()));
		deleteRecursive(abstractTmpRoot);
		FileSystem.createDirectory(abstractTmpRoot);
		backend.emit(phpAbstractCatchProgram(), new BackendContext(abstractTmpRoot, null, "Main", true, false, new StringMap<String>()));
		final abstractContent = File.getContent(Path.join([abstractTmpRoot, "index.php"]));
		assertContains(abstractContent, "__hxhx_catch_matches($__hxhx_caught, \"AbstrString\")",
			"PHP abstract String catches should route through catch matching");
		assertContains(abstractContent, "__hxhx_catch_matches($__hxhx_caught, \"AbstrException\")",
			"PHP abstract Exception catches should route through catch matching");
		assertContains(abstractContent, "function __hxhx_catch_matches($caught, $type)", "PHP runtime should expose Haxe catch matching");
		assertContains(abstractContent, "if (substr($short, -6) === \"String\") return is_string($value);",
			"PHP catch matching should follow erased String abstracts");
		assertContains(abstractContent, "if (substr($short, -9) === \"Exception\") return $value instanceof \\Exception;",
			"PHP catch matching should follow erased Exception abstracts");
		if (commandExists("php")) {
			final run = commandOutput("php", [Path.join([abstractTmpRoot, "index.php"])]);
			assertTrue(run.code == 0, "generated PHP abstract catches should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "hello", "generated PHP abstract String catch should observe the thrown value");
			assertContains(run.stdout, "CustomHaxeException", "generated PHP abstract Exception catch should observe the thrown value");
		}
		deleteRecursive(abstractTmpRoot);

		final enumTmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_enum_catch_" + Std.string(Date.now().getTime()));
		deleteRecursive(enumTmpRoot);
		FileSystem.createDirectory(enumTmpRoot);
		backend.emit(phpEnumCatchProgram(), new BackendContext(enumTmpRoot, null, "Main", true, false, new StringMap<String>()));
		final enumContent = File.getContent(Path.join([enumTmpRoot, "index.php"]));
		assertContains(enumContent, "__hxhx_catch_matches($__hxhx_caught, \"EnumError\")", "PHP enum catches should route through catch matching");
		assertContains(enumContent, "$e = __hxhx_unwrap_thrown_value($__hxhx_caught);",
			"PHP enum catches should bind the thrown enum value, not a stringified surrogate");
		assertContains(enumContent, "Type::enumEq($e, EnumError::$EError)", "PHP caught enum values should remain compatible with Type.enumEq");
		assertContains(enumContent,
			"if (substr($short, 0, 4) === \"Enum\") return is_string($value) || (is_object($value) && property_exists($value, \"__hx_ctor\"));",
			"PHP catch matching should follow the source backend enum value encodings");
		if (commandExists("php")) {
			final run = commandOutput("php", [Path.join([enumTmpRoot, "index.php"])]);
			assertTrue(run.code == 0, "generated PHP enum catches should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "EError\n1\n", "generated PHP enum catch should preserve thrown enum equality, got:\n" + run.stdout);
		}
		deleteRecursive(enumTmpRoot);

		final catchShadowTmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_catch_shadow_enum_" + Std.string(Date.now().getTime()));
		deleteRecursive(catchShadowTmpRoot);
		FileSystem.createDirectory(catchShadowTmpRoot);
		backend.emit(phpCatchLocalShadowsEnumConstructorProgram(), new BackendContext(catchShadowTmpRoot, null, "Main", true, false, new StringMap<String>()));
		final catchShadowContent = File.getContent(Path.join([catchShadowTmpRoot, "index.php"]));
		assertContains(catchShadowContent, "$e2 = __hxhx_unwrap_thrown_value($__hxhx_caught);",
			"PHP catches should bind the catch local before rendering the body");
		assertNotContains(catchShadowContent, "echo __hxhx_add_string(Expr::$e2)", "PHP catch locals should shadow same-named enum constructors");
		assertNotContains(catchShadowContent, "Type::enumEq(Expr::$e2", "PHP catch locals should shadow same-named enum constructors");
		if (commandExists("php")) {
			final run = commandOutput("php", [Path.join([catchShadowTmpRoot, "index.php"])]);
			assertTrue(run.code == 0, "generated PHP catch local shadowing should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "OutsideBounds\n1\n", "generated PHP catch local shadowing output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(catchShadowTmpRoot);

		final methodTmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_instance_method_call_" + Std.string(Date.now().getTime()));
		deleteRecursive(methodTmpRoot);
		FileSystem.createDirectory(methodTmpRoot);
		backend.emit(phpInstanceMethodCallProgram(), new BackendContext(methodTmpRoot, null, "Main", true, false, new StringMap<String>()));
		final methodContent = File.getContent(Path.join([methodTmpRoot, "index.php"]));
		assertContains(methodContent, "return $this->inner();", "PHP helper classes should rewrite same-class instance method calls through $this");
		if (commandExists("php")) {
			final run = commandOutput("php", [Path.join([methodTmpRoot, "index.php"])]);
			assertTrue(run.code == 0, "generated PHP same-class instance method calls should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "ok", "generated PHP same-class instance method calls should preserve behavior");
		}
		deleteRecursive(methodTmpRoot);

		final pushTmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_array_push_" + Std.string(Date.now().getTime()));
		deleteRecursive(pushTmpRoot);
		FileSystem.createDirectory(pushTmpRoot);
		backend.emit(phpArrayPushProgram(), new BackendContext(pushTmpRoot, null, "Main", true, false, new StringMap<String>()));
		final pushContent = File.getContent(Path.join([pushTmpRoot, "index.php"]));
		assertContains(pushContent, "__hxhx_array_push($values, \"ok\")", "PHP Array.push should lower through the runtime helper");
		assertContains(pushContent, "function __hxhx_array_push(&$array, $value)", "PHP runtime should expose Array.push helper");
		if (commandExists("php")) {
			final run = commandOutput("php", [Path.join([pushTmpRoot, "index.php"])]);
			assertTrue(run.code == 0, "generated PHP Array.push should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "1", "generated PHP Array.push should return the new length");
			assertContains(run.stdout, "ok", "generated PHP Array.push should append the value");
		}
		deleteRecursive(pushTmpRoot);

		final stackTmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_call_stack_" + Std.string(Date.now().getTime()));
		deleteRecursive(stackTmpRoot);
		FileSystem.createDirectory(stackTmpRoot);
		backend.emit(phpCallStackProgram(), new BackendContext(stackTmpRoot, null, "Main", true, false, new StringMap<String>()));
		final stackContent = File.getContent(Path.join([stackTmpRoot, "index.php"]));
		assertContains(stackContent, "class CallStack", "PHP runtime should expose haxe.CallStack support");
		assertContains(stackContent, "function __hxhx_stack()", "PHP runtime should expose synthetic stack items");
		assertContains(stackContent, "new ValueException(\"boom\")", "PHP haxe.Exception construction should use the stack-carrying wrapper");
		assertContains(stackContent, "->get_stack()", "PHP haxe.Exception stack accessor calls should preserve get_stack dispatch");
		assertContains(stackContent, "ValueException::thrown(\"boom\")", "PHP haxe.Exception.thrown should route through the throwable wrapper");
		assertContains(stackContent, "__hxhx_downcast(new ValueException(\"boom\"), \"Exception\")", "PHP Std.downcast should lower through type helper");
		if (commandExists("php")) {
			final run = commandOutput("php", [Path.join([stackTmpRoot, "index.php"])]);
			assertTrue(run.code == 0, "generated PHP CallStack support should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "2", "generated PHP CallStack support should produce stack entries");
			assertContains(run.stdout, "1", "generated PHP Std.downcast should recognize haxe.Exception values");
		}
		deleteRecursive(stackTmpRoot);

		final macroTmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_helper_macro_fold_" + Std.string(Date.now().getTime()));
		deleteRecursive(macroTmpRoot);
		FileSystem.createDirectory(macroTmpRoot);
		backend.emit(phpHelperMacroFoldProgram(), new BackendContext(macroTmpRoot, null, "Main", true, false, new StringMap<String>()));
		final macroContent = File.getContent(Path.join([macroTmpRoot, "index.php"]));
		assertNotContains(macroContent, "HelperMacros::parseAndPrint", "PHP compile-time macro helper calls should fold away");
		assertContains(macroContent, "\"haxe.Exception\"", "PHP HelperMacros.typeString try/catch probe should fold to haxe.Exception");
		if (commandExists("php")) {
			final run = commandOutput("php", [Path.join([macroTmpRoot, "index.php"])]);
			assertTrue(run.code == 0, "generated PHP helper macro folds should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "haxe.Exception", "generated PHP helper macro typeString fold should preserve expected type string");
		}
		deleteRecursive(macroTmpRoot);

		final notImplementedTmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_not_implemented_exception_" + Std.string(Date.now().getTime()));
		deleteRecursive(notImplementedTmpRoot);
		FileSystem.createDirectory(notImplementedTmpRoot);
		backend.emit(phpNotImplementedExceptionProgram(), new BackendContext(notImplementedTmpRoot, null, "Main", true, false, new StringMap<String>()));
		final notImplementedContent = File.getContent(Path.join([notImplementedTmpRoot, "index.php"]));
		assertContains(notImplementedContent, "class NotImplementedException extends PosException",
			"PHP runtime should expose haxe.exceptions.NotImplementedException");
		assertContains(notImplementedContent, "function __hxhx_class_name($name)", "PHP runtime should map emitted PHP class names back to Haxe names");
		assertContains(notImplementedContent, "function __hxhx_pos_infos()", "PHP runtime should infer PosException position metadata from debug_backtrace");
		assertContains(notImplementedContent, "new NotImplementedException()",
			"PHP haxe.exceptions.NotImplementedException construction should emit a runtime class");
		assertContains(notImplementedContent, "class_exists($short) && $caught instanceof $short",
			"PHP catch matching should recognize runtime exception wrappers before unwrapping values");
		if (commandExists("php")) {
			final run = commandOutput("php", [Path.join([notImplementedTmpRoot, "index.php"])]);
			assertTrue(run.code == 0, "generated PHP NotImplementedException support should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "not-implemented", "generated PHP should catch haxe.exceptions.NotImplementedException");
		}
		deleteRecursive(notImplementedTmpRoot);

		final lambdaThrowTmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_throw_expression_lambda_" + Std.string(Date.now().getTime()));
		deleteRecursive(lambdaThrowTmpRoot);
		FileSystem.createDirectory(lambdaThrowTmpRoot);
		backend.emit(phpThrowExpressionLambdaProgram(), new BackendContext(lambdaThrowTmpRoot, null, "Main", true, false, new StringMap<String>()));
		final lambdaThrowContent = File.getContent(Path.join([lambdaThrowTmpRoot, "index.php"]));
		assertContains(lambdaThrowContent, "class ArgumentException extends PosException", "PHP runtime should expose haxe.exceptions.ArgumentException");
		assertContains(lambdaThrowContent, "function __hxhx_throw($value)", "PHP runtime should expose expression-position throw helper");
		assertContains(lambdaThrowContent, "__hxhx_throw(new ArgumentException(\"i\"))",
			"PHP expression-position throw helper calls should not render as captured variable callables");
		assertNotContains(lambdaThrowContent, "$__hxhx_throw", "PHP expression-position throw helper calls should not capture an undefined callable variable");
		if (commandExists("php")) {
			final run = commandOutput("php", [Path.join([lambdaThrowTmpRoot, "index.php"])]);
			assertTrue(run.code == 0, "generated PHP expression-position throw helper should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "lambda-throw", "generated PHP should throw from local-function/lambda bodies");
			assertContains(run.stdout, "i", "generated PHP ArgumentException should preserve the argument field");
		}
		deleteRecursive(lambdaThrowTmpRoot);

		final bytesTmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_bytes_runtime_" + Std.string(Date.now().getTime()));
		deleteRecursive(bytesTmpRoot);
		FileSystem.createDirectory(bytesTmpRoot);
		backend.emit(phpBytesRuntimeProgram(), new BackendContext(bytesTmpRoot, null, "Main", true, false, new StringMap<String>()));
		final bytesContent = File.getContent(Path.join([bytesTmpRoot, "index.php"]));
		assertContains(bytesContent, "namespace haxe\\io {", "PHP runtime should expose haxe.io namespace helpers");
		assertContains(bytesContent, "class Bytes {", "PHP runtime should expose haxe.io.Bytes");
		assertContains(bytesContent, "class BytesInput {", "PHP runtime should expose haxe.io.BytesInput");
		assertContains(bytesContent, "class BytesOutput {", "PHP runtime should expose haxe.io.BytesOutput");
		assertContains(bytesContent, "public function get_position()", "PHP BytesInput should expose typed position getters");
		assertContains(bytesContent, "public function set_position($value)", "PHP BytesInput should expose typed position setters");
		assertContains(bytesContent, "use ($b)", "PHP lambdas should value-capture outer object locals that are not reassigned later");
		assertContains(bytesContent, "\\haxe\\io\\Bytes::fastGet", "PHP imported haxe.io.Bytes.fastGet aliases should call the runtime static method");
		if (commandExists("php")) {
			final run = commandOutput("php", [Path.join([bytesTmpRoot, "index.php"])]);
			assertTrue(run.code == 0, "generated PHP Bytes runtime should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "4", "generated PHP Bytes.alloc should preserve length");
			assertContains(run.stdout, "86", "generated PHP Bytes.set should mask values to one byte");
			assertContains(run.stdout, "é", "generated PHP Bytes UTF-8 string helpers should preserve byte slices");
			assertContains(run.stdout, "CB", "generated PHP Bytes.ofData should share backing data");
			assertContains(run.stdout, "67", "generated PHP Bytes.fastGet should read shared byte data");
			assertContains(run.stdout, "4", "generated PHP BytesOutput should track written length");
			assertContains(run.stdout, "0\n1\n0\n4\n", "generated PHP BytesInput position accessors should clamp and report seek positions");
			assertContains(run.stdout, "65", "generated PHP BytesInput should read written bytes");
			assertContains(run.stdout, "-2", "generated PHP BytesInput should read signed int16 values");
			assertContains(run.stdout, "Z", "generated PHP BytesInput should read written strings");
			assertContains(run.stdout, "-1", "generated PHP Bytes.compare should preserve lexicographic order");
			assertContains(run.stdout, "1", "generated PHP Bytes.compare should preserve reverse lexicographic order");
		}
		deleteRecursive(bytesTmpRoot);

		final md5TmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_md5_make_" + Std.string(Date.now().getTime()));
		deleteRecursive(md5TmpRoot);
		FileSystem.createDirectory(md5TmpRoot);
		backend.emit(phpMd5MakeProgram(), new BackendContext(md5TmpRoot, null, "Main", true, false, new StringMap<String>()));
		final md5Content = File.getContent(Path.join([md5TmpRoot, "index.php"]));
		assertContains(md5Content, "public static function make($bytes)", "PHP haxe.crypto.Md5 should expose make(Bytes)");
		assertContains(md5Content, "\\haxe\\io\\Bytes::ofHex(md5($bytes->toString()))", "PHP Md5.make should return digest bytes");
		if (commandExists("php")) {
			final run = commandOutput("php", [Path.join([md5TmpRoot, "index.php"])]);
			assertTrue(run.code == 0, "generated PHP Md5.make support should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "68c3a96c6c6f", "generated PHP Bytes.ofString should preserve UTF-8 input for Md5.make");
			assertContains(run.stdout, "be50e8478cf24ff3595bc7307fb91b50", "generated PHP Md5.make should return digest bytes");
		}
		deleteRecursive(md5TmpRoot);

		final sha1TmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_sha1_" + Std.string(Date.now().getTime()));
		deleteRecursive(sha1TmpRoot);
		FileSystem.createDirectory(sha1TmpRoot);
		backend.emit(phpSha1Program(), new BackendContext(sha1TmpRoot, null, "Main", true, false, new StringMap<String>()));
		final sha1Content = File.getContent(Path.join([sha1TmpRoot, "index.php"]));
		assertContains(sha1Content, "class Sha1", "PHP haxe.crypto.Sha1 should be emitted");
		assertContains(sha1Content, "public static function encode($value)", "PHP haxe.crypto.Sha1 should expose encode");
		assertContains(sha1Content, "public static function make($bytes)", "PHP haxe.crypto.Sha1 should expose make(Bytes)");
		if (commandExists("php")) {
			final run = commandOutput("php", [Path.join([sha1TmpRoot, "index.php"])]);
			assertTrue(run.code == 0, "generated PHP Sha1 support should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d", "generated PHP Sha1.encode should hash strings");
			assertContains(run.stdout, "35b5ea45c5e41f78b46a937cc74d41dfea920890", "generated PHP Sha1.make should return digest bytes");
		}
		deleteRecursive(sha1TmpRoot);

		final base64TmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_base64_" + Std.string(Date.now().getTime()));
		deleteRecursive(base64TmpRoot);
		FileSystem.createDirectory(base64TmpRoot);
		backend.emit(phpBase64Program(), new BackendContext(base64TmpRoot, null, "Main", true, false, new StringMap<String>()));
		final base64Content = File.getContent(Path.join([base64TmpRoot, "index.php"]));
		assertContains(base64Content, "class Base64", "PHP haxe.crypto.Base64 should be emitted");
		assertContains(base64Content, "public static function encode($bytes, $complement = true)", "PHP Base64 should expose encode");
		assertContains(base64Content, "public static function decode($value, $complement = true)", "PHP Base64 should expose decode");
		if (commandExists("php")) {
			final run = commandOutput("php", [Path.join([base64TmpRoot, "index.php"])]);
			assertTrue(run.code == 0, "generated PHP Base64 support should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "SMOpbGxvdw==", "generated PHP Base64.encode should emit padded output by default");
			assertContains(run.stdout, "SMOpbGxvdw", "generated PHP Base64.encode should support unpadded output");
			assertContains(run.stdout, "Héllow", "generated PHP Base64.decode should return Bytes with original UTF-8 data");
			assertContains(run.stdout, "exc", "generated PHP Base64.decode should reject invalid input");
		}
		deleteRecursive(base64TmpRoot);

		final baseCodeTmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_basecode_" + Std.string(Date.now().getTime()));
		deleteRecursive(baseCodeTmpRoot);
		FileSystem.createDirectory(baseCodeTmpRoot);
		backend.emit(phpBaseCodeProgram(), new BackendContext(baseCodeTmpRoot, null, "Main", true, false, new StringMap<String>()));
		final baseCodeContent = File.getContent(Path.join([baseCodeTmpRoot, "index.php"]));
		assertContains(baseCodeContent, "class BaseCode", "PHP haxe.crypto.BaseCode should be emitted");
		assertContains(baseCodeContent, "public function encodeString($value)", "PHP BaseCode should expose encodeString");
		assertContains(baseCodeContent, "public function decodeString($value)", "PHP BaseCode should expose decodeString");
		if (commandExists("php")) {
			final run = commandOutput("php", [Path.join([baseCodeTmpRoot, "index.php"])]);
			assertTrue(run.code == 0, "generated PHP BaseCode support should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "iceFr6NLtM", "generated PHP BaseCode should encode alternate base64");
			assertContains(run.stdout, "Héllow", "generated PHP BaseCode should decode alternate base64");
			assertContains(run.stdout, "CPNMU", "generated PHP BaseCode should encode base32-hex");
			assertContains(run.stdout, "foo", "generated PHP BaseCode should decode base32-hex");
		}
		deleteRecursive(baseCodeTmpRoot);

		final stringToolsUrlTmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_stringtools_url_" + Std.string(Date.now().getTime()));
		deleteRecursive(stringToolsUrlTmpRoot);
		FileSystem.createDirectory(stringToolsUrlTmpRoot);
		backend.emit(phpStringToolsUrlProgram(), new BackendContext(stringToolsUrlTmpRoot, null, "Main", true, false, new StringMap<String>()));
		final stringToolsUrlContent = File.getContent(Path.join([stringToolsUrlTmpRoot, "index.php"]));
		assertContains(stringToolsUrlContent, "class StringTools", "PHP StringTools should be emitted");
		assertContains(stringToolsUrlContent, "public static function urlEncode($value)", "PHP StringTools should expose urlEncode");
		assertContains(stringToolsUrlContent, "public static function urlDecode($value)", "PHP StringTools should expose urlDecode");
		if (commandExists("php")) {
			final run = commandOutput("php", [Path.join([stringToolsUrlTmpRoot, "index.php"])]);
			assertTrue(run.code == 0, "generated PHP StringTools URL support should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "%C3%A9", "generated PHP StringTools.urlEncode should encode UTF-8 bytes");
			assertContains(run.stdout, "é", "generated PHP StringTools.urlDecode should decode UTF-8 bytes");
			assertContains(run.stdout, "a%2Fb%2Bc", "generated PHP StringTools.urlEncode should escape slash and plus");
			assertContains(run.stdout, "a/b+c", "generated PHP StringTools.urlDecode should unescape slash and plus");
		}
		deleteRecursive(stringToolsUrlTmpRoot);

		final optionalStringTmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_optional_string_null_" + Std.string(Date.now().getTime()));
		deleteRecursive(optionalStringTmpRoot);
		FileSystem.createDirectory(optionalStringTmpRoot);
		backend.emit(phpOptionalStringNullProgram(), new BackendContext(optionalStringTmpRoot, null, "Main", true, false, new StringMap<String>()));
		final optionalStringContent = File.getContent(Path.join([optionalStringTmpRoot, "index.php"]));
		assertContains(optionalStringContent, "if ($value !== null) $value = __hxhx_to_string_value($value);",
			"PHP optional String parameters should only coerce non-null values");
		assertContains(optionalStringContent, "$this->optTyped(null, \"str\")", "PHP known typed optional calls should pad skipped arguments with null");
		assertContains(optionalStringContent, "if ($x === null) $x = 5;", "PHP defaulted optional parameters should apply defaults to explicit null arguments");
		assertContains(optionalStringContent, "function($a, $b = null)", "PHP closures should accept omitted optional/defaulted arguments");
		if (commandExists("php")) {
			final run = commandOutput("php", [Path.join([optionalStringTmpRoot, "index.php"])]);
			assertTrue(run.code == 0, "generated PHP optional String null support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "true\nhello\ntrue\nstr\n55\ntrue\n5\nhello\n5\n6\n5\n7.4\n5\n7.4\n3\n3\n3\n",
				"generated PHP optional String args should preserve null and align typed optional calls, got:\n" + run.stdout);
		}
		deleteRecursive(optionalStringTmpRoot);

		final xmlTmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_xml_runtime_" + Std.string(Date.now().getTime()));
		deleteRecursive(xmlTmpRoot);
		FileSystem.createDirectory(xmlTmpRoot);
		backend.emit(phpXmlRuntimeProgram(), new BackendContext(xmlTmpRoot, null, "Main", true, false, new StringMap<String>()));
		final xmlContent = File.getContent(Path.join([xmlTmpRoot, "index.php"]));
		assertContains(xmlContent, "class Xml", "PHP runtime should expose a minimal Xml class");
		assertContains(xmlContent, "public static function parse($source)", "PHP Xml runtime should expose parse");
		if (commandExists("php")) {
			final run = commandOutput("php", [Path.join([xmlTmpRoot, "index.php"])]);
			final expected = "true\ntrue\nexc\nexc\nexc\nexc\nexc\ntrue\na\n<b href=\"hello\">World<b/></b>\nhello\nfalse\nhref\n\n<b>World<b/></b>\nWorld\nb\n1\n<a><b><c/> <d/> \\n <e/><![CDATA[<x>]]></b></a>\n\"\ntrue\ntrue\n<!--Hello-->\nHello\n<![CDATA[<x>]]>\nHello\n<?XHTML?>\n<!DOCTYPE XHTML>\nexc\nexc\nexc\nexc\nexc\nexc\nexc\nexc\nexc\n<\n@\nô\n?\nÿ\n<a>&gt;<b>&lt;</b>&lt;&gt;<b>&gt;&lt;</b>\"</a>\n<i>I<a>A</a></i>\n<node key=\"a&quot;b&#039;&amp;c&gt;d&lt;e\"/>\nexc\nexc\nsomething with < & \" ' special characters >\ntrue\ntrue\ntrue\nexc\n";
			assertTrue(run.code == 0, "generated PHP Xml runtime should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == expected, "generated PHP Xml runtime should match TestXML.testBasic subset, got:\n" + run.stdout);
		}
		deleteRecursive(xmlTmpRoot);

		final shadowTmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_scoped_local_shadow_" + Std.string(Date.now().getTime()));
		deleteRecursive(shadowTmpRoot);
		FileSystem.createDirectory(shadowTmpRoot);
		backend.emit(phpScopedLocalShadowProgram(), new BackendContext(shadowTmpRoot, null, "Main", true, false, new StringMap<String>()));
		final shadowContent = File.getContent(Path.join([shadowTmpRoot, "index.php"]));
		assertContains(shadowContent, "$x__hx_scope_", "PHP shadowed locals should be renamed away from the outer variable");
		if (commandExists("php")) {
			final run = commandOutput("php", [Path.join([shadowTmpRoot, "index.php"])]);
			final expected = "hello\n\nhello\n0\nbranch\n0\nloop\n0\nmatched\n0\ncaught\n0\n";
			assertTrue(run.code == 0, "generated PHP scoped locals should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == expected, "generated PHP scoped locals should preserve Haxe shadowing, got:\n" + run.stdout);
		}
		deleteRecursive(shadowTmpRoot);

		final loopCaptureTmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_loop_capture_" + Std.string(Date.now().getTime()));
		deleteRecursive(loopCaptureTmpRoot);
		FileSystem.createDirectory(loopCaptureTmpRoot);
		backend.emit(phpLoopCaptureProgram(), new BackendContext(loopCaptureTmpRoot, null, "Main", true, false, new StringMap<String>()));
		final loopCaptureContent = File.getContent(Path.join([loopCaptureTmpRoot, "index.php"]));
		assertContains(loopCaptureContent, "(function() use (&$funs, &$sum)",
			"PHP loops that create ref-capturing closures should isolate per-iteration locals");
		assertContains(loopCaptureContent, "(function() use (&$i, &$incs, &$total, &$decs)",
			"PHP loops should isolate per-iteration mutable captures while preserving outer writes");
		if (commandExists("php")) {
			final run = commandOutput("php", [Path.join([loopCaptureTmpRoot, "index.php"])]);
			final expected = "1\n1\n1\n3\n1\n0\n0\n0\n2\n1\n1\n0\n3\n2\n2\n0\n";
			assertTrue(run.code == 0, "generated PHP loop captures should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == expected, "generated PHP loop captures should preserve per-iteration closure locals, got:\n" + run.stdout);
		}
		deleteRecursive(loopCaptureTmpRoot);

		final subCaptureTmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_subcapture_" + Std.string(Date.now().getTime()));
		deleteRecursive(subCaptureTmpRoot);
		FileSystem.createDirectory(subCaptureTmpRoot);
		backend.emit(phpSubCaptureProgram(), new BackendContext(subCaptureTmpRoot, null, "Main", true, false, new StringMap<String>()));
		final subCaptureContent = File.getContent(Path.join([subCaptureTmpRoot, "index.php"]));
		assertNotContains(subCaptureContent, "$__hxhx_for_in(",
			"PHP expression-lowered for-in loops should lower to real foreach blocks instead of undefined variable-function calls");
		assertNotContains(subCaptureContent, "use ($i, &$sum)",
			"PHP nested loop capture lowering should not leak inner lambda locals into outer closure captures");
		if (commandExists("php")) {
			final run = commandOutput("php", [Path.join([subCaptureTmpRoot, "index.php"])]);
			assertTrue(run.code == 0, "generated PHP nested subcapture loops should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "10\n15\n20\n25\n30\n",
				"generated PHP nested subcapture loops should preserve closure capture semantics, got:\n" + run.stdout);
		}
		deleteRecursive(subCaptureTmpRoot);

		final eRegTmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_ereg_" + Std.string(Date.now().getTime()));
		deleteRecursive(eRegTmpRoot);
		FileSystem.createDirectory(eRegTmpRoot);
		backend.emit(phpERegProgram(), new BackendContext(eRegTmpRoot, null, "Main", true, false, new StringMap<String>()));
		final eRegContent = File.getContent(Path.join([eRegTmpRoot, "index.php"]));
		assertContains(eRegContent, "class EReg {", "PHP source-native runtime should emit an EReg support class");
		assertContains(eRegContent, "if ($this->last === null || !array_key_exists(0, $this->matches) || $n < 0) throw new \\Exception(\"EReg::matched\");",
			"PHP EReg.matched should throw when called before any successful match");
		assertContains(eRegContent, "__hxhx_string_substr($r->matched(0), 1)",
			"PHP should lower chained EReg.matched(...).substr(...) through the string helper");
		if (commandExists("php")) {
			final run = commandOutput("php", [Path.join([eRegTmpRoot, "index.php"])]);
			final expected = "m1=true\n" + "g0=aabca\n" + "g1=b\n" + "g2=c\n" + "left=xx\n" + "right=yyy\n" + "pos=2,len=5\n" + "m2=true\n" + "dg0=12\n"
				+ "dleft=ab\n" + "dright=cd\n" + "rep=a#b#c\n" + "parts=a|b|c\n" + "map=a[1]b[22]c\n" + "mapsub=[aa]b[]cx\n"
				+ "mapzero=[]a[]a[]a[]b[]a[]c[x]\n" + "sub0=true\n" + "sub0right=bab\n" + "sub1=true\n" + "sub1left=ab\n" + "sub1right=b\n" + "esc=a\\+b\n";
			assertTrue(run.code == 0, "generated PHP EReg runtime should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == expected, "generated PHP EReg runtime should preserve core regex behavior, got:\n" + run.stdout);
		}
		deleteRecursive(eRegTmpRoot);

		final anonCallableTmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_anon_callable_" + Std.string(Date.now().getTime()));
		deleteRecursive(anonCallableTmpRoot);
		FileSystem.createDirectory(anonCallableTmpRoot);
		backend.emit(phpAnonCallableFieldProgram(), new BackendContext(anonCallableTmpRoot, null, "Main", true, false, new StringMap<String>()));
		final anonCallableContent = File.getContent(Path.join([anonCallableTmpRoot, "index.php"]));
		assertContains(anonCallableContent, "class __HxAnon {", "PHP anonymous-object runtime should expose callable field dispatch");
		assertContains(anonCallableContent, "new __HxAnon([\"inc\" => function() use (&$count)",
			"PHP anonymous object literals should preserve callable closure fields");
		if (commandExists("php")) {
			final run = commandOutput("php", [Path.join([anonCallableTmpRoot, "index.php"])]);
			assertTrue(run.code == 0, "generated PHP anonymous callable fields should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "2\n2\n", "generated PHP anonymous callable fields should preserve closure dispatch, got:\n" + run.stdout);
		}
		deleteRecursive(anonCallableTmpRoot);
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

	static function assertPhpTypeErrorExpressionProbe():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_type_error_expression_probe_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpTypeErrorExpressionProbeProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertNotContains(content, "$typeError(", "PHP source backend should fold unqualified typeError expression probes");
		assertContains(content, "$badFloat = true;", "PHP source backend should flag Float assigned to {v:Int} expression probes");
		assertContains(content, "$okInt = false;", "PHP source backend should accept Int assigned to {v:Int} expression probes");
		assertContains(content, "$badString = true;", "PHP source backend should flag String assigned to {v:Int} expression probes");
		assertContains(content, "$badExtra = true;", "PHP source backend should flag extra fields in constant anonymous expression probes");
		assertContains(content, "$okPointCall = false;", "PHP source backend should accept well-formed anonymous argument expression probes");
		assertContains(content, "$okSizeCall = false;", "PHP source backend should accept alternate anonymous argument expression probes");
		assertContains(content, "$duplicateMapKey = true;", "PHP source backend should flag duplicate map literal keys in typeError probes");
		assertContains(content, "$mixedMapKey = true;", "PHP source backend should flag mixed map literal key kinds in typeError probes");
		assertContains(content, "$mixedMapValue = true;", "PHP source backend should flag mixed map literal value kinds in typeError probes");
		assertContains(content, "$okMapLiteral = false;", "PHP source backend should accept consistent map literal typeError probes");
		assertContains(content, "$badAbstractAdd = true;", "PHP source backend should fold incompatible abstract overload addition probes");
		assertContains(content, "$badAbstractSub = true;", "PHP source backend should fold missing abstract overload subtraction probes");
		assertContains(content, "$badAbstractNot = true;", "PHP source backend should fold unsupported abstract logical-not probes");
		assertContains(content, "$badAbstractPostfix = true;", "PHP source backend should fold unsupported abstract postfix probes");
		assertContains(content, "$badOptionalSkip = true;", "PHP source backend should fold optional-parameter skip typeError probes");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP typeError expression probes should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "true\nfalse\ntrue\ntrue\nfalse\nfalse\ntrue\ntrue\ntrue\nfalse\ntrue\ntrue\ntrue\ntrue\ntrue\n",
				"generated PHP typeError expression probes should preserve expected results, got:\n" + run.stdout);
		}
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

	static function assertPhpAbstractCastConstraint():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_abstract_cast_constraint_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpAbstractCastConstraintProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "$s = __hxhx_to_string_value($z);", "PHP abstract-constrained String assignments should lower through scalar conversion");
		assertContains(content, "$i = __hxhx_int_value($zi);", "PHP abstract-constrained Int assignments should lower through scalar conversion");
		assertContains(content, "$badInt = true;", "PHP unqualified typeError should fold abstract String-to-Int probes");
		assertContains(content, "$badString = true;", "PHP unqualified typeError should fold abstract Int-to-String probes");
		assertContains(content, "Helper::t(true);", "PHP nested source-parsed typeError probes should fold abstract Int-to-String probes");
		assertNotContains(content, "$typeError(", "PHP abstract cast constraint probes should not emit runtime typeError calls");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP abstract cast constraint support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "foo\n13\ntrue\ntrue\n", "generated PHP abstract cast constraint output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpLoweredAbstractCastTypeErrorProbe():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_lowered_abstract_cast_type_error_probe_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpLoweredAbstractCastTypeErrorProbeProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "$badInt = true;", "PHP typeError should fold lowered lambda Int abstract-cast probes");
		assertContains(content, "$badString = true;", "PHP typeError should fold lowered lambda String abstract-cast probes");
		assertContains(content, "$badScopedString = true;", "PHP typeError should fold scoped lowered lambda String abstract-cast probes");
		assertContains(content, "$tester->t(true);", "PHP typeError should fold nested test-helper abstract-cast probes");
		assertNotContains(content, "$typeError(", "PHP lowered abstract-cast probes should not emit runtime typeError calls");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP lowered abstract-cast typeError probes should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "true\ntrue\ntrue\n", "generated PHP lowered abstract-cast typeError probe output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpTypedAsHelperProbe():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_typed_as_helper_probe_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpTypedAsHelperProbeProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertNotContains(content, "$typedAs(", "PHP source backend should fold unqualified HelperMacros.typedAs compile-time probes");
		assertNotContains(content, "HelperMacros::typedAs", "PHP source backend should fold qualified HelperMacros.typedAs compile-time probes");
		assertContains(content, "echo \"typedAs-ok\" . PHP_EOL;", "folded typedAs probes should keep following runtime statements reachable");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP typedAs helper probes should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "typedAs-ok\n", "generated PHP typedAs helper probe output mismatch, got:\n" + run.stdout);
		}
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
		assertContains(content, "$my->invert()->get()", "PHP abstract-style unary minus should dispatch the known operator method before member access");
		assertContains(content, "return __hxhx_construct_like($left, $sum);",
			"PHP abstract-style numeric addition should preserve the left boxed abstract shape");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpAbstractThisClosureCapture():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_abstract_this_closure_capture_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpAbstractThisClosureCaptureProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "(function($__hxhx_this_value) { return function() use ($__hxhx_this_value)",
			"PHP abstract-style lambdas should capture this backing value at closure creation time");
		assertContains(content, "})(__hxhx_copy_value($this->__hx_value))",
			"PHP abstract-style lambda captures should snapshot the backing slot instead of late-binding $this");
		assertNotContains(content, "return $this; };", "PHP abstract-style lambdas should not return the mutable wrapper object");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP abstract closure capture should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "foo\nfoo\nbar\n", "generated PHP abstract closure capture output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpExposingAbstractArray():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_exposing_abstract_array_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpExposingAbstractArrayProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "function __hxhx_array_push(&$array, $value)", "PHP runtime should expose an abstract-aware Array.push helper");
		assertContains(content, "function __hxhx_array_pop(&$array)", "PHP runtime should expose an abstract-aware Array.pop helper");
		assertContains(content, "__hxhx_array_push($exposing, 12)", "PHP array-backed abstract push should lower through the shared helper");
		assertContains(content, "__hxhx_array_pop($exposing)", "PHP array-backed abstract pop should lower through the shared helper");
		assertContains(content, "$array->__hx_value[] = $value", "PHP Array.push helper should mutate abstract-wrapper backing arrays");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP exposing-abstract array support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "1\n12\nnull\n", "generated PHP exposing-abstract array output mismatch, got:\n" + run.stdout);
		}
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
		assertNotContains(content, "Child::fProp(", "PHP function-valued property calls should not lower as undefined class methods");
		assertNotContains(content, "->fProp(", "PHP function-valued property calls should not lower as undefined instance methods");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP super property support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "2\n5\ntest2\ntest09\n", "generated PHP super property output mismatch, got:\n" + run.stdout);
		}
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

	static function assertPhpTypedMapLiteralWithLambdaField():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_typed_map_lambda_field_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpTypedMapLiteralWithLambdaFieldProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "__hxhx_map_literal([[1, function($value) {", "PHP typed map assignments should preserve map literal entries");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP typed map lambda field support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "42\n", "generated PHP typed map lambda field output mismatch, got:\n" + run.stdout);
		}
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

	static function assertPythonSysEnvironmentRuntimeShim():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_sys_environment_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final pos = HxPos.unknown();
		final existsCall:HxExpr = ECall(EField(ECall(EField(EIdent("Sys"), "environment"), []), "exists"), [EString("__HXHX_NO_SUCH_ENV__")]);
		final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [
			SExpr(ECall(EField(EIdent("Sys"), "println"), [ECall(EField(EIdent("Std"), "string"), [existsCall])]), pos)
		], "");
		final mainClass = new HxClassDecl("Main", true, [mainFn]);
		final mainDecl = new HxModuleDecl("", [], mainClass, [mainClass], false, false);
		final program = MacroStage.expandProgram([typedSyntheticModule("Main.hx", mainDecl)], []);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("python-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "Main.py"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class Sys:", "Python runtime should define Sys for direct Sys.environment calls");
		assertContains(content, "def environment():", "Python Sys shim should expose environment");
		assertContains(content, "return Map(os.environ.items())", "Python Sys.environment should return a map-like object with exists");
		if (commandExists("python3")) {
			final run = commandOutput("python3", [outputPath]);
			assertTrue(run.code == 0, "generated Python Sys.environment shim should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "False", "missing environment keys should report false through exists");
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

	static function assertJavaUtilityProcessRuntime():Void {
		if (!commandExists("javac") || !commandExists("jar") || !commandExists("java"))
			return;
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_java_utility_process_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final outputDir = Path.join([tmpRoot, "bin", "java", "UtilityProcess-Debug"]);
		final backend = BackendRegistry.requireForTarget("java-native");
		final result = backend.emit(javaUtilityProcessRuntimeProgram(),
			new BackendContext(outputDir, null, "UtilityProcess", true, true, new StringMap<String>()));
		final sourcePath = Path.join([outputDir, "src", "UtilityProcess.java"]);
		final content = File.getContent(sourcePath);
		assertContains(content, "hxhx Java sys runtime shim", "Java UtilityProcess entrypoint should use the runtime shim");
		assertNotContains(content, "compile shim", "Java UtilityProcess should not keep the compile-only shim");
		assertTrue(FileSystem.exists(result.entryPath), "Java UtilityProcess runtime shim should still package a jar");
		final argsRun = commandOutput("java", ["-jar", result.entryPath, "args", "hello"]);
		assertTrue(argsRun.code == 0, "Java UtilityProcess args case should exit cleanly: " + argsRun.stderr);
		assertContains(argsRun.stdout, "hello", "Java UtilityProcess args case should print the provided argument");
		final stdinRun = commandOutputWithInput("java", ["-jar", result.entryPath, "stdin.readLine"], "line-one\n");
		assertTrue(stdinRun.code == 0, "Java UtilityProcess stdin.readLine case should exit cleanly: " + stdinRun.stderr);
		assertContains(stdinRun.stdout, "line-one", "Java UtilityProcess stdin.readLine case should echo one input line");
		final stdoutRun = commandOutput("java", ["-jar", result.entryPath, "stdout.writeString", "out-text", "nfc"]);
		assertTrue(stdoutRun.code == 0, "Java UtilityProcess stdout.writeString case should exit cleanly: " + stdoutRun.stderr);
		assertContains(stdoutRun.stdout, "out-text", "Java UtilityProcess stdout.writeString case should write to stdout");
		final unicodeRun = commandOutput("java", ["-jar", result.entryPath, "stdout.writeString", "14", "nfd"]);
		final unicodeExpected = String.fromCharCode(0x0061) + String.fromCharCode(0x0307);
		assertTrue(unicodeRun.code == 0, "Java UtilityProcess indexed Unicode case should exit cleanly: " + unicodeRun.stderr);
		assertTrue(unicodeRun.stdout == unicodeExpected, "Java UtilityProcess indexed Unicode case should decode sequence arguments");
		final stderrRun = commandOutput("java", ["-jar", result.entryPath, "stderr.writeString", "err-text", "nfc"]);
		assertTrue(stderrRun.code == 0, "Java UtilityProcess stderr.writeString case should exit cleanly");
		assertContains(stderrRun.stderr, "err-text", "Java UtilityProcess stderr.writeString case should write to stderr");
		final envRun = commandOutput("java", [
			"-Dhxhx.utility.test=value",
			"-jar",
			result.entryPath,
			"getEnv",
			"hxhx.utility.test"
		]);
		assertTrue(envRun.code == 0, "Java UtilityProcess getEnv case should exit cleanly: " + envRun.stderr);
		assertContains(envRun.stdout, "value", "Java UtilityProcess getEnv should read JVM/system environment values");
		final exitRun = commandOutput("java", ["-jar", result.entryPath, "exitCode", "7"]);
		assertTrue(exitRun.code == 7, "Java UtilityProcess exitCode case should propagate exit status");
		deleteRecursive(tmpRoot);
	}

	static function assertJavaFileSystemFullPathResolvesSymlink():Void {
		if (!commandExists("javac") || !commandExists("jar") || !commandExists("java") || !commandExists("ln"))
			return;
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_java_filesystem_" + Std.string(Date.now().getTime()));
		function cleanup() {
			if (commandExists("rm"))
				Sys.command("rm", ["-rf", tmpRoot]);
			else
				deleteRecursive(tmpRoot);
		}
		cleanup();
		final targetDir = Path.join([tmpRoot, "real-target"]);
		final linkPath = Path.join([tmpRoot, "linked-target"]);
		FileSystem.createDirectory(tmpRoot);
		FileSystem.createDirectory(targetDir);
		final linkCode = Sys.command("ln", ["-s", FileSystem.fullPath(targetDir), linkPath]);
		if (linkCode != 0) {
			cleanup();
			return;
		}
		final outputDir = Path.join([tmpRoot, "bin", "java", "Main-Debug"]);
		final backend = BackendRegistry.requireForTarget("java-native");
		final result = backend.emit(javaFileSystemFullPathProgram(FileSystem.fullPath(linkPath)),
			new BackendContext(outputDir, null, "Main", true, true, new StringMap<String>()));
		final sourcePath = Path.join([outputDir, "src", "sys", "FileSystem.java"]);
		assertTrue(FileSystem.exists(sourcePath), "Java source backend should emit a sys.FileSystem support stub");
		final run = commandOutput("java", ["-jar", result.entryPath]);
		assertTrue(run.code == 0, "Java FileSystem.fullPath symlink case should run: " + run.stderr);
		assertContains(Path.normalize(run.stdout), Path.normalize(FileSystem.fullPath(targetDir)),
			"Java FileSystem.fullPath should resolve symlinks to their real target");
		cleanup();
	}

	static function assertPhpTypeCheck():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_type_check_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpTypeCheckProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content,
			"__hxhx_add_string((is_int($i) || (is_float($i) && is_finite($i) && floor($i) == $i && $i >= -2147483648 && $i <= 2147483647)))",
			"PHP `is Int` checks should accept in-range integral Float values like Haxe");
		assertContains(content, "__hxhx_add_string(is_string($s))", "PHP `is String` checks should lower to is_string");
		assertContains(content, "__hxhx_add_string((is_int($i) || is_float($i)))", "PHP direct `is Float` checks should accept Int values like Haxe");
		assertContains(content, "__hxhx_is_of_type($i, \"Float\")", "PHP Std.isOfType Float checks should use the runtime helper");
		assertContains(content, "__hxhx_is_of_type($i, $c)", "PHP Std.isOfType should accept dynamic class values");
		assertContains(content, "__hxhx_is_of_type(10000000000.0, \"Int\")", "PHP whole-number Float literals should stay floats");
		assertContains(content, "case \"Float\": return is_int($value) || is_float($value) || ($hasBoxedValue && __hxhx_is_of_type($boxedValue, $type));",
			"PHP Std.isOfType Float should accept Int values like Haxe and boxed abstract values");
		assertContains(content,
			"case \"Int\": return is_int($value) || (is_float($value) && is_finite($value) && floor($value) == $value && $value >= -2147483648 && $value <= 2147483647) || ($hasBoxedValue && __hxhx_is_of_type($boxedValue, $type));",
			"PHP Std.isOfType Int should accept in-range integral Float values like Haxe and boxed abstract values");
		assertContains(content, "case \"haxe.ds.List\": return $value instanceof List_;",
			"PHP Std.isOfType List should recognize the sanitized List runtime class");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP type checks should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "true\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\nfalse\ntrue\nfalse\ntrue\nfalse\nfalse\ntrue\nfalse\nfalse\ntrue\ntrue\nfalse\nfalse\ntrue\ntrue\ntrue\n",
				"generated PHP type check output mismatch, got:\n"
				+ run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpInterfaceCasts():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_interface_casts_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpInterfaceCastProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "interface CapA {", "PHP source backend should emit Haxe interfaces as PHP interfaces");
		assertContains(content, "interface CapB extends CapA {", "PHP source backend should preserve interface inheritance");
		assertContains(content, "class OnlyA implements CapA {", "PHP source backend should preserve class interface implementation");
		assertContains(content, "class Both implements CapB {", "PHP source backend should preserve transitive interface implementation");
		assertContains(content, "__hxhx_cast($a, \"CapA\")", "PHP nominal casts should use the runtime cast helper");
		assertContains(content, "__hxhx_cast($a, \"CapB\")", "PHP failed interface casts should be checked at runtime");
		assertContains(content, "interface_exists($candidate)", "PHP runtime type checks should include interface candidates");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP interface casts should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "true\nraised\ntrue\ntrue\n", "generated PHP interface cast output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpArrayDynamicCasts():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_array_dynamic_casts_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpArrayDynamicCastProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "__hxhx_cast($values, \"Array\")", "PHP Array<Dynamic> casts should normalize to the Array runtime type");
		assertNotContains(content, "__hxhx_cast($values, \"Array<Dynamic>\")", "PHP Array<Dynamic> casts should not use generic type text at runtime");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP Array<Dynamic> casts should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "3\n", "generated PHP Array<Dynamic> cast output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpAbstractValueCasts():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_abstract_value_casts_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpAbstractValueCastProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertNotContains(content, "__hxhx_cast(1, \"Wrap\")", "PHP abstract value casts should not lower through nominal runtime casts");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP abstract value casts should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "1\n", "generated PHP abstract value cast output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpSyntaxIntrinsics():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_syntax_intrinsics_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpSyntaxIntrinsicProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "$one + $two", "PHP Syntax.code should inline literal PHP with rendered arguments");
		assertContains(content, "__hxhx_field($anon, \"field\")", "PHP Syntax.field should lower through the field helper");
		assertNotContains(content, "Syntax::code", "imported php.Syntax.code should not emit a runtime class call");
		assertNotContains(content, "Syntax::field", "imported php.Syntax.field should not emit a runtime class call");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP Syntax intrinsic support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "3\nok\n", "generated PHP Syntax intrinsic output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);

		final userTmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_user_syntax_class_" + Std.string(Date.now().getTime()));
		deleteRecursive(userTmpRoot);
		FileSystem.createDirectory(userTmpRoot);
		backend.emit(phpUserSyntaxClassProgram(), new BackendContext(userTmpRoot, null, "Main", true, false, new StringMap<String>()));
		final userOutputPath = Path.join([userTmpRoot, "index.php"]);
		final userContent = File.getContent(userOutputPath);
		assertContains(userContent, "class Syntax {", "PHP user classes named Syntax should still be emitted normally");
		assertContains(userContent, "Syntax::code(\"ok\")", "PHP user Syntax classes should keep normal static calls");
		if (commandExists("php")) {
			final userRun = commandOutput("php", [userOutputPath]);
			assertTrue(userRun.code == 0, "generated PHP user Syntax class should execute, stderr:\n" + userRun.stderr);
			assertTrue(userRun.stdout == "user:ok\n", "generated PHP user Syntax class output mismatch, got:\n" + userRun.stdout);
		}
		deleteRecursive(userTmpRoot);
	}

	static function assertPhpNullEquality():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_null_equality_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpNullEqualityProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "if ($left === null || $right === null) return $left === $right;",
			"PHP equality helper should preserve Haxe null equality before PHP loose equality");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP null equality support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "false\nfalse\ntrue\n", "generated PHP null equality output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpUserClassTypeCheck():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_user_class_type_check_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpUserClassTypeCheckProgram(), new BackendContext(tmpRoot, null, "unit.Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "__hxhx_is_of_type($value, \"MyClass\")", "PHP direct user-class `is` checks should use the runtime type helper");
		assertContains(content, "__hxhx_is_of_type($value, $c)", "PHP direct `is` checks should accept dynamic class values");
		assertContains(content, "__hxhx_class_value(\"MyClass\")", "PHP class values should be tagged separately from ordinary strings");
		assertContains(content, "class __HxClassValue", "PHP runtime should tag class meta-values so they are not ordinary strings");
		assertContains(content, "public static function createInstance($cls, $args)", "PHP Type should expose createInstance");
		assertContains(content, "__hxhx_runtime_class_name($cls)", "PHP Type.createInstance should resolve Haxe class values to emitted PHP classes");
		assertContains(content, "public static function createEmptyInstance($cls)", "PHP Type should expose createEmptyInstance");
		assertContains(content, "newInstanceWithoutConstructor()", "PHP Type.createEmptyInstance should allocate without running the constructor");
		assertContains(content, "$resolved = __hxhx_class_name($type)", "PHP runtime type helper should resolve class aliases before instanceof checks");
		assertContains(content, "str_replace(\".\", \"\\\\\", $resolved)", "PHP runtime type helper should try package-qualified PHP class names");
		assertContains(content, "case \"Class\": case \"Class<Dynamic>\": case \"Class_\": $candidate = __hxhx_class_candidate($value);",
			"PHP runtime type helper should classify class values through canonical class candidates");
		assertContains(content, "if ($type === null) return false;", "PHP null pseudo-type checks should match upstream Std.isOfType behavior");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP user class type checks should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "true\ntrue\ntrue\ntrue\ntrue\ntrue\nfalse\nfalse\nfalse\nfalse\nfalse\ntrue\ntrue\ntrue\nfalse\ntrue\nunit.MyClass\nunit.MyClass\ntrue\n33\n55\ntrue\ntrue\ntrue\ntrue\n",
				"generated PHP user class type check output mismatch, got:\n"
				+ run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpEnumTypeCheck():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_enum_type_check_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpEnumTypeCheckProgram(), new BackendContext(tmpRoot, null, "unit.Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "\"__hx_enum\" => \"MyEnum\"", "PHP scanned enum values should carry their enum type marker");
		assertContains(content, "public static $__hx_is_enum = true;", "PHP scanned enum helpers should mark enum class values");
		assertContains(content, "$enumName = __hxhx_class_name($value->__hx_enum)", "PHP runtime type helper should canonicalize enum value type markers");
		assertContains(content, "case \"Enum\": case \"Enum<Dynamic>\": case \"Enum_\": return __hxhx_is_enum_class_value($value);",
			"PHP runtime type helper should classify enum class values without accepting enum records");
		assertContains(content, "$enumShort === $short", "PHP runtime type helper should allow short enum markers to match package-qualified type values");
		assertContains(content, "property_exists($candidate, $ctor) || method_exists($candidate, $ctor)",
			"PHP runtime type helper should recognize enum records that only carry constructor metadata");
		assertContains(content, "public static function createEnum($enum, $ctor, $args = null)", "PHP Type should expose createEnum");
		assertContains(content, "public static function getEnumConstructs($enum)", "PHP Type should expose getEnumConstructs");
		assertContains(content, "public static function allEnums($enum)", "PHP Type should expose allEnums");
		assertContains(content, "return $runtime::${$name};", "PHP Type.createEnum should return no-arg enum constructor fields");
		assertContains(content, "return $runtime::$name(...array_values($args));", "PHP Type.createEnum should invoke enum constructor methods");
		assertNotContains(content, "$__unprotect__", "PHP upstream __unprotect__ test helper should lower to its wrapped expression");
		assertContains(content, "if ($type === null) return false;", "PHP null pseudo-type checks should match upstream Std.isOfType behavior");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP enum type checks should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "true\ntrue\ntrue\ntrue\ntrue\nfalse\ntrue\nfalse\nfalse\nfalse\nunit.MyEnum\nA|B\ntrue\nA\ntrue\n1\ntrue\n55\nexc\nexc\nexc\n",
				"generated PHP enum type check output mismatch, got:\n"
				+ run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpTypeReflection():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_type_reflection_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpTypeReflectionProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class Type {", "PHP runtime should emit the Type support class");
		assertContains(content, "public static function getClassName($cls)", "PHP Type runtime should expose getClassName");
		assertContains(content, "public static function resolveClass($name)", "PHP Type runtime should expose resolveClass");
		assertContains(content, "\"List\" => \"haxe.ds.List\"", "PHP class-name map should include imported haxe.ds.List alias");
		assertContains(content, "\"List_\" => \"haxe.ds.List\"", "PHP class-name map should include sanitized haxe.ds.List runtime alias");
		assertContains(content, "class List_ implements \\IteratorAggregate", "PHP runtime should emit a sanitized List support class");
		assertContains(content, "$values = new List_()", "PHP haxe.ds.List construction should lower to the runtime shim");
		assertContains(content, "__hxhx_is_of_type($values, \"List\")", "PHP Std.isOfType should check haxe.ds.List values through the runtime helper");
		assertContains(content, "$stringMap = new Map(null, \"haxe.ds.StringMap\")", "PHP haxe.ds.StringMap construction should tag the Map runtime shim");
		assertContains(content, "$stringMap instanceof Map && $stringMap->__hx_type === \"haxe.ds.StringMap\"",
			"PHP direct haxe.ds.StringMap checks should require the Map runtime tag");
		assertContains(content, "__hxhx_is_of_type($stringMap, \"StringMap\")", "PHP Std.isOfType should check haxe.ds.StringMap through the runtime helper");
		assertContains(content,
			"[__hxhx_class_value(\"String\"), __hxhx_class_value(\"Array\"), __hxhx_class_value(\"List\"), __hxhx_class_value(\"ReflectThing\"), __hxhx_class_value(\"MyReflectEnum\")]",
			"PHP class and enum literals in value position should lower to tagged reflection values");
		assertContains(content, "Type::getClassName(__hxhx_array_get($types, 0))", "PHP Type.getClassName should accept dynamic class values from arrays");
		assertContains(content, "public static function getInstanceFields($cls)", "PHP Type runtime should expose getInstanceFields");
		assertContains(content, "public static function getClassFields($cls)", "PHP Type runtime should expose getClassFields");
		assertContains(content, "public static function typeof($value)", "PHP Type runtime should expose typeof");
		assertContains(content, "__hxhx_value_type(\"TClass\", 6", "PHP ValueType constructors should lower to enum-like runtime values");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP Type reflection support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "String\nArray\ntrue\ntrue\ntrue\nhaxe.ds.List\ntrue\nReflectThing\ntrue\nmethod#value\nhelper#stat\nget_x#set_x#set_y#y\nget_sx#set_sx#set_sy#sy\nMyReflectEnum\ntrue\nString\ntrue\ntrue\nhaxe.ds.List\n2\na\nb\ntrue\ntrue\nhaxe.ds.StringMap\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\n",
				"generated PHP Type reflection output mismatch, got:\n"
				+ run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpGenericStaticReflection():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_generic_static_reflection_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpGenericStaticReflectionProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "public static function gf1_Int($value)", "PHP @:generic static calls should emit reflected specialization wrappers");
		assertContains(content, "public static function gf1_haxe_ds_GenericStack_Int($value)",
			"PHP @:generic static reflection should preserve constructed generic type suffixes");
		assertContains(content, "public static function gf1_func_Int_String($value)",
			"PHP @:generic static reflection should preserve typed function literal suffixes");
		assertContains(content, "public static function gf2_String_Int($label, $values)",
			"PHP @:generic static reflection should bind Array<T> arguments to their generic item type");
		assertContains(content, "public static function gf2_String_Array_Int($label, $values)",
			"PHP @:generic static reflection should bind nested Array<T> arguments to nested generic item types");
		assertContains(content, "public static function gf3_GenericBox_Array_GenericBox($seed, $values)",
			"PHP @:generic static reflection should bind empty-array direct generic parameters from prior object bindings");
		assertContains(content, "GenericReflect::overloadFake_String(\"bar\")",
			"PHP @:generic static String calls should prefer explicit specialized implementations");
		assertContains(content, "return self::gf1($value);", "PHP @:generic specialization wrappers should delegate to the generic implementation");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP generic static reflection support should execute, stderr:\n" + run.stderr);
			final lines = run.stdout.split("\n");
			assertTrue(lines.length >= 12, "generated PHP generic static reflection output too short, got:\n" + run.stdout);
			for (i in 1...10)
				assertTrue(lines[i] == "true", "generated PHP generic static reflection field check failed, got:\n" + run.stdout);
			assertTrue(lines[10] == "1", "generated PHP same-class generic static int call should keep generic behavior, got:\n" + run.stdout);
			assertTrue(lines[11] == "barfoo", "generated PHP same-class generic static String call should use explicit specialization, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpGenericStaticReflectionTextFallback():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_generic_static_text_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpGenericStaticReflectionTextFallbackProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final content = File.getContent(Path.join([tmpRoot, "index.php"]));
		assertContains(content, "public static function gf2_String_Int($label, $values)",
			"PHP raw-body @:generic reflection should bind Array<T> arguments to item type");
		assertContains(content, "public static function gf2_String_Array_Int($label, $values)",
			"PHP raw-body @:generic reflection should bind nested Array<T> arguments to nested item type");
		deleteRecursive(tmpRoot);
	}

	static function assertPhpGenericConstructible():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_generic_constructible_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpGenericConstructibleProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "__hxhx_construct_like($seed, \"tail\")",
			"PHP constructible generic constructor should lower through runtime sample construction");
		assertContains(content, "new MyGeneric(function($i)", "PHP constructor parser should preserve arguments after function-type constructor parameters");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP constructible generic support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "tail\nfalse\ntail\n4\n", "generated PHP constructible generic output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpTypeErrorGenericNull():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_type_error_generic_null_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpTypeErrorGenericNullProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "echo __hxhx_add_string(true)", "PHP typeError(generic(null)) should fold to the helper macro result");
		assertNotContains(content, "$typeError", "PHP typeError(generic(null)) should not lower as a runtime variable call");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP typeError generic-null support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "true\n", "generated PHP typeError generic-null output mismatch, got:\n" + run.stdout);
		}
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

	static function assertPythonModuloUsesHaxeRemainderSemantics():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_python_modulo_semantics_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final src = [
			"class Main {",
			"  static function main() {",
			"    var a:Int = -5;",
			"    a %= 7;",
			"    Sys.println(Std.string(a));",
			"    Sys.println(Std.string(-5 % 7));",
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
		assertContains(content, "def hxhx_mod(left, right):", "Python runtime should include a Haxe-style modulo helper");
		assertContains(content, "a = hxhx_mod(a, 7)", "Python modulo assignment should lower through the Haxe-style modulo helper");
		assertContains(content, "hxhx_mod((-5), 7)", "Python modulo expressions should lower through the Haxe-style modulo helper");
		if (commandExists("python3")) {
			final run = commandOutput("python3", [outputPath]);
			assertTrue(run.code == 0, "generated Python modulo helper should execute, stderr:\n" + run.stderr);
			assertContains(run.stdout, "-5\n-5", "generated Python modulo should preserve Haxe signed remainder behavior");
		}
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

	static function assertPhpDateRuntimeSupport():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_date_runtime_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final src = [
			"class Main {",
			"  static function main() {",
			"    var d = new Date(2012, 7, 17, 1, 2, 3);",
			"    Sys.println(d.getDay());",
			"    Sys.println(d.getDate());",
			"    Sys.println(d.getMonth());",
			"    Sys.println(d.getFullYear());",
			"    Sys.println(d.getHours());",
			"    Sys.println(d.getMinutes());",
			"    Sys.println(d.getSeconds());",
			"    Sys.println(d.toString());",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		final program = MacroStage.expandProgram([typed], []);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class Date {", "PHP runtime should provide the Haxe Date class");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP Date runtime support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "5\n17\n7\n2012\n1\n2\n3\n2012-08-17 01:02:03\n",
				"generated PHP Date runtime support should match Haxe local Date getters, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpHaxeJsonRuntimeSupport():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_haxe_json_runtime_" + Std.string(Date.now().getTime()));
		final srcDir = Path.join([tmpRoot, "src"]);
		final haxeDir = Path.join([srcDir, "haxe"]);
		final unitDir = Path.join([srcDir, "unit"]);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(haxeDir);
		FileSystem.createDirectory(unitDir);
		final src = [
			"package unit;",
			"",
			"import haxe.Json;",
			"",
			"class Main {",
			"  static function main() {",
			"    var parsed = Json.parse(\"{\\\"name\\\":\\\"hx\\\",\\\"nums\\\":[1,2],\\\"ok\\\":true}\");",
			"    Sys.println(parsed.name + \":\" + parsed.nums[1] + \":\" + parsed.ok);",
			"    var encoded = Json.stringify({name: \"hx\", nums: [1, 2], ok: true});",
			"    Sys.println(Json.parse(encoded).name);",
			"  }",
			"}",
		].join("\n");
		File.saveContent(Path.join([haxeDir, "Json.hx"]), [
			"package haxe;",
			"extern class Json {",
			"  static function parse(text:String):Dynamic;",
			"  static function stringify(value:Dynamic, ?replacer:Dynamic, ?space:String):String;",
			"}",
		].join("\n"));
		File.saveContent(Path.join([unitDir, "Main.hx"]), src);
		final resolved = ResolverStage.parseProjectRoots([srcDir], ["unit.Main"], new StringMap<String>());
		final index = TyperIndex.build(resolved);
		final loader = new ModuleLoader([srcDir], new StringMap<String>(), index, function(_typePath:String):Bool {
			return false;
		});
		loader.markResolvedAlready(resolved);
		final typed = new Array<TypedModule>();
		for (module in resolved)
			typed.push(TyperStage.typeResolvedModule(module, index, loader));
		final program = MacroStage.expandProgram(typed, []);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "unit.Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class Json {", "PHP haxe namespace support should provide haxe.Json");
		assertContains(content, "\\haxe\\Json::parse", "PHP imported haxe.Json calls should reference the namespaced runtime class");
		assertContains(content, "\\haxe\\Json::stringify", "PHP imported haxe.Json stringify should reference the namespaced runtime class");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP haxe.Json runtime support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "hx:2:true\nhx\n", "generated PHP haxe.Json runtime support output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpHaxeJsonStringifyReplacer():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_haxe_json_replacer_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final src = [
			"class Main {",
			"  static function main() {",
			"    var encoded = haxe.Json.stringify({keep: 1, drop: 2}, function(key:String, value:Dynamic) {",
			"      if (key == \"drop\") return null;",
			"      return value;",
			"    });",
			"    Sys.println(encoded);",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		final program = MacroStage.expandProgram([typed], []);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "$replacer(strval($key), $value)", "PHP haxe.Json should call replacers with key and value");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP haxe.Json replacer support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "{\"keep\":1,\"drop\":null}\n", "generated PHP haxe.Json replacer output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpHaxeJsonNonFiniteMathConstants():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_haxe_json_nonfinite_math_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final src = [
			"class Main {",
			"  static function main() {",
			"    Sys.println(haxe.Json.stringify(Math.POSITIVE_INFINITY));",
			"    Sys.println(haxe.Json.stringify(Math.NEGATIVE_INFINITY));",
			"    Sys.println(haxe.Json.stringify(Math.NaN));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		final program = MacroStage.expandProgram([typed], []);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "haxe\\Json::stringify(INF)", "PHP Math.POSITIVE_INFINITY should lower to the native INF constant");
		assertContains(content, "haxe\\Json::stringify(-INF)", "PHP Math.NEGATIVE_INFINITY should lower to the native -INF constant");
		assertContains(content, "haxe\\Json::stringify(NAN)", "PHP Math.NaN should lower to the native NAN constant");
		assertNotContains(content, "Math::$POSITIVE_INFINITY", "PHP Math.POSITIVE_INFINITY should not render as an undeclared static property");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP haxe.Json non-finite Math constants should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "null\nnull\nnull\n", "generated PHP haxe.Json non-finite Math constants output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpHaxeFormatJsonPrinterRuntimeSupport():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_haxe_format_json_printer_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final src = [
			"class Main {",
			"  static function main() {",
			"    Sys.println(haxe.format.JsonPrinter.print({a: function() {}, b: 1}));",
			"    Sys.println(haxe.format.JsonPrinter.print(function() {}));",
			"    Sys.println(haxe.format.JsonPrinter.print(Math.POSITIVE_INFINITY));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		final program = MacroStage.expandProgram([typed], []);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "namespace haxe\\format {", "PHP runtime should expose haxe.format namespace helpers");
		assertContains(content, "class JsonPrinter {", "PHP runtime should expose haxe.format.JsonPrinter");
		assertContains(content, "\\haxe\\Json::stringify($value, $replacer, $space)", "PHP JsonPrinter should delegate through the shared haxe.Json encoder");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP haxe.format.JsonPrinter runtime support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "{\"b\":1}\n\"<fun>\"\nnull\n", "generated PHP haxe.format.JsonPrinter output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpHaxeFormatJsonParserRuntimeSupport():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_haxe_format_json_parser_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final src = [
			"class Main {",
			"  static function main() {",
			"    Sys.println(haxe.format.JsonParser.parse(\"\\\"\\\\u00E9\\\"\"));",
			"    try {",
			"      haxe.format.JsonParser.parse(\"{\\\"\\\"\\\"a\\\": 1}\");",
			"      Sys.println(\"missing-error\");",
			"    } catch (_:Dynamic) {",
			"      Sys.println(\"invalid-json\");",
			"    }",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		final program = MacroStage.expandProgram([typed], []);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class JsonParser {", "PHP runtime should expose haxe.format.JsonParser");
		assertContains(content, "\\haxe\\Json::parse($text)", "PHP JsonParser should delegate through the shared haxe.Json parser");
		assertContains(content, "json_last_error() !== JSON_ERROR_NONE", "PHP haxe.Json parser should reject malformed JSON");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP haxe.format.JsonParser runtime support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "é\ninvalid-json\n", "generated PHP haxe.format.JsonParser output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpHaxeResourceRuntimeSupport():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_haxe_resource_" + Std.string(Date.now().getTime()));
		final srcDir = Path.join([tmpRoot, "src"]);
		final haxeDir = Path.join([srcDir, "haxe"]);
		final unitDir = Path.join([srcDir, "unit"]);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(haxeDir);
		FileSystem.createDirectory(unitDir);
		final textName = "re/s?!%[]))(\"'1.txt";
		final src = [
			"package unit;",
			"",
			"import haxe.Resource;",
			"",
			"class Main {",
			"  static function main() {",
			"    var names = Resource.listNames().filter(function(name) return name != \"serializedValues.txt\");",
			"    Sys.println(names.length);",
			"    Sys.println(names[0] == \"re/s?!%[]))(\\\"'1.txt\");",
			"    Sys.println(Resource.getString(\"re/s?!%[]))(\\\"'1.txt\"));",
			"    Sys.println(Resource.getBytes(\"re/s?!%[]))(\\\"'1.bin\").sub(0, 5).toString());",
			"    Sys.println(Resource.getBytes(\"re/s?!%[]))(\\\"'1.bin\").get(5));",
			"    Sys.println(Resource.getString(\"nope\") == null);",
			"    Sys.println(Resource.getBytes(\"nope\") == null);",
			"  }",
			"}",
		].join("\n");
		File.saveContent(Path.join([haxeDir, "Resource.hx"]), [
			"package haxe;",
			"extern class Resource {",
			"  static function listNames():Array<String>;",
			"  static function getString(name:String):Null<String>;",
			"  static function getBytes(name:String):Null<haxe.io.Bytes>;",
			"}",
		].join("\n"));
		File.saveContent(Path.join([unitDir, "Main.hx"]), src);
		final resolved = ResolverStage.parseProjectRoots([srcDir], ["unit.Main"], new StringMap<String>());
		final index = TyperIndex.build(resolved);
		final loader = new ModuleLoader([srcDir], new StringMap<String>(), index, function(_typePath:String):Bool {
			return false;
		});
		loader.markResolvedAlready(resolved);
		final typed = new Array<TypedModule>();
		for (module in resolved)
			typed.push(TyperStage.typeResolvedModule(module, index, loader));
		final program = MacroStage.expandProgram(typed, []);
		final backend = BackendRegistry.requireForTarget("php-native");
		final resources = [
			{name: textName, data: haxe.io.Bytes.ofString("Héllo World !")},
			{name: "re/s?!%[]))(\"'1.bin", data: haxe.io.Bytes.ofHex("48656c6c6f0021576f726c64")},
			{name: "serializedValues.txt", data: haxe.io.Bytes.ofString("skip")}
		];
		backend.emit(program, new BackendContext(tmpRoot, null, "unit.Main", true, false, new StringMap<String>(), resources));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class Resource {", "PHP runtime should expose haxe.Resource");
		assertContains(content, "public static function listNames()", "PHP haxe.Resource should list embedded resource names");
		assertContains(content, "public static function getBytes($name)", "PHP haxe.Resource should expose embedded bytes");
		assertContains(content, "\\haxe\\Resource::getString", "PHP imported haxe.Resource calls should target the namespaced runtime class");
		assertContains(content, "48656c6c6f0021576f726c64", "PHP haxe.Resource should embed binary payloads as hex");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP haxe.Resource runtime support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "2\n1\nHéllo World !\nHello\n0\n1\n1\n", "generated PHP haxe.Resource output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpStdDateToolsSupport():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_std_datetools_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final pos = HxPos.unknown();
		final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [
			SExpr(ECall(EField(EIdent("Sys"), "println"), [ECall(EField(EIdent("Std"), "string"), [EField(EIdent("InitBase"), "sinline")])]), pos),
			SExpr(ECall(EField(EIdent("Sys"), "println"), [
				ECall(EField(EIdent("DateTools"), "format"), [
					ENew("Date", [EInt(2012), EInt(7), EInt(17), EInt(1), EInt(2), EInt(3)]),
					EString("%F %T")
				])
			]), pos)
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
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class DateTools {", "PHP std support should provide a DateTools helper when std DateTools is skipped");
		assertContains(content, "public static function minutes($n)", "PHP DateTools helper should include minute conversion");
		assertContains(content, "InitBase::$sinline = DateTools::minutes(1);", "PHP static initializer should be able to reference std DateTools");
		assertNotContains(content, "std-datetools-source-should-not-render", "PHP DateTools support should not dump the upstream std source body");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP std DateTools helper should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "60000\n2012-08-17 01:02:03\n", "generated PHP std DateTools helper output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpPackageQualifiedClassReference():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_package_class_ref_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		final pos = HxPos.unknown();
		final mainFn = new HxFunctionDecl("main", HxVisibility.Public, true, [], "Void", [
			SExpr(ECall(EField(EIdent("Sys"), "println"), [EArrayAccess(EField(EIdent("DCEClass"), "c"), EInt(1))]), pos)
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
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "unit.Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "DCEClass::$c = [null, __hxhx_class_value(\"unit.UsedReferenced2\")];",
			"PHP static initializers should preserve package-qualified class references as tagged values");
		assertNotContains(content, "$unit->UsedReferenced2", "PHP package-qualified class references should not lower as instance field reads");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP package-qualified class reference should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "unit.UsedReferenced2\n", "generated PHP should print the qualified class reference, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpStdStringMapClassReference():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_std_string_map_ref_" + Std.string(Date.now().getTime()));
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
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "TestReflect::$TYPES = [__hxhx_class_value(\"haxe.ds.StringMap\")];",
			"PHP static initializers should preserve std package-qualified class references as tagged values");
		assertNotContains(content, "haxe\\ds::$StringMap", "PHP package prefixes should not lower as static class-property receivers");
		assertNotContains(content, "std-string-map-source-should-not-render", "PHP StringMap class references should not dump the upstream std source body");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP std StringMap class reference should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "haxe.ds.StringMap\n", "generated PHP should print the std StringMap class reference, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpTypeNameHelpersForStaticInitializers():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_type_name_helpers_" + Std.string(Date.now().getTime()));
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
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "TestReflect::$TNAMES = [\"haxe.ds.StringMap\", __hxhx_add(__hxhx_add(\"unit\", \".\"), \"MyEnum\")];",
			"PHP static initializers should lower type-name helper calls without local callables");
		assertNotContains(content, "$u(\"haxe.ds.StringMap\")", "PHP type-name helper calls should not lower as undefined local callable variables");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP type-name helpers should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "haxe.ds.StringMap,unit.MyEnum\n", "generated PHP should evaluate type-name helper calls, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpDefaultArgsOnOverrides():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_default_args_override_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final src = [
			"interface IDefArgs {",
			"  public function get(x:Int = 5):Int;",
			"}",
			"class BaseDefArgs {",
			"  public function new() {}",
			"  public function get(x = 3) return x;",
			"}",
			"class ExtDefArgs extends BaseDefArgs implements IDefArgs {",
			"  public function new() { super(); }",
			"  override function get(x = 7) return x;",
			"}",
			"class Main {",
			"  static function main() {",
			"    var e = new ExtDefArgs();",
			"    Sys.println(Std.string(e.get()));",
			"    var b:BaseDefArgs = e;",
			"    Sys.println(Std.string(b.get()));",
			"    var i:IDefArgs = e;",
			"    Sys.println(Std.string(i.get()));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		final program = MacroStage.expandProgram([typed], []);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "public function get($x = 7)", "PHP override methods should preserve parsed default arguments");
		assertContains(content, "$e->get()", "PHP zero-argument concrete calls should remain valid when callee has a default");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP default-arg override should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "7\n7\n7\n", "generated PHP default-arg override output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpTryCatchRawRenamesScopedLocalFunctions():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_try_raw_scoped_local_function_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final src = [
			"class Main {",
			"  static function main() {",
			"    function test():String {",
			"      throw \"never call me\";",
			"    }",
			"    var s = try test() catch(e:String) e;",
			"    Sys.println(s);",
			"    function test():String throw \"never call me\";",
			"    var s = try test() catch(e:String) e;",
			"    Sys.println(s);",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		final program = MacroStage.expandProgram([typed], []);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "$test__hx_scope_1 = function()", "PHP duplicate local functions should receive scoped names");
		assertContains(content, "return $test__hx_scope_1();", "PHP raw try/catch expressions should use renamed local function bindings");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP scoped try/catch local functions should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "never call me\nnever call me\n", "generated PHP scoped try/catch local function output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpLocalFunctionOptionalArgs():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_local_function_optional_args_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final src = [
			"class Main {",
			"  static function main() {",
			"    function id(v:Dynamic, ?pos:Dynamic) return v;",
			"    Sys.println(id(\"ok\"));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		final program = MacroStage.expandProgram([typed], []);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "$id = function($v, $pos = null)", "PHP local function optional args should receive default null");
		assertContains(content, "$id(\"ok\")", "PHP local functions with optional args should remain callable with required args only");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP local optional function should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "ok\n", "generated PHP local optional function output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpSameClassFunctionFieldCall():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_same_class_function_field_call_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final src = [
			"class HelperMacros {",
			"  public static function typeError(e) return false;",
			"}",
			"class Holder {",
			"  var callback:Void->Int;",
			"  var unary:Int->Int;",
			"  var optional:?Int->String;",
			"  public function new() {}",
			"  public function run():Void {",
			"    callback = () -> 7;",
			"    Sys.println(callback());",
			"    callback = function() return 9;",
			"    Sys.println(callback());",
			"    unary = value -> value + 1;",
			"    Sys.println(Std.string(HelperMacros.typeError(unary())));",
			"    Sys.println(Std.string(HelperMacros.typeError(unary(4))));",
			"    optional = (?value) -> Std.string(value);",
			"    Sys.println(optional());",
			"    Sys.println(optional(4));",
			"    Sys.println(Std.string(HelperMacros.typeError(optional(4, 5))));",
			"  }",
			"}",
			"class Main {",
			"  static function main() {",
			"    new Holder().run();",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		final program = MacroStage.expandProgram([typed], []);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "__hxhx_call_field($this, \"callback\")",
			"PHP same-class function-typed fields should call the stored value, not a missing method");
		assertNotContains(content, "$this->callback()", "PHP same-class function-typed fields should not emit method-call syntax");
		assertNotContains(content, "__hxhx_call_field($this, \"unary\")",
			"PHP typeError probes for function-typed fields should fold without evaluating invalid calls");
		assertContains(content, "function($value = null)", "PHP optional function-typed field lambdas should emit nullable PHP parameters");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP same-class function field calls should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "7\n9\ntrue\nfalse\nnull\n4\ntrue\n", "generated PHP same-class function field call output mismatch, got:\n"
				+ run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpOptionalBeforeRequiredFunctionFieldCall():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_optional_before_required_field_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpOptionalBeforeRequiredFunctionFieldProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertNotContains(content, "function($a = null, $b)", "PHP lambdas should not rely on deprecated optional-before-required parameter signatures");
		assertContains(content, "__hxhx_call_field($this, \"combine\", null, \"--\")",
			"PHP function-typed field calls should pass null for skipped optional parameters before required parameters");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP optional-before-required field call should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "3\n", "generated PHP optional-before-required field call output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpOpaqueBlockExprCapturesOuterLocals():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_opaque_block_expr_capture_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final src = [
			"class Main {",
			"  static function main() {",
			"    var prefix = \"value\";",
			"    var s = { var x:String = prefix + \":ok\"; x; };",
			"    Sys.println(s);",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		final program = MacroStage.expandProgram([typed], []);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "function() use (&$prefix)", "PHP opaque block expressions should capture outer locals");
		assertContains(content, "$x = __hxhx_to_string_value(__hxhx_add($prefix, \":ok\"));",
			"PHP opaque block expressions should lower typed local statements");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP opaque block expression should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "value:ok\n", "generated PHP opaque block expression output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpNullFieldAccessThrowsNpe():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_null_field_access_npe_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final src = [
			"class Main {",
			"  static var nf1:Base = null;",
			"  static function main() {",
			"    var got = try nf1.s catch (e:Any) \"NPE\";",
			"    Sys.println(got);",
			"  }",
			"}",
			"class Base {",
			"  public var s:String;",
			"  public function new(s:String) this.s = s;",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		final program = MacroStage.expandProgram([typed], []);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "function __hxhx_field($obj, $field)", "PHP runtime should centralize field reads");
		assertContains(content, "throw ValueException::thrown(\"NPE\");", "PHP null field reads should throw a catchable NPE value");
		assertContains(content, "__hxhx_field(Main::$nf1, \"s\")", "PHP same-class static field reads should flow through null-safe field helper");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP null field access should execute through catch, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "NPE\n", "generated PHP null field access output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpConstructorDefaultArgs():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_constructor_default_args_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final src = [
			"class BaseConstrOpt {",
			"  public var s:String;",
			"  public var i:Int;",
			"  public var b:Bool;",
			"  public function new(s:String = \"test\", i:Int = -5, b:Bool = true) {",
			"    this.s = s;",
			"    this.i = i;",
			"    this.b = b;",
			"  }",
			"}",
			"class SubConstrOpt extends BaseConstrOpt {",
			"  public function new() { super(); }",
			"}",
			"class SubConstrOpt2 extends BaseConstrOpt {}",
			"class SubConstrOpt3 extends BaseConstrOpt {",
			"  public function new(s = \"test2\", i = -6) { super(s, i); }",
			"}",
			"class Main {",
			"  static function dump(b:BaseConstrOpt) {",
			"    Sys.println(b.s + \",\" + Std.string(b.i) + \",\" + Std.string(b.b));",
			"  }",
			"  static function main() {",
			"    dump(new BaseConstrOpt());",
			"    dump(new BaseConstrOpt(null, 99));",
			"    dump(new SubConstrOpt());",
			"    dump(new SubConstrOpt2());",
			"    dump(new SubConstrOpt3());",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		final program = MacroStage.expandProgram([typed], []);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "public function __construct($s = \"test\", $i = (-5), $b = true)",
			"PHP constructors should preserve parsed default arguments");
		assertContains(content, "parent::__construct($s, $i)", "PHP super constructor calls should remain valid with parent defaults");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP constructor default args should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "test,-5,true\ntest,99,true\ntest,-5,true\ntest,-5,true\ntest2,-6,true\n",
				"generated PHP constructor default args output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpInlineCastSelfReturn():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_inline_cast_self_return_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpInlineCastSelfReturnProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class InlineBase {", "PHP inline-cast regression should emit the normal base class");
		assertContains(content, "public function self() {\n    return $this;\n  }", "PHP normal return-this methods should preserve the receiver object");
		assertNotContains(content, "class InlineBase {\n  public $__hx_value;",
			"PHP normal classes should not get the abstract backing slot just because they return this");
		assertContains(content, "return $this->self();", "PHP inline cast should keep the receiver-producing helper call reachable");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP inline-cast self-return support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "quoted\n", "generated PHP inline-cast self-return output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpConstrainedParameterScannerFlow():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_constrained_param_scanner_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpConstrainedParameterScannerFlowProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "public static function staticSingle($a) {\n    return $a;\n  }",
			"PHP scanner-backed constrained static helpers should preserve simple return bodies");
		assertContains(content, "public function memberAnon($v) {", "PHP scanner-backed structural constrained helpers should preserve args");
		assertNotContains(content, "public function memberAnon() {", "PHP scanner should not mistake structural constraints for the member body");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP constrained parameter scanner flow should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "true\ntrue\n", "generated PHP constrained parameter scanner output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpStringBufRuntimeSupport():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_stringbuf_runtime_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final src = [
			"class Main {",
			"  static function main() {",
			"    var b = new StringBuf();",
			"    Sys.println(Std.string(b.length));",
			"    b.add(-45);",
			"    b.add(1.456);",
			"    b.add(null);",
			"    b.add(true);",
			"    b.add(false);",
			"    b.add(\"Hello!\");",
			"    b.addSub(\"Bla\", 1, 2);",
			"    b.addChar(\"R\".code);",
			"    Sys.println(b.toString());",
			"    Sys.println(Std.string(b.length));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		final program = MacroStage.expandProgram([typed], []);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "class StringBuf {", "PHP runtime should provide StringBuf");
		assertContains(content, "$b->addSub(\"Bla\", 1, 2);", "PHP StringBuf addSub calls should emit normally");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP StringBuf runtime should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "0\n-451.456nulltruefalseHello!laR\n30\n", "generated PHP StringBuf output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpClosureBindCallbacks():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_closure_bind_callbacks_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final src = [
			"class Main {",
			"  static function main() {",
			"    var join = function(a:String, b:String, c:String) return a + b + c;",
			"    Sys.println(join.bind()(\"a\", \"b\", \"c\"));",
			"    Sys.println(join.bind(\"a\")(\"b\", \"c\"));",
			"    Sys.println(join.bind(\"a\", \"b\")(\"c\"));",
			"    Sys.println(join.bind(\"a\", \"b\", \"c\")());",
			"    Sys.println(join.bind(_, \"b\", \"c\")(\"a\"));",
			"    Sys.println(join.bind(_, \"b\")(\"a\", \"c\"));",
			"    Sys.println(join.bind(_)(\"a\", \"b\", \"c\"));",
			"    Sys.println(join.bind(_, \"b\", _)(\"a\", \"c\"));",
			"    Sys.println(join.bind().bind(_, \"b\", \"c\")(\"a\"));",
			"    Sys.println(join.bind(\"a\").bind(\"b\", \"c\")());",
			"    Sys.println(join.bind(\"a\", _).bind(\"b\")(\"c\"));",
			"    Sys.println(join.bind(_, \"b\").bind(\"a\")(\"c\"));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		final program = MacroStage.expandProgram([typed], []);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "__hxhx_bind($join)", "PHP closure bind should support zero-argument bind calls");
		assertContains(content, "__hxhx_bind_placeholder()", "PHP closure bind should encode underscore placeholders explicitly");
		assertNotContains(content, "Closure::bind()", "PHP closure bind should not lower Haxe bind syntax to PHP Closure::bind");
		assertNotContains(content, "__hxhx_bind($join, $_", "PHP closure bind placeholders should not emit an undefined underscore variable");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP closure bind callbacks should execute, stderr:\n" + run.stderr);
			final expected = [
				"abc", "abc", "abc", "abc", "abc", "abc", "abc", "abc", "abc", "abc", "abc", "abc",
			].join("\n") + "\n";
			assertTrue(run.stdout == expected, "generated PHP closure bind callbacks should preserve argument order, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpInstanceMethodValueBind():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_instance_method_value_bind_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final src = [
			"class MyClass {",
			"  var base:Int;",
			"  public function new(base:Int) {",
			"    this.base = base;",
			"  }",
			"  public function add(x:Int, y:Int):Int {",
			"    return base + x + y;",
			"  }",
			"}",
			"class ParamBind<T> {",
			"  public function new() {}",
			"  public function bind(value:T):T {",
			"    return value;",
			"  }",
			"  public function label(prefix:String, value:T):String {",
			"    return prefix + Std.string(value);",
			"  }",
			"}",
			"class SelfBind {",
			"  public function new() {}",
			"  public function id(x:Int):Int {",
			"    return x;",
			"  }",
			"  public function sq(x:Int):Int {",
			"    return x * x;",
			"  }",
			"  public function run():Void {",
			"    var foo = id.bind(3);",
			"    var bar = sq.bind(5);",
			"    Sys.println(foo());",
			"    Sys.println(bar());",
			"  }",
			"}",
			"class Main {",
			"  static function main() {",
			"    var c = new MyClass(100);",
			"    var d = new MyClass(100);",
			"    var add = c.add;",
			"    Sys.println(c.add(1, 2));",
			"    Sys.println(c.add.bind(1)(2));",
			"    Sys.println(add(1, 2));",
			"    Sys.println(Std.string(Reflect.compareMethods(c.add, c.add)));",
			"    Sys.println(Std.string(Reflect.compareMethods(c.add, d.add)));",
			"    Sys.println(Std.string(Reflect.compareMethods(String.fromCharCode, String.fromCharCode)));",
			"    Sys.println(Std.string(Reflect.compareMethods(c.add, null)));",
			"    var p = new ParamBind<String>();",
			"    var label = p.label;",
			"    Sys.println(p.bind(\"ok\"));",
			"    Sys.println(label(\">\", \"ok\"));",
			"    Sys.println(p.label.bind(\">\")(\"ok\"));",
			"    new SelfBind().run();",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		final program = MacroStage.expandProgram([typed], []);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "__hxhx_field($c, \"add\")", "PHP instance method values should lower through the callable field helper");
		assertContains(content, "$p->bind(\"ok\")", "PHP instance methods named bind should not be mistaken for Haxe partial application");
		assertContains(content, "public static function compareMethods($a, $b)", "PHP Reflect should expose compareMethods");
		assertNotContains(content, "__hxhx_bind($this->id, 3)", "PHP same-instance method values should not bind missing properties");
		assertNotContains(content, "__hxhx_bind($p, \"ok\")", "PHP real bind methods should remain method calls");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP instance method-value bind support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "103\n103\n103\ntrue\nfalse\ntrue\nfalse\nok\n>ok\n>ok\n3\n25\n",
				"generated PHP method-value bind support should preserve receiver binding, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpStringUsingExtensionCalls():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_string_using_extension_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final src = [
			"using UsingBase;",
			"using UsingChild1;",
			"using UsingChild2;",
			"",
			"class UsingBase {",
			"  static function privFunc(s:String) return s.toUpperCase();",
			"  static public function pupFunc(s:String) return s.toUpperCase();",
			"}",
			"class UsingChild1 extends UsingBase {",
			"  static public function test() {",
			"    return \"foo\".pupFunc() + \"foo\".privFunc() + \"FOO\".siblingFunc();",
			"  }",
			"  static function siblingFunc(s:String) return s.toLowerCase();",
			"}",
			"class UsingChild2 extends UsingBase {",
			"  static public function test() {",
			"    return \"foo\".siblingFunc();",
			"  }",
			"  static public function siblingFunc(s:String) return s.toUpperCase();",
			"}",
			"class UsingUnrelated {",
			"  static public function test() {",
			"    var err = HelperMacros.typeError(\"foo\".privFunc());",
			"    return err + \"foo\".pupFunc() + \"foo\".siblingFunc();",
			"  }",
			"}",
			"class Main {",
			"  static function main() {",
			"    Sys.println(UsingChild1.test());",
			"    Sys.println(UsingChild2.test());",
			"    Sys.println(UsingUnrelated.test());",
			"  }",
			"}",
		].join("\n");
		final scannedHelpers = ParserStageScanHelpers.scanModuleLocalHelperClasses(src, "Main");
		var scannedUsingUnrelatedBodyLength = -1;
		for (helper in scannedHelpers)
			if (helper.name == "UsingUnrelated")
				for (fn in helper.functions)
					if (fn.name == "test")
						scannedUsingUnrelatedBodyLength = fn.body.length;
		assertTrue(scannedUsingUnrelatedBodyLength == 2, "Stage3 helper scanner should retain simple local-var plus return static helper bodies");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		final program = MacroStage.expandProgram([typed], []);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "UsingChild2::pupFunc(\"foo\")", "PHP using extension calls should lower inherited helpers as static calls");
		assertContains(content, "UsingChild2::siblingFunc(\"FOO\")", "PHP using extension resolution should prefer later using helpers");
		assertNotContains(content, "\"foo\"->pupFunc()", "PHP using extension calls should not emit string member calls");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP using extension calls should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "FOOFOOFOO\nFOO\ntrueFOOFOO\n", "generated PHP using extension output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);

		final moduleTmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_string_using_module_extension_" + Std.string(Date.now().getTime()));
		deleteRecursive(moduleTmpRoot);
		FileSystem.createDirectory(moduleTmpRoot);
		final mainSrc = [
			"using UsingModule;",
			"class Main {",
			"  static function main() {",
			"    Sys.println(\"foo\".usingTest());",
			"  }",
			"}",
		].join("\n");
		final usingSrc = [
			"class EarlierUsing {",
			"  static public function usingTest(s:String) return \"1\";",
			"}",
			"class LaterUsing {",
			"  static public function usingTest(s:String) return \"3\";",
			"}",
		].join("\n");
		final mainTyped = TyperStage.typeModule(ParserStage.parse(mainSrc, "Main.hx"));
		final usingTyped = TyperStage.typeModule(ParserStage.parse(usingSrc, "UsingModule.hx"));
		final moduleProgram = MacroStage.expandProgram([mainTyped, usingTyped], []);
		backend.emit(moduleProgram, new BackendContext(moduleTmpRoot, null, "Main", true, false, new StringMap<String>()));
		final moduleOutputPath = Path.join([moduleTmpRoot, "index.php"]);
		final moduleContent = File.getContent(moduleOutputPath);
		assertContains(moduleContent, "LaterUsing::usingTest(\"foo\")", "PHP using module aliases should resolve later module-local string extension helpers");
		assertNotContains(moduleContent, "\"foo\"->usingTest()", "PHP using module aliases should not emit string member calls");
		if (commandExists("php")) {
			final run = commandOutput("php", [moduleOutputPath]);
			assertTrue(run.code == 0, "generated PHP using module extension call should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "3\n", "generated PHP using module extension output mismatch, got:\n" + run.stdout);
		}
		deleteRecursive(moduleTmpRoot);
	}

	static function assertPhpClosureCapturesMutableLocalByReference():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_closure_mutable_capture_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final src = [
			"class Main {",
			"  static function main() {",
			"    var x = 4;",
			"    var f = function() return x;",
			"    Sys.println(f());",
			"    x++;",
			"    Sys.println(f());",
			"    var o = { f: f };",
			"    Sys.println(o.f());",
			"    var m = { cos: Math.cos };",
			"    Sys.println(m.cos(0));",
			"    var bar = null;",
			"    if (true) {",
			"      var y = 2;",
			"      bar = function() return y;",
			"    }",
			"    Sys.println(bar());",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		final program = MacroStage.expandProgram([typed], []);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "use (&$x)", "PHP closures should capture mutable locals by reference");
		assertContains(content, "return Math::cos(...$__hxhx_args);", "PHP static method values should lower to callable closures");
		assertNotContains(content, "$this->bar();", "PHP local closures named like helper methods should not rewrite to same-class helper calls");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP mutable closure capture support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "4\n5\n5\n1\n2\n", "generated PHP mutable closure capture should observe later local mutation, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpStringLengthInCharCodeAtArg():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_string_length_char_code_at_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final src = [
			"class Main {",
			"  static function main() {",
			"    final value = '[foo => 1]';",
			"    Sys.println(value.charCodeAt(value.length - 1));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		final program = MacroStage.expandProgram([typed], []);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "__hxhx_length($value) - 1", "PHP string .length inside charCodeAt arguments should lower through __hxhx_length");
		assertNotContains(content, "$value->length - 1", "PHP string .length should not emit object-property access inside charCodeAt arguments");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP string length/charCodeAt support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "93\n", "generated PHP string length/charCodeAt support should return the final char code, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpStdPackageRootShadowing():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_std_package_shadow_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final src = [
			"class Main {",
			"  static function main() {",
			"    var haxe = 20;",
			"    var Std = 50;",
			"    var foo = function() return haxe;",
			"    var bar = function() return Std;",
			"    Sys.println(std.haxe.crypto.Md5.encode(\"\"));",
			"    Sys.println(std.Std.int(45.3));",
			"    Sys.println(foo());",
			"    Sys.println(bar());",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		final program = MacroStage.expandProgram([typed], []);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "haxe\\crypto\\Md5::encode(\"\")", "PHP std.haxe package root should lower to the haxe.crypto type path");
		assertContains(content, "Std::int(45.3)", "PHP std.Std package root should lower to the Std type path");
		assertNotContains(content, "$std->haxe", "PHP std package root should not lower as a local variable chain");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP std package-root shadowing support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "d41d8cd98f00b204e9800998ecf8427e\n45\n20\n50\n",
				"generated PHP std package-root shadowing support should preserve type and local lookups, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpStaticPropertyGetter():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_static_property_getter_" + Std.string(Date.now().getTime()));
		final srcDir = Path.join([tmpRoot, "src"]);
		final unitDir = Path.join([srcDir, "unit"]);
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(unitDir);
		final src = [
			"package unit;",
			"import unit.MyClass;",
			"class MyDynamicClass {",
			"  var v:Int;",
			"  public function new(v) {",
			"    this.v = v;",
			"  }",
			"  static var Z = 10;",
			"  public dynamic static function staticDynamic(x, y) {",
			"    return Z + x + y;",
			"  }",
			"  @:isVar public static var W(get, set):Int = 55;",
			"  static function get_W() return W + 2;",
			"  static function set_W(v) { W = v; return v; }",
			"}",
			"class Test {",
			"  function eq(left:Int, right:Int):Void {",
			"    Sys.println(left + ':' + right);",
			"  }",
			"}",
			"class TestMisc extends Test {",
			"  public function new() {}",
			"  public function testPropertyInit():Void {",
			"    eq(MyDynamicClass.W, 57);",
			"  }",
			"  static function main() {",
			"    Sys.println(MyDynamicClass.W);",
			"    new TestMisc().testPropertyInit();",
			"  }",
			"}",
		].join("\n");
		File.saveContent(Path.join([unitDir, "MyClass.hx"]), ["package unit;", "class MyClass {}"].join("\n"));
		File.saveContent(Path.join([unitDir, "TestMisc.hx"]), src);
		final resolved = ResolverStage.parseProjectRoots([srcDir], ["unit.TestMisc"], new StringMap<String>());
		final index = TyperIndex.build(resolved);
		final loader = new ModuleLoader([srcDir], new StringMap<String>(), index, function(_typePath:String):Bool {
			return false;
		});
		loader.markResolvedAlready(resolved);
		final typed = new Array<TypedModule>();
		for (module in resolved)
			typed.push(TyperStage.typeResolvedModule(module, index, loader));
		final program = MacroStage.expandProgram(typed, []);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "unit.TestMisc", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "echo MyDynamicClass::get_W() . PHP_EOL;", "PHP static property reads should call get_<field> accessors");
		assertContains(content, "$this->eq(MyDynamicClass::get_W(), 57);",
			"PHP static property reads should use get_<field> accessors inside instance helper calls");
		assertContains(content, "return __hxhx_add(MyDynamicClass::$W, 2);", "PHP static getters should read the backing field without accessor recursion");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP static property getter support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "57\n57:57\n", "generated PHP static property getter support should use get_W, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpInheritedFieldDynamicOverride():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_inherited_field_dynamic_override_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final src = [
			"class MyDynamicClass {",
			"  var v:Int;",
			"  public function new(v) {",
			"    this.v = v;",
			"  }",
			"  public function viaGet() {",
			"    return v;",
			"  }",
			"  public dynamic function add(x, y) {",
			"    return v + x + y;",
			"  }",
			"  static var Z = 10;",
			"  public dynamic static function staticDynamic(x, y) {",
			"    return Z + x + y;",
			"  }",
			"}",
			"class MyDynamicSubClass extends MyDynamicClass {",
			"  override function add(x, y) {",
			"    return (v + x + y) * 2;",
			"  }",
			"}",
			"class MyOtherDynamicClass extends MyDynamicClass {",
			"  public function new(v) {",
			"    add = function(x, y) return x + y + 10;",
			"    super(v);",
			"  }",
			"}",
			"class Main {",
			"  static function main() {",
			"    var inst = new MyDynamicSubClass(100);",
			"    var add = inst.add;",
			"    Sys.println(inst.add(1, 2));",
			"    Sys.println(add(1, 2));",
			"    inst.add = function(x, y) return inst.viaGet() * 2 + x + y;",
			"    add = inst.add;",
			"    Sys.println(inst.add(1, 2));",
			"    Sys.println(add(1, 2));",
			"    var other = new MyOtherDynamicClass(0);",
			"    var otherAdd = other.add;",
			"    Sys.println(other.add(1, 2));",
			"    Sys.println(otherAdd(1, 2));",
			"    Sys.println(MyDynamicClass.staticDynamic(1, 2));",
			"    MyDynamicClass.staticDynamic = function(x, y) return x + y + 100;",
			"    Sys.println(MyDynamicClass.staticDynamic(1, 2));",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		final program = MacroStage.expandProgram([typed], []);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "return __hxhx_mul(__hxhx_add(__hxhx_add($this->v, $x), $y), 2);",
			"PHP overrides should rewrite inherited fields through this");
		assertNotContains(content, "__hxhx_add(__hxhx_add($v, $x), $y)", "PHP overrides should not emit inherited fields as locals");
		assertContains(content, "__hxhx_call_field($inst, \"add\", 1, 2)", "PHP dynamic method calls on typed locals should honor runtime field reassignment");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP inherited dynamic override support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "206\n206\n203\n203\n13\n13\n13\n103\n",
				"generated PHP inherited dynamic override support should preserve receiver fields and dynamic reassignment, got:\n" + run.stdout);
		}
		deleteRecursive(tmpRoot);
	}

	static function assertPhpSameNameLocalStaticField():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_same_name_local_static_field_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final src = [
			"class Main {",
			"  static var unit = 'testing package conflict';",
			"  static function main() {",
			"    Sys.println(unit);",
			"    var unit = unit;",
			"    Sys.println(unit);",
			"    Sys.println(Main.unit);",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		final program = MacroStage.expandProgram([typed], []);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(program, new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "$unit = Main::$unit;", "PHP same-name local initializers should read same-class static fields before shadowing");
		assertNotContains(content, "$unit = $unit;", "PHP same-name local initializers should not read the uninitialized local");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP same-name local/static field support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "testing package conflict\ntesting package conflict\ntesting package conflict\n",
				"generated PHP same-name local/static field support should match Haxe resolution, got:\n" + run.stdout);
		}
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
		assertContains(content, "return new __HxAnon([\"x\" => self::$__basic_x, \"y\" => \"final\"]);",
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

	static function assertPhpMapComprehensionRuntimeSupport():Void {
		final tmpRoot = Path.normalize(".tmp/m14_source_native_backend_php_map_comprehension_runtime_" + Std.string(Date.now().getTime()));
		deleteRecursive(tmpRoot);
		FileSystem.createDirectory(tmpRoot);
		final backend = BackendRegistry.requireForTarget("php-native");
		backend.emit(phpMapComprehensionRuntimeProgram(), new BackendContext(tmpRoot, null, "Main", true, false, new StringMap<String>()));
		final outputPath = Path.join([tmpRoot, "index.php"]);
		final content = File.getContent(outputPath);
		assertContains(content, "function __hxhx_map_comprehension($iterable, $projector)",
			"PHP runtime should include the map-comprehension helper used by upstream-shaped lowering");
		assertContains(content, "__hxhx_map_comprehension([\"a\", \"b\"]",
			"PHP map comprehensions should lower through the runtime helper with the source iterable");
		assertNotContains(content, "$__hxhx_map_comprehension",
			"PHP map-comprehension helper calls should emit as direct function calls, not variable callables");
		if (commandExists("php")) {
			final run = commandOutput("php", [outputPath]);
			assertTrue(run.code == 0, "generated PHP map-comprehension helper support should execute, stderr:\n" + run.stderr);
			assertTrue(run.stdout == "true\nB\n12\n", "generated PHP map-comprehension helper output mismatch, got:\n" + run.stdout);
		}
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
		assertPhpMapLiteralTypeTags();
		assertPhpMapSetTypeTags();
		assertPhpHaxeSerializerRuntimeSupport();
		assertPhpHaxeSerializerImportRuntimeSupport();
		assertPhpPoint3StringEqualityRuntimeSupport();
		assertPhpPoint3UnaryScaleRuntimeSupport();
		assertPhpLambdaListRuntimeSupport();
		assertPhpGenericStackRuntimeSupport();
		assertPhpMapKeysIteratorRuntimeSupport();
		assertPhpMetaRuntimeSupport();
		assertPhpReflectMakeVarArgs();
		assertPhpReflectFields();
		assertPhpReflectCallMethod();
		assertPhpReflectPropertyAccess();
		assertPhpSamePackageQualifiedStaticPath();
		assertPhpInstanceFieldMethodCall();
		assertPhpInheritedTestHelperCall();
		assertPhpShadowedTestHelperClosure();
		assertNativeProtocolOptionalArgDecode();
		assertNativeProtocolDefaultArgSourceDecode();
		assertNativeProtocolConstructorDefaultArgSourceDecode();
		assertPhpPlusSemantics();
		assertPhpAnonymousToStringField();
		assertPhpCyclicObjectStringification();
		assertPhpEnumString();
		assertPhpStdEnumAbstractSupport();
		assertPhpStdIoErrorEnumSupport();
		assertPhpStdIoErrorRuntimeExceptions();
		assertPhpBitwisePrecedence();
		assertPhpSameClassStaticHelperCall();
		assertPhpSameClassStaticInlineCall();
		assertPhpStaticFunctionFieldCall();
		assertPhpBitwiseEqualityPrecedence();
		assertPhpModuloMultiplicationPrecedence();
		assertPhpFloatModulo();
		assertPhpMathRuntime();
		assertPhpMathRandomRuntime();
		assertPhpStdRandomRuntime();
		assertPhpTernaryAssignmentLogical();
		assertPhpStringIndexOf();
		assertPhpStringFromCharCode();
		assertPhpWebShim();
		assertPhpMacroExpr();
		assertPythonMacroExpr();
		assertPhpDollarString();
		assertPhpInt64LiteralExtension();
		assertPhpHaxeInt64RuntimeSupport();
		assertPhpInt64GlobalClassDoesNotCollide();
		assertPythonNumericLiteralFieldCallSyntax();
		assertPhpArrayConstructor();
		assertPhpArrayOperations();
		assertPhpSameClassArrayFieldMap();
		assertPhpObjectArrayAccess();
		assertPhpReservedTypeName();
		assertPhpDuplicateStaticFieldEmission();
		assertPhpDuplicateMethodEmission();
		assertPhpReservedValueName();
		assertPhpNonConstantStaticFieldDefault();
		assertPhpArrayPostfixStatement();
		assertPhpCrossPackageSupportClassEmission();
		assertPhpImportedHaxelibEnumSupportClassEmission();
		assertPhpMacroType();
		assertPhpMacroRestProbe();
		assertPythonMacroType();
		assertPhpTryCatchExpression();
		assertPhpThrownValueCatch();
		assertPhpTypeErrorProbe();
		assertPhpTypeErrorExpressionProbe();
		assertPhpTypeErrorBlockProbe();
		assertPhpAbstractCastConstraint();
		assertPhpLoweredAbstractCastTypeErrorProbe();
		assertPhpTypedAsHelperProbe();
		assertPhpFollowWithAbstractsProbe();
		assertPhpArrayComprehensionClosure();
		assertPhpAbstractThisPostfix();
		assertPhpAbstractThisClosureCapture();
		assertPhpExposingAbstractArray();
		assertPhpInlineCastSelfReturn();
		assertPhpConstrainedParameterScannerFlow();
		assertPythonAbstractThisPostfix();
		assertPhpSuperConstructor();
		assertPhpSuperProperty();
		assertPhpForKeyValue();
		assertPythonForKeyValue();
		assertPythonTryCatchRawExpression();
		assertPythonTypeCheck();
		assertPhpTypeCheck();
		assertPhpInterfaceCasts();
		assertPhpArrayDynamicCasts();
		assertPhpAbstractValueCasts();
		assertPhpSyntaxIntrinsics();
		assertPhpNullEquality();
		assertPhpUserClassTypeCheck();
		assertPhpEnumTypeCheck();
		assertPhpTypeReflection();
		assertPhpGenericStaticReflection();
		assertPhpGenericStaticReflectionTextFallback();
		assertPhpGenericConstructible();
		assertPhpTypeErrorGenericNull();
		assertPhpShiftAssignment();
		assertPythonShiftAssignment();
		assertPythonModuloUsesHaxeRemainderSemantics();
		assertPhpNullCoalescing();
		assertPythonNullCoalescing();
		assertPythonNullCoalescingAssignmentExpression();
		assertPhpCompileTimeOnlyMacroSupportSkipped();
		assertPhpDateRuntimeSupport();
		assertPhpHaxeJsonRuntimeSupport();
		assertPhpHaxeJsonStringifyReplacer();
		assertPhpHaxeJsonNonFiniteMathConstants();
		assertPhpHaxeFormatJsonPrinterRuntimeSupport();
		assertPhpHaxeFormatJsonParserRuntimeSupport();
		assertPhpHaxeResourceRuntimeSupport();
		assertPhpStdDateToolsSupport();
		assertPhpPackageQualifiedClassReference();
		assertPhpStdStringMapClassReference();
		assertPhpTypeNameHelpersForStaticInitializers();
		assertPhpDefaultArgsOnOverrides();
		assertPhpTryCatchRawRenamesScopedLocalFunctions();
		assertPhpLocalFunctionOptionalArgs();
		assertPhpSameClassFunctionFieldCall();
		assertPhpOptionalBeforeRequiredFunctionFieldCall();
		assertPhpOpaqueBlockExprCapturesOuterLocals();
		assertPhpNullFieldAccessThrowsNpe();
		assertPhpConstructorDefaultArgs();
		assertPhpStringBufRuntimeSupport();
		assertPhpClosureBindCallbacks();
		assertPhpInstanceMethodValueBind();
		assertPhpStringUsingExtensionCalls();
		assertPhpClosureCapturesMutableLocalByReference();
		assertPhpStringLengthInCharCodeAtArg();
		assertPhpStdPackageRootShadowing();
		assertPhpStaticPropertyGetter();
		assertPhpInheritedFieldDynamicOverride();
		assertPhpSameNameLocalStaticField();
		assertPhpUnitLocalStaticFallback();
		assertPythonUnitLocalStaticFallback();
		assertPhpUnitMapComprehensionFallback();
		assertPhpMapComprehensionRuntimeSupport();
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
		assertPythonUtestRunnerAddCasesMacroStub();
		assertPythonStaticInitializersAfterSupportClasses();
		assertPythonStdDateToolsSupport();
		assertPythonTimerRuntimeShim();
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
		assertPythonStdVectorNamespaceSupport();
		assertPythonMainClassConstructedAtRuntime();
		assertPythonMetaSupport();
		assertPythonValueExceptionBaseSupport();
		assertArrayLiteral();
		assertPythonMapLiteralWithLambda();
		assertPhpTypedMapLiteralWithLambdaField();
		assertPythonMapRuntimeShim();
		assertPythonSysEnvironmentRuntimeShim();
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
		assertJavaUtilityProcessRuntime();
		assertJavaFileSystemFullPathResolvesSymlink();
		assertPhpSwitchStatement();
	}
}
