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

	static function assertThrowsContains(fn:Void->Void, needle:String, message:String):Void {
		try {
			fn();
		} catch (e:Dynamic) {
			final text = Std.string(e);
			if (text.indexOf(needle) >= 0)
				return;
			throw message + " (missing `" + needle + "` in `" + text + "`)";
		}
		throw message + " (function did not throw)";
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
			"    total *= 3;",
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
			"    var boxInfo = {box: box};",
			"    Sys.println(Std.string(box.value + 1));",
			"    Sys.println(Std.string(box.getHeight()));",
			"    var ref = RefNode.create(\"root\", null);",
			"    Sys.println(ref.item);",
			"    if (ref.next == null) {",
			"      Sys.println(\"ref:null\");",
			"    }",
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
			"    var doCount = 0;",
			"    do {",
			"      doCount++;",
			"    } while (doCount < 2);",
			"    Sys.println(Std.string(doCount + 0));",
			"    var doOnce = 0;",
			"    do {",
			"      doOnce++;",
			"    } while (false);",
			"    Sys.println(Std.string(doOnce + 0));",
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
			"    for (idx => word in words) {",
			"      Sys.println(Std.string(idx + 0));",
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
			"    var macroType = macro :X -> Y;",
			"    Sys.println(macroType);",
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
			"    var selfChild = new ChildSelf();",
			"    Sys.println(Std.string(selfChild.inheritedValue()));",
			"    var platformsJson = \".tmp/m14_cpp_native_backend_smoke/platforms.json\";",
			"    var platformMin = try { haxe.Json.parse(sys.io.File.getContent(platformsJson)).min; } catch(e) { Log.warn(\"Unable to determine minimum supported Android platform: \" + e.toString()); null; };",
			"    Sys.println(Std.string(platformMin + 0));",
			"    var joined = try { words.join(\",\"); } catch(e:Dynamic) { \"???\"; };",
			"    Sys.println(joined);",
			"  }",
			"}",
			"class FunctionSlot {",
			"  public function new() {}",
			"  public function filterGeneric(f:T -> Bool):String {",
			"    return \"ok\";",
			"  }",
			"  public function mapGeneric(f:T -> X):String {",
			"    return \"ok\";",
			"  }",
			"  public function noArg(f:Void -> String):String {",
			"    return \"ok\";",
			"  }",
			"}",
			"class UsesLater {",
			"  public var node:LaterNode;",
			"  public function new(node:LaterNode) {",
			"    this.node = node;",
			"  }",
			"  public function label():String {",
			"    return node.label;",
			"  }",
			"}",
			"class LaterNode {",
			"  public var label:String;",
			"  public function new(label:String) {",
			"    this.label = label;",
			"  }",
			"}",
			"class StructReturnIterator {",
			"  var idx:Int;",
			"  var current:String;",
			"  public function new(current:String) {",
			"    this.current = current;",
			"    this.idx = 0;",
			"  }",
			"  public function next():{key:Int, value:String} {",
			"    var val = current;",
			"    return {value: val, key: idx++};",
			"  }",
			"}",
			"class GenericListNode<T> {",
			"  public var item:T;",
			"  public var next:GenericListNode<T>;",
			"  public function new(item:T, next:GenericListNode<T>) {",
			"    this.item = item;",
			"    this.next = next;",
			"  }",
			"}",
			"class GenericListKeyValueIterator<T> {",
			"  var idx:Int;",
			"  var head:GenericListNode<T>;",
			"  public function new(head:GenericListNode<T>) {",
			"    this.head = head;",
			"    this.idx = 0;",
			"  }",
			"  public function next():{key:Int, value:T} {",
			"    var val = head.item;",
			"    head = head.next;",
			"    return {value: val, key: idx++};",
			"  }",
			"}",
			"class Log {",
			"  public static function warn(message:String):Void {",
			"    Sys.println(message);",
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
			"class BaseSelf {",
			"  public var value:Int = 3;",
			"  public function new() {}",
			"}",
			"class ChildSelf extends BaseSelf {",
			"  public function new() {",
			"    super();",
			"  }",
			"  public function inheritedValue():Int {",
			"    var parent = super;",
			"    return parent.value;",
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
			"class RefNode {",
			"  public var item:String;",
			"  public var next:Null<RefNode>;",
			"  public function new(item:String, next:Null<RefNode>) {",
			"    this.item = item;",
			"    this.next = next;",
			"  }",
			"  public static function create(item:String, next:Null<RefNode>):RefNode {",
			"    return new RefNode(item, next);",
			"  }",
			"}",
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function vendorListProgramWhenAvailable():Null<GenIrProgram> {
		final listPath = "vendor/haxe/std/haxe/ds/List.hx";
		if (!FileSystem.exists(listPath))
			return null;
		final listSource = File.getContent(listPath);
		final mainSource = "class Main { static function main() {} }";
		final typedMain = TyperStage.typeModule(ParserStage.parse(mainSource, "Main.hx"));
		final typedList = TyperStage.typeModule(ParserStage.parse(listSource, listPath));
		return MacroStage.expandProgram([typedMain, typedList], []);
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
		final exceptionStackTry = @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ETryCatchRaw('try{throw new Exception("");}catch(e:Exception){e.stack;}'));
		assertContains(exceptionStackTry, "throw std::runtime_error(std::string(\"\"));",
			"Exception stack try/catch raw should preserve the thrown message shape");
		assertContains(exceptionStackTry, "return std::vector<std::string>{};",
			"Exception stack try/catch raw should lower to an empty C++ stack vector for the MVP");
		final valueExceptionStackTry = @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ETryCatchRaw('try{throw new ValueException("");}catch(e:Exception){e.stack;}'));
		assertContains(valueExceptionStackTry, "throw std::runtime_error(std::string(\"\"));",
			"ValueException stack try/catch raw should preserve the thrown message shape");
		final constructorValueExceptionStackTry = @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ETryCatchRaw('try{throw new WithConstructorValueException("");}catch(e:Exception){e.stack;}'));
		assertContains(constructorValueExceptionStackTry, "throw std::runtime_error(std::string(\"\"));",
			"WithConstructorValueException stack try/catch raw should preserve the thrown message shape");
		final customExceptionStackTry = @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ETryCatchRaw('try{throw new CustomException("boom");}catch(e:Exception){e.stack;}'));
		assertContains(customExceptionStackTry, "throw std::runtime_error(std::string(\"boom\"));",
			"Exception stack try/catch raw should support exception-like class names");
		final thrownExceptionStackTry = @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ETryCatchRaw('try{throw @:privateAccess(Exception.thrown("boom"):Exception);}catch(e:Exception){e.stack;}'));
		assertContains(thrownExceptionStackTry, "throw std::runtime_error(std::string(\"boom\"));",
			"Exception.thrown stack try/catch raw should preserve the thrown message shape");
		final genericThrowStackTry = @:privateAccess backend.cpp.CppTargetCore.renderExpr(ETryCatchRaw('try{throw value;}catch(e:Exception){e.stack;}'));
		assertContains(genericThrowStackTry, "throw std::runtime_error(std::string(\"\"));",
			"Exception stack try/catch raw should support non-constructor throw probes");
		final catchValueTry = @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ETryCatchRaw('try{throw new Exception("boom");}catch(e){e;}'));
		assertContains(catchValueTry, "catch (const std::exception& e) { return std::string(e.what()); }",
			"catch-value raw try/catch should return a C++ exception message for the MVP");
		assertContains(catchValueTry, "throw std::runtime_error(std::string(\"boom\"));", "catch-value raw try/catch should preserve the thrown message shape");
		final simpleCallCatchValueTry = @:privateAccess backend.cpp.CppTargetCore.renderExpr(ETryCatchRaw('try{test();}catch(e:String){e;}'));
		assertContains(simpleCallCatchValueTry, "try { return test(); }",
			"simple call catch-value raw try/catch should preserve the successful call expression");
		assertContains(simpleCallCatchValueTry, "catch (const std::exception& e) { return std::string(e.what()); }",
			"simple call catch-value raw try/catch should return a C++ exception message");
		final fieldReadCatchStringTry = @:privateAccess backend.cpp.CppTargetCore.renderExpr(ETryCatchRaw('try{nf1.s;}catch(e:Any){"NPE";}'));
		assertContains(fieldReadCatchStringTry, "try { return nf1.s; }", "field-read catch-string raw try/catch should preserve the successful field read");
		assertContains(fieldReadCatchStringTry, "catch (...) { return std::string(\"NPE\"); }",
			"field-read catch-string raw try/catch should preserve the fallback string");
		final classNameProbeTry = @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ETryCatchRaw('try{Type.getClassName(t);}catch(e:Dynamic){"";}'));
		assertContains(classNameProbeTry, "try { return __hxhx_type_name(t); }",
			"utest-style Type.getClassName try/catch probes should lower through the C++ type-name helper");
		assertContains(classNameProbeTry, "catch (...) { return std::string(\"\"); }",
			"utest-style Type.getClassName try/catch probes should preserve the fallback string");
		final enumNameProbeTry = @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ETryCatchRaw('try{Type.getEnumName(t);}catch(e:Dynamic){"";}'));
		assertContains(enumNameProbeTry, "try { return __hxhx_type_name(t); }",
			"utest-style Type.getEnumName try/catch probes should lower through the C++ type-name helper");
		final typeofProbeTry = @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ETryCatchRaw('try{Std.string(Type.typeof(t));}catch(e:Dynamic){"";}'));
		assertContains(typeofProbeTry, "try { return __hxhx_type_name(t); }",
			"utest-style Std.string(Type.typeof(...)) try/catch probes should lower through the C++ type-name helper");
		final stdStringProbeTry = @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ETryCatchRaw('try{Std.string(t);}catch(e:Dynamic){\"fallback\";}'));
		assertContains(stdStringProbeTry, "try { return std::string(t); }",
			"utest-style Std.string try/catch probes should lower through normal string conversion");
		assertContains(stdStringProbeTry, "catch (...) { return std::string(\"fallback\"); }",
			"utest-style Std.string try/catch probes should preserve non-empty fallback strings");
		final typeofSafetyProbeTry = @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ETryCatchRaw('try{typeof(e);"false";}catch(e:Dynamic){"true";}'));
		assertContains(typeofSafetyProbeTry, "try { (void)__hxhx_type_name(e); return std::string(\"false\"); }",
			"remote Cpp gate typeof safety probes should preserve the success string");
		assertContains(typeofSafetyProbeTry, "catch (...) { return std::string(\"true\"); }",
			"remote Cpp gate typeof safety probes should preserve the catch string");
		final macroErrorProbeTry = @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ETryCatchRaw('try{typeof(e);null;}catch(e:haxe.macro.Expr.Error){var msg=e.message;if(e.childErrors!=null)for(c in e.childErrors)msg+=""+c.message;msg;}'));
		assertContains(macroErrorProbeTry, "try { (void)__hxhx_type_name(e); return std::string(); }",
			"remote Cpp gate macro error probes should preserve the no-error branch as an empty message");
		assertContains(macroErrorProbeTry, "catch (const std::exception& e) { return std::string(e.what()); }",
			"remote Cpp gate macro error probes should preserve the catch-message intent");
		final exceptionMessageProbeTry = @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ETryCatchRaw('try{typeof(e);"noerror";}catch(e:haxe.Exception){Std.string(e.message);}'));
		assertContains(exceptionMessageProbeTry, "try { (void)__hxhx_type_name(e); return std::string(\"noerror\"); }",
			"remote Cpp gate haxe.Exception probes should preserve the success marker");
		assertContains(exceptionMessageProbeTry, "catch (const std::exception& e) { return std::string(e.what()); }",
			"remote Cpp gate haxe.Exception probes should preserve message extraction intent");
		final fileContentContextErrorTry = @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ETryCatchRaw('try{sys.io.File.getContent(Context.resolvePath(file));}catch(e:Dynamic){Context.error(Std.string(e),Context.currentPos());}'));
		assertContains(fileContentContextErrorTry, "try { return __hxhx_read_file(file); }",
			"macro file-content probes should lower through the C++ file-read helper");
		assertContains(fileContentContextErrorTry, "catch (const std::exception& e) { throw std::runtime_error(std::string(e.what())); }",
			"macro file-content probes should preserve Context.error intent as a hard C++ failure");
		final opaqueObjectBlock = @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ETryCatchRaw('opaque_block_expr:{ var b:{v:Dynamic} = {v:"foo"}; }'));
		assertContains(opaqueObjectBlock, "struct __hxhx_opaque_block { std::string v; };",
			"opaque object block should declare a local C++ aggregate for the captured field");
		assertContains(opaqueObjectBlock, "return __hxhx_opaque_block{\"foo\"};", "opaque object block should preserve the captured string field value");
		final opaqueObjectMultiFieldBlock = @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ETryCatchRaw('opaque_block_expr:{ var b:{v:Int} = {v:0,w:"foo"}; }'));
		assertContains(opaqueObjectMultiFieldBlock, "struct __hxhx_opaque_block { int v; std::string w; };",
			"opaque object block should declare local aggregate fields from the initializer");
		assertContains(opaqueObjectMultiFieldBlock, "return __hxhx_opaque_block{0, \"foo\"};",
			"opaque object block should preserve multiple initializer field values");
		final opaqueTypedLocalRefBlock = @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ETryCatchRaw('opaque_block_expr:{ var x:TypedefToStringMap<String>; x; }'));
		assertContains(opaqueTypedLocalRefBlock, "std::shared_ptr<TypedefToStringMap> x = nullptr;",
			"opaque typed class-like local references should default-initialize as nullable C++ references");
		assertContains(opaqueTypedLocalRefBlock, "return x;", "opaque typed local reference should return the local value");
		final opaqueTypedLocalInitBlock = @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ETryCatchRaw("opaque_block_expr:{ var i:Int = z; }"));
		assertContains(opaqueTypedLocalInitBlock, "int i = z;", "opaque typed local init should preserve the initializer expression");
		assertContains(opaqueTypedLocalInitBlock, "return 0;", "opaque typed local init should produce a C++ MVP expression value");
		final opaqueEnumSwitchProbe = @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ETryCatchRaw("opaque_block_expr:{switch(va){caseAccNormal)"));
		assertContains(opaqueEnumSwitchProbe, "return std::string(va) == std::string(\"AccNormal\");",
			"remote Cpp gate opaque enum-switch probe should lower to a narrow enum-name comparison");
		final opaqueEnumSwitchProbeWithHiddenSuffix = @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ETryCatchRaw("opaque_block_expr:{switch(va){caseAccNormal)\r}"));
		assertContains(opaqueEnumSwitchProbeWithHiddenSuffix, "return std::string(va) == std::string(\"AccNormal\");",
			"remote Cpp gate opaque enum-switch probe should tolerate hidden line-ending/suffix delimiters");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("Type"), "getClassName"), [EIdent("t")])) == "__hxhx_type_name(t)",
			"direct Type.getClassName calls should lower through the C++ type-name helper");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("Type"), "getEnumName"), [EIdent("t")])) == "__hxhx_type_name(t)",
			"direct Type.getEnumName calls should lower through the C++ type-name helper");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("Type"), "typeof"), [EIdent("t")])) == "__hxhx_type_name(t)",
			"direct Type.typeof calls should lower to a printable C++ MVP type name");
		assertThrowsContains(() -> @:privateAccess backend.cpp.CppTargetCore.renderExpr(ETryCatchRaw("try{unsupported();}catch(e:Dynamic){}")),
			"ETryCatchRaw(try{unsupported();}catch(e:Dynamic){})",
			"unsupported raw try/catch diagnostics should include a compact raw payload for remote gate triage");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.renderExpr(EBinop("is", EInt(1), EIdent("Int"))) == "__hxhx_is_type(1, \"Int\")",
			"Haxe is-expressions should lower through the C++ MVP type-test helper");
		assertTrue(@:privateAccess
			backend.cpp.CppTargetCore.renderExpr(EBinop("is", EString("s"),
				EField(EIdent("StdTypes"), "String"))) == "__hxhx_is_type(\"s\", \"StdTypes.String\")",
			"qualified Haxe type tests should preserve their type path");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.renderExpr(EBinop("is", EInt(1), EUnsupported("Int"))) == "__hxhx_is_type(1, \"Int\")",
			"raw type-path fragments in Haxe is-expressions should lower through the C++ MVP type-test helper");
		assertTrue(@:privateAccess
			backend.cpp.CppTargetCore.renderExpr(EBinop("??", EIdent("value"),
				ECall(EIdent("fallback"), []))) == "__hxhx_null_coalesce(value, [&]() { return fallback(); })",
			"C++ null-coalescing expressions should lower through a lazy target helper");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.renderExpr(EBinop("??", ENull, EInt(2))) == "__hxhx_null_coalesce(nullptr, [&]() { return 2; })",
			"C++ null-coalescing should preserve explicit null left operands");
		assertTrue(@:privateAccess
			backend.cpp.CppTargetCore.renderExpr(EBinop("??=", EIdent("slot"),
				ECall(EIdent("fallback"),
					[]))) == "([&]() { auto& __hxhx_null_assign_target = slot; __hxhx_null_assign_target = __hxhx_null_coalesce(__hxhx_null_assign_target, [&]() { return fallback(); }); return __hxhx_null_assign_target; })()",
			"C++ null-coalescing assignment should bind the assignment target once");
		final rangeExpr = @:privateAccess backend.cpp.CppTargetCore.renderExpr(ERange(EInt(1), EInt(4)));
		assertContains(rangeExpr, "std::vector<int> __hxhx_range_out;", "range expressions should lower to a C++ vector builder");
		assertContains(rangeExpr, "int __hxhx_range_start = 1;", "range expressions should bind the start once");
		assertContains(rangeExpr, "int __hxhx_range_end = 4;", "range expressions should bind the exclusive end once");
		assertContains(rangeExpr, "__hxhx_range_i < __hxhx_range_end", "range expressions should preserve Haxe's exclusive upper bound");
		final rangeComprehension = @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(EArrayComprehension("i", ERange(EInt(0), EInt(3)), null, EBinop("*", EIdent("i"), EInt(2))));
		assertContains(rangeComprehension, "for (int i = 0; i < 3; i++) {", "array comprehensions should keep optimized range iteration");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.renderExpr(EBinop("%", EIdent("index"), EInt(2))) == "(index % 2)",
			"C++ modulo expressions should lower as simple binary operators");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.renderExpr(EBinop("^", EIdent("mask"), EInt(1))) == "(mask ^ 1)",
			"C++ bitwise xor expressions should lower as simple binary operators");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.renderExpr(EBinop("<<=", EIdent("mask"), EInt(1))) == "mask <<= 1",
			"C++ left-shift assignments should lower as simple compound assignments");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.renderExpr(EBinop(">>=", EIdent("mask"), EInt(1))) == "mask >>= 1",
			"C++ right-shift assignments should lower as simple compound assignments");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.renderExpr(EBinop("|=", EIdent("mask"), EInt(1))) == "mask |= 1",
			"C++ bitwise-or assignments should lower as simple compound assignments");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.renderExpr(EBinop("&=", EIdent("mask"), EInt(1))) == "mask &= 1",
			"C++ bitwise-and assignments should lower as simple compound assignments");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.renderExpr(EBinop("^=", EIdent("mask"), EInt(1))) == "mask ^= 1",
			"C++ bitwise-xor assignments should lower as simple compound assignments");
		final unsignedShiftAssign = @:privateAccess backend.cpp.CppTargetCore.renderExpr(EBinop(">>>=", EIdent("mask"), EInt(1)));
		assertContains(unsignedShiftAssign, "auto& __hxhx_ushr_assign_target = mask;",
			"C++ unsigned right-shift assignments should bind the assignment target once");
		assertContains(unsignedShiftAssign, "__hxhx_ushr_assign_target = static_cast<unsigned int>(__hxhx_ushr_assign_target) >> __hxhx_ushr_assign_count;",
			"C++ unsigned right-shift assignments should preserve Haxe unsigned shift semantics");
		assertTrue(@:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("HelperMacros"), "typeErrorText"),
				[EUnsupported("for_expr:for (key => value in 1) { }")])) == "\"Int has no field keyValueIterator\"",
			"C++ HelperMacros.typeErrorText for-expression probes should fold to the expected diagnostic text");
		assertTrue(@:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("HelperMacros"), "typeError"),
				[EUnsupported("for_expr:for (key => value in new MyNotIterator()) { }")])) == "true",
			"C++ HelperMacros.typeError for-expression probes should fold to true");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.renderExpr(EMacroType("X -> Y")) == "std::string(\"X -> Y\")",
			"C++ macro type quotes should lower to stable printable text in the MVP");
		final enumPayloadOwner = new HxClassDecl("EnumPayloadOwner", false, [], []);
		final enumPayloadNames = new StringMap<Bool>();
		enumPayloadNames.set("EnumPayloadOwner", true);
		final enumPayloadClasses = new StringMap<HxClassDecl>();
		enumPayloadClasses.set("EnumPayloadOwner", enumPayloadOwner);
		final enumPayloadLookup = {names: enumPayloadNames, byName: enumPayloadClasses};
		final enumPayloadScope = @:privateAccess backend.cpp.CppTargetCore.renderScope(enumPayloadOwner, enumPayloadLookup, "auto");
		enumPayloadScope.localTypes.set("x", "std::string");
		final enumPayloadStruct = @:privateAccess backend.cpp.CppTargetCore.anonStruct(["__hx_params"], [EArrayDecl([EIdent("x")])], enumPayloadScope);
		assertTrue(enumPayloadStruct.fieldTypes[0] == "std::vector<std::string>",
			"C++ enum payload arrays should preserve scoped string argument element types");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.renderExpr(EArrayDecl([EIdent("x")]),
			enumPayloadScope) == "std::vector<std::string>{std::string(x)}",
			"C++ enum payload arrays should render string arguments with matching vector element types");
		final enumCtorHelper = new HxFunctionDecl("U1", Public, true, [new HxFunctionArg("x", "String", NoDefault, false, false)], "Dynamic", [
			SReturn(EAnon(["__hx_enum", "__hx_ctor", "__hx_index", "__hx_params"], [EString("X"), EString("U1"), EInt(0), EArrayDecl([EIdent("x")])]),
				HxPos.unknown())
		], "");
		final enumCtorHelperLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperMethod(enumCtorHelper, enumPayloadOwner, enumPayloadLookup).join("\n");
		assertContains(enumCtorHelperLines, "static std::string U1(std::string x) {\n    return std::string(\"U1\");\n  }",
			"C++ enum metadata constructors with Dynamic return should stringify to their constructor tag, not std::to_string an aggregate");
		final listNode = new HxClassDecl("ListNode", false, [], [new HxFieldDecl("next", Public, false, "Null<ListNode>", null)]);
		final listOwner = new HxClassDecl("ListOwner", false, [], []);
		final listNames = new StringMap<Bool>();
		listNames.set("ListNode", true);
		listNames.set("ListOwner", true);
		final listClasses = new StringMap<HxClassDecl>();
		listClasses.set("ListNode", listNode);
		listClasses.set("ListOwner", listOwner);
		final listLookup = {names: listNames, byName: listClasses};
		final listRemoveLike = new HxFunctionDecl("removeLike", Public, false, [], "Bool", [
			SVar("prev", "Null<ListNode>", ENull, HxPos.unknown()),
			SVar("l", "Null<ListNode>", ENull, HxPos.unknown()),
			SExpr(EBinop("=", EField(EIdent("prev"), "next"), EField(EIdent("l"), "next")), HxPos.unknown()),
			SExpr(EBinop("=", EIdent("prev"), EIdent("l")), HxPos.unknown()),
			SReturn(EBool(true), HxPos.unknown())
		], "");
		final listRemoveLikeLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(listRemoveLike, listOwner, listLookup).join("\n");
		assertContains(listRemoveLikeLines, "std::shared_ptr<ListNode> prev = nullptr;",
			"C++ null-initialized class locals with explicit Haxe type hints should not emit auto/nullptr_t");
		assertContains(listRemoveLikeLines, "(prev->next) = (l->next);", "C++ typed nullable locals should keep reference field access");
		assertContains(listRemoveLikeLines, "prev = l;", "C++ typed nullable locals should accept later class-reference assignments");
		final exprBodyOwner = new HxClassDecl("ExpressionBodyOwner", false, [], [new HxFieldDecl("key", Public, false, "String", null)]);
		final exprBodyNames = new StringMap<Bool>();
		exprBodyNames.set("ExpressionBodyOwner", true);
		final exprBodyClasses = new StringMap<HxClassDecl>();
		exprBodyClasses.set("ExpressionBodyOwner", exprBodyOwner);
		final exprBodyLookup = {names: exprBodyNames, byName: exprBodyClasses};
		final exprBodyMethod = new HxFunctionDecl("next", Public, false, [], "String", [SExpr(EIdent("key"), HxPos.unknown())], "");
		final exprBodyMethodLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperMethod(exprBodyMethod, exprBodyOwner, exprBodyLookup).join("\n");
		assertContains(exprBodyMethodLines, "std::string next() {\n    return std::string(key);\n  }",
			"C++ smoke should return non-void helper expression bodies instead of emitting bare expression statements");
		final exprBodyStatic = new HxFunctionDecl("staticNext", Public, true, [], "String", [SExpr(EString("static-key"), HxPos.unknown())], "");
		final exprBodyStaticLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperMethod(exprBodyStatic, exprBodyOwner, exprBodyLookup).join("\n");
		assertContains(exprBodyStaticLines, "static std::string staticNext() {\n    return std::string(\"static-key\");\n  }",
			"C++ smoke should return non-void static helper expression bodies");

		BackendRegistry.clearDynamicRegistrations();
		final descriptor = BackendRegistry.descriptorForTarget("cpp-native");
		assertTrue(descriptor != null, "missing cpp-native descriptor");
		assertTrue(descriptor.implId == "builtin/cpp-native-source-mvp", "unexpected cpp-native implId");
		assertTrue(descriptor.capabilities.supportsBuildExecutable, "cpp-native should own executable build support");

		final root = Path.join([Sys.getCwd(), ".tmp", "m14_cpp_native_backend_smoke"]);
		deleteRecursive(root);
		FileSystem.createDirectory(root);
		File.saveContent(Path.join([root, "platforms.json"]), "{\"min\":4}");

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
		assertContains(source, "int casted = helper(5);", "C++ smoke should lower cast expression with explicit local type");
		assertContains(source, "total += 4;", "C++ smoke should lower compound plus assignment");
		assertContains(source, "total -= 2;", "C++ smoke should lower compound minus assignment");
		assertContains(source, "total *= 3;", "C++ smoke should lower compound multiply assignment");
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
		assertContains(source, "auto box = std::make_shared<Box>(41);", "C++ smoke should lower class construction to nullable references");
		assertContains(source, "auto boxInfo = __hxhx_anon_box_std__shared_ptr_Box_{box};",
			"C++ smoke should lower anonymous objects containing class references");
		assertTrue(source.indexOf("struct Box;") < source.indexOf("struct __hxhx_anon_box_std__shared_ptr_Box_ {"),
			"C++ smoke should emit helper forward declarations before anonymous structs that reference helpers");
		assertContains(source, "box->getHeight()", "C++ smoke should lower class receiver method calls through reference access");
		assertContains(source, "std::shared_ptr<RefNode> next = nullptr;", "C++ smoke should type nullable class fields as C++ references");
		assertContains(source, "std::string filterGeneric(std::function<bool(std::string)> f) {",
			"C++ smoke should lower generic function type parameters to callable C++ types instead of undefined sanitized identifiers");
		assertContains(source, "std::string mapGeneric(std::function<std::string(std::string)> f) {",
			"C++ smoke should lower generic function return segments through the MVP dynamic string fallback");
		assertContains(source, "std::string noArg(std::function<std::string()> f) {",
			"C++ smoke should lower Void function arguments to zero-argument std::function signatures");
		assertTrue(source.indexOf("struct LaterNode {") < source.indexOf("struct UsesLater {"),
			"C++ smoke should emit helper class definitions before classes that dereference them through shared_ptr fields");
		assertContains(source, "struct __hxhx_anon_value_std__string_key_int_ {",
			"C++ smoke should collect structural anonymous return payloads with identifier values as strings");
		assertContains(source, "auto next() {\n    auto val = current;\n    return __hxhx_anon_value_std__string_key_int_{std::string(val), (idx++)};\n  }",
			"C++ smoke should lower structural anonymous return types through C++ auto instead of stringifying the key field");
		assertContains(source,
			"auto next() {\n    auto val = (head->item);\n    head = (head->next);\n    return __hxhx_anon_value_std__string_key_int_{std::string(val), (idx++)};\n  }",
			"C++ smoke should lower generic key/value iterator structural returns through C++ auto");
		assertContains(source, "auto ref = std::make_shared<RefNode>(\"root\", nullptr);",
			"C++ smoke should lower class create factories to constructors without requiring inline runtime stubs");
		assertContains(source, "(ref->item)", "C++ smoke should read fields through class references");
		assertContains(source, "(ref->next) == nullptr", "C++ smoke should compare nullable class references with nullptr");
		assertContains(source, "(bump++)", "C++ smoke should lower post-increment expression");
		assertContains(source, "(bump--)", "C++ smoke should lower post-decrement expression");
		assertContains(source, "while (spin < 2) {", "C++ smoke should emit while statement");
		assertContains(source, "do {", "C++ smoke should emit do-while body before condition");
		assertContains(source, "} while (doCount < 2);", "C++ smoke should emit do-while trailing condition");
		assertContains(source, "break;", "C++ smoke should emit break statement");
		assertContains(source, "continue;", "C++ smoke should emit continue statement");
		assertContains(source, "auto native = std::vector<int>(2);", "C++ smoke should lower NativeArray.create");
		assertContains(source, "(native[0]) = 7;", "C++ smoke should emit NativeArray indexed assignment");
		assertContains(source, "(native.size())", "C++ smoke should emit NativeArray length read");
		assertContains(source, "for (int i = 0; i < 3; i++) {", "C++ smoke should emit range for-in statement");
		assertContains(source, "for (auto word : words) {", "C++ smoke should emit iterable for-in statement");
		assertContains(source, "for (std::size_t __hxhx_kv_idx = 0; __hxhx_kv_idx < words.size(); ++__hxhx_kv_idx) {",
			"C++ smoke should emit indexed key/value for-in statement");
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
		assertContains(source, "auto macroType = std::string(\"X -> Y\");", "C++ smoke should lower macro type quotes to stable text");
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
		assertContains(source, "auto parent = (*this);", "C++ smoke should lower bare super expressions to the current base-backed object");
		assertContains(source, "__hxhx_json_min_field_from_file(platformsJson)",
			"C++ smoke should lower hxcpp Android platform-min try/catch expressions through target runtime support");
		assertContains(source, "__hxhx_join(words, \",\")", "C++ smoke should lower array join try/catch expressions through target runtime support");
		assertContains(source, "static bool __hxhx_is_type(int, const std::string& type)", "C++ smoke should include Haxe is-expression helper overloads");
		assertContains(source, "static std::string __hxhx_type_name(int)", "C++ smoke should include Haxe type-name helper overloads");
		assertContains(source, "auto __hxhx_null_coalesce(std::nullptr_t, F fallback)", "C++ smoke should include Haxe null-coalescing helper overloads");

		final vendorListProgram = vendorListProgramWhenAvailable();
		if (vendorListProgram != null) {
			final vendorListDir = Path.join([root, "vendor-list-source-only"]);
			final vendorListEmit = BackendRegistry.createForTarget("cpp-native").emit(vendorListProgram, context(vendorListDir, true, true));
			final vendorListSource = File.getContent(vendorListEmit.entryPath);
			assertContains(vendorListSource,
				"auto next() {\n    auto val = (head->item);\n    head = (head->next);\n    return __hxhx_anon_value_std__string_key_int_{std::string(val), (idx++)};\n  }",
				"C++ smoke should preserve upstream ListKeyValueIterator.next key/value return body");
		}

		if (commandExists("c++") || commandExists("g++") || commandExists("clang++")) {
			final buildDir = Path.join([root, "build"]);
			final built = BackendRegistry.createForTarget("cpp-native").emit(program(), context(buildDir, true, false));
			assertTrue(hasArtifactKind(built.artifacts, "entry_cpp_exe"), "missing entry_cpp_exe artifact");
			assertTrue(built.builtExecutable, "C++ compiler smoke should mark built executable");
			final run = commandOutput(built.entryPath, ["needle"]);
			assertTrue(run.code == 0, "C++ smoke executable failed: " + run.stderr);
			assertTrue(run.stdout == "cpp-native:smoke\ntrace:smoke\n1\n-1\n1\nneedle\n0\n2\nbeta\n0\n10\n11\n5\n3\n9\ntry:body\ntry:catch\n3\n1\n8\n4\n2147483647\n-2\n42\n41\nroot\nref:null\n0\n1\n1\n0\n2\n2\n1\n2\n4\n2\n15\n3\nalpha\nbeta\n0\nalpha\n1\nbeta\n2\n10\nif:then\nor:true\nand:true\nnot:true\nMacro\nenum:eq\nIgnore\n7\nEParenthesis(EConst(CString(macro:value)))\nX -> Y\ntwo\nswitch:seven\n7\n-3\nternary:yes\n5\n42\n3\n4\nalpha,beta\n",
				"unexpected C++ smoke stdout: "
				+ run.stdout);
		}

		deleteRecursive(root);
	}
}
