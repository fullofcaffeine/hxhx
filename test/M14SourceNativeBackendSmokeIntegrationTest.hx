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
			"  function bar() this++;",
			"}",
			"",
			"class Main {",
			"  static function main() {",
			"    var counter = new Counter(2);",
			"    Sys.println(Std.string(counter));",
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
		assertContains(content, "class Sys", "PHP source backend should emit a minimal Sys helper");
		assertContains(content, "return new __HxArray(array_slice($argv, 1));", "Sys.args should expose CLI args without the script name");
		assertContains(content, "$verbose = (Sys::args()->indexOf(\"-v\") >= 0);", "Sys.args should lower as a static call usable by indexOf");
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
		assertContains(content, "echo strval($ok) . PHP_EOL;", "folded typeError results should still flow through normal printing");
		assertContains(content, "echo $message . PHP_EOL;", "folded typeErrorText results should still flow through normal printing");
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
		assertContains(content, "$__hxhx_result[] = function($value) use ($i) { return ($value * $i); };",
			"PHP closures yielded from comprehensions should capture the comprehension binder");
		assertContains(content, "return $__hxhx_result;", "PHP array comprehensions should return the collected array");
		assertContains(content, "echo strval($funcs[0](10)) . PHP_EOL;",
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
		assertContains(content, "$this->__hx_value = $i;", "PHP abstract constructor assignments to this should target the backing slot");
		assertContains(content, "$this->__hx_value = ($this->__hx_value + 1);", "PHP statement-position postfix this updates should target the backing slot");
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
		assertContains(content, "return (parent::get_prop() . 1);", "PHP super property reads should lower through parent getters");
		assertContains(content, "return (parent::set_prop($v) . 1);", "PHP super property writes should lower through parent setters");
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
		assertContains(content, "echo (strval($index) . strval($value)) . PHP_EOL;",
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
		assertContains(content, "echo strval($value) . PHP_EOL;", "PHP immediate lambda-call results should still flow through later statements");
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
		assertContains(content, "strval(is_int($i))", "PHP `is Int` checks should lower to is_int");
		assertContains(content, "strval(is_string($s))", "PHP `is String` checks should lower to is_string");
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
		emit("php-native", "php", "index.php", "echo (\"source-native:\" . \"php\") . PHP_EOL;");
		emit("lua-native", "lua", "Main.lua", "print((\"source-native:\" .. \"lua\"))");
		assertPythonOutputHint();
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
		assertPhpWebShim();
		assertPhpMacroExpr();
		assertPhpTryCatchExpression();
		assertPhpTypeErrorProbe();
		assertPhpArrayComprehensionClosure();
		assertPhpAbstractThisPostfix();
		assertPhpSuperConstructor();
		assertPhpSuperProperty();
		assertPhpForKeyValue();
		assertPhpTypeCheck();
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
