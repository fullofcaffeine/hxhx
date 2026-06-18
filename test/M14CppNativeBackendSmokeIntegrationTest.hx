import backend.BackendContext;
import backend.BackendRegistry;
import backend.GenIrProgram;
import haxe.ds.StringMap;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

class M14CppNativeBackendSmokeIntegrationTest {
	static function assertTrue(cond:Bool, message:String):Void {
		if (!cond)
			throw message;
	}

	static function assertContains(haystack:String, needle:String, message:String):Void {
		if (haystack.indexOf(needle) < 0)
			throw message + " (missing `" + needle + "` in `" + haystack + "`)";
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

	static function program():GenIrProgram {
		final src = [
			"class Main {",
			"  static function helper(x:Int):Int {",
			"    return x + 6;",
			"  }",
			"  static function main() {",
			"    var suffix = \"smoke\";",
			"    Sys.println(\"cpp-native:\" + suffix);",
			"    trace(\"trace:\" + suffix);",
			"    Sys.println(Std.string(\"abc\".indexOf(\"b\")));",
			"    Sys.println(Std.string(\"abc\".indexOf(\"z\")));",
			"    var args = Sys.args();",
			"    Sys.println(Std.string(args.length));",
			"    Sys.println(args[0]);",
			"    Sys.println(Std.string(args.indexOf(\"needle\")));",
			"    var words = [\"alpha\", \"beta\"];",
			"    Sys.println(Std.string(words.length));",
			"    Sys.println(words[1]);",
			"    Sys.println(Std.string(words.indexOf(\"alpha\")));",
			"    Sys.println(Std.string(helper(4)));",
			"    var casted:Int = cast helper(5);",
			"    Sys.println(Std.string(casted + 0));",
			"    var total = 1;",
			"    total += 4;",
			"    Sys.println(Std.string(total + 0));",
			"    total -= 2;",
			"    Sys.println(Std.string(total + 0));",
			"    try {",
			"      Sys.println(\"try:body\");",
			"    } catch (e:Dynamic) {",
			"      Sys.println(\"try:catch\");",
			"    }",
			"    try {",
			"      throw \"boom\";",
			"    } catch (e:Dynamic) {",
			"      Sys.println(\"try:catch\");",
			"    }",
			"    Sys.println(Std.string((1 | 2) + 0));",
			"    Sys.println(Std.string((3 & 1) + 0));",
			"    Sys.println(Std.string((1 << 3) + 0));",
			"    Sys.println(Std.string((8 >> 1) + 0));",
			"    Sys.println(Std.string(((-1) >>> 1) + 0));",
			"    Sys.println(Std.string((~1) + 0));",
			"    var box = new Box(41);",
			"    Sys.println(Std.string(box.value + 1));",
			"    Sys.println(Std.string(box.getHeight()));",
			"    var bump = 0;",
			"    Sys.println(Std.string(bump++));",
			"    Sys.println(Std.string(bump + 0));",
			"    Sys.println(Std.string(bump--));",
			"    Sys.println(Std.string(bump + 0));",
			"    var spin = 0;",
			"    while (spin < 2) {",
			"      spin++;",
			"    }",
			"    Sys.println(Std.string(spin + 0));",
			"    var stop = 0;",
			"    while (true) {",
			"      stop++;",
			"      if (stop == 2) break;",
			"    }",
			"    Sys.println(Std.string(stop + 0));",
			"    var skip = 0;",
			"    var continued = 0;",
			"    while (skip < 3) {",
			"      skip++;",
			"      if (skip == 2) continue;",
			"      continued += skip;",
			"    }",
			"    Sys.println(Std.string(continued + 0));",
			"    var native = NativeArray.create(2);",
			"    native[0] = 7;",
			"    native[1] = 8;",
			"    Sys.println(Std.string(native.length));",
			"    Sys.println(Std.string(native[0] + native[1]));",
			"    var loopTotal = 0;",
			"    for (i in 0...3) {",
			"      loopTotal += i;",
			"    }",
			"    Sys.println(Std.string(loopTotal + 0));",
			"    for (word in words) {",
			"      Sys.println(word);",
			"    }",
			"    var doubled = [for (value in [1, 2, 3]) if (value > 1) value * 2];",
			"    Sys.println(Std.string(doubled.length));",
			"    Sys.println(Std.string(doubled[0] + doubled[1]));",
			"    if (native[0] == 7) {",
			"      Sys.println(\"if:then\");",
			"    } else {",
			"      Sys.println(\"if:else\");",
			"    }",
			"    if (false || native[0] == 7) {",
			"      Sys.println(\"or:true\");",
			"    }",
			"    if (native[0] == 7 && native[1] == 8) {",
			"      Sys.println(\"and:true\");",
			"    }",
			"    if (!false) {",
			"      Sys.println(\"not:true\");",
			"    }",
			"    var mode = Macro;",
			"    Sys.println(mode);",
			"    if (mode == Macro) {",
			"      Sys.println(\"enum:eq\");",
			"    }",
			"    var ignored = Ignore(\"reason\");",
			"    Sys.println(ignored);",
			"    var id = x -> x + 1;",
			"    Sys.println(Std.string(id(6)));",
			"    var macroQuote = macro (\"macro:value\");",
			"    Sys.println(macroQuote);",
			"    var switched = switch (2) {",
			"      case 1: \"one\";",
			"      case 2: \"two\";",
			"      default: \"other\";",
			"    };",
			"    Sys.println(switched);",
			"    switch (native[0]) {",
			"      case 7:",
			"        Sys.println(\"switch:seven\");",
			"      default:",
			"        Sys.println(\"switch:other\");",
			"    }",
			"    var info = { count: 3 };",
			"    Sys.println(Std.string(info.count + 4));",
			"    Sys.println(Std.string(-info.count));",
			"    Sys.println(info.count == 3 ? \"ternary:yes\" : \"ternary:no\");",
			"    var child = new Child(5);",
			"    Sys.println(Std.string(child.value));",
			"    Sys.println(Std.string(child.inherited()));",
			"  }",
			"}",
			"class Base {",
			"  public function new() {}",
			"  public function label():Int {",
			"    return 40;",
			"  }",
			"}",
			"class Child extends Base {",
			"  public var value:Int;",
			"  public function new(value:Int) {",
			"    super();",
			"    this.value = value;",
			"  }",
			"  public function inherited():Int {",
			"    return super.label() + 2;",
			"  }",
			"}",
			"class Box {",
			"  public var value:Int;",
			"  public function new(value:Int) {",
			"    this.value = value;",
			"  }",
			"  public function getHeight():Int {",
			"    return value;",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function context(outDir:String, buildExecutable:Bool, noCompilation:Bool):BackendContext {
		final defines = new StringMap<String>();
		if (noCompilation)
			defines.set("no-compilation", "1");
		return new BackendContext(outDir, null, "Main", true, buildExecutable, defines);
	}

	static function hasArtifactKind(artifacts:Array<backend.EmitArtifact>, kind:String):Bool {
		for (artifact in artifacts)
			if (artifact.kind == kind)
				return true;
		return false;
	}

	static function main():Void {
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.renderExpr(EUnsupported("8")) == "8",
			"numeric unsupported fragments should render as integer literals");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.renderExpr(EUnsupported("=")) == "0",
			"single-token assignment recovery fragments should render as neutral C++ zero");
		assertTrue(@:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ECall(EEnumValue("Ignore"),
				[EString("reason")])) == "([&]() { auto __hxhx_enum_arg_0 = \"reason\"; (void)__hxhx_enum_arg_0; return std::string(\"Ignore\"); })()",
			"payload enum constructor calls should lower to their enum tag string for the C++ MVP");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.renderExpr(ECall(ECall(ECall(EIdent("f6_a"), []), []), [])) == "((f6_a())())()",
			"nested calls should lower by invoking the rendered callee expression");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.renderExpr(EBinop("=>", EString("key"), EInt(42))) == "std::make_pair(\"key\", 42)",
			"arrow expressions should lower to C++ pairs");

		BackendRegistry.clearDynamicRegistrations();
		final descriptor = BackendRegistry.descriptorForTarget("cpp-native");
		assertTrue(descriptor != null, "missing cpp-native descriptor");
		assertTrue(descriptor.implId == "builtin/cpp-native-source-mvp", "unexpected cpp-native implId");
		assertTrue(descriptor.capabilities.supportsBuildExecutable, "cpp-native should own executable build support");

		final root = Path.join([Sys.getCwd(), ".tmp", "m14_cpp_native_backend_smoke"]);
		deleteRecursive(root);
		FileSystem.createDirectory(root);

		final sourceOnlyDir = Path.join([root, "source-only"]);
		final sourceOnly = BackendRegistry.createForTarget("cpp-native").emit(program(), context(sourceOnlyDir, true, true));
		assertTrue(sourceOnly.entryPath == Path.join([sourceOnlyDir, "src", "Main.cpp"]), "unexpected C++ source entry path: " + sourceOnly.entryPath);
		assertTrue(hasArtifactKind(sourceOnly.artifacts, "entry_cpp_source"), "missing entry_cpp_source artifact");
		assertTrue(!sourceOnly.builtExecutable, "no-compilation C++ smoke should not build executable");
		final source = File.getContent(sourceOnly.entryPath);
		assertContains(source, "int main(int argc, char** argv)", "C++ smoke should emit main");
		assertContains(source, "auto suffix = \"smoke\";", "C++ smoke should emit local var");
		assertContains(source, "std::cout << (std::string(\"cpp-native:\") + std::string(suffix)) << std::endl;", "C++ smoke should emit println");
		assertContains(source, "std::cout << (std::string(\"trace:\") + std::string(suffix)) << std::endl;", "C++ smoke should emit trace");
		assertContains(source, "__hxhx_args(argc, argv)", "C++ smoke should emit Sys.args helper call");
		assertContains(source, "__hxhx_index_of(\"abc\", std::string(\"b\"), 0)", "C++ smoke should emit string indexOf helper call");
		assertContains(source, "__hxhx_index_of(args, std::string(\"needle\"), 0)", "C++ smoke should emit vector indexOf helper call");
		assertContains(source, "std::vector<std::string>{std::string(\"alpha\"), std::string(\"beta\")}", "C++ smoke should emit string array literal");
		assertContains(source, "static int helper(int x) {", "C++ smoke should emit main-class static helper function");
		assertContains(source, "helper(4)", "C++ smoke should lower direct identifier function call");
		assertContains(source, "auto casted = helper(5);", "C++ smoke should lower cast expression");
		assertContains(source, "total += 4;", "C++ smoke should lower compound plus assignment");
		assertContains(source, "total -= 2;", "C++ smoke should lower compound minus assignment");
		assertContains(source, "try {", "C++ smoke should emit try statement");
		assertContains(source, "throw std::runtime_error(std::string(\"boom\"));", "C++ smoke should emit throw statement");
		assertContains(source, "} catch (...) {", "C++ smoke should emit catch-all statement");
		assertContains(source, "(1 | 2)", "C++ smoke should emit bitwise-or expression");
		assertContains(source, "(3 & 1)", "C++ smoke should emit bitwise-and expression");
		assertContains(source, "(1 << 3)", "C++ smoke should emit left-shift expression");
		assertContains(source, "(8 >> 1)", "C++ smoke should emit right-shift expression");
		assertContains(source, "(static_cast<unsigned int>((-1)) >> 1)", "C++ smoke should emit unsigned right-shift expression");
		assertContains(source, "(~1)", "C++ smoke should emit bitwise-not expression");
		assertContains(source, "struct Box {", "C++ smoke should emit helper class struct");
		assertContains(source, "int value = 0;", "C++ smoke should emit helper class field");
		assertContains(source, "Box(int value) {", "C++ smoke should emit helper class constructor");
		assertContains(source, "this->value = value;", "C++ smoke should emit constructor field assignment");
		assertContains(source, "int getHeight() {", "C++ smoke should emit helper class method");
		assertContains(source, "return static_cast<int>(value);", "C++ smoke should emit helper method return");
		assertContains(source, "auto box = Box(41);", "C++ smoke should lower new expression");
		assertContains(source, "box.getHeight()", "C++ smoke should lower receiver method call");
		assertContains(source, "(bump++)", "C++ smoke should lower post-increment expression");
		assertContains(source, "(bump--)", "C++ smoke should lower post-decrement expression");
		assertContains(source, "while (spin < 2) {", "C++ smoke should emit while statement");
		assertContains(source, "break;", "C++ smoke should emit break statement");
		assertContains(source, "continue;", "C++ smoke should emit continue statement");
		assertContains(source, "auto native = std::vector<int>(2);", "C++ smoke should lower NativeArray.create");
		assertContains(source, "(native[0]) = 7;", "C++ smoke should emit NativeArray indexed assignment");
		assertContains(source, "(native.size())", "C++ smoke should emit NativeArray length read");
		assertContains(source, "for (int i = 0; i < 3; i++) {", "C++ smoke should emit range for-in statement");
		assertContains(source, "for (auto word : words) {", "C++ smoke should emit iterable for-in statement");
		assertContains(source, "std::vector<int> __hxhx_comp_out;", "C++ smoke should allocate array comprehension vector");
		assertContains(source, "for (auto value : std::vector<int>{1, 2, 3}) {", "C++ smoke should iterate array comprehension source");
		assertContains(source, "if (value > 1) {", "C++ smoke should emit array comprehension guard");
		assertContains(source, "__hxhx_comp_out.push_back((value * 2));", "C++ smoke should push array comprehension yield");
		assertContains(source, "if ((native[0]) == 7) {", "C++ smoke should emit if statement");
		assertContains(source, "false || ((native[0]) == 7)", "C++ smoke should emit logical-or expression");
		assertContains(source, "((native[0]) == 7) && ((native[1]) == 8)", "C++ smoke should emit logical-and expression");
		assertContains(source, "if ((!false)) {", "C++ smoke should emit logical-not expression");
		assertContains(source, "auto mode = std::string(\"Macro\");", "C++ smoke should lower enum value tags as strings");
		assertContains(source, "(mode == std::string(\"Macro\"))", "C++ smoke should compare enum value tags as strings");
		assertContains(source, "auto ignored = ([&]() { auto __hxhx_enum_arg_0 = \"reason\"; (void)__hxhx_enum_arg_0; return std::string(\"Ignore\"); })();",
			"C++ smoke should lower enum constructor calls as tag strings while evaluating payloads");
		assertContains(source, "auto id = [&](auto x) { return (x + 1); };", "C++ smoke should lower expression lambdas");
		assertContains(source, "id(6)", "C++ smoke should call local lambda values");
		assertContains(source, "auto macroQuote = std::string(\"EParenthesis(EConst(CString(macro:value)))\");",
			"C++ smoke should lower macro quote wrappers to stable text");
		assertContains(source, "auto switched = ([&]() {", "C++ smoke should lower switch expressions through an IIFE");
		assertContains(source, "auto __hxhx_switch = 2;", "C++ smoke should bind switch expression scrutinee");
		assertContains(source, "else if (__hxhx_switch == 2) {", "C++ smoke should lower switch expression int cases");
		assertContains(source, "auto __hxhx_switch_stmt = (native[0]);", "C++ smoke should bind switch statement scrutinee");
		assertContains(source, "if (__hxhx_switch_stmt == 7) {", "C++ smoke should lower switch statement int cases");
		assertContains(source, "} else {", "C++ smoke should emit else branch");
		assertContains(source, "struct __hxhx_anon_count_int_ {", "C++ smoke should emit anonymous object struct");
		assertContains(source, "auto info = __hxhx_anon_count_int_{3};", "C++ smoke should lower anonymous object literal");
		assertContains(source, "((info.count) + 4)", "C++ smoke should read anonymous object field");
		assertContains(source, "(-(info.count))", "C++ smoke should emit unary minus");
		assertContains(source, "(((info.count) == 3) ? std::string(\"ternary:yes\") : std::string(\"ternary:no\"))",
			"C++ smoke should emit ternary expression");
		assertContains(source, "struct Child : public Base {", "C++ smoke should emit child helper class inheritance");
		assertContains(source, "Base::label()", "C++ smoke should lower super method calls to qualified base calls");
		assertContains(source, "/* base constructor call omitted */", "C++ smoke should lower bare super constructor call");

		if (commandExists("c++") || commandExists("g++") || commandExists("clang++")) {
			final buildDir = Path.join([root, "build"]);
			final built = BackendRegistry.createForTarget("cpp-native").emit(program(), context(buildDir, true, false));
			assertTrue(hasArtifactKind(built.artifacts, "entry_cpp_exe"), "missing entry_cpp_exe artifact");
			assertTrue(built.builtExecutable, "C++ compiler smoke should mark built executable");
			final run = commandOutput(built.entryPath, ["needle"]);
			assertTrue(run.code == 0, "C++ smoke executable failed: " + run.stderr);
			assertTrue(run.stdout == "cpp-native:smoke\ntrace:smoke\n1\n-1\n1\nneedle\n0\n2\nbeta\n0\n10\n11\n5\n3\ntry:body\ntry:catch\n3\n1\n8\n4\n2147483647\n-2\n42\n41\n0\n1\n1\n0\n2\n2\n4\n2\n15\n3\nalpha\nbeta\n2\n10\nif:then\nor:true\nand:true\nnot:true\nMacro\nenum:eq\nIgnore\n7\nEParenthesis(EConst(CString(macro:value)))\ntwo\nswitch:seven\n7\n-3\nternary:yes\n5\n42\n",
				"unexpected C++ smoke stdout: "
				+ run.stdout);
		}

		deleteRecursive(root);
	}
}
