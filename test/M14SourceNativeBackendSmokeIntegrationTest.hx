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
		assertAnonymousObjectExpression();
		assertLoopControlStatements();
		assertPostfixExpressions();
		assertHelperClassEmission();
		assertHelperInstanceFieldEmission();
		assertCrossModuleClassEmission();
		assertArrayLiteral();
		assertConstructorExpression();
		assertForInStatement();
		assertBinaryOperators();
		assertEnumValue();
		assertLambdaExpression();
		assertSwitchExpression();
		assertSwitchStatement();
	}
}
