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
			"class BodyOnlyUser {",
			"  public function new() {}",
			"  public function render():Void {",
			"    var buf = new BodyOnlyBuffer();",
			"    buf.add(\"{\");",
			"  }",
			"}",
			"class BodyOnlyBuffer {",
			"  var text:String;",
			"  public function new() {",
			"    text = \"\";",
			"  }",
			"  public function add(value:String):Void {",
			"    text += value;",
			"  }",
			"  public function toString():String {",
			"    return text;",
			"  }",
			"}",
			"class StaticBodyUser {",
			"  public function new() {}",
			"  public function render():String {",
			"    return StaticBodyProvider.check(\"ok\");",
			"  }",
			"}",
			"class StaticBodyProvider {",
			"  public function new() {}",
			"  public static function check(value:String):String {",
			"    return value;",
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
			"class ArrayKeyValueLike {",
			"  var current:Int;",
			"  var array:Array<String>;",
			"  public function new(array:Array<String>) {",
			"    this.array = array;",
			"    this.current = 0;",
			"  }",
			"  public function next():{key:Int, value:String} {",
			"    return {value: array[current], key: current++};",
			"  }",
			"}",
			"class QualifiedNativeArrayUser {",
			"  public function new() {}",
			"  public function make(length:Int):Array<Int> {",
			"    return cpp.NativeArray.create(length);",
			"  }",
			"}",
			"class QualifiedNativeArrayStringUser {",
			"  public function new() {}",
			"  public function copyFirst(length:Int):Array<String> {",
			"    var result = cpp.NativeArray.create(length);",
			"    var seed = [\"seed\"];",
			"    cpp.NativeArray.unsafeSet(result, 0, cpp.NativeArray.unsafeGet(seed, 0));",
			"    return result;",
			"  }",
			"}",
			"class CppReservedNames {",
			"  public static function and(a:Int, b:Int):Int {",
			"    return a + b;",
			"  }",
			"  public static function or(a:Int, b:Int):Int {",
			"    return a - b;",
			"  }",
			"  public static function xor(a:Int, b:Int):Int {",
			"    return a * b;",
			"  }",
			"}",
			"class LambdaLike {",
			"  public function new() {}",
			"  public static function array(it:Iterable<String>):Array<String> {",
			"    return [for (x in it) x];",
			"  }",
			"  public static function arrayFromNew(it:Iterable<String>):Array<String> {",
			"    var a = new Array();",
			"    for (x in it) a.push(x);",
			"    return a;",
			"  }",
			"  public static function mapLike(it:Iterable<String>, f:String->String):Array<String> {",
			"    return [for (x in it) f(x)];",
			"  }",
			"  public static function mapiLike(it:Iterable<String>, f:(index:Int, item:String)->String):Array<String> {",
			"    var i = 0;",
			"    return [for (x in it) f(i++, x)];",
			"  }",
			"  public static function flattenLike(it:Iterable<Iterable<String>>):Array<String> {",
			"    return [for (x in it) for (y in x) y];",
			"  }",
			"  public static function flatten(it:Iterable<Iterable<String>>):Array<String> {",
			"    return [for (x in it) for (y in x) y];",
			"  }",
			"  public static function map(it:Iterable<String>, f:String->Iterable<String>):Array<Iterable<String>> {",
			"    return [for (x in it) f(x)];",
			"  }",
			"  public static function flatMap(it:Iterable<String>, f:String->Iterable<String>):Array<String> {",
			"    return LambdaLike.flatten(LambdaLike.map(it, f));",
			"  }",
			"  public static function filter(it:Iterable<String>, f:String->Bool):Array<String> {",
			"    return [for (x in it) if (f(x)) x];",
			"  }",
			"  public static function filterInferred(it:Iterable<String>, f:String->Bool) {",
			"    return [for (x in it) if (f(x)) x];",
			"  }",
			"  public static function count(it:Iterable<String>, ?pred:String->Bool):Int {",
			"    var n = 0;",
			"    if (pred == null) {",
			"      for (_ in it) n++;",
			"    } else {",
			"      for (x in it) if (pred(x)) n++;",
			"    }",
			"    return n;",
			"  }",
			"  public static function empty(it:Array<String>):Bool {",
			"    return !it.iterator().hasNext();",
			"  }",
			"}",
			"class CppStringToolsLike {",
			"  public static function urlEncode(s:String):String {",
			"    return untyped s.__URLEncode();",
			"  }",
			"  public static function urlDecode(s:String):String {",
			"    return untyped s.__URLDecode();",
			"  }",
			"  public static function htmlUnescape(s:String):String {",
			"    return s.split(\"&gt;\").join(\">\").split(\"&lt;\").join(\"<\");",
			"  }",
			"  public static function startsWith(s:String, start:String):Bool {",
			"    return s.length >= start.length && s.lastIndexOf(start, 0) == 0;",
			"  }",
			"  public static function isSpace(s:String, pos:Int):Bool {",
			"    var c = s.charCodeAt(pos);",
			"    return c == 32;",
			"  }",
			"  public static function trimPiece(s:String):String {",
			"    return s.substr(1, 2);",
			"  }",
			"  public static function middle(s:String):String {",
			"    return s.substring(1, 3);",
			"  }",
			"  public static function hexLike(n:Int):String {",
			"    var s = \"\";",
			"    var hexChars = \"0123456789ABCDEF\";",
			"    s = hexChars.charAt(n & 15) + s;",
			"    return s;",
			"  }",
			"  public static function zeroCode():Int {",
			"    return \"0\".code;",
			"  }",
			"}",
			"class StringIteratorUnicode {",
			"  var offset = 0;",
			"  var s:String;",
			"  public function new(s:String) {",
			"    this.s = s;",
			"  }",
			"  public function hasNext() {",
			"    return offset < s.length;",
			"  }",
			"  public function next() {",
			"    return StringTools.unsafeCodeAt(s, offset++);",
			"  }",
			"}",
			"class CppStringIteratorForInLike {",
			"  public static function sum(s:String):Int {",
			"    var total = 0;",
			"    for (code in new StringIteratorUnicode(s)) {",
			"      total += code;",
			"    }",
			"    return total;",
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

	static function vendorLambdaProgramWhenAvailable():Null<GenIrProgram> {
		final lambdaPath = "vendor/haxe/std/Lambda.hx";
		if (!FileSystem.exists(lambdaPath))
			return null;
		final lambdaSource = File.getContent(lambdaPath);
		final mainSource = "class Main { static function main() {} }";
		final typedMain = TyperStage.typeModule(ParserStage.parse(mainSource, "Main.hx"));
		final typedLambda = TyperStage.typeModule(ParserStage.parse(lambdaSource, lambdaPath));
		return MacroStage.expandProgram([typedMain, typedLambda], []);
	}

	static function mathExternProgram():GenIrProgram {
		final src = [
			"extern class Math {",
			"  static var PI(default, null):Float;",
			"  static var NaN(default, null):Float;",
			"  static var POSITIVE_INFINITY(default, null):Float;",
			"  static function cos(value:Float):Float;",
			"  static function isNaN(value:Float):Bool;",
			"  static function isFinite(value:Float):Bool;",
			"  private static function __init__():Void untyped {",
			"    Math.NaN = Number[\"NaN\"];",
			"  }",
			"}",
			"class Main {",
			"  static function main() {",
			"    Sys.println(Std.string(Math.isNaN(Math.NaN)));",
			"    Sys.println(Std.string(Math.isFinite(Math.PI)));",
			"    var cosine = Math.cos;",
			"    Sys.println(Std.string(cosine(0.0)));",
			"  }",
			"}"
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
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.renderExpr(EField(EIdent("Math"), "NaN")) == "std::numeric_limits<double>::quiet_NaN()",
			"C++ Math.NaN should lower as a target intrinsic instead of a generated helper field");
		assertTrue(@:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("Math"), "isNaN"),
				[EField(EIdent("Math"), "NaN")])) == "std::isnan(std::numeric_limits<double>::quiet_NaN())",
			"C++ Math.isNaN should lower as a target intrinsic instead of a generated helper method");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("Math"), "round"),
			[EFloat(1.5)])) == "static_cast<int>(std::floor((1.5) + 0.5))",
			"C++ Math.round should preserve Haxe's floor(x + 0.5) semantics");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.renderExpr(EField(EIdent("Math"), "cos")) == "[](double v) { return std::cos(v); }",
			"C++ Math method references should lower to callable target intrinsics");
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
		final optionalOwner = new HxClassDecl("OptionalOwner", false, [], []);
		final optionalLookup = {names: new StringMap<Bool>(), byName: new StringMap<HxClassDecl>()};
		final optionalLenMethod = new HxFunctionDecl("addSubLike", Public, false, [
			new HxFunctionArg("s", "String", NoDefault, false, false),
			new HxFunctionArg("len", "Int", NoDefault, true, false)
		], "Void", [
			SIf(EBinop("==", EIdent("len"), ENull), SExpr(ECall(EIdent("use"), [EIdent("s")]), HxPos.unknown()),
				SExpr(ECall(EIdent("useLen"), [EIdent("len")]), HxPos.unknown()), HxPos.unknown())
		], "");
		final optionalLenLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(optionalLenMethod, optionalOwner, optionalLookup).join("\n");
		assertContains(optionalLenLines, "void addSubLike(std::string s, std::optional<int> len = std::nullopt) {",
			"C++ optional scalar args should use std::optional instead of invalid int/nullptr pairs");
		assertContains(optionalLenLines, "if (!len.has_value()) {", "C++ optional scalar null checks should test optional presence");
		assertContains(optionalLenLines, "useLen(len.value());", "C++ optional scalar value uses should unwrap after null checks");
		final optionalReturnMethod = new HxFunctionDecl("firstLike", Public, false, [new HxFunctionArg("value", "String", NoDefault, false, false)],
			"Null<String>", [
				SIf(EBinop("==", EIdent("value"), EString("")), SReturn(ENull, HxPos.unknown()), SReturn(EIdent("value"), HxPos.unknown()), HxPos.unknown())
			], "");
		final optionalReturnLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(optionalReturnMethod, optionalOwner, optionalLookup)
			.join("\n");
		assertContains(optionalReturnLines, "std::optional<std::string> firstLike(std::string value) {",
			"C++ optional string returns should use std::optional instead of falling through to int casts");
		assertContains(optionalReturnLines, "return std::nullopt;", "C++ optional returns should lower return null to std::nullopt");
		assertContains(optionalReturnLines, "return value;", "C++ optional returns should return payload expressions without static_cast<int>");
		final defaultBoolMethod = new HxFunctionDecl("exceptionStackLike", Public, true,
			[new HxFunctionArg("fullStack", "", Default(EBool(false)), false, false)], "Bool", [
				SReturn(ETernary(EIdent("fullStack"), EBool(true), EBool(false)), HxPos.unknown())
			], "");
		final defaultBoolLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(defaultBoolMethod, optionalOwner, optionalLookup).join("\n");
		assertContains(defaultBoolLines, "static bool exceptionStackLike(bool fullStack) {",
			"C++ default false arguments without explicit type hints should infer bool, not std::string");
		assertContains(defaultBoolLines, "return ((fullStack) ? true : false);", "C++ default false arguments should be usable as boolean ternary conditions");
		assertTrue(defaultBoolLines.indexOf("std::string fullStack") < 0, "C++ default false arguments should not fall back to std::string");
		final switchPatternMethod = new HxFunctionDecl("equalItemsLike", Public, true, [
			new HxFunctionArg("item1", "String", NoDefault, false, false),
			new HxFunctionArg("item2", "String", NoDefault, false, false)
		], "Bool", [
			SReturn(ESwitch(EIdent("item1"), [PEnumExtract("Module", [PBind("m1")]), PWildcard], [
				ESwitch(EIdent("item2"), [PEnumExtract("Module", [PBind("m2")]), PWildcard], [EBinop("==", EIdent("m1"), EIdent("m2")), EBool(false)]),
				EBool(false)
			]), HxPos.unknown())
		], "");
		final switchPatternLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(switchPatternMethod, optionalOwner, optionalLookup).join("\n");
		assertContains(switchPatternLines, "auto m1 = __hxhx_switch;",
			"C++ switch branches should bind enum-pattern variables before rendering branch expressions");
		assertContains(switchPatternLines, "auto m2 = __hxhx_switch;",
			"C++ nested switch branches should bind enum-pattern variables before rendering branch expressions");
		assertContains(switchPatternLines, "return (m1 == m2);", "C++ switch branch expressions should use pattern variables after they are declared");
		final arrayPatternMethod = new HxFunctionDecl("equalArrayItemsLike", Public, true,
			[new HxFunctionArg("items", "Array<String>", NoDefault, false, false)], "Bool", [
				SReturn(ESwitch(EIdent("items"), [PArray([PBind("item1"), PBind("item2")]), PWildcard],
					[EBinop("==", EIdent("item1"), EIdent("item2")), EBool(false)]),
					HxPos.unknown())
			], "");
		final arrayPatternLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(arrayPatternMethod, optionalOwner, optionalLookup).join("\n");
		assertContains(arrayPatternLines, "auto item1 = (__hxhx_switch[0]);",
			"C++ array-pattern variables should bind to indexed elements, not the whole array value");
		assertContains(arrayPatternLines, "auto item2 = (__hxhx_switch[1]);",
			"C++ array-pattern variables should bind each requested index before rendering branch expressions");
		assertContains(arrayPatternLines, "return (item1 == item2);", "C++ array-pattern branch expressions should use indexed binders after declaration");
		final stringSource = new HxClassDecl("StringSource", false, [
			new HxFunctionDecl("toString", Public, false, [], "String", [SReturn(EString("source"), HxPos.unknown())], "")
		], []);
		final stringCaller = new HxClassDecl("StringCaller", false, [], []);
		final stringCallNames = new StringMap<Bool>();
		stringCallNames.set("StringSource", true);
		stringCallNames.set("StringCaller", true);
		final stringCallClasses = new StringMap<HxClassDecl>();
		stringCallClasses.set("StringSource", stringSource);
		stringCallClasses.set("StringCaller", stringCaller);
		final stringCallLookup = {names: stringCallNames, byName: stringCallClasses};
		final stringCallMethod = new HxFunctionDecl("renderLike", Public, false, [], "String", [
			SVar("s", "", ENew("StringSource", []), HxPos.unknown()),
			SReturn(ECall(EField(EIdent("s"), "toString"), []), HxPos.unknown())
		], "");
		final stringCallLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(stringCallMethod, stringCaller, stringCallLookup).join("\n");
		assertContains(stringCallLines, "return s->toString();",
			"C++ string-returning method calls should flow directly instead of std::to_string(std::string)");
		assertTrue(stringCallLines.indexOf("std::to_string(s->toString())") < 0, "C++ string-returning method calls should not be wrapped in std::to_string");
		final baseString = new HxClassDecl("BaseString", false, [
			new HxFunctionDecl("toString", Public, false, [], "String", [SReturn(EString("base"), HxPos.unknown())], "")
		], []);
		final childString = new HxClassDecl("ChildString", false, [], [], "BaseString");
		final superStringNames = new StringMap<Bool>();
		for (name in ["BaseString", "ChildString"])
			superStringNames.set(name, true);
		final superStringClasses = new StringMap<HxClassDecl>();
		superStringClasses.set("BaseString", baseString);
		superStringClasses.set("ChildString", childString);
		final superStringLookup = {names: superStringNames, byName: superStringClasses};
		final superStringMethod = new HxFunctionDecl("renderSuperString", Public, false, [], "String",
			[SReturn(ECall(EField(ESuper, "toString"), []), HxPos.unknown())], "");
		final superStringLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperMethod(superStringMethod, childString, superStringLookup).join("\n");
		assertContains(superStringLines, "return BaseString::toString();",
			"C++ string-returning super method calls should flow directly instead of std::to_string(std::string)");
		assertTrue(superStringLines.indexOf("std::to_string(BaseString::toString())") < 0,
			"C++ string-returning super method calls should not be wrapped in std::to_string");
		final selfStringOwner = new HxClassDecl("SelfStringOwner", false, [], []);
		final selfStringNames = new StringMap<Bool>();
		selfStringNames.set("SelfStringOwner", true);
		final selfStringClasses = new StringMap<HxClassDecl>();
		selfStringClasses.set("SelfStringOwner", selfStringOwner);
		final selfStringLookup = {names: selfStringNames, byName: selfStringClasses};
		final selfStringMethod = new HxFunctionDecl("toStringLike", Public, false, [], "String", [SReturn(EThis, HxPos.unknown())], "");
		final selfStringLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(selfStringMethod, selfStringOwner, selfStringLookup).join("\n");
		assertContains(selfStringLines, "return __hxhx_type_name((*this));",
			"C++ class-like self stringification should use the target type-name helper instead of std::to_string(object)");
		assertTrue(selfStringLines.indexOf("std::to_string((*this))") < 0, "C++ class-like self stringification should not call std::to_string");
		final classRefStringMethod = new HxFunctionDecl("refStringLike", Public, false, [], "String", [
			SVar("next", "", ENew("SelfStringOwner", []), HxPos.unknown()),
			SReturn(EIdent("next"), HxPos.unknown())
		], "");
		final classRefStringLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperMethod(classRefStringMethod, selfStringOwner, selfStringLookup).join("\n");
		assertContains(classRefStringLines, "return __hxhx_type_name(next);",
			"C++ class-like reference stringification should use the target type-name helper instead of std::to_string(shared_ptr)");
		assertTrue(classRefStringLines.indexOf("std::to_string(next)") < 0, "C++ class-like reference stringification should not call std::to_string");
		final vectorItem = new HxClassDecl("VectorItem", false, [], []);
		final vectorProvider = new HxClassDecl("VectorProvider", false, [
			new HxFunctionDecl("items", Public, true, [], "Array<VectorItem>", [SReturn(EArrayDecl([]), HxPos.unknown())], "")
		], []);
		final vectorReturnOwner = new HxClassDecl("VectorReturnOwner", false, [], []);
		final vectorReturnNames = new StringMap<Bool>();
		for (name in ["VectorItem", "VectorProvider", "VectorReturnOwner"])
			vectorReturnNames.set(name, true);
		final vectorReturnClasses = new StringMap<HxClassDecl>();
		vectorReturnClasses.set("VectorItem", vectorItem);
		vectorReturnClasses.set("VectorProvider", vectorProvider);
		vectorReturnClasses.set("VectorReturnOwner", vectorReturnOwner);
		final vectorReturnLookup = {names: vectorReturnNames, byName: vectorReturnClasses};
		final vectorReturnMethod = new HxFunctionDecl("callStackLike", Public, true, [], "Array<VectorItem>",
			[SReturn(ECall(EField(EIdent("VectorProvider"), "items"), []), HxPos.unknown())], "");
		final vectorReturnLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperMethod(vectorReturnMethod, vectorReturnOwner, vectorReturnLookup).join("\n");
		assertContains(vectorReturnLines, "return VectorProvider::items();",
			"C++ vector-valued return expressions should return directly instead of falling through to int casts");
		assertTrue(vectorReturnLines.indexOf("static_cast<int>(VectorProvider::items())") < 0,
			"C++ vector-valued return expressions should not emit static_cast<int>");
		final stackItem = new HxClassDecl("StackItem", false, [], []);
		final nativeTraceProvider = new HxClassDecl("NativeTraceProvider", false, [
			new HxFunctionDecl("toHaxe", Public, true, [], "Array<StackItem>", [SReturn(EArrayDecl([]), HxPos.unknown())], "")
		], []);
		final localCallStack = new HxClassDecl("LocalCallStack", false, [
			new HxFunctionDecl("exceptionStackLike", Public, true, [], "Array<StackItem>", [
				SVar("eStack", "LocalCallStack", ECall(EField(EIdent("NativeTraceProvider"), "toHaxe"), []), HxPos.unknown()),
				SReturn(ECall(EField(EIdent("eStack"), "asArray"), []), HxPos.unknown())
			],
				""),
			new HxFunctionDecl("take", Public, false, [new HxFunctionArg("n", "Int", NoDefault, false, false)], "LocalCallStack",
				[SReturn(ECall(EField(EThis, "slice"), [EInt(0), EIdent("n")]), HxPos.unknown())], ""),
			new HxFunctionDecl("get", Public, false, [new HxFunctionArg("i", "Int", NoDefault, false, false)], "StackItem",
				[SReturn(EArrayAccess(EThis, EIdent("i")), HxPos.unknown())], ""),
			new HxFunctionDecl("len", Public, false, [], "Int", [SReturn(EField(EThis, "length"), HxPos.unknown())], ""),
			new HxFunctionDecl("asArray", Public, false, [], "Array<StackItem>", [SReturn(EThis, HxPos.unknown())], "")
		], [], "", ["__hxhx_abstract", "__hxhx_abstract_underlying=Array<StackItem>"]);
		final abstractNames = new StringMap<Bool>();
		for (name in ["StackItem", "NativeTraceProvider", "LocalCallStack"])
			abstractNames.set(name, true);
		final abstractClasses = new StringMap<HxClassDecl>();
		abstractClasses.set("StackItem", stackItem);
		abstractClasses.set("NativeTraceProvider", nativeTraceProvider);
		abstractClasses.set("LocalCallStack", localCallStack);
		final abstractLookup = {names: abstractNames, byName: abstractClasses};
		final abstractLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(localCallStack, abstractLookup).join("\n");
		assertContains(abstractLines, "std::vector<std::shared_ptr<StackItem>> __values;",
			"C++ array-backed abstract wrappers should store the underlying vector");
		assertContains(abstractLines, "LocalCallStack(std::vector<std::shared_ptr<StackItem>> values) : __values(values) {}",
			"C++ array-backed abstract wrappers should accept the underlying vector without shared_ptr mismatch");
		assertContains(abstractLines, "LocalCallStack eStack = NativeTraceProvider::toHaxe();",
			"C++ locals typed as array-backed abstracts should be value wrappers, not std::shared_ptr<Abstract>");
		assertContains(abstractLines, "return eStack.asArray();", "C++ array-backed abstract locals should call abstract methods through value access");
		assertContains(abstractLines, "LocalCallStack slice(int start, int end) const {",
			"C++ array-backed abstract wrappers should provide forwarded slice support");
		assertContains(abstractLines, "return ((*this)[i]);", "C++ array-backed abstract wrappers should provide operator[] support for array access");
		assertContains(abstractLines, "return static_cast<int>(this->__values.size());",
			"C++ array-backed abstract self length should read the underlying vector size");
		assertTrue(abstractLines.indexOf("std::shared_ptr<LocalCallStack> eStack") < 0,
			"C++ array-backed abstract locals should not be emitted as shared_ptr values");
		final abstractFieldOwner = new HxClassDecl("AbstractFieldOwner", false, [], [new HxFieldDecl("stack", Public, false, "LocalCallStack", null)]);
		abstractNames.set("AbstractFieldOwner", true);
		abstractClasses.set("AbstractFieldOwner", abstractFieldOwner);
		final abstractFieldLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(abstractFieldOwner, abstractLookup).join("\n");
		assertContains(abstractFieldLines, "LocalCallStack stack = LocalCallStack();",
			"C++ fields typed as array-backed abstracts should default to value wrappers instead of int zero");
		final primitiveAbstract = new HxClassDecl("Int32", false, [
			new HxFunctionDecl("negate", Public, false, [], "Int32", [SReturn(EUnop("~", EThis), HxPos.unknown())], ""),
			new HxFunctionDecl("ucompare", Public, true, [
				new HxFunctionArg("a", "Int32", NoDefault, false, false),
				new HxFunctionArg("b", "Int32", NoDefault, false, false)
			], "Int",
				[SReturn(EBinop("-", EIdent("a"), EIdent("b")), HxPos.unknown())], "")
		], [], "", []);
		final primitiveNames = new StringMap<Bool>();
		primitiveNames.set("Int32", true);
		final primitiveClasses = new StringMap<HxClassDecl>();
		primitiveClasses.set("Int32", primitiveAbstract);
		final primitiveLookup = {names: primitiveNames, byName: primitiveClasses};
		final primitiveLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(primitiveAbstract, primitiveLookup).join("\n");
		assertContains(primitiveLines, "static int ucompare(int a, int b) {",
			"C++ primitive-backed abstract helpers should erase abstract argument types to the underlying primitive");
		assertContains(primitiveLines, "return static_cast<int>((a - b));",
			"C++ primitive-backed abstract static helper bodies should operate on primitive values");
		assertTrue(primitiveLines.indexOf("negate(") < 0,
			"C++ primitive-backed abstract helpers should not emit instance wrapper methods that require abstract this semantics");
		assertTrue(primitiveLines.indexOf("std::shared_ptr<Int32>") < 0,
			"C++ primitive-backed abstracts should not leak shared_ptr wrapper types into helper signatures");
		final stringIterator = new HxClassDecl("StringIterator", false, [
			new HxFunctionDecl("new", Public, false, [new HxFunctionArg("s", "String", NoDefault, false, false)], "Void",
				[SExpr(EBinop("=", EField(EThis, "s"), EIdent("s")), HxPos.unknown())], ""),
			new HxFunctionDecl("hasNext", Public, false, [], "", [
				SReturn(EBinop("<", EIdent("offset"), EField(EIdent("s"), "length")), HxPos.unknown())
			], ""),
			new HxFunctionDecl("next", Public, false, [], "", [
				SReturn(ECall(EField(EIdent("StringTools"), "unsafeCodeAt"), [EIdent("s"), EUnop("post++", EIdent("offset"))]), HxPos.unknown())
			], "")
		], [
			new HxFieldDecl("offset", Public, false, "", EInt(0)),
			new HxFieldDecl("s", Public, false, "String", null)
		]);
		final stringKeyValueIterator = new HxClassDecl("StringKeyValueIterator", false, [
			new HxFunctionDecl("next", Public, false, [], "", [
				SReturn(EAnon(["key", "value"], [
					EIdent("offset"),
					ECall(EField(EIdent("StringTools"), "fastCodeAt"), [EIdent("s"), EUnop("post++", EIdent("offset"))])
				]), HxPos.unknown())
			], "")
		], [
			new HxFieldDecl("offset", Public, false, "", EInt(0)),
			new HxFieldDecl("s", Public, false, "String", null)
		]);
		final stringIteratorNames = new StringMap<Bool>();
		for (name in ["StringIterator", "StringKeyValueIterator"])
			stringIteratorNames.set(name, true);
		final stringIteratorClasses = new StringMap<HxClassDecl>();
		stringIteratorClasses.set("StringIterator", stringIterator);
		stringIteratorClasses.set("StringKeyValueIterator", stringKeyValueIterator);
		final stringIteratorLookup = {names: stringIteratorNames, byName: stringIteratorClasses};
		final stringIteratorLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(stringIterator, stringIteratorLookup).join("\n");
		final stringKeyValueIteratorLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(stringKeyValueIterator, stringIteratorLookup)
			.join("\n");
		assertContains(stringIteratorLines, "int offset = 0;", "C++ string iterator offset fields should keep integer defaults");
		assertContains(stringIteratorLines, "bool hasNext() {\n    return (offset < (s.size()));\n  }",
			"C++ string iterator hasNext should repair erased String hints to Bool");
		assertContains(stringIteratorLines, "int next() {\n    return static_cast<int>(static_cast<int>(static_cast<unsigned char>(s[(offset++)])));\n  }",
			"C++ string iterator next should lower StringTools.unsafeCodeAt directly to an int code point");
		assertContains(stringKeyValueIteratorLines, "auto next() {", "C++ string key/value iterator records should return auto, not String");
		assertContains(stringKeyValueIteratorLines,
			"return __hxhx_anon_key_int__value_int_{offset, static_cast<int>(static_cast<unsigned char>(s[(offset++)]))};",
			"C++ string key/value iterator records should infer integer key/value fields");
		assertTrue(stringIteratorLines.indexOf("std::string offset = 0;") < 0, "C++ string iterator offset fields should not default through std::string");
		assertTrue(stringIteratorLines.indexOf("std::to_string(StringTools::unsafeCodeAt") < 0,
			"C++ string iterator code-point calls should not leak incomplete StringTools static calls");
		final stdArray = new HxClassDecl("Array", false, [
			new HxFunctionDecl("map", Public, false, [new HxFunctionArg("f", "String->String", NoDefault, false, false)], "Array<String>", [
				SVar("result", "Array<String>", ECall(EField(EIdent("cpp.NativeArray"), "create"), [EField(EThis, "length")]), HxPos.unknown()),
				SExpr(EBinop("=", EArrayAccess(EIdent("result"), EInt(0)), ECall(EIdent("f"), [EArrayAccess(EThis, EInt(0))])), HxPos.unknown()),
				SForIn("value", EThis, SBlock([], HxPos.unknown()), HxPos.unknown()),
				SReturn(EIdent("result"), HxPos.unknown())
			], ""),
			new HxFunctionDecl("filter", Public, false, [new HxFunctionArg("f", "String->Bool", NoDefault, false, false)], "Array<String>", [
				SReturn(EArrayComprehension("v", EThis, ECall(EIdent("f"), [EIdent("v")]), EIdent("v")), HxPos.unknown())
			], "")
		], [new HxFieldDecl("length", Public, false, "Int", null)]);
		final stdArrayNames = new StringMap<Bool>();
		stdArrayNames.set("Array", true);
		final stdArrayClasses = new StringMap<HxClassDecl>();
		stdArrayClasses.set("Array", stdArray);
		final stdArrayLookup = {names: stdArrayNames, byName: stdArrayClasses};
		final stdArrayLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(stdArray, stdArrayLookup).join("\n");
		assertContains(stdArrayLines, "std::vector<std::string> __values;",
			"C++ std Array helper should own vector-backed storage instead of being an empty fake helper");
		assertContains(stdArrayLines, "std::string& operator[](int index) { return __values[index]; }",
			"C++ std Array helper should expose mutable operator[] for generated Array.map writes/reads");
		assertContains(stdArrayLines, "auto begin() { return __values.begin(); }", "C++ std Array helper should expose begin() for range-for over this");
		assertContains(stdArrayLines, "auto end() { return __values.end(); }", "C++ std Array helper should expose end() for range-for over this");
		assertContains(stdArrayLines, "(result[0]) = f(((*this)[0]));", "C++ std Array helper methods should compile lowered unsafeGet/indexing on this");
		assertContains(stdArrayLines, "for (auto value : (*this)) {", "C++ std Array helper should support generated range-for over this");
		assertContains(stdArrayLines, "std::vector<std::string> __hxhx_comp_out;",
			"C++ std Array helper comprehensions should infer string vector output from the this-iterator binder");
		assertContains(stdArrayLines, "__hxhx_comp_out.push_back(v);", "C++ std Array helper comprehensions should push string binders into string vectors");
		assertTrue(stdArrayLines.indexOf("std::vector<int> __hxhx_comp_out;") < 0,
			"C++ std Array helper comprehensions should not default string binder output to vector<int>");
		final erasedMapiMethod = new HxFunctionDecl("mapiErased", Public, true, [
			new HxFunctionArg("it", "Iterable<String>", NoDefault, false, false),
			new HxFunctionArg("f", "String", NoDefault, false, false)
		], "Array<String>", [
			SVar("i", "Int", EInt(0), HxPos.unknown()),
			SReturn(EArrayComprehension("x", EIdent("it"), null, ECall(EIdent("f"), [EUnop("post++", EIdent("i")), EIdent("x")])), HxPos.unknown())
		], "");
		final erasedMapiLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(erasedMapiMethod, stdArray, stdArrayLookup).join("\n");
		assertContains(erasedMapiLines,
			"static std::vector<std::string> mapiErased(std::vector<std::string> it, std::function<std::string(int, std::string)> f) {",
			"C++ helper rendering should recover erased callable parameter shapes from call usage");
		assertContains(erasedMapiLines, "std::vector<std::string> __hxhx_comp_out;",
			"C++ erased callable recovery should let mapi comprehensions use the callback return type");
		assertTrue(erasedMapiLines.indexOf("std::string f") < 0,
			"C++ helper rendering should not keep erased String callback parameters as std::string when the body calls them");
		final ctorBase = new HxClassDecl("CtorBase", false, [
			new HxFunctionDecl("new", Public, false, [new HxFunctionArg("message", "String", NoDefault, false, false)], "Void", [], "")
		], []);
		final ctorSub = new HxClassDecl("CtorSub", false, [
			new HxFunctionDecl("new", Public, false, [new HxFunctionArg("message", "String", NoDefault, false, false)], "Void",
				[SExpr(ECall(ESuper, [EIdent("message")]), HxPos.unknown())], "")
		], [], "CtorBase");
		final ctorNames = new StringMap<Bool>();
		for (name in ["CtorBase", "CtorSub"])
			ctorNames.set(name, true);
		final ctorClasses = new StringMap<HxClassDecl>();
		ctorClasses.set("CtorBase", ctorBase);
		ctorClasses.set("CtorSub", ctorSub);
		final ctorLookup = {names: ctorNames, byName: ctorClasses};
		final ctorSubLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(ctorSub, ctorLookup).join("\n");
		assertContains(ctorSubLines, "CtorSub(std::string message) : CtorBase(message) {",
			"C++ subclass constructors should lower leading super(...) to a base initializer list");
		assertTrue(ctorSubLines.indexOf("base constructor call omitted") < 0, "C++ leading super(...) should not remain as an omitted body comment");
		final optionalCtorBase = new HxClassDecl("OptionalCtorBase", false, [
			new HxFunctionDecl("new", Public, false, [new HxFunctionArg("message", "String", NoDefault, false, false)], "Void", [], "")
		], []);
		final optionalCtorSub = new HxClassDecl("OptionalCtorSub", false, [
			new HxFunctionDecl("new", Public, false, [new HxFunctionArg("message", "String", NoDefault, true, false)], "Void",
				[SExpr(ECall(ESuper, [EIdent("message")]), HxPos.unknown())], "")
		], [], "OptionalCtorBase");
		final optionalCtorNames = new StringMap<Bool>();
		for (name in ["OptionalCtorBase", "OptionalCtorSub"])
			optionalCtorNames.set(name, true);
		final optionalCtorClasses = new StringMap<HxClassDecl>();
		optionalCtorClasses.set("OptionalCtorBase", optionalCtorBase);
		optionalCtorClasses.set("OptionalCtorSub", optionalCtorSub);
		final optionalCtorLookup = {names: optionalCtorNames, byName: optionalCtorClasses};
		final optionalCtorSubLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(optionalCtorSub, optionalCtorLookup).join("\n");
		assertContains(optionalCtorSubLines, "OptionalCtorSub(std::optional<std::string> message = std::nullopt) : OptionalCtorBase(message.value()) {",
			"C++ constructor scopes should type optional args before rendering super initializer lists");
		final posInfos = new HxClassDecl("PosInfos", false, [], []);
		final posException = new HxClassDecl("PosException", false, [
			new HxFunctionDecl("new", Public, false, [new HxFunctionArg("pos", "PosInfos", NoDefault, true, false)], "Void", [
				SIf(EBinop("==", EIdent("pos"), ENull),
					SExpr(EBinop("=", EIdent("posInfos"),
						EAnon(["fileName", "lineNumber", "className", "methodName"],
							[EString("(unknown)"), EInt(0), EString("(unknown)"), EString("(unknown)")])),
						HxPos.unknown()),
					SExpr(EBinop("=", EIdent("posInfos"), EIdent("pos")), HxPos.unknown()), HxPos.unknown())
			],
				""),
			new HxFunctionDecl("toString", Public, false, [], "String", [SReturn(EField(EIdent("posInfos"), "className"), HxPos.unknown())], "")
		], [new HxFieldDecl("posInfos", Public, false, "PosInfos", null)]);
		final posNames = new StringMap<Bool>();
		for (name in ["PosInfos", "PosException"])
			posNames.set(name, true);
		final posClasses = new StringMap<HxClassDecl>();
		posClasses.set("PosInfos", posInfos);
		posClasses.set("PosException", posException);
		final posLookup = {names: posNames, byName: posClasses};
		final posInfosLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(posInfos, posLookup).join("\n");
		final posExceptionLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(posException, posLookup).join("\n");
		assertContains(posInfosLines, "std::string fileName = std::string();", "C++ PosInfos typedef placeholders should render the stdlib position fields");
		assertContains(posExceptionLines, "std::shared_ptr<PosInfos> pos = nullptr", "C++ optional PosInfos args should stay nullable references");
		assertContains(posExceptionLines,
			"posInfos = std::make_shared<PosInfos>(std::string(\"(unknown)\"), 0, std::string(\"(unknown)\"), std::string(\"(unknown)\"));",
			"C++ assignments from matching position literals should wrap into PosInfos shared pointers");
		assertContains(posExceptionLines, "posInfos = pos;", "C++ PosInfos reference assignments should pass existing pointers through");
		assertContains(posExceptionLines, "return (posInfos->className);", "C++ PosInfos string fields should not be wrapped with std::to_string");
		final genericReturnOwner = new HxClassDecl("GenericReturnOwner", false, [], []);
		final genericReturnNames = new StringMap<Bool>();
		genericReturnNames.set("GenericReturnOwner", true);
		final genericReturnClasses = new StringMap<HxClassDecl>();
		genericReturnClasses.set("GenericReturnOwner", genericReturnOwner);
		final genericReturnLookup = {names: genericReturnNames, byName: genericReturnClasses};
		final genericReturnMethod = new HxFunctionDecl("filterLike", Public, false, [], "", [
			SVar("next", "", ENew("GenericReturnOwner", []), HxPos.unknown()),
			SReturn(EIdent("next"), HxPos.unknown())
		], "");
		final genericReturnLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperMethod(genericReturnMethod, genericReturnOwner, genericReturnLookup).join("\n");
		assertContains(genericReturnLines, "std::shared_ptr<GenericReturnOwner> filterLike() {",
			"C++ helper methods with inferred class return locals should not fall back to std::string");
		assertContains(genericReturnLines, "return next;",
			"C++ helper methods returning inferred class locals should forward the reference instead of stringifying it");
		assertTrue(genericReturnLines.indexOf("std::string filterLike()") < 0,
			"C++ helper methods returning inferred class locals should not declare std::string");
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
		final vectorNullMethod = new HxFunctionDecl("splitLike", Public, false, [], "Array<String>", [SReturn(ENull, HxPos.unknown())], "");
		final vectorNullLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperMethod(vectorNullMethod, exprBodyOwner, exprBodyLookup).join("\n");
		assertContains(vectorNullLines, "std::vector<std::string> splitLike() {\n    return {};\n  }",
			"C++ value-vector returns should default null to an empty vector instead of nullptr");

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
		assertContains(source, "auto suffix = std::string(\"smoke\");", "C++ smoke should emit string local vars as std::string");
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
		assertTrue(source.indexOf("struct BodyOnlyBuffer {") < source.indexOf("struct BodyOnlyUser {"),
			"C++ smoke should emit helper definitions before inline methods that construct/use them in method bodies");
		assertTrue(source.indexOf("struct StaticBodyProvider {") < source.indexOf("struct StaticBodyUser {"),
			"C++ smoke should emit helper definitions before inline static method calls on later classes");
		assertContains(source, "struct __hxhx_anon_value_std__string_key_int_ {",
			"C++ smoke should collect structural anonymous return payloads with identifier values as strings");
		assertContains(source,
			"auto next() {\n    auto val = std::string(current);\n    return __hxhx_anon_value_std__string_key_int_{std::string(val), (idx++)};\n  }",
			"C++ smoke should lower structural anonymous return types through C++ auto instead of stringifying the key field");
		assertContains(source,
			"auto next() {\n    auto val = (head->item);\n    head = (head->next);\n    return __hxhx_anon_value_std__string_key_int_{std::string(val), (idx++)};\n  }",
			"C++ smoke should lower generic key/value iterator structural returns through C++ auto");
		assertContains(source, "return __hxhx_anon_value_std__string_key_int_{std::string((array[current])), (current++)};",
			"C++ smoke should infer anonymous return value fields from array access element types");
		assertTrue(source.indexOf("__hxhx_anon_value_int__key_int_{(array[current])") < 0,
			"C++ smoke should not infer string array accesses as int anonymous return fields");
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
		assertContains(source, "return std::vector<int>(length);", "C++ smoke should lower qualified cpp.NativeArray.create");
		assertContains(source, "auto result = std::vector<std::string>(length);",
			"C++ smoke should use enclosing vector return type for qualified cpp.NativeArray.create locals");
		assertContains(source, "auto seed = std::vector<std::string>{std::string(\"seed\")};",
			"C++ smoke should keep string array element type for NativeArray unsafe access coverage");
		assertContains(source, "(result[0]) = (seed[0]);", "C++ smoke should lower qualified cpp.NativeArray unsafeSet/unsafeGet intrinsics");
		assertTrue(source.indexOf("(cpp.NativeArray).create") < 0, "C++ smoke should not leak qualified cpp.NativeArray.create syntax");
		assertTrue(source.indexOf("(cpp.NativeArray).unsafeSet") < 0, "C++ smoke should not leak qualified cpp.NativeArray.unsafeSet syntax");
		assertTrue(source.indexOf("(cpp.NativeArray).unsafeGet") < 0, "C++ smoke should not leak qualified cpp.NativeArray.unsafeGet syntax");
		assertTrue(source.indexOf("auto result = std::vector<int>(length);") < 0,
			"C++ smoke should not infer Array<String> NativeArray.create locals as vector<int>");
		assertContains(source, "static int and_(int a, int b) {", "C++ smoke should sanitize alternative-token method names");
		assertContains(source, "static int or_(int a, int b) {", "C++ smoke should sanitize alternative-token method names");
		assertContains(source, "static int xor_(int a, int b) {", "C++ smoke should sanitize alternative-token method names");
		assertTrue(source.indexOf("static int and(int a, int b)") < 0, "C++ smoke should not emit unsanitized and method names");
		assertTrue(source.indexOf("static int or(int a, int b)") < 0, "C++ smoke should not emit unsanitized or method names");
		assertTrue(source.indexOf("static int xor(int a, int b)") < 0, "C++ smoke should not emit unsanitized xor method names");
		assertContains(source, "static std::vector<std::string> array(std::vector<std::string> it) {",
			"C++ smoke should lower Iterable<String> arguments to vector values");
		assertContains(source, "static std::vector<std::string> arrayFromNew(std::vector<std::string> it) {",
			"C++ smoke should keep Array<T> return helpers on vector values");
		assertContains(source, "auto a = std::vector<std::string>{};", "C++ smoke should lower new Array() to the function vector return shape");
		assertContains(source, "a.push_back(x);", "C++ smoke should lower Array.push on vector locals to push_back");
		assertContains(source, "return a;", "C++ smoke should return vector-backed Array locals directly");
		assertTrue(source.indexOf("std::make_shared<Array>") < 0, "C++ smoke should not construct std Array values as shared_ptr helper classes");
		assertContains(source, "static std::vector<std::string> mapLike(std::vector<std::string> it, std::function<std::string(std::string)> f) {",
			"C++ smoke should keep function-valued map helpers typed");
		assertContains(source, "__hxhx_comp_out.push_back(f(x));", "C++ smoke should infer comprehension output from local std::function call return types");
		assertContains(source, "static std::vector<std::string> mapiLike(std::vector<std::string> it, std::function<std::string(int, std::string)> f) {",
			"C++ smoke should lower named function-typed mapi helpers to callable C++ signatures");
		assertContains(source, "__hxhx_comp_out.push_back(f((i++), x));",
			"C++ smoke should infer comprehension output from multi-argument local std::function calls");
		assertContains(source, "static std::vector<std::string> flattenLike(std::vector<std::vector<std::string>> it) {",
			"C++ smoke should lower nested Iterable<T> arguments to vector values");
		assertContains(source, "for (auto y : x) {", "C++ smoke should lower nested comprehension for-in markers to nested loops");
		assertContains(source, "__hxhx_comp_out.push_back(y);", "C++ smoke should push nested comprehension yields directly");
		assertTrue(source.indexOf("__hxhx_for_in") < 0, "C++ smoke should not leak internal nested for-in markers into generated source");
		assertContains(source,
			"static std::vector<std::string> flatMap(std::vector<std::string> it, std::function<std::vector<std::string>(std::string)> f) {",
			"C++ smoke should lower Iterable<T> inside function types to vector values");
		assertContains(source, "std::vector<std::string> __hxhx_flat_map_out;",
			"C++ smoke should lower flatten(map(...)) to a direct flatMap vector accumulator");
		assertContains(source, "for (auto __hxhx_flat_map_value : f(__hxhx_flat_map_item)) {",
			"C++ smoke should call the flatMap mapper directly inside the nested loop");
		assertContains(source, "__hxhx_flat_map_out.push_back(__hxhx_flat_map_value);", "C++ smoke should append flattened mapper values directly");
		assertContains(source, "static std::vector<std::string> filter(std::vector<std::string> it, std::function<bool(std::string)> f) {",
			"C++ smoke should infer vector returns from filtered comprehensions");
		assertContains(source, "static std::vector<std::string> filterInferred(std::vector<std::string> it, std::function<bool(std::string)> f) {",
			"C++ smoke should infer omitted return types from filtered comprehensions with scoped loop binders");
		assertTrue(source.indexOf("static std::vector<int> filterInferred") < 0, "C++ smoke should not infer filtered string comprehensions as vector<int>");
		assertTrue(source.indexOf("return std::to_string(([&]() {\n  std::vector<std::string> __hxhx_comp_out;") < 0,
			"C++ smoke should not stringify filtered array comprehensions");
		assertContains(source, "static int count(std::vector<std::string> it, std::optional<std::function<bool(std::string)>> pred = std::nullopt) {",
			"C++ smoke should keep optional Lambda.count predicates typed as optional callables");
		assertContains(source, "return __hxhx_url_encode(s);", "C++ smoke should lower StringTools URL encode native string calls to support helpers");
		assertContains(source, "return __hxhx_url_decode(s);", "C++ smoke should lower StringTools URL decode native string calls to support helpers");
		assertTrue(source.indexOf("std::to_string(__hxhx_url_encode") < 0, "C++ smoke should not stringify URL encode helper results");
		assertContains(source, "__hxhx_split(s, std::string(\"&gt;\"))", "C++ smoke should lower String.split to target support helpers");
		assertContains(source, "__hxhx_join(__hxhx_split(s, std::string(\"&gt;\")), std::string(\">\"))",
			"C++ smoke should lower split/join chains through target support helpers");
		assertContains(source, "__hxhx_last_index_of(s, std::string(start), 0)", "C++ smoke should lower String.lastIndexOf to target support helpers");
		assertContains(source, "auto c = static_cast<int>(static_cast<unsigned char>(s[pos]));",
			"C++ smoke should lower String.charCodeAt to direct code-point reads");
		assertContains(source, "return s.substr(1, 2);", "C++ smoke should preserve std::string substr results without stringifying");
		assertContains(source, "return __hxhx_substring(s, 1, 3);", "C++ smoke should lower Haxe substring to target support helpers");
		assertContains(source, "auto s = std::string(\"\");", "C++ smoke should infer mutable literal string locals as std::string");
		assertContains(source, "__hxhx_char_at(hexChars, (n & 15)) + s", "C++ smoke should lower String.charAt to target support helpers");
		assertContains(source, "return static_cast<int>(static_cast<int>(static_cast<unsigned char>(\"0\"[0])));",
			"C++ smoke should lower String literal .code to a code-point read");
		assertTrue(source.indexOf(".split(") < 0, "C++ smoke should not emit nonexistent std::string split calls");
		assertTrue(source.indexOf(".lastIndexOf(") < 0, "C++ smoke should not emit nonexistent std::string lastIndexOf calls");
		assertTrue(source.indexOf(".charCodeAt(") < 0, "C++ smoke should not emit nonexistent std::string charCodeAt calls");
		assertTrue(source.indexOf(".substring(") < 0, "C++ smoke should not emit nonexistent std::string substring calls");
		assertTrue(source.indexOf("std::to_string(s.substr") < 0, "C++ smoke should not stringify std::string substr results");
		assertContains(source, "auto __hxhx_iter_code = std::make_shared<StringIteratorUnicode>(s);",
			"C++ smoke should bind Haxe iterator protocol objects before looping");
		assertContains(source, "while (__hxhx_iter_code->hasNext()) {", "C++ smoke should lower Haxe iterator protocol loops through hasNext()");
		assertContains(source, "auto code = __hxhx_iter_code->next();", "C++ smoke should lower Haxe iterator protocol loop values through next()");
		assertTrue(source.indexOf("for (auto code : std::make_shared<StringIteratorUnicode>(s))") < 0,
			"C++ smoke should not use C++ range-for over Haxe iterator objects");
		assertContains(source, "if (pred.value()(x)) {", "C++ smoke should unwrap optional callables before invocation");
		assertContains(source, "static bool empty(std::vector<std::string> it) {", "C++ smoke should lower Array<String> arguments to vector values");
		assertContains(source, "return (!(!it.empty()));", "C++ smoke should lower iterator().hasNext() on vectors through empty()");
		assertTrue(source.indexOf("std::shared_ptr<Iterable>") < 0, "C++ smoke should not emit a fake unresolved Iterable runtime class in helper signatures");
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
		assertContains(source, "Child(int value) : Base() {", "C++ smoke should lower bare super constructor calls to base initializer lists");
		assertTrue(source.indexOf("/* base constructor call omitted */") < 0, "C++ leading super constructor calls should not remain as omitted body comments");
		assertContains(source, "auto parent = (*this);", "C++ smoke should lower bare super expressions to the current base-backed object");
		assertContains(source, "__hxhx_json_min_field_from_file(platformsJson)",
			"C++ smoke should lower hxcpp Android platform-min try/catch expressions through target runtime support");
		assertContains(source, "__hxhx_join(words, \",\")", "C++ smoke should lower array join try/catch expressions through target runtime support");
		assertContains(source, "static bool __hxhx_is_type(int, const std::string& type)", "C++ smoke should include Haxe is-expression helper overloads");
		assertContains(source, "static std::string __hxhx_type_name(int)", "C++ smoke should include Haxe type-name helper overloads");
		assertContains(source, "auto __hxhx_null_coalesce(std::nullptr_t, F fallback)", "C++ smoke should include Haxe null-coalescing helper overloads");

		final mathExternDir = Path.join([root, "math-extern-source-only"]);
		final mathExternEmit = BackendRegistry.createForTarget("cpp-native").emit(mathExternProgram(), context(mathExternDir, true, true));
		final mathExternSource = File.getContent(mathExternEmit.entryPath);
		assertContains(mathExternSource, "#include <cmath>", "C++ Math intrinsics should include <cmath>");
		assertContains(mathExternSource, "#include <limits>", "C++ Math constants should include <limits>");
		assertContains(mathExternSource, "std::isnan(std::numeric_limits<double>::quiet_NaN())",
			"C++ Math extern calls should lower directly to target intrinsics");
		assertContains(mathExternSource, "std::isfinite(3.14159265358979323846)",
			"C++ Math extern constants should lower directly to target intrinsic constants");
		assertContains(mathExternSource, "auto cosine = [](double v) { return std::cos(v); };",
			"C++ Math extern method references should lower directly to callable target intrinsics");
		assertTrue(mathExternSource.indexOf("struct Math") < 0, "C++ should not emit upstream Math extern as a fake helper class");
		assertTrue(mathExternSource.indexOf("Math::__init__") < 0, "C++ should not emit upstream Math extern initializers");
		assertTrue(mathExternSource.indexOf("Number[") < 0, "C++ should not leak JS-era Math extern initializer code");

		final vendorListProgram = vendorListProgramWhenAvailable();
		if (vendorListProgram != null) {
			final vendorListDir = Path.join([root, "vendor-list-source-only"]);
			final vendorListEmit = BackendRegistry.createForTarget("cpp-native").emit(vendorListProgram, context(vendorListDir, true, true));
			final vendorListSource = File.getContent(vendorListEmit.entryPath);
			assertContains(vendorListSource,
				"auto next() {\n    auto val = (head->item);\n    head = (head->next);\n    return __hxhx_anon_value_std__string_key_int_{std::string(val), (idx++)};\n  }",
				"C++ smoke should preserve upstream ListKeyValueIterator.next key/value return body");
		}

		final vendorLambdaProgram = vendorLambdaProgramWhenAvailable();
		if (vendorLambdaProgram != null) {
			final vendorLambdaDir = Path.join([root, "vendor-lambda-source-only"]);
			final vendorLambdaEmit = BackendRegistry.createForTarget("cpp-native").emit(vendorLambdaProgram, context(vendorLambdaDir, true, true));
			final vendorLambdaSource = File.getContent(vendorLambdaEmit.entryPath);
			assertContains(vendorLambdaSource,
				"static std::vector<std::string> mapi(std::vector<std::string> it, std::function<std::string(int, std::string)> f) {",
				"C++ smoke should preserve upstream Lambda.mapi callback type shape");
			assertContains(vendorLambdaSource, "__hxhx_comp_out.push_back(f((i++), x));",
				"C++ smoke should keep upstream Lambda.mapi callback invocation callable");
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
