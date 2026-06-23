import backend.BackendContext;
import backend.BackendRegistry;
import backend.GenIrProgram;
import HxExpr;
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

	static function countOccurrences(haystack:String, needle:String):Int {
		var count = 0;
		var offset = 0;
		while (true) {
			final found = haystack.indexOf(needle, offset);
			if (found < 0)
				return count;
			count++;
			offset = found + needle.length;
		}
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

	static function protocolLine(key:String, payload:String):String {
		final escaped = StringTools.replace(StringTools.replace(StringTools.replace(StringTools.replace(payload, "\\", "\\\\"), "\n", "\\n"), "\r", "\\r"),
			"\t", "\\t");
		return "ast " + key + " " + escaped.length + ":" + escaped;
	}

	static function typedSyntheticModule(filePath:String, decl:HxModuleDecl):TypedModule {
		final mainClass = HxModuleDecl.getMainClass(decl);
		final env = new TyModuleEnv(HxModuleDecl.getPackagePath(decl), HxModuleDecl.getImports(decl), new TyClassEnv(HxClassDecl.getName(mainClass), []));
		return new TypedModule(new ParsedModule("", decl, filePath), env);
	}

	static function assertNativeProtocolStructuralArgTypeSplitting():Void {
		final structural = "{ms:Float,seconds:Int,minutes:Int,hours:Int,days:Int}";
		final encoded = [
			"hxhx_frontend_v=2",
			protocolLine("class", "DateToolsLike"),
			"ast static_main 0",
			protocolLine("method", "make|public|1|o|Float|||o:" + structural + "|"),
			"ok"
		].join("\n");
		final decl = ParserStageNativeDecode.decodeNativeProtocol(encoded);
		final cls = HxModuleDecl.getMainClass(decl);
		for (fn in HxClassDecl.getFunctions(cls)) {
			if (HxFunctionDecl.getName(fn) == "make") {
				final args = HxFunctionDecl.getArgs(fn);
				assertTrue(args.length == 1, "native protocol structural arg fixture should decode one arg");
				assertTrue(HxFunctionArg.getTypeHint(args[0]) == structural,
					"native protocol argtypes should split at top-level commas only, preserving structural hints");
				return;
			}
		}
		throw "native protocol structural arg fixture should decode make";
	}

	static function assertNativeProtocolStructuralNullReturnRecovery():Void {
		final structuralNull = "Null<{file:String, pos:Int}>";
		final source = "class CompilerLike { public static function getDisplayPos():" + structuralNull + " { return null; } }";
		final encoded = [
			"hxhx_frontend_v=2",
			protocolLine("class", "CompilerLike"),
			"ast static_main 0",
			protocolLine("method", "getDisplayPos|public|1||Null||||"),
			"ok"
		].join("\n");
		final decl = ParserStageNativeDecode.decodeNativeProtocol(encoded, source);
		final cls = HxModuleDecl.getMainClass(decl);
		for (fn in HxClassDecl.getFunctions(cls)) {
			if (HxFunctionDecl.getName(fn) == "getDisplayPos") {
				assertTrue(HxFunctionDecl.getReturnTypeHint(fn) == structuralNull,
					"native protocol return recovery should preserve source Null<structural> hints instead of stale bare Null");
				return;
			}
		}
		throw "native protocol structural Null return fixture should decode getDisplayPos";
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
			"    var nums = [3, 4];",
			"    var numsIt = nums.iterator();",
			"    Sys.println(Std.string(numsIt.hasNext()));",
			"    Sys.println(Std.string(numsIt.next() + 0));",
			"    Sys.println(Std.string(numsIt.next() + 0));",
			"    Sys.println(Std.string(numsIt.hasNext()));",
			"    Sys.println(Std.string(helper(4)));",
			"    Sys.println(\"q:\" + Assert.q(1.5) + \":\" + Assert.q(true) + \":\" + Assert.q(\"ok\"));",
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
			"    Sys.println(Std.string(mode == Macro));",
			"    var cls:Class<Dynamic> = null;",
			"    Sys.println(Std.string(Misc.isOfType(\"value\", cls)));",
			"    var ignored = Ignore(\"reason\");",
			"    Sys.println(ignored);",
			"    var id = x -> x + 1;",
			"    Sys.println(Std.string(id(6)));",
			"    var macroQuote = macro (\"macro:value\");",
			"    Sys.println(macroQuote);",
			"    var macroExtract = switch (macroQuote.expr) {",
			"      case EParenthesis({ expr: EConst(CString(s)) }): s;",
			"      case _: \"none\";",
			"    };",
			"    Sys.println(macroExtract);",
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
			"class DateToolsLike {",
			"  public static function parse(t:Float) {",
			"    return { ms: t % 1000, seconds: 2, minutes: 3, hours: 4, days: 5 };",
			"  }",
			"  public static function make(o:{",
			"    ms:Float,",
			"    seconds:Int,",
			"    minutes:Int,",
			"    hours:Int,",
			"    days:Int",
			"  }) {",
			"    return o.ms + 1000.0 * (o.seconds + 60.0 * (o.minutes + 60.0 * (o.hours + 24.0 * o.days)));",
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
			"class GenericImplicitNode<T> {",
			"  public var item:T;",
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
			"  public function printItem(item:String):String {",
			"    return item;",
			"  }",
			"  public function mapJoin(items:Array<String>):String {",
			"    return items.map(printItem).join(\", \");",
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
			"  public static function replaceLiteral(s:String):String {",
			"    return StringTools.replace(s, \"na\", \"X\");",
			"  }",
			"  public static function replaceChain(s:String):String {",
			"    return s.replace(\"\\\\\", \"\\\\\\\\\").replace(\"\\n\", \"\\\\n\").replace(\"\\t\", \"\\\\t\");",
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
			"  public static function ltrim(s:String):String {",
			"    return s.substr(0, s.length);",
			"  }",
			"  public static function rtrim(s:String):String {",
			"    return s.substr(0, s.length);",
			"  }",
			"  public static function trim(s:String):String {",
			"    return ltrim(rtrim(s));",
			"  }",
			"  public static function quoteUnixArg(argument:String):String {",
			"    return haxe.SysTools.quoteUnixArg(argument);",
			"  }",
			"  public static function quoteWinArg(argument:String, escapeMetaCharacters:Bool):String {",
			"    return haxe.SysTools.quoteWinArg(argument, escapeMetaCharacters);",
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
			"class CppInputReadLineLike {",
			"  public static function fromBuffer():String {",
			"    var buf = new BodyOnlyBuffer();",
			"    var s;",
			"    try {",
			"      s = buf.toString();",
			"      if (s.charCodeAt(s.length - 1) == 13) {",
			"        s = s.substr(0, -1);",
			"      }",
			"    } catch (e:Dynamic) {",
			"      s = buf.toString();",
			"    }",
			"    return s;",
			"  }",
			"  public static function inferredNoInitInt():Int {",
			"    var x;",
			"    x = 1;",
			"    return x;",
			"  }",
			"}",
			"class CppInt64HelperLike {",
			"  public static function trim(s:String):String {",
			"    return s;",
			"  }",
			"  public static function parseStringLike(sParam:String):Int64 {",
			"    var base = Int64.ofInt(10);",
			"    var current = Int64.ofInt(0);",
			"    var multiplier = Int64.ofInt(1);",
			"    var s = StringTools.trim(sParam);",
			"    if (s.charAt(0) == \"-\") {",
			"      current = Int64.sub(current, multiplier);",
			"      s = s.substring(1, s.length);",
			"    }",
			"    var digitInt = s.charCodeAt(s.length - 1) - \"0\".code;",
			"    current = Int64.add(current, Int64.mul(multiplier, Int64.ofInt(digitInt)));",
			"    if (Int64.isNeg(current)) {",
			"      return Int64.neg(current);",
			"    }",
			"    return current;",
			"  }",
			"  public static function fromFloatLike(f:Float):Int64 {",
			"    var noFractions = f - (f % 1);",
			"    var neg = noFractions < 0;",
			"    var rest = neg ? -noFractions : noFractions;",
			"    var curr = rest % 2;",
			"    return Int64.ofInt(0);",
			"  }",
			"}",
			"class Int64Helper {",
			"  public static function parseString(s:String):Int64 {",
			"    return Int64.ofInt(0);",
			"  }",
			"  public static function fromFloat(f:Float):Int64 {",
			"    return Int64.ofInt(0);",
			"  }",
			"}",
			"class CppInt64StaticUseLike {",
			"  public static function parse(s:String):Int64 {",
			"    return Int64.parseString(s);",
			"  }",
			"  public static function from(f:Float):Int64 {",
			"    return Int64.fromFloat(f);",
			"  }",
			"  public static function quotient(a:Int64, b:Int64):Int64 {",
			"    var result = Int64.divMod(a, b);",
			"    return result.quotient;",
			"  }",
			"  public static function compareSigned(a:Int64, b:Int64):Int {",
			"    return Int64.compare(a, b);",
			"  }",
			"  public static function compareUnsigned(a:Int64, b:Int64):Int {",
			"    return Int64.ucompare(a, b);",
			"  }",
			"}",
			"class StringIteratorUnicode {",
			"  var offset = 0;",
			"  var s:String;",
			"  public static function unicodeIterator(s:String) {",
			"    return new StringIteratorUnicode(s);",
			"  }",
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
			"class StringKeyValueIteratorUnicode {",
			"  var byteOffset = 0;",
			"  var charOffset = 0;",
			"  var s:String;",
			"  public static function unicodeKeyValueIterator(s:String) {",
			"    return new StringKeyValueIteratorUnicode(s);",
			"  }",
			"  public function new(s:String) {",
			"    this.s = s;",
			"  }",
			"  public function hasNext() {",
			"    return byteOffset < s.length;",
			"  }",
			"  public function next() {",
			"    return {key: charOffset++, value: StringTools.unsafeCodeAt(s, byteOffset++)};",
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
			"typedef LikeStatus = {",
			"  var expectedValue:Dynamic;",
			"  var actualValue:Dynamic;",
			"  var error:String;",
			"  var path:String;",
			"  var recursive:Bool;",
			"}",
			"typedef MetadataDescription = {",
			"  final metadata:String;",
			"  final doc:String;",
			"  @:optional final links:Array<String>;",
			"  @:optional final params:Array<String>;",
			"  @:optional final platforms:Array<Platform>;",
			"  @:optional final targets:Array<MetadataTarget>;",
			"}",
			"class JsonParserLike {",
			"  var str:String;",
			"  var pos:Int;",
			"  public static function parse(str:String):Dynamic {",
			"    return new JsonParserLike(str).doParseLike();",
			"  }",
			"  public function new(?str:String) {",
			"    this.str = str;",
			"    this.pos = 0;",
			"  }",
			"  function parseString():String {",
			"    return \"field\";",
			"  }",
			"  function parseRec():Dynamic {",
			"    return {};",
			"  }",
			"  public function doParseLike():Dynamic {",
			"    var result = parseRec();",
			"    return result;",
			"  }",
			"  public function parseObjectLike():Dynamic {",
			"    var obj = {}, field = null, comma:Null<Bool> = null;",
			"    Reflect.setField(obj, field, parseRec());",
			"    field = parseString();",
			"    comma = false;",
			"    return obj;",
			"  }",
			"  public function parseArrayLike():Dynamic {",
			"    var arr = [], comma:Null<Bool> = null;",
			"    arr.push(parseRec());",
			"    comma = true;",
			"    return arr;",
			"  }",
			"  function nextCharLike():Int {",
			"    return 0;",
			"  }",
			"  function invalidCharLike():Void {}",
			"  function parseNumberLike(c:Int):Dynamic {",
			"    return c;",
			"  }",
			"  public function parseStringEscapeLike():String {",
			"    var uc:Int = Std.parseInt(\"0x\" + str.substr(pos, 4));",
			"    return Std.string(uc);",
			"  }",
			"  public function parseRecScopeLike():Dynamic {",
			"    while (true) {",
			"      var c = nextCharLike();",
			"      switch (c) {",
			"        case 123:",
			"          var obj = {}, field = null, comma:Null<Bool> = null;",
			"          while (true) {",
			"            var c = nextCharLike();",
			"            switch (c) {",
			"              case 32:",
			"              case 125:",
			"                if (field != null || comma == false) invalidCharLike();",
			"                return obj;",
			"              case 58:",
			"                if (field == null) invalidCharLike();",
			"                Reflect.setField(obj, field, parseRec());",
			"                field = null;",
			"                comma = true;",
			"              case 44:",
			"                if (comma) comma = false else invalidCharLike();",
			"              case 34:",
			"                if (field != null || comma) invalidCharLike();",
			"                field = parseString();",
			"              default:",
			"                invalidCharLike();",
			"            }",
			"          }",
			"        case 48, 49:",
			"          return parseNumberLike(c);",
			"        default:",
			"          invalidCharLike();",
			"      }",
			"    }",
			"  }",
			"}",
			"class JsonUseStringLike {",
			"  public static function parseAsString(s:String):String {",
			"    return JsonParserLike.parse(s);",
			"  }",
			"}",
			"class JsonPrinterLike {",
			"  var replacer:String->String->String;",
			"  public function new(replacer:String->String->String) {",
			"    this.replacer = replacer;",
			"  }",
			"  function add(s:String):Void {}",
			"  function quote(s:String):Void {}",
			"  function objString(s:String):Void {}",
			"  function classString(s:String):Void {}",
			"  function inferredString(s):Void {",
			"    quote(s);",
			"  }",
			"  function valueLike():Dynamic {",
			"    return {};",
			"  }",
			"  public function write(k:String, v:Dynamic):Void {",
			"    v = valueLike();",
			"    v = replacer(k, v);",
			"    var values:Array<Dynamic> = v;",
			"    for (i in 0...values.length) write(i, values[i]);",
			"    switch (Type.typeof(v)) {",
			"      case TObject:",
			"        objString(v);",
			"      case TInt:",
			"        add(v);",
			"      case TFloat:",
			"        if (Math.isFinite(v)) add(v);",
			"      case TBool:",
			"        add(v);",
			"      case TClass(c):",
			"        if (c == haxe.ds.StringMap) {",
			"          var map:haxe.ds.StringMap<Dynamic> = v;",
			"          var obj = {};",
			"          for (key in map.keys()) Reflect.setField(obj, key, map.get(key));",
			"          objString(obj);",
			"        } else if (c == Date) {",
			"          var date:Date = v;",
			"          quote(date.toString());",
			"        } else {",
			"          classString(v);",
			"        }",
			"      case _:",
			"        inferredString(v);",
			"        quote(v);",
			"    }",
			"  }",
			"}",
			"class NativeStackTraceLike {",
			"  static function callStack():Dynamic {}",
			"  static function exceptionStack():Dynamic {}",
			"  static function toHaxe(nativeStackTrace:String, skip:Null<Int> = 0):Array<String> {",
			"    var out:Array<String> = [];",
			"    return out;",
			"  }",
			"  public static function callStackHaxe():Array<String> {",
			"    return toHaxe(callStack());",
			"  }",
			"  public static function exceptionStackHaxe():Array<String> {",
			"    return toHaxe(exceptionStack(), 1);",
			"  }",
			"}",
			"class Assert {",
			"  public static function q(v:Dynamic):String {",
			"    return Std.string(v);",
			"  }",
			"  public static function sameAs(expected:Dynamic, value:Dynamic, status:LikeStatus, approx:Float):Bool {",
			"    status.expectedValue = expected;",
			"    status.actualValue = value;",
			"    if (!_floatEquals(expected, value, approx)) {",
			"      status.error = \"float mismatch\";",
			"    }",
			"    var path = status.path;",
			"    for (i in 0...2) {",
			"      status.path = path == \"\" ? \"array[\" + i + \"]\" : path + \"[\" + i + \"]\";",
			"    }",
			"    status.error = status.path;",
			"    return status.error == \"\" || status.recursive;",
			"  }",
			"  static function _floatEquals(expected:Float, value:Float, approx:Float):Bool {",
			"    return Math.abs(expected - value) <= approx;",
			"  }",
			"}",
			"class Misc {",
			"  public static function isOfType<T>(v:Dynamic, t:Class<T>):Bool {",
			"    return true;",
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
			"class ReturnIfNode {",
			"  public var left:ReturnIfNode;",
			"  public function new(left:ReturnIfNode) {",
			"    this.left = left;",
			"  }",
			"}",
			"class ReturnIfTreeLike {",
			"  public function new() {}",
			"  public function firstNode(t:ReturnIfNode) {",
			"    return if (t == null) throw \"missing\"; else if (t.left == null) t; else firstNode(t.left);",
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

	static function vendorBalancedTreeProgramWhenAvailable():Null<GenIrProgram> {
		final treePath = "vendor/haxe/std/haxe/ds/BalancedTree.hx";
		if (!FileSystem.exists(treePath))
			return null;
		final treeSource = File.getContent(treePath);
		final mainSource = "class Main { static function main() {} }";
		final typedMain = TyperStage.typeModule(ParserStage.parse(mainSource, "Main.hx"));
		final typedTree = TyperStage.typeModule(ParserStage.parse(treeSource, treePath));
		return MacroStage.expandProgram([typedMain, typedTree], []);
	}

	static function vendorJsonParserProgramWhenAvailable():Null<GenIrProgram> {
		final parserPath = "vendor/haxe/std/haxe/format/JsonParser.hx";
		if (!FileSystem.exists(parserPath))
			return null;
		final parserSource = File.getContent(parserPath);
		final mainSource = "class Main { static function main() {} }";
		final typedMain = TyperStage.typeModule(ParserStage.parse(mainSource, "Main.hx"));
		final typedParser = TyperStage.typeModule(ParserStage.parse(parserSource, parserPath));
		return MacroStage.expandProgram([typedMain, typedParser], []);
	}

	static function stdlibSupportDuplicationProgram():GenIrProgram {
		final src = [
			"class Main {",
			"  static function main() {}",
			"}",
			"class StringMap<V> {",
			"  public function new() {}",
			"  public function get(key:String):V return null;",
			"  public function set(key:String, value:V):Void {}",
			"  public function keys():Dynamic return null;",
			"  public function toString():String return \"[object StringMap]\";",
			"}",
			"class Date {",
			"  public function new() {}",
			"  public function getDay():Int return 0;",
			"  public function toString():String return \"\";",
			"}",
			"class UsesStdlibSupport {",
			"  static function use(v:Dynamic, c:String):Void {",
			"    if (c == haxe.ds.StringMap) {",
			"      var map:haxe.ds.StringMap<Dynamic> = v;",
			"      map.keys();",
			"    } else if (c == Date) {",
			"      var date:Date = v;",
			"      date.toString();",
			"    }",
			"  }",
			"}"
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function vendorExprToolsProgramWhenAvailable():Null<GenIrProgram> {
		final exprToolsPath = "vendor/haxe/std/haxe/macro/ExprTools.hx";
		if (!FileSystem.exists(exprToolsPath))
			return null;
		final exprToolsSource = File.getContent(exprToolsPath);
		final mainSource = "class Main { static function main() {} }";
		final typedMain = TyperStage.typeModule(ParserStage.parse(mainSource, "Main.hx"));
		final typedExprTools = TyperStage.typeModule(ParserStage.parse(exprToolsSource, exprToolsPath));
		return MacroStage.expandProgram([typedMain, typedExprTools], []);
	}

	static function vendorTemplateProgramWhenAvailable():Null<GenIrProgram> {
		final templatePath = "vendor/haxe/std/haxe/Template.hx";
		if (!FileSystem.exists(templatePath))
			return null;
		final templateSource = File.getContent(templatePath);
		final mainSource = "class Main { static function main() {} }";
		final typedMain = TyperStage.typeModule(ParserStage.parse(mainSource, "Main.hx"));
		final typedTemplate = TyperStage.typeModule(ParserStage.parse(templateSource, templatePath));
		return MacroStage.expandProgram([typedMain, typedTemplate], []);
	}

	static function assertVendorBalancedTreeReturnTypesWhenAvailable():Void {
		final treeProgram = vendorBalancedTreeProgramWhenAvailable();
		if (treeProgram == null)
			return;
		final names = new StringMap<Bool>();
		final classes = new StringMap<HxClassDecl>();
		var balancedTree:Null<HxClassDecl> = null;
		for (typed in treeProgram.getTypedModules()) {
			final decl = typed.getParsed().getDecl();
			for (cls in HxModuleDecl.getClasses(decl)) {
				@:privateAccess backend.cpp.CppTargetCore.addClassLookupAliases(HxClassDecl.getName(cls), cls, names, classes);
				if (HxClassDecl.getName(cls) == "BalancedTree")
					balancedTree = cls;
			}
		}
		assertTrue(balancedTree != null, "vendor BalancedTree fixture should expose BalancedTree class");
		for (fn in HxClassDecl.getFunctions(balancedTree)) {
			if (HxFunctionDecl.getName(fn) == "setLoop") {
				final returnType = @:privateAccess backend.cpp.CppTargetCore.cppFunctionReturnType(fn, balancedTree, {names: names, byName: classes});
				assertContains(returnType, "std::shared_ptr<TreeNode",
					"C++ BalancedTree.setLoop should use a known TreeNode return instead of recursive inference");
				return;
			}
		}
		throw "vendor BalancedTree fixture should expose setLoop";
	}

	static function assertVendorJsonParserReturnTypesWhenAvailable():Void {
		final parserProgram = vendorJsonParserProgramWhenAvailable();
		if (parserProgram == null)
			return;
		final names = new StringMap<Bool>();
		final classes = new StringMap<HxClassDecl>();
		var jsonParser:Null<HxClassDecl> = null;
		for (typed in parserProgram.getTypedModules()) {
			final decl = typed.getParsed().getDecl();
			for (cls in HxModuleDecl.getClasses(decl)) {
				@:privateAccess backend.cpp.CppTargetCore.addClassLookupAliases(HxClassDecl.getName(cls), cls, names, classes);
				if (HxClassDecl.getName(cls) == "JsonParser")
					jsonParser = cls;
			}
		}
		assertTrue(jsonParser != null, "vendor JsonParser fixture should expose JsonParser class");
		for (fn in HxClassDecl.getFunctions(jsonParser)) {
			if (HxFunctionDecl.getName(fn) == "doParse") {
				final returnType = @:privateAccess backend.cpp.CppTargetCore.cppFunctionReturnType(fn, jsonParser, {names: names, byName: classes});
				assertContains(returnType, "std::any",
					"C++ JsonParser.doParse should propagate erased Dynamic through parseRec instead of recursive inference");
				return;
			}
		}
		throw "vendor JsonParser fixture should expose doParse";
	}

	static function assertRawSwitchDynamicReturnType():Void {
		final getValueLike = new HxFunctionDecl("getValueLike", Public, true, [new HxFunctionArg("e", "Dynamic", NoDefault, false, false)], "Dynamic", [
			SReturn(ESwitchRaw("switch (e) { case object: {}; case array: []; case _: getValueLike(e); }"), HxPos.unknown())
		], "");
		final owner = new HxClassDecl("ExprToolsLike", false, [getValueLike], []);
		final classes = new StringMap<HxClassDecl>();
		classes.set("ExprToolsLike", owner);
		final names = new StringMap<Bool>();
		names.set("ExprToolsLike", true);
		final returnType = @:privateAccess backend.cpp.CppTargetCore.cppFunctionReturnType(getValueLike, owner, {names: names, byName: classes});
		assertContains(returnType, "std::any",
			"C++ raw switch expressions returned from Dynamic helpers should erase before function-scope inference recurses");
	}

	static function anonCollectScopeProgram():GenIrProgram {
		final capture = new HxFunctionDecl("capture", Public, false, [
			new HxFunctionArg("arg", "{label:String}", NoDefault, false, false),
			new HxFunctionArg("value", "T", NoDefault, false, false)
		], "{label:String,count:Int,value:T}", [
			SVar("local", "{count:Int}", EAnon(["count"], [EInt(1)]), HxPos.unknown()),
			SReturn(EAnon(["label", "count", "value"], [
				EField(EIdent("arg"), "label"),
				EField(EIdent("local"), "count"),
				EIdent("value")
			]), HxPos.unknown())
		], "", ["__hxhx_fn_type_params=T"]);
		final main = new HxClassDecl("Main", true, [new HxFunctionDecl("main", Public, true, [], "Void", [], "")], []);
		final owner = new HxClassDecl("AnonCollectScope", false, [capture], []);
		final decl = new HxModuleDecl("", [], main, [main, owner], false, false);
		return new GenIrProgram([typedSyntheticModule("AnonCollectScope.hx", decl)], false);
	}

	static function assertCppAnonCollectUsesLightweightFunctionScope():Void {
		final program = anonCollectScopeProgram();
		final lookup = @:privateAccess backend.cpp.CppTargetCore.collectClassLookup(program);
		final structs = @:privateAccess backend.cpp.CppTargetCore.collectAnonStructs(program, lookup);
		final names = [for (struct in structs) struct.name].join("\n");
		assertContains(names, "__hxhx_anon_label_std__string", "C++ anonymous collection should preserve structural argument hints");
		assertContains(names, "__hxhx_anon_count_int", "C++ anonymous collection should preserve local structural variable hints");
		assertContains(names, "__hxhx_anon_label_std__string_count_int__value_std__string",
			"C++ anonymous collection should preserve structural return hints while using function type-parameter scope");
	}

	static function assertVendorExprToolsReturnTypesWhenAvailable():Void {
		final exprToolsProgram = vendorExprToolsProgramWhenAvailable();
		if (exprToolsProgram == null)
			return;
		final names = new StringMap<Bool>();
		final classes = new StringMap<HxClassDecl>();
		var exprTools:Null<HxClassDecl> = null;
		for (typed in exprToolsProgram.getTypedModules()) {
			final decl = typed.getParsed().getDecl();
			for (cls in HxModuleDecl.getClasses(decl)) {
				@:privateAccess backend.cpp.CppTargetCore.addClassLookupAliases(HxClassDecl.getName(cls), cls, names, classes);
				if (HxClassDecl.getName(cls) == "ExprTools")
					exprTools = cls;
			}
		}
		assertTrue(exprTools != null, "vendor ExprTools fixture should expose ExprTools class");
		for (fn in HxClassDecl.getFunctions(exprTools)) {
			if (HxFunctionDecl.getName(fn) == "getValue") {
				final returnType = @:privateAccess backend.cpp.CppTargetCore.cppFunctionReturnType(fn, exprTools, {names: names, byName: classes});
				assertContains(returnType, "std::any", "C++ ExprTools.getValue should erase raw switch Dynamic returns before recursive inference");
				return;
			}
		}
		throw "vendor ExprTools fixture should expose getValue";
	}

	static function assertVendorTemplateReturnTypesWhenAvailable():Void {
		final templateProgram = vendorTemplateProgramWhenAvailable();
		if (templateProgram == null)
			return;
		final names = new StringMap<Bool>();
		final classes = new StringMap<HxClassDecl>();
		var template:Null<HxClassDecl> = null;
		for (typed in templateProgram.getTypedModules()) {
			final decl = typed.getParsed().getDecl();
			for (cls in HxModuleDecl.getClasses(decl)) {
				@:privateAccess backend.cpp.CppTargetCore.addClassLookupAliases(HxClassDecl.getName(cls), cls, names, classes);
				if (HxClassDecl.getName(cls) == "Template")
					template = cls;
			}
		}
		assertTrue(template != null, "vendor Template fixture should expose Template class");
		final expected = [
			"parse" => "std::shared_ptr<TemplateExpr>",
			"parseBlock" => "std::shared_ptr<TemplateExpr>",
			"parseTokens" => "std::shared_ptr<List",
			"parseExpr" => "std::function"
		];
		final seen = new StringMap<Bool>();
		for (fn in HxClassDecl.getFunctions(template)) {
			final name = HxFunctionDecl.getName(fn);
			if (expected.exists(name)) {
				final returnType = @:privateAccess backend.cpp.CppTargetCore.cppFunctionReturnType(fn, template, {names: names, byName: classes});
				assertContains(returnType, expected.get(name),
					"C++ Template." + name + " should use a known return fact instead of recursive helper inference");
				seen.set(name, true);
			}
		}
		for (name in expected.keys())
			assertTrue(seen.exists(name), "vendor Template fixture should expose " + name);
	}

	static function missingIMapProgram():GenIrProgram {
		final src = [
			"class UsesMissingIMap {",
			"  var map:IMap<String,String>;",
			"  var keys:Iterator<String>;",
			"  public function new(map:IMap<String,String>) {",
			"    this.map = map;",
			"    this.keys = map.keys();",
			"  }",
			"  public function keys():Iterator<String> {",
			"    return map.keys();",
			"  }",
			"  public function next() {",
			"    var key = keys.next();",
			"    return { value: map.get(key), key: key };",
			"  }",
			"}",
			"class Main {",
			"  static function main() {}",
			"}"
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function mapKeyValueIteratorProgram():GenIrProgram {
		final src = [
			"interface IMap<K,V> {",
			"  public function get(key:K):Null<V>;",
			"  public function keys():Iterator<K>;",
			"}",
			"class MapKeyValueIterator<K,V> {",
			"  var map:IMap<K,V>;",
			"  var keys:Iterator<K>;",
			"  public function new(map:IMap<K,V>) {",
			"    this.map = map;",
			"    this.keys = map.keys();",
			"  }",
			"  public function next() {",
			"    var key = keys.next();",
			"    return { value: map.get(key), key: key };",
			"  }",
			"}",
			"class Main {",
			"  static function main() {}",
			"}"
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function macroRefTypeProgram():GenIrProgram {
		final src = [
			"typedef Ref<T> = {",
			"  public function get():T;",
			"  public function toString():String;",
			"}",
			"typedef BaseType = {",
			"  var name:String;",
			"}",
			"typedef MacroClassInfo = BaseType & {",
			"  var final_type:Ref<ClassType>;",
			"  var fields:Ref<Array<ClassType>>;",
			"}",
			"enum ModuleType {",
			"  TClassDecl(c:Ref<ClassType>);",
			"}",
			"class ClassType {",
			"  public function new() {}",
			"}",
			"class MacroTypeUse {",
			"  public static function getLocalClass():Ref<ClassType> {",
			"    return null;",
			"  }",
			"  public static function getLocalUsing():Array<Ref<ClassType>> {",
			"    return [];",
			"  }",
			"  public static function typeAndStoreExpr():{final type:Ref<ClassType>; final expr:String;} {",
			"    return null;",
			"  }",
			"}",
			"class Main {",
			"  static function main() {}",
			"}"
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function macroCompilerNullSurfaceProgram():GenIrProgram {
		final pos = HxPos.unknown();
		final mainClass = new HxClassDecl("Main", true, [new HxFunctionDecl("main", Public, true, [], "Void", [], "")]);
		final mainDecl = new HxModuleDecl("", [], mainClass, [mainClass], false, false);
		final nullClass = new HxClassDecl("Null", false, []);
		final positionClass = new HxClassDecl("Position", false, [new HxFunctionDecl("new", Public, false, [], "Void", [], "")]);
		final baseTypeClass = new HxClassDecl("BaseType", false, []);
		final nullSafetyModeClass = new HxClassDecl("NullSafetyMode", false, []);
		final includePositionClass = new HxClassDecl("IncludePosition", false, []);
		final metadataDescriptionClass = new HxClassDecl("MetadataDescription", false, []);
		final defineDescriptionClass = new HxClassDecl("DefineDescription", false, []);
		final jsGenApiClass = new HxClassDecl("JSGenApi", false, []);
		final compilerClass = new HxClassDecl("Compiler", false, [
			new HxFunctionDecl("getDisplayPos", Public, true, [], "Null<Position>", [
				SReturn(ECall(EIdent("callMacroApi"), [EString("get_display_pos"), EInt(0)]), pos)
			], ""),
			new HxFunctionDecl("getMalformedBareNull", Public, true, [], "Null", [
				SReturn(ECall(EIdent("callMacroApi"), [EString("get_display_pos"), EInt(0)]), pos)
			], ""),
			new HxFunctionDecl("getDecodedStaleNullPointer", Public, true, [], "std::shared_ptr<Null>", [
				SReturn(ECall(EIdent("callMacroApi"), [EString("get_display_pos"), EInt(0)]), pos)
			],
				""),
			new HxFunctionDecl("getDefine", Public, true, [new HxFunctionArg("key", "String", NoDefault, false, false)], "__HxMacroExpr",
				[SReturn(EMacroExpr(EString("defined"), []), pos)], ""),
			new HxFunctionDecl("include", Public, true, [
				new HxFunctionArg("pack", "String", NoDefault, false, false),
				new HxFunctionArg("rec", "Bool", Default(EBool(true)), true, false),
				new HxFunctionArg("ignore", "Array<String>", Default(ENull), true, false),
				new HxFunctionArg("classPaths", "Array<String>", Default(ENull), true, false),
				new HxFunctionArg("strict", "Bool", Default(EBool(false)), true, false)
			], "Void", [
				SVar("include", "", ELambda(["pack"], ECall(EIdent("include"), [EIdent("pack")])), pos)
			], ""),
			new HxFunctionDecl("exclude", Public, true, [
				new HxFunctionArg("pack", "String", NoDefault, false, false),
				new HxFunctionArg("rec", "Bool", Default(EBool(true)), true, false)
			], "Void", [
				SExpr(ECall(EField(EIdent("Context"), "onGenerate"),
					[
						ELambda(["types"], ECall(EIdent("__hxhx_for_in"), [EIdent("types"), ELambda(["t"], ENull), ENull]))
					]),
					pos)
			],
				""),
			new HxFunctionDecl("excludeFile", Public, true, [new HxFunctionArg("fileName", "String", NoDefault, false, false)], "Void",
				[SVar("classes", "", ENew("StringMap", []), pos)], ""),
			new HxFunctionDecl("excludeBaseType", Public, true, [new HxFunctionArg("baseType", "BaseType", NoDefault, false, false)], "Void", [
				SExpr(ECall(EField(EField(EIdent("baseType"), "meta"), "add"), [EString(":hxGen")]), pos)
			], ""),
			new HxFunctionDecl("patchTypes", Public, true, [new HxFunctionArg("file", "String", NoDefault, false, false)], "Void", [
				SVar("rp", "Array<String>", EArrayDecl([EString("field"), EString("type")]), pos),
				SVar("r", "String", ECall(EField(EIdent("rp"), "shift"), []), pos)
			], ""),
			new HxFunctionDecl("keep", Public, true, [
				new HxFunctionArg("path", "String", Default(ENull), true, false),
				new HxFunctionArg("paths", "Array<String>", Default(ENull), true, false),
				new HxFunctionArg("recursive", "Bool", Default(EBool(true)), true, false)
			], "Void",
				[SExpr(ECall(EField(EIdent("paths"), "push"), [EIdent("path")]), pos)], ""),
			new HxFunctionDecl("nullSafety", Public, true, [
				new HxFunctionArg("path", "String", NoDefault, false, false),
				new HxFunctionArg("mode", "NullSafetyMode", Default(ENull), true, false),
				new HxFunctionArg("recursive", "Bool", Default(EBool(true)), true, false)
			], "Void", [
				SExpr(ECall(EIdent("addGlobalMetadata"), [EIdent("path"), EString("@:nullSafety"), EIdent("recursive")]), pos)
			], ""),
			new HxFunctionDecl("addGlobalMetadata", Public, true, [
				new HxFunctionArg("pathFilter", "String", NoDefault, false, false),
				new HxFunctionArg("meta", "String", NoDefault, false, false),
				new HxFunctionArg("recursive", "Bool", Default(EBool(true)), true, false),
				new HxFunctionArg("toTypes", "Bool", Default(EBool(true)), true, false),
				new HxFunctionArg("toFields", "Bool", Default(EBool(false)), true, false)
			], "Void", [
				SExpr(ECall(EIdent("load"), [EString("add_global_metadata_impl"), EInt(5)]), pos)
			], ""),
			new HxFunctionDecl("registerMetadataDescriptionFile", Public, true, [
				new HxFunctionArg("path", "String", NoDefault, false, false),
				new HxFunctionArg("source", "String", Default(ENull), true, false)
			], "Void", [
				SVar("content", "Array<MetadataDescription>", ECall(EField(EIdent("Json"), "parse"), [EIdent("path")]), pos)
			], ""),
			new HxFunctionDecl("registerDefinesDescriptionFile", Public, true, [
				new HxFunctionArg("path", "String", NoDefault, false, false),
				new HxFunctionArg("source", "String", Default(ENull), true, false)
			], "Void", [
				SVar("content", "Array<DefineDescription>", ECall(EField(EIdent("Json"), "parse"), [EIdent("path")]), pos)
			], ""),
			new HxFunctionDecl("registerCustomMetadata", Public, true, [
				new HxFunctionArg("meta", "MetadataDescription", NoDefault, false, false),
				new HxFunctionArg("source", "String", Default(ENull), true, false)
			],
				"Void", [SExpr(ECall(EIdent("load"), [EString("register_metadata_impl"), EInt(2)]), pos)], ""),
			new HxFunctionDecl("registerCustomDefine", Public, true, [
				new HxFunctionArg("define", "DefineDescription", NoDefault, false, false),
				new HxFunctionArg("source", "String", Default(ENull), true, false)
			],
				"Void", [SExpr(ECall(EIdent("load"), [EString("register_define_impl"), EInt(2)]), pos)], ""),
			new HxFunctionDecl("setCustomJSGenerator", Public, true, [new HxFunctionArg("callb", "JSGenApi->Void", NoDefault, false, false)], "Void",
				[SExpr(ECall(EIdent("load"), [EString("set_custom_js_generator"), EInt(1)]), pos)], ""),
			new HxFunctionDecl("load", Public, true, [
				new HxFunctionArg("f", "String", NoDefault, false, false),
				new HxFunctionArg("nargs", "", NoDefault, false, false)
			], "Dynamic", [
				SReturn(ECall(EIdent("__bad_untyped_callable"), [EIdent("f"), EIdent("nargs")]), pos)
			],
				""),
			new HxFunctionDecl("flushDiskCache", Public, true, [], "Void", [SExpr(ECall(EIdent("load"), [EString("flush_disk_cache"), EInt(0)]), pos)], ""),
			new HxFunctionDecl("includeFile", Public, true, [
				new HxFunctionArg("file", "String", NoDefault, false, false),
				new HxFunctionArg("position", "IncludePosition", Default(ENull), true, false)
			], "String",
				[SReturn(ECall(EField(EIdent("position"), "toLowerCase"), []), pos)], "")
		]);
		final compilerDecl = new HxModuleDecl("haxe.macro", [], compilerClass, [
			nullClass,
			positionClass,
			baseTypeClass,
			nullSafetyModeClass,
			includePositionClass,
			metadataDescriptionClass,
			defineDescriptionClass,
			jsGenApiClass,
			compilerClass
		], false, false);
		return MacroStage.expandProgram([
			typedSyntheticModule("Main.hx", mainDecl),
			typedSyntheticModule("std/haxe/macro/Compiler.hx", compilerDecl)
		], []);
	}

	static function enumCarrierNameCollisionProgram():GenIrProgram {
		final src = [
			"enum Constant {",
			"  CIdent(name:String);",
			"}",
			"enum Binop {",
			"  OpAdd;",
			"}",
			"enum Expr {",
			"  EConst(c:Constant);",
			"  EBinop(op:Binop, e1:Expr, e2:Expr);",
			"}",
			"class Main {",
			"  static function main() {}",
			"}"
		].join("\n");
		final parsed = ParserStage.parse(src, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function enumConstructorCarrierCollisionProgram():GenIrProgram {
		final src = [
			"class Main { static function main() {} }",
			"class TVar {",
			"  public function new() {}",
			"}",
			"class TypedExpr {",
			"  public function new() {}",
			"}",
			"enum TypedExprDef {",
			"  TVar(v:TVar);",
			"  TFor(v:TVar, e1:TypedExpr, e2:TypedExpr);",
			"}"
		].join("\n");
		final parsed = ParserStage.parse(src, "TypedExprDefShape.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function contextLoadCallableProgram():GenIrProgram {
		final src = [
			"class Message {",
			"  public function new() {}",
			"}",
			"class Position {",
			"  public function new() {}",
			"}",
			"class Type {",
			"  public function new() {}",
			"}",
			"class Context {",
			"  static function load(name:String, nargs:Int):Dynamic {",
			"    return null;",
			"  }",
			"  public static function error(msg:String, pos:Position, depth:Int):String {",
			"    return load(\"error\", 2)(msg, pos, depth);",
			"  }",
			"  public static function reportError(msg:String, pos:Position, depth:Int):Void {",
			"    load(\"report_error\", 2)(msg, pos, depth);",
			"  }",
			"  public static function getMessages():Array<Message> {",
			"    return load(\"get_messages\", 0);",
			"  }",
			"  public static function initMacrosDone():Bool {",
			"    return load(\"init_macros_done\", 0);",
			"  }",
			"  public static function localType():Type {",
			"    var l:Type = load(\"get_local_type\", 0);",
			"    return l;",
			"  }",
			"}",
			"class Main {",
			"  static function main() {}",
			"}"
		].join("\n");
		final parsed = ParserStage.parse(src, "ContextLoadCallableShape.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function switchExpectedRefProgram():GenIrProgram {
		final src = [
			"class ClassType {",
			"  public function new() {}",
			"}",
			"class Ref<T> {",
			"  public var value:T;",
			"  public function new(value:T) {",
			"    this.value = value;",
			"  }",
			"}",
			"enum LocalType {",
			"  TInst(c:Ref<ClassType>);",
			"  TOther;",
			"}",
			"class Context {",
			"  public static function getLocalClass(l:LocalType):Ref<ClassType> {",
			"    return switch (l) {",
			"      case TInst(c): c;",
			"      case _: null;",
			"    }",
			"  }",
			"}",
			"class Main {",
			"  static function main() {}",
			"}"
		].join("\n");
		final parsed = ParserStage.parse(src, "SwitchExpectedRefShape.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function macroAbstractOperatorShapeProgram():GenIrProgram {
		final src = [
			"class Main { static function main() {} }",
			"enum Binop {",
			"  OpAdd;",
			"}",
			"enum Unop {",
			"  OpIncrement;",
			"}",
			"class ClassField {",
			"  public function new() {}",
			"}",
			"typedef AbstractType = {",
			"  var binops:Array<{op:Binop, field:ClassField}>;",
			"  var unops:Array<{op:Unop, postFix:Bool, field:ClassField}>;",
			"}",
			"class AbstractTypeUser {",
			"  public static function emptyBinops():Array<{op:Binop, field:ClassField}> {",
			"    return [];",
			"  }",
			"}"
		].join("\n");
		final parsed = ParserStage.parse(src, "MacroAbstractOperatorShape.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function mainLoopRuntimeProgram():GenIrProgram {
		final src = [
			"class Lock {",
			"  public function new() {}",
			"  public function acquire():Void {}",
			"  public function wait(?timeout:Float):Bool return true;",
			"  public function release():Void {}",
			"}",
			"class Mutex {",
			"  public function new() {}",
			"  public function acquire():Void {}",
			"  public function tryAcquire():Bool return true;",
			"  public function release():Void {}",
			"}",
			"class Timer {",
			"  public static function stamp():Float return 0.0;",
			"}",
			"class MainEvent {",
			"  public var f:Void->Void;",
			"  public var prev:MainEvent;",
			"  public var next:MainEvent;",
			"  public var nextRun:Float;",
			"  public var priority:Int;",
			"  public function new(f:Void->Void, ?priority:Int = 0) {",
			"    this.f = f;",
			"    this.priority = priority;",
			"  }",
			"  public function delay(?t:Float):Void {",
			"    nextRun = t == null ? Math.NEGATIVE_INFINITY : Timer.stamp() + t;",
			"  }",
			"  public function stop():Void {",
			"    if (prev != null) prev.next = next;",
			"    if (next != null) next.prev = prev;",
			"    if (MainLoop.pending == this) MainLoop.pending = next;",
			"  }",
			"}",
			"class MainLoop {",
			"  public static var pending:MainEvent;",
			"  public static function add(f:Void->Void, ?priority:Int = 0):MainEvent {",
			"    var event = new MainEvent(f, priority);",
			"    pending = event;",
			"    return event;",
			"  }",
			"  public static function hasEvents():Bool return pending != null;",
			"  public static function sortEvents():Void {",
			"    var p = pending;",
			"    var q = p.next;",
			"    if (q != null && p.priority > q.priority) pending = q;",
			"  }",
			"  public static function tick():Float {",
			"    sortEvents();",
			"    return Timer.stamp();",
			"  }",
			"}",
			"class EntryPoint {",
			"  static var sleepLock:Lock = new Lock();",
			"  static var mutex:Mutex = new Mutex();",
			"  static var threadCount:Int = 0;",
			"  static var pending:Array<Void->Void> = [];",
			"  public static function wakeup():Void sleepLock.release();",
			"  public static function runInMainThread(f:Void->Void):Void {",
			"    mutex.acquire();",
			"    pending.push(f);",
			"    mutex.release();",
			"    wakeup();",
			"  }",
			"  public static function processEvents():Float {",
			"    mutex.acquire();",
			"    var f = pending.shift();",
			"    mutex.release();",
			"    f();",
			"    return MainLoop.tick();",
			"  }",
			"}",
			"class Main {",
			"  static function main() {",
			"    EntryPoint.runInMainThread(() -> {});",
			"    var event = MainLoop.add(() -> {}, 1);",
			"    event.delay(0.0);",
			"    event.stop();",
			"    EntryPoint.processEvents();",
			"  }",
			"}"
		].join("\n");
		final parsed = ParserStage.parse(src, "MainLoopRuntime.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function vendorReadOnlyArrayProgramWhenAvailable():Null<GenIrProgram> {
		final readOnlyArrayPath = "vendor/haxe/std/haxe/ds/ReadOnlyArray.hx";
		if (!FileSystem.exists(readOnlyArrayPath))
			return null;
		final readOnlyArraySource = File.getContent(readOnlyArrayPath);
		final mainSource = "class Main { static function main() {} }";
		final typedMain = TyperStage.typeModule(ParserStage.parse(mainSource, "Main.hx"));
		final typedReadOnlyArray = TyperStage.typeModule(ParserStage.parse(readOnlyArraySource, readOnlyArrayPath));
		return MacroStage.expandProgram([typedMain, typedReadOnlyArray], []);
	}

	static function vendorVectorProgramWhenAvailable():Null<GenIrProgram> {
		final vectorPath = "vendor/haxe/std/haxe/ds/Vector.hx";
		if (!FileSystem.exists(vectorPath))
			return null;
		final vectorSource = File.getContent(vectorPath);
		final mainSource = "class Main { static function main() {} }";
		final typedMain = TyperStage.typeModule(ParserStage.parse(mainSource, "Main.hx"));
		final typedVector = TyperStage.typeModule(ParserStage.parse(vectorSource, vectorPath));
		return MacroStage.expandProgram([typedMain, typedVector], []);
	}

	static function vendorNativeArrayProgramWhenAvailable():Null<GenIrProgram> {
		final nativeArrayPath = "vendor/haxe/std/cpp/NativeArray.hx";
		if (!FileSystem.exists(nativeArrayPath))
			return null;
		final nativeArraySource = File.getContent(nativeArrayPath);
		final mainSource = "class Main { static function main() {} }";
		final typedMain = TyperStage.typeModule(ParserStage.parse(mainSource, "Main.hx"));
		final typedNativeArray = TyperStage.typeModule(ParserStage.parse(nativeArraySource, nativeArrayPath));
		return MacroStage.expandProgram([typedMain, typedNativeArray], []);
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
		assertNativeProtocolStructuralArgTypeSplitting();
		assertNativeProtocolStructuralNullReturnRecovery();
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
		assertTrue(@:privateAccess ParserStage.sourceStructuralTypeHintIsMoreSpecific("String", "{ ms:Float, seconds:Int }"),
			"parser enrichment should prefer scanned structural source hints over erased native String argument hints");
		assertTrue(@:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("Math"), "isNaN"),
				[EField(EIdent("Math"), "NaN")])) == "std::isnan(std::numeric_limits<double>::quiet_NaN())",
			"C++ Math.isNaN should lower as a target intrinsic instead of a generated helper method");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("Math"), "round"),
			[EFloat(1.5)])) == "static_cast<int>(std::floor((1.5) + 0.5))",
			"C++ Math.round should preserve Haxe's floor(x + 0.5) semantics");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.renderExpr(EField(EIdent("Math"), "cos")) == "[](double v) { return std::cos(v); }",
			"C++ Math method references should lower to callable target intrinsics");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.renderExpr(EField(EIdent("Error"), "OutsideBounds")) == "std::string(\"OutsideBounds\")",
			"C++ Error enum-like fields should lower to tag strings instead of invalid dotted values");
		assertCppAnonCollectUsesLightweightFunctionScope();
		final reflectCompareExpr = @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("Reflect"), "compare"), [EString("a"), EString("b")]));
		assertContains(reflectCompareExpr, "auto __hxhx_cmp_left = std::string(\"a\");",
			"C++ Reflect.compare string literals should compare std::string values instead of raw C string addresses");
		assertContains(reflectCompareExpr, "return __hxhx_compare(__hxhx_cmp_left, __hxhx_cmp_right);",
			"C++ Reflect.compare should lower to a target-owned numeric comparison expression");
		assertTrue(reflectCompareExpr.indexOf("Reflect::compare") < 0, "C++ Reflect.compare should not emit an undeclared generated static helper call");
		final reflectCallMethodExpr = @:privateAccess backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("Reflect"), "callMethod"), [
			EIdent("target"),
			ECall(EField(EIdent("Reflect"), "field"), [EIdent("target"), EIdent("name")]),
			EArrayDecl([])
		]));
		assertContains(reflectCallMethodExpr, "__hxhx_reflect_call_method(target, __hxhx_reflect_field(target, __hxhx_stringify(name))",
			"C++ Reflect.callMethod with Reflect.field should lower through target-owned erased helpers");
		assertTrue(reflectCallMethodExpr.indexOf("Reflect::callMethod") < 0,
			"C++ Reflect.callMethod should not force generated helper signatures while Full1 reflection is still erased");
		assertTrue(reflectCallMethodExpr.indexOf("Reflect::field") < 0,
			"C++ Reflect.field should not render as a generated helper returning a string where callMethod expects a callable");
		final reflectIsFunctionExpr = @:privateAccess backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("Reflect"), "isFunction"), [
			ECall(EField(EIdent("Reflect"), "field"), [EIdent("value"), EString("iterator")])
		]));
		assertTrue(reflectIsFunctionExpr == "__hxhx_reflect_is_function(__hxhx_reflect_field(value, std::string(\"iterator\")))",
			"C++ Reflect.isFunction should accept erased Reflect.field results through target-owned support");
		assertTrue(reflectIsFunctionExpr.indexOf("Reflect::isFunction") < 0,
			"C++ Reflect.isFunction should not require the generated string-only helper for erased field values");
		assertRawSwitchDynamicReturnType();
		final fixtureDecl = new HxClassDecl("TestFixture", false, [], [
			new HxFieldDecl("target", Public, false, "String", null),
			new HxFieldDecl("method", Public, false, "String", null)
		]);
		final handlerDecl = new HxClassDecl("TestHandler", false, [], [new HxFieldDecl("fixture", Public, false, "TestFixture", null)]);
		final handlerClasses = new StringMap<HxClassDecl>();
		handlerClasses.set("TestFixture", fixtureDecl);
		handlerClasses.set("TestHandler", handlerDecl);
		final handlerScope = @:privateAccess backend.cpp.CppTargetCore.renderScope(handlerDecl, {names: new StringMap<Bool>(), byName: handlerClasses},
			"String");
		handlerScope.localTypes.set("handler", "std::shared_ptr<TestHandler>");
		final nestedReferenceFieldExpr = @:privateAccess backend.cpp.CppTargetCore.renderExpr(EField(EField(EIdent("handler"), "fixture"), "target"),
			handlerScope);
		assertContains(nestedReferenceFieldExpr, "(handler->fixture)->target",
			"C++ nested field access should use -> after an intermediate std::shared_ptr field");
		assertTrue(nestedReferenceFieldExpr.indexOf("(handler->fixture).target") < 0,
			"C++ nested field access should not use dot access on std::shared_ptr fields");
		final genericHandlerScope = @:privateAccess backend.cpp.CppTargetCore.renderScope(handlerDecl, {names: new StringMap<Bool>(), byName: handlerClasses},
			"String");
		genericHandlerScope.localTypes.set("handler", "std::shared_ptr<TestHandler<std::string>>");
		final genericNestedReferenceFieldExpr = @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(EField(EField(EIdent("handler"), "fixture"), "target"), genericHandlerScope);
		assertContains(genericNestedReferenceFieldExpr, "(handler->fixture)->target",
			"C++ nested field access should preserve intermediate reference fields on generic class receivers");
		assertTrue(genericNestedReferenceFieldExpr.indexOf("(handler->fixture).target") < 0,
			"C++ nested field access should not lose field type information for generic class receivers");
		final reflectCompareOwner = new HxClassDecl("ReflectCompareOwner", false, [], []);
		final reflectCompareMethod = new HxFunctionDecl("compareLike", Public, false, [
			new HxFunctionArg("left", "String", NoDefault, false, false),
			new HxFunctionArg("right", "String", NoDefault, false, false)
		], "", [
			SReturn(ECall(EField(EIdent("Reflect"), "compare"), [EIdent("left"), EIdent("right")]), HxPos.unknown())
		], "");
		final reflectCompareLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperMethod(reflectCompareMethod, reflectCompareOwner,
				{names: new StringMap<Bool>(), byName: new StringMap<HxClassDecl>()})
				.join("\n");
		assertContains(reflectCompareLines, "int compareLike(std::string left, std::string right) {",
			"C++ helpers returning Reflect.compare should infer Int instead of falling back to String");
		assertTrue(reflectCompareLines.indexOf("std::string compareLike") < 0, "C++ Reflect.compare helpers should not infer std::string returns");
		final enumValueMapOwner = new HxClassDecl("EnumValueMap", false, [
			new HxFunctionDecl("compare", Public, false, [
				new HxFunctionArg("k1", "EnumValue", NoDefault, false, false),
				new HxFunctionArg("k2", "EnumValue", NoDefault, false, false)
			], "Int", [SReturn(EInt(0), HxPos.unknown())], ""),
			new HxFunctionDecl("compareArgs", Public, false, [
				new HxFunctionArg("a1", "Array<String>", NoDefault, false, false),
				new HxFunctionArg("a2", "Array<String>", NoDefault, false, false)
			], "Int", [SReturn(EInt(0), HxPos.unknown())], "")
		], []);
		final enumValueMapNames = new StringMap<Bool>();
		enumValueMapNames.set("EnumValueMap", true);
		final enumValueMapClasses = new StringMap<HxClassDecl>();
		enumValueMapClasses.set("EnumValueMap", enumValueMapOwner);
		final enumValueMapLookup = {names: enumValueMapNames, byName: enumValueMapClasses};
		final enumValueMapCompareArg = new HxFunctionDecl("compareArg", Public, false, [
			new HxFunctionArg("v1", "Dynamic", NoDefault, false, false),
			new HxFunctionArg("v2", "Dynamic", NoDefault, false, false)
		], "Int", [
			SIf(ECall(EField(EIdent("Reflect"), "isEnumValue"), [EIdent("v1")]),
				SReturn(ECall(EIdent("compare"), [EIdent("v1"), EIdent("v2")]), HxPos.unknown()), null, HxPos.unknown()),
			SIf(EBinop("is", EIdent("v1"), EIdent("Array")), SReturn(ECall(EIdent("compareArgs"), [EIdent("v1"), EIdent("v2")]), HxPos.unknown()), null,
				HxPos.unknown()),
			SReturn(ECall(EField(EIdent("Reflect"), "compare"), [EIdent("v1"), EIdent("v2")]), HxPos.unknown())
		], "");
		final enumValueMapCompareArgLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperMethod(enumValueMapCompareArg, enumValueMapOwner, enumValueMapLookup).join("\n");
		assertContains(enumValueMapCompareArgLines, "int compareArg(std::any v1, std::any v2) {",
			"C++ EnumValueMap-style Dynamic compare helpers should keep erased std::any arguments");
		assertContains(enumValueMapCompareArgLines, "if (__hxhx_is_enum_value(v1)) {",
			"C++ Reflect.isEnumValue should lower to target-owned enum-value detection for erased values");
		assertContains(enumValueMapCompareArgLines, "compare(__hxhx_enum_value_ptr(v1), __hxhx_enum_value_ptr(v2))",
			"C++ erased enum compare calls should extract EnumValue pointers from std::any arguments");
		assertContains(enumValueMapCompareArgLines, "compareArgs(__hxhx_string_vector_any(v1), __hxhx_string_vector_any(v2))",
			"C++ erased array compare calls should extract string arrays from std::any arguments");
		assertContains(enumValueMapCompareArgLines, "return __hxhx_compare(__hxhx_cmp_left, __hxhx_cmp_right);",
			"C++ Reflect.compare should not emit raw std::any less-than/greater-than comparisons");
		final shadowOwner = new HxClassDecl("JsonPrinterShadow", false, [], []);
		final shadowScope = @:privateAccess backend.cpp.CppTargetCore.renderScope(shadowOwner,
			{names: new StringMap<Bool>(), byName: new StringMap<HxClassDecl>()}, "void");
		shadowScope.localTypes.set("v", "std::any");
		shadowScope.localNames.set("v", "v");
		shadowScope.localNameCounts.set("v", 1);
		shadowScope.localTypeOverrides.set("v", "std::shared_ptr<EnumValue>");
		final shadowLines = @:privateAccess backend.cpp.CppTargetCore.renderStmt(SVar("v", "Array<Dynamic>", EIdent("v"), HxPos.unknown()), "  ", shadowScope)
			.join("\n");
		assertContains(shadowLines, "std::vector<std::string> v_2 = __hxhx_string_vector_any(v);",
			"C++ shadowing typed locals should render initializers against the previous binding and keep explicit Array<Dynamic> type hints");
		assertTrue(shadowLines.indexOf("std::shared_ptr<EnumValue> v_2 = v_2") < 0,
			"C++ explicit typed locals must not inherit stale Dynamic/enum overrides or self-initialize when shadowing a parameter");
		final typeNameStringTernary = @:privateAccess backend.cpp.CppTargetCore.stringExpr(ECall(EField(EIdent("Std"), "string"), [
			ETernary(EBinop("!=", EIdent("type"), ENull), ECall(EField(EIdent("Type"), "getClassName"), [EIdent("type")]), EString("Dynamic"))
		]));
		assertContains(typeNameStringTernary, "? __hxhx_type_name(type) : std::string(\"Dynamic\")",
			"C++ string contexts should preserve string-typed ternaries instead of numeric stringifying them");
		assertTrue(typeNameStringTernary.indexOf("std::to_string") < 0, "C++ string contexts should not wrap string-typed ternaries in std::to_string");
		assertTrue(@:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("__global__"), "__hxcpp_memory_get_double"),
				[EIdent("b"), EIdent("pos")])) == "__hxhx_memory_get_double(b, pos)",
			"C++ hxcpp byte-memory float intrinsics should lower to target-owned helpers");
		assertTrue(@:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("__global__"), "__hxcpp_reinterpret_le_int32_as_float32"),
				[EIdent("i")])) == "__hxhx_reinterpret_le_int32_as_float32(i)",
			"C++ hxcpp float reinterpret intrinsics should lower to target-owned helpers");
		assertTrue(@:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("__global__"), "__hxcpp_reinterpret_float64_as_le_int32_high"),
				[EIdent("v")])) == "__hxhx_reinterpret_float64_as_le_int32_high(v)",
			"C++ hxcpp float64 high-word reinterpret intrinsics should lower to target-owned helpers");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("__global__"), "__hxcpp_utc_date"),
			[
				EIdent("year"),
				EIdent("month"),
				EIdent("day"),
				EIdent("hour"),
				EIdent("min"),
				EIdent("sec")
			])) == "__hxhx_utc_date(year, month, day, hour, min, sec)",
			"C++ hxcpp UTC date intrinsic should lower to target-owned support instead of unresolved __global__");
		assertTrue(@:privateAccess
			backend.cpp.CppTargetCore.inferExprCppType(ECall(EField(EIdent("__global__"), "__hxcpp_reinterpret_float32_as_le_int32"), [EFloat(1.0)])) == "int",
			"C++ hxcpp float-to-int reinterpret intrinsics should infer integer return types");
		assertTrue(@:privateAccess
			backend.cpp.CppTargetCore.inferExprCppType(ECall(EField(EIdent("__global__"), "__hxcpp_utc_date"),
				[EInt(1970), EInt(0), EInt(1), EInt(0), EInt(0), EInt(0)])) == "double",
			"C++ hxcpp UTC date intrinsic should infer Float/double return type");
		final parenthesizedAssignmentExpr = @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ECall(EIdent("__hxhx_parenthesized"), [EBinop("=", EIdent("last"), ECall(EIdent("readByte"), []))]));
		assertTrue(parenthesizedAssignmentExpr == "(last = readByte())",
			"C++ parenthesized assignment sentinels should preserve grouping instead of leaking helper calls, got: " + parenthesizedAssignmentExpr);
		assertTrue(@:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("__global__"), "__hxcpp_string_of_bytes"),
				[EIdent("b"), EIdent("result"), EIdent("pos"), EIdent("len"), EBool(true)])) == "__hxhx_string_of_bytes(b, result, pos, len)",
			"C++ hxcpp string-of-bytes intrinsic should ignore optional target flags and lower to target-owned helpers");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.renderExpr(EIdent("UTF8")) == "nullptr",
			"C++ Encoding.UTF8 constructor shorthand should not render as an unresolved bare identifier in the MVP");
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
		assertContains(opaqueTypedLocalRefBlock, "std::shared_ptr<TypedefToStringMap<std::string>> x = nullptr;",
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
		final opaqueStringMapBlock = @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ETryCatchRaw('opaque_block_expr:{var h = new haxe.ds.StringMap(); h.set("lt","<"); h.set("gt",">"); h.set("amp","&"); h.set("quot","\\""); h.set("apos","\'"); h;}'));
		assertContains(opaqueStringMapBlock, "std::map<std::string, std::string> h;",
			"remote Cpp gate opaque StringMap escape-table block should lower to a target-owned C++ string map");
		assertContains(opaqueStringMapBlock, 'h["quot"] = "\\"";', "opaque StringMap escape-table block should preserve escaped quote values");
		assertContains(opaqueStringMapBlock, "return h;", "opaque StringMap escape-table block should return the constructed map");
		final enumMetaOwner = new HxClassDecl("EnumMetaOwner", false, [], [
			new HxFieldDecl("__hx_enum_ctors", Public, true, "Dynamic", EArrayDecl([EString("U1"), EString("U2")])),
			new HxFieldDecl("U2", Public, true, "Dynamic",
				EAnon(["__hx_enum", "__hx_ctor", "__hx_index", "__hx_params"], [EString("EnumMetaOwner"), EString("U2"), EInt(1), EArrayDecl([])]))
		]);
		final enumMetaNames = new StringMap<Bool>();
		enumMetaNames.set("EnumMetaOwner", true);
		final enumMetaClasses = new StringMap<HxClassDecl>();
		enumMetaClasses.set("EnumMetaOwner", enumMetaOwner);
		final enumMetaLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperClass(enumMetaOwner, {names: enumMetaNames, byName: enumMetaClasses}).join("\n");
		assertContains(enumMetaLines, "inline static std::vector<std::string> __hx_enum_ctors = std::vector<std::string>{",
			"C++ static fields with erased type hints should infer vector types from array initializers");
		assertContains(enumMetaLines,
			"inline static __hxhx_anon___hx_enum_std__string___hx_ctor_std__string___hx_index_int____hx_params_std__vector_std__string_ U2 =",
			"C++ static fields with erased type hints should infer generated anon struct types from object initializers");
		assertTrue(enumMetaLines.indexOf("inline static std::string __hx_enum_ctors = std::vector") < 0,
			"C++ enum metadata arrays should not fall back to string-typed static fields");
		assertTrue(enumMetaLines.indexOf("inline static std::string U2 = __hxhx_anon") < 0,
			"C++ enum metadata values should not fall back to string-typed static fields");
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
		final falseGuardComprehension = @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(EArrayComprehension("i", ERange(EInt(0), EInt(3)), EBool(false), EIdent("i")));
		assertContains(falseGuardComprehension, "if (false) {", "C++ array-comprehension guards should not emit `if false {`");
		assertTrue(falseGuardComprehension.indexOf("if false {") < 0, "C++ array-comprehension guards must use valid C-style condition syntax");
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
		final complexTypeCarrier = new HxClassDecl("ComplexType", false, [], [new HxFieldDecl("__hx_is_enum", Public, true, "Bool", EBool(true))]);
		final typeToolsNullable = new HxFunctionDecl("nullable", Public, true, [new HxFunctionArg("complexType", "ComplexType", NoDefault, false, false)],
			"ComplexType", [SReturn(EString("Null<$complexType>"), HxPos.unknown())], "");
		final typeToolsOwner = new HxClassDecl("TypeTools", false, [typeToolsNullable], []);
		final typeToolsNames = new StringMap<Bool>();
		for (name in ["ComplexType", "TypeTools"])
			typeToolsNames.set(name, true);
		final typeToolsClasses = new StringMap<HxClassDecl>();
		typeToolsClasses.set("ComplexType", complexTypeCarrier);
		typeToolsClasses.set("TypeTools", typeToolsOwner);
		final typeToolsNullableLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(typeToolsNullable, typeToolsOwner, {
			names: typeToolsNames,
			byName: typeToolsClasses
		}).join("\n");
		assertContains(typeToolsNullableLines, "static std::shared_ptr<ComplexType> nullable(std::shared_ptr<ComplexType> complexType) {",
			"C++ ComplexType helper methods should preserve their enum-carrier reference return type");
		assertContains(typeToolsNullableLines, "return nullptr;",
			"C++ string-only macro ComplexType placeholders should lower to a neutral enum-carrier reference default");
		assertTrue(typeToolsNullableLines.indexOf("return std::string(\"Null<$complexType>\");") < 0,
			"C++ ComplexType-returning helpers must not return bare string placeholders");
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
		enumPayloadScope.localTypes.set("op", "std::shared_ptr<Binop>");
		enumPayloadScope.localTypes.set("constant", "std::shared_ptr<Constant>");
		final enumRawCarrierStruct = @:privateAccess
			backend.cpp.CppTargetCore.anonStruct(["__hx_params"], [EArrayDecl([EIdent("op"), EIdent("constant")])], enumPayloadScope);
		assertTrue(enumRawCarrierStruct.fieldTypes[0] == "std::vector<std::string>",
			"C++ enum metadata payload arrays should not infer raw enum-carrier class vector types");
		final enumRawCarrierPayload = @:privateAccess
			backend.cpp.CppTargetCore.valueExprForExpectedType(EArrayDecl([EIdent("op"), EIdent("constant")]), enumRawCarrierStruct.fieldTypes[0],
				enumPayloadScope);
		assertContains(enumRawCarrierPayload, "std::vector<std::string>{",
			"C++ enum metadata payload rendering should keep the string-vector storage contract");
		assertTrue(enumRawCarrierPayload.indexOf("std::vector<std::shared_ptr<Binop>>") < 0,
			"C++ enum metadata payload rendering should not leak raw Binop carrier vector types");
		final enumCtorHelper = new HxFunctionDecl("U1", Public, true, [new HxFunctionArg("x", "String", NoDefault, false, false)], "Dynamic", [
			SReturn(EAnon(["__hx_enum", "__hx_ctor", "__hx_index", "__hx_params"], [EString("X"), EString("U1"), EInt(0), EArrayDecl([EIdent("x")])]),
				HxPos.unknown())
		], "");
		final enumCtorHelperLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperMethod(enumCtorHelper, enumPayloadOwner, enumPayloadLookup).join("\n");
		assertContains(enumCtorHelperLines, "static std::string U1(std::string x) {\n    return std::string(\"U1\");\n  }",
			"C++ enum metadata constructors with Dynamic return should stringify to their constructor tag, not std::to_string an aggregate");
		final assertOwner = new HxClassDecl("Assert", false, [], []);
		final assertNames = new StringMap<Bool>();
		assertNames.set("Assert", true);
		final assertClasses = new StringMap<HxClassDecl>();
		assertClasses.set("Assert", assertOwner);
		final assertLookup = {names: assertNames, byName: assertClasses};
		final assertQStringify = new HxFunctionDecl("q", Public, true, [new HxFunctionArg("v", "Dynamic", NoDefault, false, false)], "String",
			[SReturn(ECall(EField(EIdent("Std"), "string"), [EIdent("v")]), HxPos.unknown())], "");
		final assertQLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(assertQStringify, assertOwner, assertLookup).join("\n");
		assertContains(assertQLines, "template<typename T>\n  static std::string q(const T& v) {\n    return __hxhx_stringify(v);\n  }",
			"C++ Assert.q Dynamic stringification should be a polymorphic diagnostic helper, not q(std::string)");
		assertTrue(assertQLines.indexOf("q(std::string v)") < 0, "C++ Assert.q should not reject numeric diagnostic values");
		final assertQErased = new HxFunctionDecl("q", Public, true, [new HxFunctionArg("v", "", NoDefault, false, false)], "",
			[SReturn(ECall(EField(EIdent("Std"), "string"), [EIdent("v")]), HxPos.unknown())], "");
		final assertQErasedLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(assertQErased, assertOwner, assertLookup).join("\n");
		assertContains(assertQErasedLines, "template<typename T>\n  static std::string q(const T& v)",
			"C++ Assert.q should stay polymorphic even if upstream helper hints are erased during parsing");
		final likeStatus = new HxClassDecl("LikeStatus", false, [], [
			new HxFieldDecl("expectedValue", Public, false, "Dynamic", null),
			new HxFieldDecl("actualValue", Public, false, "Dynamic", null),
			new HxFieldDecl("error", Public, false, "String", null),
			new HxFieldDecl("path", Public, false, "String", null),
			new HxFieldDecl("recursive", Public, false, "Bool", null)
		]);
		assertNames.set("LikeStatus", true);
		assertClasses.set("LikeStatus", likeStatus);
		final assertSameAs = new HxFunctionDecl("sameAs", Public, true, [
			new HxFunctionArg("expected", "", NoDefault, false, false),
			new HxFunctionArg("value", "", NoDefault, false, false),
			new HxFunctionArg("status", "LikeStatus", NoDefault, false, false),
			new HxFunctionArg("approx", "Float", NoDefault, false, false)
		], "Bool", [
			SExpr(EBinop("=", EField(EIdent("status"), "expectedValue"), EIdent("expected")), HxPos.unknown()),
			SReturn(ECall(EIdent("_floatEquals"), [EIdent("expected"), EIdent("value"), EIdent("approx")]), HxPos.unknown())
		], "");
		final assertSameAsLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(assertSameAs, assertOwner, assertLookup).join("\n");
		assertContains(assertSameAsLines,
			"template<typename TExpected, typename TValue, typename TStatus>\n  static bool sameAs(const TExpected& expected, const TValue& value, TStatus& status, double approx)",
			"C++ Assert.sameAs should accept Dynamic-erased expected/value and structural status objects");
		assertContains(assertSameAsLines, "__hxhx_same_as(expected, value, __hxhx_same_as_approx)",
			"C++ Assert.sameAs should delegate mixed numeric/vector/string comparison to a compile-safe target helper");
		assertContains(assertSameAsLines, "auto& __hxhx_status = __hxhx_status_ref(status);",
			"C++ Assert.sameAs should normalize pointer or structural status values through a small target helper");
		assertContains(assertSameAsLines, "(__hxhx_status.expectedValue) = __hxhx_stringify(expected);",
			"C++ Assert.sameAs should stringify Dynamic expected values when storing diagnostic status");
		assertTrue(assertSameAsLines.indexOf("sameAs(std::string expected, std::string value") < 0,
			"C++ Assert.sameAs should not reject numeric diagnostic values through a string-only signature");
		final assertSame = new HxFunctionDecl("same", Public, true, [
			new HxFunctionArg("expected", "Dynamic", NoDefault, false, false),
			new HxFunctionArg("value", "Dynamic", NoDefault, false, false),
			new HxFunctionArg("recursive", "Bool", NoDefault, true, false),
			new HxFunctionArg("msg", "String", NoDefault, true, false),
			new HxFunctionArg("approx", "Float", NoDefault, true, false),
			new HxFunctionArg("pos", "PosInfos", NoDefault, true, false)
		], "Bool", [SReturn(EBool(true), HxPos.unknown())], "");
		final assertSameLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(assertSame, assertOwner, assertLookup).join("\n");
		assertContains(assertSameLines, "template<typename TExpected, typename TValue>\n  static bool same(const TExpected& expected, const TValue& value",
			"C++ Assert.same should accept Dynamic-erased expected/value through a template boundary");
		assertContains(assertSameLines, "__hxhx_stringify(expected)", "C++ Assert.same diagnostics should stringify templated expected values");
		assertContains(assertSameLines, "__hxhx_same_as(expected, value", "C++ Assert.same should compare templated values without narrowing to strings");
		assertTrue(assertSameLines.indexOf("same(std::string expected, std::string value") < 0,
			"C++ Assert.same should not reject array/bool values through a string-only signature");
		final assertSameStatusScope = @:privateAccess backend.cpp.CppTargetCore.renderScope(assertOwner, assertLookup, "bool");
		assertSameStatusScope.localTypes.set("recursive", "std::optional<bool>");
		assertSameStatusScope.localTypes.set("expected", "std::string");
		assertSameStatusScope.localTypes.set("value", "std::string");
		final assertSameStatusExpr:HxExpr = EAnon(["recursive", "path", "error", "expectedValue", "actualValue"], [
			ETernary(EBinop("==", EIdent("recursive"), ENull), EBool(true), EIdent("recursive")),
			EString(""),
			ENull,
			EIdent("expected"),
			EIdent("value")
		]);
		final assertSameStatusStruct = @:privateAccess backend.cpp.CppTargetCore.anonStruct(["recursive", "path", "error", "expectedValue", "actualValue"], [
			ETernary(EBinop("==", EIdent("recursive"), ENull), EBool(true), EIdent("recursive")),
			EString(""),
			ENull,
			EIdent("expected"),
			EIdent("value")
		], assertSameStatusScope);
		assertTrue(assertSameStatusStruct.name.indexOf("recursive_bool") >= 0,
			"C++ Assert.same status anonymous object should infer recursive as Bool, not Int");
		assertTrue(assertSameStatusStruct.name.indexOf("error_std__string") >= 0,
			"C++ Assert.same status anonymous object should infer null error as String, not Int");
		final assertSameStatusLiteral = @:privateAccess backend.cpp.CppTargetCore.renderExpr(assertSameStatusExpr, assertSameStatusScope);
		assertContains(assertSameStatusLiteral, "recursive_bool", "C++ Assert.same status literal should use the bool aggregate shape");
		assertContains(assertSameStatusLiteral, "error_std__string", "C++ Assert.same status literal should use the string error aggregate shape");
		assertContains(assertSameStatusLiteral, "std::string()", "C++ Assert.same status null error should initialize as an empty string");
		final assertPass = new HxFunctionDecl("pass", Public, true, [
			new HxFunctionArg("msg", "String", Default(EString("pass expected")), true, false),
			new HxFunctionArg("pos", "PosInfos", NoDefault, true, false)
		], "Bool", [SReturn(EBool(true), HxPos.unknown())], "");
		final assertPassFromPos = new HxFunctionDecl("passFromPos", Public, true, [new HxFunctionArg("pos", "PosInfos", NoDefault, false, false)], "Bool",
			[SReturn(ECall(EIdent("pass"), [EIdent("pos")]), HxPos.unknown())], "");
		final assertPassOwner = new HxClassDecl("Assert", false, [assertPass, assertPassFromPos], []);
		final assertPassNames = new StringMap<Bool>();
		for (name in ["Assert", "PosInfos"])
			assertPassNames.set(name, true);
		final assertPassClasses = new StringMap<HxClassDecl>();
		assertPassClasses.set("Assert", assertPassOwner);
		assertPassClasses.set("PosInfos", new HxClassDecl("PosInfos", false, [], []));
		final assertPassLookup = {names: assertPassNames, byName: assertPassClasses};
		final assertPassFromPosLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(assertPassFromPos, assertPassOwner, assertPassLookup)
			.join("\n");
		assertContains(assertPassFromPosLines, "return pass(std::string(\"pass expected\"), pos);",
			"C++ same-owner calls should pad skipped optional arguments when a PosInfos argument targets the trailing position parameter");
		final assertBoolHelpers = new HxClassDecl("Assert", false, [
			new HxFunctionDecl("isTrue", Public, true, [
				new HxFunctionArg("value", "Bool", NoDefault, false, false),
				new HxFunctionArg("msg", "String", NoDefault, true, false),
				new HxFunctionArg("pos", "PosInfos", NoDefault, true, false)
			], "Bool", [SReturn(EIdent("value"), HxPos.unknown())], ""),
			new HxFunctionDecl("isFalse", Public, true, [
				new HxFunctionArg("value", "Bool", NoDefault, false, false),
				new HxFunctionArg("msg", "String", NoDefault, true, false),
				new HxFunctionArg("pos", "PosInfos", NoDefault, true, false)
			], "Bool", [SReturn(EUnop("!", EIdent("value")), HxPos.unknown())], "")
		], []);
		final testBoolWrapper = new HxFunctionDecl("t", Public, false, [
			new HxFunctionArg("v", "", NoDefault, false, false),
			new HxFunctionArg("pos", "PosInfos", NoDefault, true, false)
		], "String", [
			SReturn(ETernary(ECall(EField(EIdent("Assert"), "isTrue"), [EIdent("v"), ENull, EIdent("pos")]), EString("true"), EString("false")),
				HxPos.unknown())
		], "");
		final testBoolOwner = new HxClassDecl("Test", false, [testBoolWrapper], []);
		final testBoolNames = new StringMap<Bool>();
		for (name in ["Test", "Assert", "PosInfos"])
			testBoolNames.set(name, true);
		final testBoolClasses = new StringMap<HxClassDecl>();
		testBoolClasses.set("Test", testBoolOwner);
		testBoolClasses.set("Assert", assertBoolHelpers);
		testBoolClasses.set("PosInfos", new HxClassDecl("PosInfos", false, [], []));
		final testBoolLookup = {names: testBoolNames, byName: testBoolClasses};
		final testBoolWrapperLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(testBoolWrapper, testBoolOwner, testBoolLookup).join("\n");
		assertContains(testBoolWrapperLines, "std::string t(bool v, std::shared_ptr<PosInfos> pos = nullptr)",
			"C++ wrappers that forward erased args into known Bool helper params should infer bool, not std::string");
		assertTrue(testBoolWrapperLines.indexOf("std::string t(std::string v") < 0,
			"C++ Assert.isTrue wrapper args should not stay string-only when call sites pass bools");
		final arraySortCompare = new HxFunctionDecl("compare", Public, true, [
			new HxFunctionArg("a", "Array<String>", NoDefault, false, false),
			new HxFunctionArg("cmp", "String->String->Int", NoDefault, false, false),
			new HxFunctionArg("i", "", NoDefault, false, false),
			new HxFunctionArg("j", "", NoDefault, false, false)
		], "Int", [
			SReturn(ECall(EIdent("cmp"), [EArrayAccess(EIdent("a"), EIdent("i")), EArrayAccess(EIdent("a"), EIdent("j"))]), HxPos.unknown())
		], "");
		final arraySortLower = new HxFunctionDecl("lower", Public, true, [
			new HxFunctionArg("a", "Array<String>", NoDefault, false, false),
			new HxFunctionArg("cmp", "String->String->Int", NoDefault, false, false),
			new HxFunctionArg("from", "", NoDefault, false, false),
			new HxFunctionArg("to", "", NoDefault, false, false),
			new HxFunctionArg("val", "", NoDefault, false, false)
		], "Int", [
			SIf(EBinop("<", ECall(EIdent("compare"), [EIdent("a"), EIdent("cmp"), EIdent("val"), EIdent("from")]), EInt(0)),
				SReturn(EIdent("to"), HxPos.unknown()), null, HxPos.unknown()),
			SReturn(EIdent("from"), HxPos.unknown())
		], "");
		final arraySortDoMerge = new HxFunctionDecl("doMerge", Public, true, [
			new HxFunctionArg("a", "Array<String>", NoDefault, false, false),
			new HxFunctionArg("cmp", "String->String->Int", NoDefault, false, false),
			new HxFunctionArg("from", "", NoDefault, false, false),
			new HxFunctionArg("pivot", "", NoDefault, false, false),
			new HxFunctionArg("to", "", NoDefault, false, false),
			new HxFunctionArg("len1", "", NoDefault, false, false),
			new HxFunctionArg("len2", "", NoDefault, false, false)
		], "Void", [
			SVar("len11", "", EBinop(">>", EIdent("len1"), EInt(1)), HxPos.unknown()),
			SVar("len22", "", EBinop(">>", EIdent("len2"), EInt(1)), HxPos.unknown()),
			SVar("first_cut", "", EBinop("+", EIdent("from"), EIdent("len11")), HxPos.unknown()),
			SExpr(ECall(EIdent("lower"), [EIdent("a"), EIdent("cmp"), EIdent("pivot"), EIdent("to"), EIdent("first_cut")]), HxPos.unknown()),
			SExpr(ECall(EIdent("doMerge"), [
				EIdent("a"),
				EIdent("cmp"),
				EIdent("from"),
				EIdent("first_cut"),
				EIdent("to"),
				EIdent("len11"),
				EIdent("len22")
			]), HxPos.unknown()),
			SReturnVoid(HxPos.unknown())
		], "");
		final arraySortRec = new HxFunctionDecl("rec", Public, true, [
			new HxFunctionArg("a", "Array<String>", NoDefault, false, false),
			new HxFunctionArg("cmp", "String->String->Int", NoDefault, false, false),
			new HxFunctionArg("from", "", NoDefault, false, false),
			new HxFunctionArg("to", "", NoDefault, false, false)
		], "Void", [
			SVar("middle", "", EBinop(">>", EBinop("+", EIdent("from"), EIdent("to")), EInt(1)), HxPos.unknown()),
			SIf(EBinop("<", EBinop("-", EIdent("to"), EIdent("from")), EInt(12)), SBlock([
				SIf(EBinop("<=", EIdent("to"), EIdent("from")), SReturnVoid(HxPos.unknown()), null, HxPos.unknown()),
				SExpr(EArrayAccess(EIdent("a"), EBinop("-", EIdent("to"), EInt(1))), HxPos.unknown())
			], HxPos.unknown()), null, HxPos.unknown()),
			SExpr(ECall(EIdent("doMerge"), [
				EIdent("a"),
				EIdent("cmp"),
				EIdent("from"),
				EIdent("middle"),
				EIdent("to"),
				EBinop("-", EIdent("middle"), EIdent("from")),
				EBinop("-", EIdent("to"), EIdent("middle"))
			]), HxPos.unknown()),
			SReturnVoid(HxPos.unknown())
		], "");
		final arraySortSort = new HxFunctionDecl("sort", Public, true, [
			new HxFunctionArg("a", "Array<String>", NoDefault, false, false),
			new HxFunctionArg("cmp", "String->String->Int", NoDefault, false, false)
		], "", [
			SReturn(ECall(EIdent("rec"), [EIdent("a"), EIdent("cmp"), EInt(0), EField(EIdent("a"), "length")]), HxPos.unknown())
		], "");
		final arraySortOwner = new HxClassDecl("ArraySort", false, [arraySortSort, arraySortRec, arraySortDoMerge, arraySortLower, arraySortCompare], []);
		final arraySortNames = new StringMap<Bool>();
		arraySortNames.set("ArraySort", true);
		final arraySortClasses = new StringMap<HxClassDecl>();
		arraySortClasses.set("ArraySort", arraySortOwner);
		final arraySortLookup = {names: arraySortNames, byName: arraySortClasses};
		final arraySortSortLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(arraySortSort, arraySortOwner, arraySortLookup).join("\n");
		final arraySortRecLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(arraySortRec, arraySortOwner, arraySortLookup).join("\n");
		final arraySortDoMergeLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(arraySortDoMerge, arraySortOwner, arraySortLookup)
			.join("\n");
		final arraySortLowerLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(arraySortLower, arraySortOwner, arraySortLookup).join("\n");
		assertContains(arraySortSortLines, "static void sort(std::vector<std::string> a, std::function<int(std::string, std::string)> cmp)",
			"C++ ArraySort-like wrappers returning void helper calls should infer void rather than std::string");
		assertContains(arraySortRecLines, "static void rec(std::vector<std::string> a, std::function<int(std::string, std::string)> cmp, int from, int to)",
			"C++ ArraySort-like index/range helper parameters should infer int from arithmetic and array-index use");
		assertContains(arraySortDoMergeLines,
			"static void doMerge(std::vector<std::string> a, std::function<int(std::string, std::string)> cmp, int from, int pivot, int to, int len1, int len2)",
			"C++ ArraySort-like sibling helper calls should reuse inferred integer range parameters");
		assertContains(arraySortLowerLines,
			"static int lower(std::vector<std::string> a, std::function<int(std::string, std::string)> cmp, int from, int to, int val)",
			"C++ ArraySort-like binary-search helpers should infer forwarded compare indexes as int");
		assertTrue(arraySortRecLines.indexOf("std::string from") < 0 && arraySortRecLines.indexOf("std::string to") < 0,
			"C++ ArraySort-like helper indexes should not stay string-shaped");
		final nativeStringRaw = new HxFunctionDecl("raw", Public, true, [new HxFunctionArg("inString", "String", NoDefault, false, false)], "RawConstPointer",
			[
				SReturn(EUntyped(ECall(EField(EIdent("inString"), "raw_ptr"), [])), HxPos.unknown())
			], "");
		final nativeStringRawChar = new HxFunctionDecl("rawChar", Public, true, [new HxFunctionArg("inString", "String", NoDefault, false, false)],
			"RawConstPointer<Char>", [
				SReturn(EUntyped(ECall(EField(EIdent("inString"), "raw_ptr"), [])), HxPos.unknown())
			], "");
		final nativeStringCStr = new HxFunctionDecl("c_str", Public, true, [new HxFunctionArg("inString", "String", NoDefault, false, false)], "ConstPointer",
			[
				SReturn(ECall(EField(EField(EIdent("cpp"), "ConstPointer"), "fromPointer"), [EUntyped(ECall(EField(EIdent("inString"), "c_str"), []))]),
					HxPos.unknown())
			], "");
		final nativeStringCStrChar = new HxFunctionDecl("cStrChar", Public, true, [new HxFunctionArg("inString", "String", NoDefault, false, false)],
			"ConstPointer<Char>", [
				SReturn(ECall(EField(EField(EIdent("cpp"), "ConstPointer"), "fromPointer"), [EUntyped(ECall(EField(EIdent("inString"), "c_str"), []))]),
					HxPos.unknown())
			], "");
		final nativeStringFromPointer = new HxFunctionDecl("fromPointer", Public, true, [new HxFunctionArg("inPtr", "ConstPointer", NoDefault, false, false)],
			"String", [
				SReturn(ECall(EField(EIdent("__global__"), "String"), [EField(EIdent("inPtr"), "ptr")]), HxPos.unknown())
			], "");
		final nativeStringFromGcPointer = new HxFunctionDecl("fromGcPointer", Public, true, [
			new HxFunctionArg("inPtr", "ConstPointer", NoDefault, false, false),
			new HxFunctionArg("inLen", "Int", NoDefault, false, false)
		], "String", [
			SReturn(ECall(EField(EIdent("__global__"), "String"), [EField(EIdent("inPtr"), "ptr"), EIdent("inLen")]), HxPos.unknown())
		], "");
		final nativeStringOwner = new HxClassDecl("NativeString", false, [
			nativeStringRaw,
			nativeStringRawChar,
			nativeStringCStr,
			nativeStringCStrChar,
			nativeStringFromPointer,
			nativeStringFromGcPointer
		], []);
		final nativeStringNames = new StringMap<Bool>();
		for (name in ["NativeString", "RawConstPointer", "ConstPointer"])
			nativeStringNames.set(name, true);
		final nativeStringClasses = new StringMap<HxClassDecl>();
		nativeStringClasses.set("NativeString", nativeStringOwner);
		final nativeStringLookup = {names: nativeStringNames, byName: nativeStringClasses};
		final nativeStringRawLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(nativeStringRaw, nativeStringOwner, nativeStringLookup)
			.join("\n");
		final nativeStringRawCharLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(nativeStringRawChar, nativeStringOwner,
			nativeStringLookup)
			.join("\n");
		final nativeStringCStrLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(nativeStringCStr, nativeStringOwner, nativeStringLookup)
			.join("\n");
		final nativeStringCStrCharLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(nativeStringCStrChar, nativeStringOwner,
			nativeStringLookup)
			.join("\n");
		final nativeStringFromPointerLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(nativeStringFromPointer, nativeStringOwner,
			nativeStringLookup)
			.join("\n");
		final nativeStringFromGcPointerLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(nativeStringFromGcPointer, nativeStringOwner,
			nativeStringLookup)
			.join("\n");
		assertContains(nativeStringRawLines, "return std::make_shared<RawConstPointer<void>>(inString.c_str());",
			"C++ NativeString.raw should lower raw_ptr through target-owned pointer support");
		assertContains(nativeStringRawCharLines, "return std::make_shared<RawConstPointer<std::shared_ptr<Char>>>(inString.c_str());",
			"C++ NativeString.raw should preserve typed RawConstPointer<T> return arguments");
		assertContains(nativeStringCStrLines, "return std::make_shared<ConstPointer<void>>(inString.c_str());",
			"C++ cpp.ConstPointer.fromPointer should lower to target-owned pointer support");
		assertContains(nativeStringCStrCharLines, "return std::make_shared<ConstPointer<std::shared_ptr<Char>>>(inString.c_str());",
			"C++ cpp.ConstPointer.fromPointer should preserve typed ConstPointer<T> return arguments");
		assertTrue(@:privateAccess backend.cpp.CppTypeModel.cppTypeHint("RawConstPointer<Char>") == "std::shared_ptr<RawConstPointer<std::shared_ptr<Char>>>",
			"C++ RawConstPointer<T> extern hints should preserve the target-owned generic argument");
		assertContains(nativeStringFromPointerLines, "return __hxhx_string_from_pointer((inPtr->ptr));",
			"C++ __global__.String(pointer) should lower to target-owned string-from-pointer support");
		assertContains(nativeStringFromGcPointerLines, "return __hxhx_string_from_pointer((inPtr->ptr), inLen);",
			"C++ __global__.String(pointer, len) should lower to target-owned string-from-pointer support");
		assertTrue(nativeStringCStrLines.indexOf("cpp.ConstPointer") < 0 && nativeStringFromPointerLines.indexOf("__global__.String") < 0,
			"C++ NativeString pointer intrinsics should not leak hxcpp-native syntax into generated C++");
		final metadataWrappedValue = ECall(EIdent("__hxhx_expr_meta"), [EString("nullSafety"), EString("Off"), EString("wrapped")]);
		final metadataExpr = @:privateAccess backend.cpp.CppTargetCore.renderExpr(metadataWrappedValue);
		final metadataStringExpr = @:privateAccess backend.cpp.CppTargetCore.stringExpr(metadataWrappedValue);
		final metadataType = @:privateAccess backend.cpp.CppTargetCore.inferExprCppType(metadataWrappedValue);
		assertTrue(metadataExpr == "\"wrapped\"", "C++ expression metadata should erase to the wrapped expression, got: " + metadataExpr);
		assertTrue(metadataStringExpr == "std::string(\"wrapped\")",
			"C++ string expression metadata should erase before string lowering, got: " + metadataStringExpr);
		assertTrue(metadataType == "std::string", "C++ expression metadata should infer from the wrapped expression, got: " + metadataType);
		assertTrue(metadataExpr.indexOf("__hxhx_expr_meta") < 0 && metadataStringExpr.indexOf("__hxhx_expr_meta") < 0,
			"C++ expression metadata should not leak as a runtime helper call");
		final iMapInterface = new HxClassDecl("IMap", false, [
			new HxFunctionDecl("get", Public, false, [new HxFunctionArg("k", "K", NoDefault, false, false)], "Null<V>", [], ""),
			new HxFunctionDecl("keys", Public, false, [], "Iterator<K>", [], ""),
			new HxFunctionDecl("keyValueIterator", Public, false, [], "KeyValueIterator<K,V>", [], "")
		], [], "", null, true);
		final iMapNames = new StringMap<Bool>();
		iMapNames.set("IMap", true);
		final iMapClasses = new StringMap<HxClassDecl>();
		iMapClasses.set("IMap", iMapInterface);
		final iMapLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(iMapInterface, {names: iMapNames, byName: iMapClasses}).join("\n");
		assertContains(iMapLines, "template<typename K, typename V>\nstruct IMap {",
			"C++ generic interfaces should render as templates instead of erasing their method type parameters");
		assertContains(iMapLines, "virtual ~IMap() = default;", "C++ interfaces should expose a virtual destructor");
		assertContains(iMapLines, "virtual std::optional<V> get(K k) = 0;", "C++ IMap-like interfaces should preserve key/value type parameters");
		assertContains(iMapLines, "virtual std::shared_ptr<__hxhx_iterator<K>> keys() = 0;",
			"C++ IMap-like interfaces should declare keys for MapKeyValueIterator");
		assertContains(iMapLines, "virtual std::shared_ptr<KeyValueIterator> keyValueIterator() = 0;",
			"C++ IMap-like interfaces should preserve class-like iterator return declarations");
		final missingIMapLines = @:privateAccess backend.cpp.CppTargetCore.renderMissingInterfaceDeclaration("IMap").join("\n");
		assertContains(missingIMapLines, "template<typename K, typename V>\nstruct IMap {",
			"C++ target-owned IMap fallback declarations should preserve key/value type parameters");
		assertContains(missingIMapLines, "virtual std::optional<V> get(K k) = 0;",
			"C++ target-owned IMap fallback declarations should not collapse map get values to String");
		assertContains(missingIMapLines, "virtual std::shared_ptr<IMap<K, V>> copy() = 0;",
			"C++ target-owned IMap fallback copy declarations should keep the generic map surface");
		final hashMapAbstract = new HxClassDecl("HashMap", false, [], [], "", ["__hxhx_abstract", "__hxhx_abstract_underlying=HashMapData<K,V>"]);
		final hashMapParams = @:privateAccess backend.cpp.CppTargetCore.genericClassTemplateParams(hashMapAbstract);
		assertTrue(hashMapParams.length == 2 && hashMapParams[0] == "K" && hashMapParams[1] == "V",
			"C++ generic abstract helpers such as HashMap should infer template parameters from their abstract underlying type");
		final packagedIMapNames = new StringMap<Bool>();
		final packagedIMapClasses = new StringMap<HxClassDecl>();
		final packagedIMap = new HxClassDecl("haxe.Constraints.IMap", false, [], [], "", null, true);
		@:privateAccess backend.cpp.CppTargetCore.addClassLookupAliases("haxe.Constraints.IMap", packagedIMap, packagedIMapNames, packagedIMapClasses);
		assertTrue(packagedIMapNames.exists("haxe_Constraints_IMap") && packagedIMapNames.exists("IMap"),
			"C++ class lookup should alias package-qualified interfaces by their rendered basename");
		assertTrue(packagedIMapClasses.get("IMap") == packagedIMap,
			"C++ class lookup basename aliases should let missing-interface guards see the real packaged interface");
		final emptyIMapLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperClass(new HxClassDecl("IMap", false, [], [], "", null, true), {
				names: iMapNames,
				byName: iMapClasses
			}).join("\n");
		assertTrue(emptyIMapLines.length == 0,
			"C++ empty parsed IMap placeholders should not emit an empty struct that conflicts with target-owned IMap declarations");
		final emptyIMapClassLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperClass(new HxClassDecl("IMap", false, [], []), {
				names: iMapNames,
				byName: iMapClasses
			}).join("\n");
		assertTrue(emptyIMapClassLines.length == 0,
			"C++ empty parsed IMap classes should not emit an empty struct that conflicts with target-owned IMap declarations");
		final iMapImplementingClass = new HxClassDecl("StringMap", false, [
			new HxFunctionDecl("copy", Public, false, [], "StringMap", [SReturn(EThis, HxPos.unknown())], "")
		], [], "", null, false, ["haxe.Constraints.IMap"]);
		final iMapImplementingNames = new StringMap<Bool>();
		iMapImplementingNames.set("StringMap", true);
		iMapImplementingNames.set("IMap", true);
		final iMapImplementingClasses = new StringMap<HxClassDecl>();
		iMapImplementingClasses.set("StringMap", iMapImplementingClass);
		iMapImplementingClasses.set("IMap", iMapInterface);
		final iMapImplementingLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(iMapImplementingClass, {
			names: iMapImplementingNames,
			byName: iMapImplementingClasses
		}).join("\n");
		assertContains(iMapImplementingLines, "struct StringMap {", "C++ IMap implementors should still render as helpers");
		assertTrue(iMapImplementingLines.indexOf(": public IMap") < 0,
			"C++ IMap is a target-owned generic surface and should not be forced into one nominal C++ base");
		final assertRaisesUse = new HxFunctionDecl("use", Public, true, [
			new HxFunctionArg("ex", "Dynamic", NoDefault, false, false),
			new HxFunctionArg("msg", "String", NoDefault, false, false)
		], "Bool", [SReturn(EBool(true), HxPos.unknown())], "");
		final assertRaisesLike = new HxFunctionDecl("raisesLike", Public, true, [], "Bool", [
			STry(SThrow(EString("boom"), HxPos.unknown()), [
				{
					name: "ex",
					typeHint: "Dynamic",
					body: SBlock([
						SVar("msg", "String", EBinop("+", EString("caught:"), EIdent("ex")), HxPos.unknown()),
						SReturn(ECall(EIdent("use"), [EIdent("ex"), EIdent("msg")]), HxPos.unknown())
					], HxPos.unknown())
				}
			], HxPos.unknown())
		], "");
		final assertRaisesOwner = new HxClassDecl("Assert", false, [assertRaisesUse, assertRaisesLike], []);
		final assertRaisesNames = new StringMap<Bool>();
		assertRaisesNames.set("Assert", true);
		final assertRaisesClasses = new StringMap<HxClassDecl>();
		assertRaisesClasses.set("Assert", assertRaisesOwner);
		final assertRaisesLookup = {names: assertRaisesNames, byName: assertRaisesClasses};
		final assertRaisesLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(assertRaisesLike, assertRaisesOwner, assertRaisesLookup)
			.join("\n");
		assertContains(assertRaisesLines, "std::string ex = std::string();",
			"C++ catch blocks should bind the Haxe catch variable before rendering catch-body references");
		assertContains(assertRaisesLines, "return use(ex, msg);", "C++ catch-body calls should keep using the declared catch variable name");
		final assertStringSequenceLike = new HxFunctionDecl("stringSequenceLike", Public, true,
			[new HxFunctionArg("value", "String", NoDefault, false, false)], "Bool", [
				SIf(EBool(false), SReturn(EBool(false), HxPos.unknown()), null, HxPos.unknown()),
				SIf(EBinop("is", EIdent("value"), EIdent("String")), SReturn(EBool(true), HxPos.unknown()), null, HxPos.unknown()),
				SReturn(EBool(false), HxPos.unknown())
			], "");
		final assertStringSequenceLikeLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperMethod(assertStringSequenceLike, assertOwner, assertLookup).join("\n");
		assertContains(assertStringSequenceLikeLines, "if (false) {", "C++ if statements should not emit `if false {`");
		assertContains(assertStringSequenceLikeLines, "if (__hxhx_is_type(value, \"String\")) {",
			"C++ if statements should parenthesize raw helper-call conditions");
		assertTrue(assertStringSequenceLikeLines.indexOf("if false {") < 0, "C++ if statements must use valid C-style condition syntax");
		final assertWarnScope = @:privateAccess backend.cpp.CppTargetCore.renderScope(assertOwner, assertLookup, "std::string");
		assertWarnScope.localTypes.set("results", "std::shared_ptr<ResultSink>");
		assertWarnScope.localTypes.set("msg", "std::string");
		final assertWarnAdd:HxExpr = ECall(EField(EIdent("results"), "add"), [ECall(EEnumValue("Warning"), [EIdent("msg")])]);
		final assertWarnAddString = @:privateAccess backend.cpp.CppTargetCore.stringExpr(assertWarnAdd, assertWarnScope);
		assertContains(assertWarnAddString, "__hxhx_stringify(results->add(([&]() {",
			"C++ unknown string-context calls should use target-owned stringify instead of assuming numeric std::to_string");
		assertContains(assertWarnAddString, "return std::string(\"Warning\");",
			"C++ enum-tag arguments inside erased string-context calls should preserve their string payload");
		assertTrue(assertWarnAddString.indexOf("std::to_string(results->add") < 0,
			"C++ Assert.warn-like results.add calls should not become std::to_string(std::string)");
		final typedEnumArg = @:privateAccess backend.cpp.CppTargetCore.valueExprForExpectedType(ECall(EEnumValue("Warning"), [EIdent("msg")]),
			"std::shared_ptr<Assertation>", assertWarnScope);
		assertContains(typedEnumArg, "return std::make_shared<Assertation>();",
			"C++ typed enum-constructor arguments should construct the expected enum carrier instead of a tag string");
		assertTrue(typedEnumArg.indexOf("return std::string(\"Warning\")") < 0,
			"C++ typed enum-constructor arguments should not leak tag strings into shared_ptr enum carriers");
		assertWarnScope.localTypes.set("typedResults", "std::shared_ptr<List<std::shared_ptr<Assertation>>>");
		final typedAssertWarnAdd:HxExpr = ECall(EField(EIdent("typedResults"), "add"), [ECall(EEnumValue("Warning"), [EIdent("msg")])]);
		final typedAssertWarnAddExpr = @:privateAccess backend.cpp.CppTargetCore.renderExpr(typedAssertWarnAdd, assertWarnScope);
		assertContains(typedAssertWarnAddExpr, "typedResults->add(([&]() {", "C++ List<T>.add should render arguments with the list element expected type");
		assertContains(typedAssertWarnAddExpr, "return std::make_shared<Assertation>();",
			"C++ List<Assertation>.add should receive an Assertation carrier, not a string tag");
		assertTrue(typedAssertWarnAddExpr.indexOf("return std::string(\"Warning\")") < 0,
			"C++ typed List enum arguments should not preserve the erased string-tag lowering");
		final lambdaStringContext = @:privateAccess backend.cpp.CppTargetCore.stringExpr(ECall(ELambda(["t"],
			ETernary(EBinop("==", EIdent("t"), EInt(0)), EString("7"), ECall(EField(EIdent("Std"), "string"), [EIdent("t")]))), [EInt(1)]),
			assertWarnScope);
		assertContains(lambdaStringContext, "([&](auto t) { return", "C++ string contexts should preserve immediate lambda calls");
		assertTrue(lambdaStringContext.indexOf("std::to_string(([&]") < 0,
			"C++ string-returning immediate lambda calls should not be wrapped in std::to_string");
		final assertCreateAsyncLike = new HxFunctionDecl("createAsyncLike", Public, true, [], "", [SReturn(ELambda([], ENull), HxPos.unknown())], "");
		final assertCreateEventLike = new HxFunctionDecl("createEventLike", Public, true, [], "", [SReturn(ELambda(["e"], ENull), HxPos.unknown())], "");
		final assertCreateLambdaOwner = new HxClassDecl("Assert", false, [assertCreateAsyncLike, assertCreateEventLike], []);
		final assertCreateLambdaNames = new StringMap<Bool>();
		assertCreateLambdaNames.set("Assert", true);
		final assertCreateLambdaClasses = new StringMap<HxClassDecl>();
		assertCreateLambdaClasses.set("Assert", assertCreateLambdaOwner);
		final assertCreateLambdaLookup = {names: assertCreateLambdaNames, byName: assertCreateLambdaClasses};
		final assertCreateAsyncLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperMethod(assertCreateAsyncLike, assertCreateLambdaOwner, assertCreateLambdaLookup).join("\n");
		final assertCreateEventLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperMethod(assertCreateEventLike, assertCreateLambdaOwner, assertCreateLambdaLookup).join("\n");
		assertContains(assertCreateAsyncLines, "static auto createAsyncLike() {",
			"C++ lambda-returning helpers with erased return hints should infer auto instead of std::string");
		assertContains(assertCreateAsyncLines, "return [&]() { return nullptr; };", "C++ lambda-returning helpers should return the lambda value directly");
		assertContains(assertCreateEventLines, "static auto createEventLike() {",
			"C++ one-arg lambda-returning helpers with erased return hints should infer auto instead of std::string");
		assertContains(assertCreateEventLines, "return [&](auto e) { return nullptr; };", "C++ event-lambda helpers should return the lambda value directly");
		assertTrue(assertCreateAsyncLines.indexOf("std::to_string([&]()") < 0, "C++ createAsync-like helpers should not stringify returned lambdas");
		assertTrue(assertCreateEventLines.indexOf("std::to_string([&](auto e)") < 0, "C++ createEvent-like helpers should not stringify returned lambdas");
		final typeHelper = new HxClassDecl("Type", false, [
			new HxFunctionDecl("getClass", Public, true, [new HxFunctionArg("value", "Dynamic", NoDefault, false, false)], "Class<Dynamic>", [], ""),
			new HxFunctionDecl("getEnum", Public, true, [new HxFunctionArg("value", "Dynamic", NoDefault, false, false)], "Enum<Dynamic>", [], "")
		], []);
		final classValue = new HxClassDecl("Class", false, [], []);
		final enumValue = new HxClassDecl("Enum", false, [], []);
		final typeStringOwner = new HxClassDecl("TypeStringOwner", false, [], []);
		final typeStringNames = new StringMap<Bool>();
		for (name in ["TypeStringOwner", "Type", "Class", "Enum"])
			typeStringNames.set(name, true);
		final typeStringClasses = new StringMap<HxClassDecl>();
		typeStringClasses.set("TypeStringOwner", typeStringOwner);
		typeStringClasses.set("Type", typeHelper);
		typeStringClasses.set("Class", classValue);
		typeStringClasses.set("Enum", enumValue);
		final typeStringLookup = {names: typeStringNames, byName: typeStringClasses};
		final typeHelperLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(HxClassDecl.getFunctions(typeHelper)[0], typeHelper,
			typeStringLookup)
			.join("\n");
		assertContains(typeHelperLines, "template<typename TValue>\n  static std::shared_ptr<Class> getClass(const TValue& value)",
			"C++ Type.getClass should accept erased values through a template boundary");
		final typeStringMethod = new HxFunctionDecl("typeToStringLike", Public, true, [new HxFunctionArg("value", "Dynamic", NoDefault, false, false)],
			"String", [
				SVar("cls", "Dynamic", ENull, HxPos.unknown()),
				SExpr(EBinop("=", EIdent("cls"), ECall(EField(EIdent("Type"), "getClass"), [EIdent("value")])), HxPos.unknown()),
				SVar("enm", "Dynamic", ENull, HxPos.unknown()),
				SExpr(EBinop("=", EIdent("enm"), ECall(EField(EIdent("Type"), "getEnum"), [EIdent("value")])), HxPos.unknown()),
				SReturn(EBinop("+", ECall(EField(EIdent("Type"), "getClassName"), [EIdent("cls")]),
					ECall(EField(EIdent("Type"), "getEnumName"), [EIdent("enm")])),
					HxPos.unknown())
			], "");
		final typeStringLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperMethod(typeStringMethod, typeStringOwner, typeStringLookup).join("\n");
		assertContains(typeStringLines, "std::shared_ptr<Class> cls = nullptr;",
			"C++ Dynamic locals assigned Type.getClass results should declare Class meta-value storage");
		assertContains(typeStringLines, "cls = Type::getClass(value);", "C++ Class meta-value locals should accept Type.getClass assignments");
		assertContains(typeStringLines, "std::shared_ptr<Enum> enm = nullptr;",
			"C++ Dynamic locals assigned Type.getEnum results should declare Enum meta-value storage");
		assertContains(typeStringLines, "enm = Type::getEnum(value);", "C++ Enum meta-value locals should accept Type.getEnum assignments");
		assertTrue(typeStringLines.indexOf("std::string cls") < 0, "C++ Type.getClass locals should not be declared as std::string");
		assertTrue(typeStringLines.indexOf("std::string enm") < 0, "C++ Type.getEnum locals should not be declared as std::string");
		final heteroTypeStringMethod = new HxFunctionDecl("typeToStringHetero", Public, true,
			[new HxFunctionArg("value", "Dynamic", NoDefault, false, false)], "String", [
				STry(SBlock([
					SVar("_t", "", ECall(EField(EIdent("Type"), "getClass"), [EIdent("value")]), HxPos.unknown()),
					SIf(EBinop("!=", EIdent("_t"), ENull), SExpr(EBinop("=", EIdent("value"), EIdent("_t")), HxPos.unknown()), null, HxPos.unknown())
				], HxPos.unknown()), [
					{
						name: "e",
						typeHint: "Dynamic",
						body: SBlock([], HxPos.unknown())
					}
				], HxPos.unknown()),
				STry(SBlock([
					SVar("_t2", "", ECall(EField(EIdent("Type"), "getEnum"), [EIdent("value")]), HxPos.unknown()),
					SIf(EBinop("!=", EIdent("_t2"), ENull), SExpr(EBinop("=", EIdent("value"), EIdent("_t2")), HxPos.unknown()), null, HxPos.unknown())
				], HxPos.unknown()), [
					{
						name: "e",
						typeHint: "Dynamic",
						body: SBlock([], HxPos.unknown())
					}
				], HxPos.unknown()),
				SReturn(ECall(EField(EIdent("Type"), "getClassName"), [EIdent("value")]), HxPos.unknown())
			], "");
		final heteroTypeStringLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperMethod(heteroTypeStringMethod, typeStringOwner, typeStringLookup).join("\n");
		assertContains(heteroTypeStringLines, "static std::string typeToStringHetero(std::any value)",
			"C++ Dynamic parameters reassigned across Class/Enum meta-values should use erased std::any storage");
		assertContains(heteroTypeStringLines, "value = _t;", "C++ erased Dynamic parameters should accept Class meta-value reassignment");
		assertContains(heteroTypeStringLines, "value = _t2;", "C++ erased Dynamic parameters should accept Enum meta-value reassignment");
		assertTrue(heteroTypeStringLines.indexOf("static std::string typeToStringHetero(std::string value)") < 0,
			"C++ heterogeneously reassigned Dynamic parameters should not remain std::string");
		final metaObject = new HxClassDecl("MetaObject", false, [], [
			new HxFieldDecl("fields", Public, false, "Dynamic<Dynamic<Null<Array<String>>>>", null),
			new HxFieldDecl("statics", Public, false, "Dynamic<Dynamic<Null<Array<String>>>>", null),
			new HxFieldDecl("obj", Public, false, "Dynamic<Null<Array<String>>>", null)
		]);
		final metaObjectNames = new StringMap<Bool>();
		metaObjectNames.set("MetaObject", true);
		final metaObjectClasses = new StringMap<HxClassDecl>();
		metaObjectClasses.set("MetaObject", metaObject);
		final metaObjectLookup = {names: metaObjectNames, byName: metaObjectClasses};
		final metaObjectLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperClass(metaObject, metaObjectLookup).join("\n");
		assertContains(metaObjectLines, "std::any fields = std::any();",
			"C++ generic Dynamic metadata fields should use erased target storage instead of an undefined Dynamic template");
		assertContains(metaObjectLines, "std::any obj = std::any();", "C++ nested generic Dynamic metadata fields should use erased target storage");
		assertTrue(metaObjectLines.indexOf("Dynamic<") < 0, "C++ generic Dynamic type hints must not emit fake Dynamic template classes");
		final metaHelper = new HxClassDecl("Meta", false, [
			new HxFunctionDecl("getMeta", Public, true, [new HxFunctionArg("t", "String", NoDefault, false, false)], "Null<MetaObject>",
				[SReturn(EField(EIdent("t"), "__meta__"), HxPos.unknown())], ""),
			new HxFunctionDecl("getType", Public, true, [new HxFunctionArg("t", "String", NoDefault, false, false)], "Dynamic<Null<Array<String>>>", [
				SVar("meta", "Null<MetaObject>", ENull, HxPos.unknown()),
				SReturn(ETernary(EBinop("||", EBinop("==", EIdent("meta"), ENull), EBool(false)), EAnon([], []), EField(EIdent("meta"), "obj")),
					HxPos.unknown())
			], ""),
			new HxFunctionDecl("getFields", Public, true, [new HxFunctionArg("t", "String", NoDefault, false, false)],
				"Dynamic<Dynamic<Null<Array<String>>>>", [
					SVar("meta", "Null<MetaObject>", ENull, HxPos.unknown()),
					SReturn(ETernary(EBinop("||", EBinop("==", EIdent("meta"), ENull), EBool(false)), EAnon([], []), EField(EIdent("meta"), "fields")),
						HxPos.unknown())
				], ""),
			new HxFunctionDecl("getStatics", Public, true, [new HxFunctionArg("t", "String", NoDefault, false, false)],
				"Dynamic<Dynamic<Null<Array<String>>>>", [
					SVar("meta", "Null<MetaObject>", ENull, HxPos.unknown()),
					SReturn(ETernary(EBinop("||", EBinop("==", EIdent("meta"), ENull), EBool(false)), EAnon([], []), EField(EIdent("meta"), "statics")),
						HxPos.unknown())
				], "")
		], []);
		metaObjectNames.set("Meta", true);
		for (name in ["Type", "Class"])
			metaObjectNames.set(name, true);
		metaObjectClasses.set("Meta", metaHelper);
		metaObjectClasses.set("Type", typeHelper);
		metaObjectClasses.set("Class", classValue);
		final getMetaLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperMethod(HxClassDecl.getFunctions(metaHelper)[0], metaHelper, metaObjectLookup).join("\n");
		final getTypeLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperMethod(HxClassDecl.getFunctions(metaHelper)[1], metaHelper, metaObjectLookup).join("\n");
		final getFieldsLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperMethod(HxClassDecl.getFunctions(metaHelper)[2], metaHelper, metaObjectLookup).join("\n");
		final metaFieldsProbe = new HxFunctionDecl("getIgnoredLike", Public, false, [
			new HxFunctionArg("target", "String", NoDefault, false, false),
			new HxFunctionArg("method", "String", NoDefault, false, false)
		], "Dynamic", [
			SVar("metas", "Dynamic", ECall(EField(EIdent("Meta"), "getFields"), [ECall(EField(EIdent("Type"), "getClass"), [EIdent("target")])]),
				HxPos.unknown()),
			SVar("metasForTestMetas", "", ECall(EField(EIdent("Reflect"), "getProperty"), [EIdent("metas"), EIdent("method")]), HxPos.unknown()),
			SIf(ECall(EField(EIdent("Reflect"), "hasField"), [EIdent("metasForTestMetas"), EString("Ignored")]),
				SVar("ignoredArgs", "Array<String>", ECall(EField(EIdent("Reflect"), "getProperty"), [EIdent("metasForTestMetas"), EString("Ignored")]),
					HxPos.unknown()),
				null, HxPos.unknown()),
			SReturn(EIdent("metasForTestMetas"), HxPos.unknown())
		], "");
		final metaProbeOwner = new HxClassDecl("MetaProbe", false, [metaFieldsProbe], []);
		metaObjectNames.set("MetaProbe", true);
		metaObjectClasses.set("MetaProbe", metaProbeOwner);
		final metaProbeLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperMethod(metaFieldsProbe, metaProbeOwner, metaObjectLookup).join("\n");
		assertContains(getMetaLines, "return __hxhx_meta_get_as<std::shared_ptr<MetaObject>>(t);",
			"C++ haxe.rtti.Meta.getMeta should lower through target-owned metadata support instead of direct __meta__ field reads");
		assertTrue(getMetaLines.indexOf("t.__meta__") < 0, "C++ haxe.rtti.Meta.getMeta must not emit invalid std::string.__meta__ reads");
		assertContains(getTypeLines, "template<typename T>", "C++ Dynamic metadata accessors should accept class/meta values generically");
		assertContains(getTypeLines, "static std::any getType(const T& t)", "C++ Dynamic metadata return helpers should keep erased std::any return types");
		assertContains(getTypeLines, "return __hxhx_meta_section_as<std::any>(t, std::string(\"obj\"));",
			"C++ haxe.rtti.Meta.getType should lower through target-owned metadata support");
		assertContains(getFieldsLines, "return __hxhx_meta_section_as<std::any>(t, std::string(\"fields\"));",
			"C++ haxe.rtti.Meta.getFields should lower through target-owned metadata support");
		assertContains(metaProbeLines, "std::any metas = Meta::getFields(Type::getClass(target));",
			"C++ haxe.rtti.Meta.getFields should accept Type.getClass metadata values at call sites");
		assertContains(metaProbeLines, "auto metasForTestMetas = __hxhx_reflect_get_property_any(metas, std::string(method));",
			"C++ Reflect.getProperty should accept erased metadata maps without requiring a std::string receiver");
		assertContains(metaProbeLines, "if (__hxhx_reflect_has_field_any(metasForTestMetas, std::string(\"Ignored\")))",
			"C++ Reflect.hasField should accept erased metadata maps without requiring a std::string receiver");
		assertContains(metaProbeLines,
			"std::vector<std::string> ignoredArgs = __hxhx_string_vector_any(__hxhx_reflect_get_property_any(metasForTestMetas, std::string(\"Ignored\")));",
			"C++ erased metadata array property extraction should cast through target-owned vector support");
		assertTrue(metaProbeLines.indexOf("Reflect::getProperty(metas") < 0,
			"C++ erased metadata map property access must not call the std::string Reflect helper");
		assertTrue(metaProbeLines.indexOf("Reflect::hasField(metasForTestMetas") < 0,
			"C++ erased metadata map field probing must not call the std::string Reflect helper");
		assertTrue(getTypeLines.indexOf("static_cast<int>(") < 0, "C++ std::any returns must not use numeric fallback casts");
		assertTrue(getFieldsLines.indexOf("static_cast<int>(") < 0, "C++ std::any field returns must not use numeric fallback casts");
		final optionalStringCtor = new HxClassDecl("FixtureLike", false, [
			new HxFunctionDecl("new", Public, false, [
				new HxFunctionArg("target", "String", NoDefault, false, false),
				new HxFunctionArg("setup", "String", NoDefault, true, false)
			], "", [
				SExpr(EBinop("=", EField(EThis, "target"), EIdent("target")), HxPos.unknown()),
				SExpr(EBinop("=", EField(EThis, "setup"), EIdent("setup")), HxPos.unknown())
			], "")
		], [
			new HxFieldDecl("target", Public, false, "String", null),
			new HxFieldDecl("setup", Public, false, "String", null)
		]);
		final optionalStringNames = new StringMap<Bool>();
		optionalStringNames.set("FixtureLike", true);
		final optionalStringClasses = new StringMap<HxClassDecl>();
		optionalStringClasses.set("FixtureLike", optionalStringCtor);
		final optionalStringCtorLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperClass(optionalStringCtor, {names: optionalStringNames, byName: optionalStringClasses}).join("\n");
		assertContains(optionalStringCtorLines,
			"FixtureLike(std::string target, std::optional<std::string> setup = std::nullopt) : target(target), setup(setup.value_or(std::string())) {",
			"C++ constructor initializer lists should unwrap optional args when assigning to non-optional fields");
		assertTrue(optionalStringCtorLines.indexOf("setup(setup)") < 0,
			"C++ constructor initializer lists must not initialize std::string fields directly from std::optional<std::string>");
		final assertStringScope = @:privateAccess backend.cpp.CppTargetCore.renderScope(assertOwner, assertLookup, "std::string");
		assertStringScope.localTypes.set("i", "int");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.stringExpr(EIdent("i"), assertStringScope) == "std::to_string(i)",
			"C++ string contexts should stringify integer locals with std::to_string, not std::string(i)");
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
		final importExprClass = new HxClassDecl("ImportExpr", false, [], []);
		final typePathClass = new HxClassDecl("TypePath", false, [], []);
		final typeDefinitionClass = new HxClassDecl("TypeDefinition", false, [], []);
		final defineModuleOwner = new HxClassDecl("DefineModuleOwner", false, [
			new HxFunctionDecl("defineModuleLike", Public, true, [
				new HxFunctionArg("modulePath", "String", NoDefault, false, false),
				new HxFunctionArg("types", "Array<TypeDefinition>", NoDefault, false, false),
				new HxFunctionArg("imports", "Array<ImportExpr>", NoDefault, true, false),
				new HxFunctionArg("usings", "Array<TypePath>", NoDefault, true, false)
			], "Void", [
				SIf(EBinop("==", EIdent("imports"), ENull), SExpr(EBinop("=", EIdent("imports"), EArrayDecl([])), HxPos.unknown()), null, HxPos.unknown()),
				SIf(EBinop("==", EIdent("usings"), ENull), SExpr(EBinop("=", EIdent("usings"), EArrayDecl([])), HxPos.unknown()), null, HxPos.unknown())
			], "")
		], []);
		final defineModuleNames = new StringMap<Bool>();
		for (name in ["DefineModuleOwner", "ImportExpr", "TypePath", "TypeDefinition"])
			defineModuleNames.set(name, true);
		final defineModuleClasses = new StringMap<HxClassDecl>();
		defineModuleClasses.set("DefineModuleOwner", defineModuleOwner);
		defineModuleClasses.set("ImportExpr", importExprClass);
		defineModuleClasses.set("TypePath", typePathClass);
		defineModuleClasses.set("TypeDefinition", typeDefinitionClass);
		final defineModuleLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperMethod(HxClassDecl.getFunctions(defineModuleOwner)[0], defineModuleOwner, {
				names: defineModuleNames,
				byName: defineModuleClasses
			}).join("\n");
		assertContains(defineModuleLines, "imports = std::vector<std::shared_ptr<ImportExpr>>{};",
			"C++ optional vector assignments should type empty array RHS values from the optional payload type");
		assertContains(defineModuleLines, "usings = std::vector<std::shared_ptr<TypePath>>{};",
			"C++ optional vector assignments should not fall back to std::vector<int> for empty arrays");
		assertTrue(defineModuleLines.indexOf("imports.value() = std::vector<int>{}") < 0,
			"C++ optional vector defaulting should not mutate value() with an int-vector fallback");
		assertTrue(defineModuleLines.indexOf("usings.value() = std::vector<int>{}") < 0,
			"C++ optional vector defaulting should not reproduce the remote Gate3 compile failure");
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
		assertContains(defaultBoolLines, "static bool exceptionStackLike(bool fullStack = false) {",
			"C++ default false arguments without explicit type hints should infer bool and preserve the default value");
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
		final typeClass = new HxClassDecl("Type", false, [], []);
		final typeParamClass = new HxClassDecl("TypeParam", false, [], []);
		final typeToolsOwner = new HxClassDecl("TypeToolsOwner", false, [], []);
		final typeToolsNames = new StringMap<Bool>();
		for (name in ["Type", "TypeParam", "TypeToolsOwner"])
			typeToolsNames.set(name, true);
		final typeToolsClasses = new StringMap<HxClassDecl>();
		typeToolsClasses.set("Type", typeClass);
		typeToolsClasses.set("TypeParam", typeParamClass);
		typeToolsClasses.set("TypeToolsOwner", typeToolsOwner);
		typeToolsClasses.set("TypePath", typePathClass);
		final impossibleEnumPayloadMethod = new HxFunctionDecl("toTypeParamLike", Public, true, [new HxFunctionArg("type", "Type", NoDefault, false, false)],
			"TypeParam", [
				SReturn(ESwitch(EIdent("type"), [PEnumExtract("TInst", [PUnsupportedGuard(PBind("e")), PWildcard]), PWildcard],
					[ECall(EEnumValue("TPExpr"), [EIdent("e")]), EEnumValue("TPType")]),
					HxPos.unknown())
			], "");
		final impossibleEnumPayloadLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(impossibleEnumPayloadMethod, typeToolsOwner, {
			names: typeToolsNames,
			byName: typeToolsClasses
		}).join("\n");
		assertTrue(impossibleEnumPayloadLines.indexOf("auto __hxhx_enum_arg_0 = e;") < 0,
			"C++ impossible enum-pattern branches should not render unbound enum-constructor payload references");
		assertContains(impossibleEnumPayloadLines, "return std::make_shared<TypeParam>();",
			"C++ switch expressions should keep the reachable default branch when impossible enum payload branches are skipped");
		final baseTypeClass = new HxClassDecl("BaseType", false, [], [new HxFieldDecl("module", Public, false, "String", null)]);
		typeToolsNames.set("BaseType", true);
		typeToolsNames.set("TypePath", true);
		typeToolsClasses.set("BaseType", baseTypeClass);
		final typePathCaptureMethod = new HxFunctionDecl("toTypePathLike", Public, true, [new HxFunctionArg("baseType", "BaseType", NoDefault, false, false)],
			"TypePath", [
				SReturn(ECall(ELambda(["module"], EIdent("pack")), [EField(EIdent("baseType"), "module")]), HxPos.unknown())
			], "");
		final typePathCaptureLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(typePathCaptureMethod, typeToolsOwner, {
			names: typeToolsNames,
			byName: typeToolsClasses
		}).join("\n");
		assertTrue(typePathCaptureLines.indexOf("return pack;") < 0, "C++ TypePath-returning continuation lambdas should not emit unbound pack references");
		assertContains(typePathCaptureLines, "return nullptr;",
			"C++ TypePath-returning unsupported continuation shapes should lower to a neutral TypePath reference");
		final typeStringSwitchOwner = new HxClassDecl("TypeTools", false, [], []);
		final typeStringSwitchClass = new HxClassDecl("Type", false, [], []);
		final typeStringSwitchNames = new StringMap<Bool>();
		for (name in ["TypeTools", "Type"])
			typeStringSwitchNames.set(name, true);
		final typeStringSwitchClasses = new StringMap<HxClassDecl>();
		typeStringSwitchClasses.set("TypeTools", typeStringSwitchOwner);
		typeStringSwitchClasses.set("Type", typeStringSwitchClass);
		final typeToolsGetClassLike = new HxFunctionDecl("getClassLike", Public, true, [new HxFunctionArg("t", "Type", NoDefault, false, false)], "String", [
			SReturn(ETernary(EBinop("==", EIdent("t"), ENull), ENull,
				ESwitch(ECall(EIdent("follow"), [EIdent("t")]), [PEnumExtract("TInst", [PBind("c"), PWildcard]), PWildcard],
					[EIdent("c"), ECall(EIdent("__hxhx_throw"), [EString("Class instance expected")])])),
				HxPos.unknown())
		], "");
		final typeToolsGetEnumLike = new HxFunctionDecl("getEnumLike", Public, true, [new HxFunctionArg("t", "Type", NoDefault, false, false)], "String", [
			SReturn(ETernary(EBinop("==", EIdent("t"), ENull), ENull,
				ESwitch(ECall(EIdent("follow"), [EIdent("t")]), [PEnumExtract("TEnum", [PBind("e"), PWildcard]), PWildcard],
					[EIdent("e"), ECall(EIdent("__hxhx_throw"), [EString("Enum instance expected")])])),
				HxPos.unknown())
		], "");
		final typeToolsGetClassLikeLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(typeToolsGetClassLike, typeStringSwitchOwner, {
			names: typeStringSwitchNames,
			byName: typeStringSwitchClasses
		}).join("\n");
		final typeToolsGetEnumLikeLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(typeToolsGetEnumLike, typeStringSwitchOwner, {
			names: typeStringSwitchNames,
			byName: typeStringSwitchClasses
		}).join("\n");
		assertContains(typeToolsGetClassLikeLines, "([&]() -> std::string {",
			"C++ TypeTools.getClass-like switch expressions should receive the String return type");
		assertContains(typeToolsGetEnumLikeLines, "([&]() -> std::string {",
			"C++ TypeTools.getEnum-like switch expressions should receive the String return type");
		assertTrue(typeToolsGetClassLikeLines.indexOf("std::to_string(((t == nullptr)") < 0,
			"C++ TypeTools.getClass-like ternaries should not wrap string-typed switches in std::to_string");
		assertTrue(typeToolsGetEnumLikeLines.indexOf("std::to_string(((t == nullptr)") < 0,
			"C++ TypeTools.getEnum-like ternaries should not wrap string-typed switches in std::to_string");
		assertTrue(typeToolsGetClassLikeLines.indexOf("return c.get();") < 0,
			"C++ TypeTools.getClass-like branches should not return pointer payloads from string switches");
		assertTrue(typeToolsGetEnumLikeLines.indexOf("return e.get();") < 0,
			"C++ TypeTools.getEnum-like branches should not return pointer payloads from string switches");
		final typeToolsTraversalOwner = new HxClassDecl("TypeTools", false, [
			new HxFunctionDecl("map", Public, true, [
				new HxFunctionArg("t", "Type", NoDefault, false, false),
				new HxFunctionArg("f", "Type->Type", NoDefault, false, false)
			], "Type", [
				SReturn(ESwitch(EIdent("t"), [PEnumExtract("TMono", [PBind("tm")]), PWildcard], [
					ECall(EIdent("f"), [ECall(EField(EIdent("tm"), "get"), [])]),
					ECall(EEnumValue("TEnum"), [EIdent("t"), ECall(EField(EIdent("t"), "map"), [EIdent("f")])])
				]), HxPos.unknown())
			], ""),
			new HxFunctionDecl("iter", Public, true, [
				new HxFunctionArg("t", "Type", NoDefault, false, false),
				new HxFunctionArg("f", "Type->Void", NoDefault, false, false)
			], "Void", [
				SSwitch(EIdent("t"), [PEnumExtract("TInst", [PWildcard, PBind("tl")]), PWildcard], [
					SForIn("next", EIdent("tl"), SExpr(ECall(EIdent("f"), [EIdent("next")]), HxPos.unknown()), HxPos.unknown()),
					SBlock([], HxPos.unknown())
				], HxPos.unknown())
			], "")
		], []);
		final typeToolsTraversalNames = new StringMap<Bool>();
		for (name in ["TypeTools", "Type"])
			typeToolsTraversalNames.set(name, true);
		final typeToolsTraversalClasses = new StringMap<HxClassDecl>();
		typeToolsTraversalClasses.set("TypeTools", typeToolsTraversalOwner);
		typeToolsTraversalClasses.set("Type", typeStringSwitchClass);
		final typeToolsMapLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(HxClassDecl.getFunctions(typeToolsTraversalOwner)[0],
			typeToolsTraversalOwner, {
				names: typeToolsTraversalNames,
				byName: typeToolsTraversalClasses
			})
			.join("\n");
		final typeToolsIterLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(HxClassDecl.getFunctions(typeToolsTraversalOwner)[1],
			typeToolsTraversalOwner, {
				names: typeToolsTraversalNames,
				byName: typeToolsTraversalClasses
			})
			.join("\n");
		assertContains(typeToolsMapLines,
			"static std::shared_ptr<Type> map(std::shared_ptr<Type> t, std::function<std::shared_ptr<Type>(std::shared_ptr<Type>)> f)",
			"C++ TypeTools.map should preserve the macro Type traversal helper signature");
		assertContains(typeToolsMapLines, "return t;", "C++ TypeTools.map should typecheck as a bounded identity helper in the C++ MVP");
		assertTrue(typeToolsMapLines.indexOf(".map(f)") < 0, "C++ TypeTools.map should not emit unsupported map calls on Type payload placeholders");
		assertTrue(typeToolsMapLines.indexOf("tm.get()") < 0, "C++ TypeTools.map should not pass raw Type pointers to typed callbacks");
		assertContains(typeToolsIterLines, "static void iter(std::shared_ptr<Type> t, std::function<void(std::shared_ptr<Type>)> f)",
			"C++ TypeTools.iter should preserve the macro Type traversal helper signature");
		assertContains(typeToolsIterLines, "(void)t;", "C++ TypeTools.iter should consume the Type argument in the bounded helper");
		assertContains(typeToolsIterLines, "(void)f;", "C++ TypeTools.iter should consume the callback argument in the bounded helper");
		assertTrue(typeToolsIterLines.indexOf("for (auto") < 0, "C++ TypeTools.iter should not iterate over Type payload placeholders");
		final classTypeCarrier = new HxClassDecl("ClassType", false, [], [
			new HxFieldDecl("fields", Public, false, "Ref<Array<ClassField>>", null),
			new HxFieldDecl("statics", Public, false, "Ref<Array<ClassField>>", null),
			new HxFieldDecl("superClass", Public, false, "Null<{t:Ref<ClassType>}>", null)
		]);
		final classFieldCarrier = new HxClassDecl("ClassField", false, [], [new HxFieldDecl("name", Public, false, "String", null)]);
		final typeToolsFindFieldOwner = new HxClassDecl("TypeTools", false, [
			new HxFunctionDecl("findField", Public, true, [
				new HxFunctionArg("c", "ClassType", NoDefault, false, false),
				new HxFunctionArg("name", "String", NoDefault, false, false),
				new HxFunctionArg("isStatic", "Bool", Default(EBool(false)), true, false)
			], "ClassField", [
				SVar("field", "",
					ECall(EField(ECall(EField(ETernary(EIdent("isStatic"), EField(EIdent("c"), "statics"), EField(EIdent("c"), "fields")), "get"), []), "find"),
						[
							ELambda(["field"], EBinop("==", EField(EIdent("field"), "name"), EIdent("name")))
						]), HxPos.unknown()),
				SReturn(ETernary(EBinop("!=", EIdent("field"), ENull), EIdent("field"), ECall(EIdent("findField"), [
					ECall(EField(EField(EIdent("c"), "superClass"), "t"), []),
					EIdent("name"),
					EIdent("isStatic")
				])), HxPos.unknown())
			], "")
		], []);
		final typeToolsFindFieldNames = new StringMap<Bool>();
		for (name in ["TypeTools", "ClassType", "ClassField"])
			typeToolsFindFieldNames.set(name, true);
		final typeToolsFindFieldClasses = new StringMap<HxClassDecl>();
		typeToolsFindFieldClasses.set("TypeTools", typeToolsFindFieldOwner);
		typeToolsFindFieldClasses.set("ClassType", classTypeCarrier);
		typeToolsFindFieldClasses.set("ClassField", classFieldCarrier);
		final typeToolsFindFieldLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(HxClassDecl.getFunctions(typeToolsFindFieldOwner)[0],
			typeToolsFindFieldOwner, {
				names: typeToolsFindFieldNames,
				byName: typeToolsFindFieldClasses
			})
			.join("\n");
		assertContains(typeToolsFindFieldLines,
			"static std::shared_ptr<ClassField> findField(std::shared_ptr<ClassType> c, std::string name, std::optional<bool> isStatic = false)",
			"C++ TypeTools.findField should preserve the macro ClassField lookup helper signature");
		assertContains(typeToolsFindFieldLines, "return nullptr;", "C++ TypeTools.findField should typecheck as a bounded neutral helper in the C++ MVP");
		assertTrue(typeToolsFindFieldLines.indexOf(".get().find") < 0, "C++ TypeTools.findField should not emit unsupported Ref/vector find calls");
		assertTrue(typeToolsFindFieldLines.indexOf("superClass).t") < 0, "C++ TypeTools.findField should not emit optional anonymous field access through .t");
		final complexTypeCarrier = new HxClassDecl("ComplexType", false, [], []);
		final printerComplexTypeOwner = new HxClassDecl("Printer", false, [
			new HxFunctionDecl("printComplexType", Public, false, [new HxFunctionArg("ct", "ComplexType", NoDefault, false, false)], "", [
				SVar("argStr", "", ECall(EField(ECall(EField(EIdent("args"), "map"), [EIdent("printComplexType")]), "join"), [EString(", ")]), HxPos.unknown()),
				SExpr(EBinop("+", EIdent("wrapArgumentsInParentheses"), EIdent("ret")), HxPos.unknown())
			], "")
		], []);
		final printerComplexTypeNames = new StringMap<Bool>();
		for (name in ["Printer", "ComplexType"])
			printerComplexTypeNames.set(name, true);
		final printerComplexTypeClasses = new StringMap<HxClassDecl>();
		printerComplexTypeClasses.set("Printer", printerComplexTypeOwner);
		printerComplexTypeClasses.set("ComplexType", complexTypeCarrier);
		final printerComplexTypeLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(HxClassDecl.getFunctions(printerComplexTypeOwner)[0],
			printerComplexTypeOwner, {
				names: printerComplexTypeNames,
				byName: printerComplexTypeClasses
			})
			.join("\n");
		assertContains(printerComplexTypeLines, "std::string printComplexType(std::shared_ptr<ComplexType> ct)",
			"C++ Printer.printComplexType should stay string-callable even when its parsed body is incomplete");
		assertContains(printerComplexTypeLines, "(void)ct;", "C++ Printer.printComplexType neutral helper should consume its argument");
		assertContains(printerComplexTypeLines, "return std::string();", "C++ Printer.printComplexType neutral helper should return a compile-safe string");
		assertTrue(printerComplexTypeLines.indexOf("args.map") < 0, "C++ Printer.printComplexType should not emit raw Haxe map/join syntax");
		assertTrue(printerComplexTypeLines.indexOf("wrapArgumentsInParentheses") < 0,
			"C++ Printer.printComplexType should not leak undeclared pattern locals from partial raw bodies");
		final fieldCarrier = new HxClassDecl("Field", false, [], []);
		final printerFieldOwner = new HxClassDecl("Printer", false, [
			new HxFunctionDecl("printField", Public, false, [new HxFunctionArg("field", "Field", NoDefault, false, false)], "", [
				SVar("orderAccess", "",
					ELambda(["access"], ECall(EField(EIdent("access"), "filter"), [ELambda(["a"], ECall(EField(EIdent("a"), "match"), [EString("AFinal")]))])),
					HxPos.unknown()),
				SReturn(EBinop("+", ECall(EField(ECall(EField(EField(EIdent("field"), "meta"), "map"), [EIdent("printMetadata")]), "join"), [EString("\n")]),
					ECall(EIdent("opt"), [EField(EIdent("field"), "type"), EIdent("printComplexType"), EString(" : ")])),
					HxPos.unknown())
			], "")
		], []);
		final printerFieldNames = new StringMap<Bool>();
		for (name in ["Printer", "Field"])
			printerFieldNames.set(name, true);
		final printerFieldClasses = new StringMap<HxClassDecl>();
		printerFieldClasses.set("Printer", printerFieldOwner);
		printerFieldClasses.set("Field", fieldCarrier);
		final printerFieldLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(HxClassDecl.getFunctions(printerFieldOwner)[0],
			printerFieldOwner, {
				names: printerFieldNames,
				byName: printerFieldClasses
			})
			.join("\n");
		assertContains(printerFieldLines, "std::string printField(std::shared_ptr<Field> field)",
			"C++ Printer.printField should stay string-callable while metadata/access lowering is incomplete");
		assertContains(printerFieldLines, "(void)field;", "C++ Printer.printField neutral helper should consume its argument");
		assertContains(printerFieldLines, "return std::string();", "C++ Printer.printField neutral helper should return a compile-safe string");
		assertTrue(printerFieldLines.indexOf(".filter") < 0, "C++ Printer.printField should not emit unsupported access.filter syntax");
		assertTrue(printerFieldLines.indexOf(".map") < 0, "C++ Printer.printField should not emit unsupported metadata map syntax");
		assertTrue(printerFieldLines.indexOf("printComplexType,") < 0, "C++ Printer.printField should not pass non-static method values directly as callbacks");
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
		final classConstructStringMethod = new HxFunctionDecl("constructStringLike", Public, true, [], "String",
			[SReturn(ENew("SelfStringOwner", []), HxPos.unknown())], "");
		final classConstructStringLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperMethod(classConstructStringMethod, selfStringOwner, selfStringLookup).join("\n");
		assertContains(classConstructStringLines, "return __hxhx_type_name(std::make_shared<SelfStringOwner>());",
			"C++ class-like construction in a String return should use target-owned stringification");
		assertTrue(classConstructStringLines.indexOf("std::to_string(std::make_shared<SelfStringOwner>") < 0,
			"C++ class-like construction in a String return should not call numeric std::to_string");
		final classConstructArgStringMethod = new HxFunctionDecl("constructArgStringLike", Public, true, [], "String",
			[SReturn(ENew("SelfStringOwner", [ENull]), HxPos.unknown())], "");
		final classConstructArgStringLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperMethod(classConstructArgStringMethod, selfStringOwner, selfStringLookup).join("\n");
		assertContains(classConstructArgStringLines, "return __hxhx_type_name(std::make_shared<SelfStringOwner>(nullptr));",
			"C++ class-like construction with args in a String return should use target-owned stringification");
		assertTrue(classConstructArgStringLines.indexOf("std::to_string(std::make_shared<SelfStringOwner>") < 0,
			"C++ class-like construction with args in a String return should not call numeric std::to_string");
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
		final vectorPopMethod = new HxFunctionDecl("popStackLike", Public, true, [new HxFunctionArg("stack", "Array<VectorItem>", NoDefault, false, false)],
			"VectorItem", [SReturn(ECall(EField(EIdent("stack"), "pop"), []), HxPos.unknown())], "");
		final vectorPopLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperMethod(vectorPopMethod, vectorReturnOwner, vectorReturnLookup).join("\n");
		assertContains(vectorPopLines, "return __hxhx_vector_pop(stack);",
			"C++ vector pop expressions should lower through target-owned vector support instead of a nonexistent std::vector::pop");
		assertTrue(vectorPopLines.indexOf("stack.pop()") < 0, "C++ vector pop expressions should not call std::vector::pop()");
		final vectorPopDiscardMethod = new HxFunctionDecl("discardPopStackLike", Public, true,
			[new HxFunctionArg("stack", "Array<VectorItem>", NoDefault, false, false)], "Void",
			[SExpr(ECall(EField(EIdent("stack"), "pop"), []), HxPos.unknown())], "");
		final vectorPopDiscardLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperMethod(vectorPopDiscardMethod, vectorReturnOwner, vectorReturnLookup).join("\n");
		assertContains(vectorPopDiscardLines, "__hxhx_vector_pop(stack);",
			"C++ vector pop statements should use the same support boundary and discard the returned value");
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
		final stdVector = new HxClassDecl("Vector", false, [
			new HxFunctionDecl("new", Public, false, [new HxFunctionArg("length", "Int", NoDefault, false, false)], "Void", [], "")
		], [], "", ["__hxhx_abstract", "__hxhx_abstract_underlying=VectorData<T>"]);
		final stdVectorNames = new StringMap<Bool>();
		stdVectorNames.set("Vector", true);
		final stdVectorClasses = new StringMap<HxClassDecl>();
		stdVectorClasses.set("Vector", stdVector);
		final stdVectorLookup = {names: stdVectorNames, byName: stdVectorClasses};
		final stdVectorLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(stdVector, stdVectorLookup).join("\n");
		assertContains(stdVectorLines, "std::vector<std::string> __values;",
			"C++ haxe.ds.Vector support should own native vector storage instead of rendering upstream abstract branch bodies");
		assertContains(stdVectorLines, "Vector(int length) : __values(length), length(length) {}",
			"C++ haxe.ds.Vector support should expose the length constructor as target-owned runtime support");
		assertContains(stdVectorLines, "std::string unsafeGet(int index) const { return __values[index]; }",
			"C++ haxe.ds.Vector support should provide unsafeGet over native vector storage");
		assertContains(stdVectorLines, "std::string unsafeSet(int index, std::string value) { __values[index] = value; return value; }",
			"C++ haxe.ds.Vector support should provide unsafeSet over native vector storage");
		assertTrue(stdVectorLines.indexOf("(*this) =") < 0, "C++ haxe.ds.Vector support should not emit inactive upstream #if assignment branches");
		final nativeArrayExtern = new HxClassDecl("NativeArray", false, [
			new HxFunctionDecl("create", Public, true, [new HxFunctionArg("length", "Int", NoDefault, false, false)], "Array<String>", [], "")
		]);
		final nativeArrayLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(nativeArrayExtern, stdVectorLookup).join("\n");
		assertTrue(nativeArrayLines.length == 0, "C++ cpp.NativeArray is an extern/intrinsic surface and should not emit a fake helper struct");
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
		final stringPrimitiveAbstract = new HxClassDecl("StringBackedFixture", false, [
			new HxFunctionDecl("NotIgnored", Public, true, [], "StringBackedFixture", [SReturn(ENew("StringBackedFixture", [ENull]), HxPos.unknown())], ""),
			new HxFunctionDecl("Ignored", Public, true, [new HxFunctionArg("reason", "String", NoDefault, false, false)], "StringBackedFixture",
				[SReturn(ENew("StringBackedFixture", [EIdent("reason")]), HxPos.unknown())], "")
		], [], "", ["__hxhx_abstract", "__hxhx_abstract_underlying=String"]);
		final stringPrimitiveNames = new StringMap<Bool>();
		stringPrimitiveNames.set("StringBackedFixture", true);
		final stringPrimitiveClasses = new StringMap<HxClassDecl>();
		stringPrimitiveClasses.set("StringBackedFixture", stringPrimitiveAbstract);
		final stringPrimitiveLookup = {names: stringPrimitiveNames, byName: stringPrimitiveClasses};
		final stringPrimitiveLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperClass(stringPrimitiveAbstract, stringPrimitiveLookup).join("\n");
		assertContains(stringPrimitiveLines, "static std::string NotIgnored() {",
			"C++ string-backed abstract static helpers should erase return types to std::string");
		assertContains(stringPrimitiveLines, "return std::string();",
			"C++ string-backed abstract construction from null should lower to the underlying string default");
		assertContains(stringPrimitiveLines, "return std::string(reason);",
			"C++ string-backed abstract construction from a string should lower to the underlying string value");
		assertTrue(stringPrimitiveLines.indexOf("std::make_shared<StringBackedFixture>") < 0,
			"C++ primitive-backed abstract constructors should not emit fake shared_ptr wrapper allocations");
		assertTrue(stringPrimitiveLines.indexOf("std::to_string(std::make_shared<StringBackedFixture>") < 0,
			"C++ string-backed abstract constructors should not be numerically stringified");
		final ignoredFixture = new HxClassDecl("IgnoredFixture", false, [
			new HxFunctionDecl("NotIgnored", Public, true, [], "IgnoredFixture", [SReturn(ENew("IgnoredFixture", [ENull]), HxPos.unknown())], ""),
			new HxFunctionDecl("get_isIgnored", Public, false, [], "Bool", [SReturn(EBinop("!=", EThis, ENull), HxPos.unknown())], ""),
			new HxFunctionDecl("get_ignoreReason", Public, false, [], "String", [SReturn(EThis, HxPos.unknown())], "")
		], [
			new HxFieldDecl("isIgnored", Public, false, "Bool", null),
			new HxFieldDecl("ignoreReason", Public, false, "String", null)
		], "", ["__hxhx_abstract", "__hxhx_abstract_underlying=String"]);
		final fixtureOwner = new HxClassDecl("FixtureOwner", false, [], [new HxFieldDecl("ignoringInfo", Public, false, "IgnoredFixture", null)]);
		final fixtureHandler = new HxClassDecl("FixtureHandler", false, [
			new HxFunctionDecl("new", Public, false, [new HxFunctionArg("fixture", "FixtureOwner", NoDefault, false, false)], "Void", [
				SIf(EField(EField(EIdent("fixture"), "ignoringInfo"), "isIgnored"),
					SVar("reason", "String", EField(EField(EIdent("fixture"), "ignoringInfo"), "ignoreReason"), HxPos.unknown()), null, HxPos.unknown())
			], "")
		]);
		final ignoredFixtureNames = new StringMap<Bool>();
		final ignoredFixtureClasses = new StringMap<HxClassDecl>();
		for (cls in [ignoredFixture, fixtureOwner, fixtureHandler]) {
			final name = HxClassDecl.getName(cls);
			ignoredFixtureNames.set(name, true);
			ignoredFixtureClasses.set(name, cls);
		}
		final ignoredFixtureLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(fixtureHandler, {
			names: ignoredFixtureNames,
			byName: ignoredFixtureClasses
		}).join("\n");
		assertContains(ignoredFixtureLines, "if (((fixture->ignoringInfo) != std::string())) {",
			"C++ string-backed abstract Bool getters should lower through the abstract getter body instead of raw string field access");
		assertContains(ignoredFixtureLines, "std::string reason = (fixture->ignoringInfo);",
			"C++ string-backed abstract String getters should lower to the underlying string expression");
		assertTrue(ignoredFixtureLines.indexOf(".isIgnored") < 0,
			"C++ string-backed abstract property reads should not emit object fields on std::string values");
		assertTrue(ignoredFixtureLines.indexOf(".ignoreReason") < 0,
			"C++ string-backed abstract property reads should not emit object fields on std::string values");
		final int64Abstract = new HxClassDecl("Int64", false, [
			new HxFunctionDecl("ofInt", Public, true, [new HxFunctionArg("x", "Int", NoDefault, false, false)], "Int64",
				[SReturn(EIdent("x"), HxPos.unknown())], ""),
			new HxFunctionDecl("add", Public, true, [
				new HxFunctionArg("a", "Int64", NoDefault, false, false),
				new HxFunctionArg("b", "Int64", NoDefault, false, false)
			], "Int64",
				[SReturn(EBinop("+", EIdent("a"), EIdent("b")), HxPos.unknown())], "")
		], [], "", []);
		final int64Names = new StringMap<Bool>();
		int64Names.set("Int64", true);
		final int64Classes = new StringMap<HxClassDecl>();
		int64Classes.set("Int64", int64Abstract);
		final int64Lookup = {names: int64Names, byName: int64Classes};
		final int64Lines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(int64Abstract, int64Lookup).join("\n");
		assertTrue(int64Lines.length == 0, "C++ Int64 should be a target-owned intrinsic surface, not a generated helper class");
		assertTrue(int64Lines.indexOf("std::shared_ptr<Int64>") < 0, "C++ Int64 primitive-backed helpers should not leak shared_ptr wrapper types");
		final int64Carrier = new HxClassDecl("__Int64", false, [], [], "", []);
		final int64CarrierLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(int64Carrier, int64Lookup).join("\n");
		assertTrue(int64CarrierLines.length == 0, "C++ __Int64 abstract carriers should not emit stale high/low helper bodies");
		final valueNullComparison = new HxClassDecl("ValueNullComparison", false, [
			new HxFunctionDecl("stringIsNull", Public, true, [new HxFunctionArg("value", "String", NoDefault, false, false)], "Bool",
				[SReturn(EBinop("==", EIdent("value"), ENull), HxPos.unknown())], ""),
			new HxFunctionDecl("stringNotNull", Public, true, [new HxFunctionArg("value", "String", NoDefault, false, false)], "Bool",
				[SReturn(EBinop("!=", EIdent("value"), ENull), HxPos.unknown())], "")
		], [], "", []);
		final valueNullNames = new StringMap<Bool>();
		valueNullNames.set("ValueNullComparison", true);
		final valueNullClasses = new StringMap<HxClassDecl>();
		valueNullClasses.set("ValueNullComparison", valueNullComparison);
		final valueNullLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperClass(valueNullComparison, {names: valueNullNames, byName: valueNullClasses}).join("\n");
		assertContains(valueNullLines, "return false;", "C++ non-nullable value == null should lower to false instead of comparing to nullptr");
		assertContains(valueNullLines, "return true;", "C++ non-nullable value != null should lower to true instead of comparing to nullptr");
		final bytesData = new HxClassDecl("BytesData", false, [], [], "", []);
		final bytes = new HxClassDecl("Bytes", false, [
			new HxFunctionDecl("new", Public, false, [
				new HxFunctionArg("length", "", NoDefault, false, false),
				new HxFunctionArg("b", "", NoDefault, false, false)
			], "Void", [
				SExpr(EBinop("=", EField(EThis, "length"), EIdent("length")), HxPos.unknown()),
				SExpr(EBinop("=", EField(EThis, "b"), EIdent("b")), HxPos.unknown())
			],
				""),
			new HxFunctionDecl("get", Public, false, [new HxFunctionArg("pos", "Int", NoDefault, false, false)], "Int",
				[SReturn(EArrayAccess(EIdent("b"), EIdent("pos")), HxPos.unknown())], ""),
			new HxFunctionDecl("set", Public, false, [
				new HxFunctionArg("pos", "Int", NoDefault, false, false),
				new HxFunctionArg("v", "Int", NoDefault, false, false)
			], "Void", [
				SExpr(EBinop("=", EArrayAccess(EIdent("b"), EIdent("pos")), EIdent("v")), HxPos.unknown())
			], ""),
			new HxFunctionDecl("fill", Public, false, [
				new HxFunctionArg("pos", "Int", NoDefault, false, false),
				new HxFunctionArg("len", "Int", NoDefault, false, false),
				new HxFunctionArg("value", "Int", NoDefault, false, false)
			], "", [
				SReturn(ECall(EField(EIdent("__global__"), "__hxcpp_memory_memset"), [EIdent("b"), EIdent("pos"), EIdent("len"), EIdent("value")]),
					HxPos.unknown())
			], ""),
			new HxFunctionDecl("getDouble", Public, false, [new HxFunctionArg("pos", "Int", NoDefault, false, false)], "Float", [
				SReturn(ECall(EField(EIdent("__global__"), "__hxcpp_memory_get_double"), [EIdent("b"), EIdent("pos")]), HxPos.unknown())
			], ""),
			new HxFunctionDecl("setDouble", Public, false, [
				new HxFunctionArg("pos", "Int", NoDefault, false, false),
				new HxFunctionArg("v", "Float", NoDefault, false, false)
			], "Void", [
				SExpr(ECall(EField(EIdent("__global__"), "__hxcpp_memory_set_double"), [EIdent("b"), EIdent("pos"), EIdent("v")]), HxPos.unknown())
			], ""),
			new HxFunctionDecl("setInt64", Public, false, [
				new HxFunctionArg("pos", "Int", NoDefault, false, false),
				new HxFunctionArg("v", "Int64", NoDefault, false, false)
			], "Void", [
				SExpr(ECall(EIdent("setInt32"), [EIdent("pos"), EField(EIdent("v"), "low")]), HxPos.unknown()),
				SExpr(ECall(EIdent("setInt32"), [EBinop("+", EIdent("pos"), EInt(4)), EField(EIdent("v"), "high")]), HxPos.unknown())
			], ""),
			new HxFunctionDecl("getString", Public, false, [
				new HxFunctionArg("pos", "Int", NoDefault, false, false),
				new HxFunctionArg("len", "Int", NoDefault, false, false),
				new HxFunctionArg("encoding", "Encoding", NoDefault, true, false)
			], "String", [
				SIf(EBinop("==", EIdent("encoding"), ENull), SExpr(EBinop("==", EIdent("encoding"), EIdent("UTF8")), HxPos.unknown()), null, HxPos.unknown()),
				SVar("result", "String", EString(""), HxPos.unknown()),
				SExpr(ECall(EField(EIdent("__global__"), "__hxcpp_string_of_bytes"), [EIdent("b"), EIdent("result"), EIdent("pos"), EIdent("len")]),
					HxPos.unknown()),
				SReturn(EIdent("result"), HxPos.unknown())
			], ""),
			new HxFunctionDecl("blit", Public, false, [
				new HxFunctionArg("pos", "Int", NoDefault, false, false),
				new HxFunctionArg("src", "Bytes", NoDefault, false, false),
				new HxFunctionArg("srcpos", "Int", NoDefault, false, false),
				new HxFunctionArg("len", "Int", NoDefault, false, false)
			], "Void", [
				SExpr(ECall(EField(EIdent("b"), "blit"), [EIdent("pos"), EField(EIdent("src"), "b"), EIdent("srcpos"), EIdent("len")]), HxPos.unknown())
			], ""),
			new HxFunctionDecl("sub", Public, false, [
				new HxFunctionArg("pos", "Int", NoDefault, false, false),
				new HxFunctionArg("len", "Int", NoDefault, false, false)
			], "Bytes", [
				SReturn(ENew("Bytes",
					[
						EIdent("len"),
						ECall(EField(EIdent("b"), "slice"), [EIdent("pos"), EBinop("+", EIdent("pos"), EIdent("len"))])
					]), HxPos.unknown())
			], ""),
			new HxFunctionDecl("compare", Public, false, [new HxFunctionArg("other", "Bytes", NoDefault, false, false)], "Int", [
				SReturn(ECall(EField(EIdent("b"), "memcmp"), [EField(EIdent("other"), "b")]), HxPos.unknown())
			], ""),
			new HxFunctionDecl("alloc", Public, true, [new HxFunctionArg("length", "Int", NoDefault, false, false)], "Bytes", [
				SVar("a", "BytesData", ENew("BytesData", []), HxPos.unknown()),
				SExpr(ECall(EField(EField(EIdent("cpp"), "NativeArray"), "setSize"), [EIdent("a"), EIdent("length")]), HxPos.unknown()),
				SReturn(ENew("Bytes", [EIdent("length"), EIdent("a")]), HxPos.unknown())
			], ""),
			new HxFunctionDecl("ofString", Public, true, [new HxFunctionArg("s", "String", NoDefault, false, false)], "Bytes", [
				SVar("a", "BytesData", ENew("BytesData", []), HxPos.unknown()),
				SExpr(ECall(EField(EIdent("__global__"), "__hxcpp_bytes_of_string"), [EIdent("a"), EIdent("s")]), HxPos.unknown()),
				SReturn(ENew("Bytes", [EField(EIdent("a"), "length"), EIdent("a")]), HxPos.unknown())
			], "")
		], [
			new HxFieldDecl("length", Public, false, "Int", null),
			new HxFieldDecl("b", Public, false, "BytesData", null)
		]);
		final bytesNames = new StringMap<Bool>();
		for (name in ["BytesData", "Bytes"])
			bytesNames.set(name, true);
		final bytesClasses = new StringMap<HxClassDecl>();
		bytesClasses.set("BytesData", bytesData);
		bytesClasses.set("Bytes", bytes);
		final bytesLookup = {names: bytesNames, byName: bytesClasses};
		final bytesDataLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(bytesData, bytesLookup).join("\n");
		assertTrue(bytesDataLines.length == 0, "C++ BytesData should be target-owned byte storage, not a generated fake helper class");
		final bytesLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(bytes, bytesLookup).join("\n");
		assertContains(bytesLines, "std::vector<int> b = {};", "C++ Bytes.b should use vector-backed BytesData storage");
		assertContains(bytesLines, "Bytes(int length, std::vector<int> b) : length(length), b(b) {",
			"C++ should recover erased Bytes constructor args and initialize fields directly");
		assertContains(bytesLines, "return static_cast<int>((b[pos]));", "C++ Bytes.get should index vector-backed BytesData directly");
		assertContains(bytesLines, "(b[pos]) = v;", "C++ Bytes.set should write vector-backed BytesData directly");
		assertContains(bytesLines, "void fill(int pos, int len, int value) {", "C++ Bytes.fill should keep its target stdlib Void return type");
		assertContains(bytesLines, "__hxhx_bytes_fill(b, pos, len, value); return;",
			"C++ Bytes.fill should lower hxcpp memset without returning a void helper");
		assertContains(bytesLines, "return __hxhx_memory_get_double(b, pos);", "C++ Bytes.getDouble should lower through target byte-memory helpers");
		assertContains(bytesLines, "__hxhx_memory_set_double(b, pos, v);", "C++ Bytes.setDouble should lower through target byte-memory helpers");
		assertContains(bytesLines, "setInt32(pos, static_cast<int>(static_cast<unsigned long long>(v) & 0xFFFFFFFFULL));",
			"C++ Int64.low on primitive Int64 should lower to a low 32-bit projection");
		assertContains(bytesLines, "setInt32((pos + 4), static_cast<int>((static_cast<unsigned long long>(v) >> 32) & 0xFFFFFFFFULL));",
			"C++ Int64.high on primitive Int64 should lower to a high 32-bit projection");
		assertContains(bytesLines, "std::string getString(int pos, int len, std::shared_ptr<Encoding> encoding = nullptr) {",
			"C++ optional Encoding parameters should keep the target enum-carrier pointer shape");
		assertContains(bytesLines, "(encoding == nullptr);",
			"C++ Encoding.UTF8 comparisons should use the carrier null representation instead of class-value strings");
		assertTrue(bytesLines.indexOf("encoding == std::string(\"UTF8\")") < 0,
			"C++ Encoding.UTF8 comparisons must not be intercepted by generic class-value comparison lowering");
		assertContains(bytesLines, "__hxhx_string_of_bytes(b, result, pos, len);", "C++ Bytes.getString should lower through target string byte helpers");
		assertContains(bytesLines, "__hxhx_bytes_of_string(a, s);", "C++ Bytes.ofString should lower through target byte string helpers");
		assertContains(bytesLines, "__hxhx_bytes_blit(b, pos, (src->b), srcpos, len);", "C++ BytesData.blit should lower through target runtime support");
		assertContains(bytesLines, "return std::make_shared<Bytes>(len, __hxhx_bytes_slice(b, pos, (pos + len)));",
			"C++ BytesData.slice should lower through target runtime support");
		assertContains(bytesLines, "return static_cast<int>(__hxhx_bytes_memcmp(b, (other->b)));",
			"C++ BytesData.memcmp should lower through target runtime support");
		assertContains(bytesLines, "std::vector<int> a = std::vector<int>{};", "C++ new BytesData() should create vector-backed storage");
		assertContains(bytesLines, "a.resize(length);", "C++ cpp.NativeArray.setSize should resize vector-backed BytesData storage");
		assertContains(bytesLines, "return std::make_shared<Bytes>(length, a);",
			"C++ Bytes.alloc should pass vector-backed BytesData to the recovered constructor");
		final bytesBufferGetBytes = new HxFunctionDecl("getBytes", Public, false, [], "Bytes", [
			SVar("b", "BytesData", ENew("BytesData", []), HxPos.unknown()),
			SExpr(EBinop("=", EIdent("b"), ENull), HxPos.unknown()),
			SReturn(ENew("Bytes", [EInt(0), EIdent("b")]), HxPos.unknown())
		], "");
		final bytesBufferOwner = new HxClassDecl("BytesBuffer", false, [bytesBufferGetBytes], []);
		final bytesBufferLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(bytesBufferGetBytes, bytesBufferOwner, bytesLookup).join("\n");
		assertContains(bytesBufferLines, "b = {};", "C++ BytesBuffer-style BytesData nulling should reset vector storage instead of assigning nullptr");
		assertTrue(bytesBufferLines.indexOf("b = nullptr") < 0, "C++ BytesData locals are vector-backed and should not receive nullptr assignments");
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
		final stringIteratorUnicode = new HxClassDecl("StringIteratorUnicode", false, [
			new HxFunctionDecl("unicodeIterator", Public, true, [new HxFunctionArg("s", "String", NoDefault, false, false)], "",
				[SReturn(ENew("StringIteratorUnicode", [EIdent("s")]), HxPos.unknown())], "")
		], []);
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
		final stringKeyValueIteratorUnicode = new HxClassDecl("StringKeyValueIteratorUnicode", false, [
			new HxFunctionDecl("unicodeKeyValueIterator", Public, true, [new HxFunctionArg("s", "String", NoDefault, false, false)], "",
				[SReturn(ENew("StringKeyValueIteratorUnicode", [EIdent("s")]), HxPos.unknown())], "")
		], []);
		final stringIteratorNames = new StringMap<Bool>();
		for (name in [
			"StringIterator",
			"StringIteratorUnicode",
			"StringKeyValueIterator",
			"StringKeyValueIteratorUnicode"
		])
			stringIteratorNames.set(name, true);
		final stringIteratorClasses = new StringMap<HxClassDecl>();
		stringIteratorClasses.set("StringIterator", stringIterator);
		stringIteratorClasses.set("StringIteratorUnicode", stringIteratorUnicode);
		stringIteratorClasses.set("StringKeyValueIterator", stringKeyValueIterator);
		stringIteratorClasses.set("StringKeyValueIteratorUnicode", stringKeyValueIteratorUnicode);
		final stringIteratorLookup = {names: stringIteratorNames, byName: stringIteratorClasses};
		final stringIteratorLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(stringIterator, stringIteratorLookup).join("\n");
		final stringIteratorUnicodeLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(stringIteratorUnicode, stringIteratorLookup).join("\n");
		final stringKeyValueIteratorLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(stringKeyValueIterator, stringIteratorLookup)
			.join("\n");
		final stringKeyValueIteratorUnicodeLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(stringKeyValueIteratorUnicode,
			stringIteratorLookup)
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
		assertContains(stringIteratorUnicodeLines,
			"static std::shared_ptr<StringIteratorUnicode> unicodeIterator(std::string s) {\n    return std::make_shared<StringIteratorUnicode>(s);\n  }",
			"C++ unicode string iterator factory should return its iterator object, not an inferred int");
		assertContains(stringKeyValueIteratorUnicodeLines,
			"static std::shared_ptr<StringKeyValueIteratorUnicode> unicodeKeyValueIterator(std::string s) {\n    return std::make_shared<StringKeyValueIteratorUnicode>(s);\n  }",
			"C++ unicode key/value iterator factory should return its iterator object, not an inferred int");
		final iMapForIterator = new HxClassDecl("IMap", false, [
			new HxFunctionDecl("get", Public, false, [new HxFunctionArg("key", "K", NoDefault, false, false)], "Null<V>", [], "")
		], [], "", null, true);
		final mapKeyValueIterator = new HxClassDecl("MapKeyValueIterator", false, [
			new HxFunctionDecl("next", Public, false, [], "", [
				SVar("key", "", ECall(EField(EIdent("keys"), "next"), []), HxPos.unknown()),
				SReturn(EAnon(["value", "key"], [
					ECall(EIdent("__hxhx_expr_meta"), [
						EString("nullSafety"),
						EString("Off"),
						ECast(ECall(EField(EIdent("map"), "get"), [EIdent("key")]), "V")
					]),
					EIdent("key")
				]), HxPos.unknown())
			], "")
		], [
			new HxFieldDecl("map", Public, false, "IMap<K,V>", null),
			new HxFieldDecl("keys", Public, false, "Iterator<K>", null)
		]);
		final mapIteratorNames = new StringMap<Bool>();
		for (name in ["IMap", "MapKeyValueIterator"])
			mapIteratorNames.set(name, true);
		final mapIteratorClasses = new StringMap<HxClassDecl>();
		mapIteratorClasses.set("IMap", iMapForIterator);
		mapIteratorClasses.set("MapKeyValueIterator", mapKeyValueIterator);
		final mapKeyValueIteratorLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperClass(mapKeyValueIterator, {names: mapIteratorNames, byName: mapIteratorClasses}).join("\n");
		assertContains(mapKeyValueIteratorLines, "template<typename K, typename V>\nstruct MapKeyValueIterator : public KeyValueIterator {",
			"C++ structural key/value iterator helpers should inherit the target-owned KeyValueIterator marker");
		assertContains(mapKeyValueIteratorLines, "auto key = keys->next();", "C++ iterator-protocol next calls should support unhinted key locals");
		assertContains(mapKeyValueIteratorLines,
			"return __hxhx_anon_value_std__string_key_std__string{map->get(key).value_or(std::string()), __hxhx_stringify(key)};",
			"C++ IMap key/value iterator records should unwrap optional map.get values into concrete anonymous value fields");
		assertTrue(mapKeyValueIteratorLines.indexOf("__hxhx_anon_value_int_key_std__string_") < 0,
			"C++ optional method-call anonymous fields should not fall back to Int");
		final fallbackMapIteratorClasses = new StringMap<HxClassDecl>();
		fallbackMapIteratorClasses.set("MapKeyValueIterator", mapKeyValueIterator);
		final fallbackMapKeyValueIteratorLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperClass(mapKeyValueIterator, {names: mapIteratorNames, byName: fallbackMapIteratorClasses}).join("\n");
		assertContains(fallbackMapKeyValueIteratorLines,
			"return __hxhx_anon_value_std__string_key_std__string{map->get(key).value_or(std::string()), __hxhx_stringify(key)};",
			"C++ fallback IMap method typing should also unwrap optional map.get values when IMap is target-owned");
		assertTrue(fallbackMapKeyValueIteratorLines.indexOf("__hxhx_anon_value_int__key_std__string") < 0,
			"C++ target-owned IMap key/value iterator records should not fall back to Int anonymous value fields");
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
		final genericStdArray = new HxClassDecl("Array", false, [
			new HxFunctionDecl("push", Public, false, [new HxFunctionArg("x", "T", NoDefault, false, false)], "Int", [], "")
		], [new HxFieldDecl("length", Public, false, "Int", null)], "",
			["__hxhx_type_params=T"]);
		final genericStdArrayLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperClass(genericStdArray, stdArrayLookup).join("\n");
		assertTrue(genericStdArrayLines.length == 0,
			"C++ upstream extern Array<T> should lower through std::vector<T>, not emit a fake non-template Array helper with incomplete T");
		final vectorJoinCorrupted = new HxClassDecl("Vector", false, [
			new HxFunctionDecl("join", Public, false, [new HxFunctionArg("sep", "T", NoDefault, false, false)], "String", [], "", ["__hxhx_fn_type_params=T"])
		], []);
		final vectorJoinCorruptedLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperClass(vectorJoinCorrupted, stdArrayLookup).join("\n");
		assertContains(vectorJoinCorruptedLines, "std::string join(std::string sep) const { return __hxhx_join(__values, sep); }",
			"C++ target-owned Vector support should keep join separators string-shaped even if native metadata says method-level T");
		assertTrue(vectorJoinCorruptedLines.indexOf("join(T__fn sep)") < 0,
			"C++ target-owned Vector support should not render metadata-corrupted upstream join declarations");
		final lambdaHasOwner = new HxClassDecl("Lambda", false, [
			new HxFunctionDecl("has", Public, true, [
				new HxFunctionArg("it", "Iterable<A>", NoDefault, false, false),
				new HxFunctionArg("elt", "A", NoDefault, false, false)
			], "Bool", [SReturn(EBool(false), HxPos.unknown())], "",
				["__hxhx_fn_type_params=A"])
		], []);
		final lambdaHasNames = new StringMap<Bool>();
		lambdaHasNames.set("Lambda", true);
		final lambdaHasClasses = new StringMap<HxClassDecl>();
		lambdaHasClasses.set("Lambda", lambdaHasOwner);
		final lambdaHasLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperClass(lambdaHasOwner, {names: lambdaHasNames, byName: lambdaHasClasses}).join("\n");
		assertContains(lambdaHasLines, "static bool has(const std::vector<A>& it, typename std::vector<A>::value_type elt) {",
			"C++ Lambda.has should deduce the element type from the iterable so string literals can convert to std::string");
		assertTrue(lambdaHasLines.indexOf("static bool has(std::vector<T> it, A elt)") < 0,
			"C++ Lambda.has should not emit an undeclared T iterable with separately deduced element arguments");
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
		final emptyArrayForwarding = new HxClassDecl("EmptyArrayForwarding", false, [
			new HxFunctionDecl("fill", Public, false, [new HxFunctionArg("ret", "Array<String>", NoDefault, false, false)], "Void", [], ""),
			new HxFunctionDecl("values", Public, false, [], "Array<String>", [
				SVar("ret", "", EArrayDecl([]), HxPos.unknown()),
				SExpr(ECall(EIdent("fill"), [EIdent("ret")]), HxPos.unknown()),
				SReturn(EIdent("ret"), HxPos.unknown())
			], "")
		], []);
		final emptyArrayNames = new StringMap<Bool>();
		emptyArrayNames.set("EmptyArrayForwarding", true);
		final emptyArrayClasses = new StringMap<HxClassDecl>();
		emptyArrayClasses.set("EmptyArrayForwarding", emptyArrayForwarding);
		final emptyArrayValuesLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(HxClassDecl.getFunctions(emptyArrayForwarding)[1],
			emptyArrayForwarding, {
				names: emptyArrayNames,
				byName: emptyArrayClasses
			})
			.join("\n");
		assertContains(emptyArrayValuesLines, "auto ret = std::vector<std::string>{};",
			"C++ empty array locals should recover vector element type from later same-owner method calls");
		assertTrue(emptyArrayValuesLines.indexOf("std::vector<int> ret") < 0,
			"C++ empty array locals passed to typed vector parameters should not stay vector<int>");
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
		final inheritedCtorBase = new HxClassDecl("InheritedCtorBase", false, [
			new HxFunctionDecl("new", Public, false, [new HxFunctionArg("value", "Int", NoDefault, false, false)], "Void", [], "")
		], []);
		final inheritedCtorSub = new HxClassDecl("InheritedCtorSub", false, [], [], "InheritedCtorBase");
		final inheritedCtorNames = new StringMap<Bool>();
		for (name in ["InheritedCtorBase", "InheritedCtorSub"])
			inheritedCtorNames.set(name, true);
		final inheritedCtorClasses = new StringMap<HxClassDecl>();
		inheritedCtorClasses.set("InheritedCtorBase", inheritedCtorBase);
		inheritedCtorClasses.set("InheritedCtorSub", inheritedCtorSub);
		final inheritedCtorLookup = {names: inheritedCtorNames, byName: inheritedCtorClasses};
		final inheritedCtorSubLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperClass(inheritedCtorSub, inheritedCtorLookup).join("\n");
		assertContains(inheritedCtorSubLines, "InheritedCtorSub(int value) : InheritedCtorBase(value) {}",
			"C++ subclasses without explicit constructors should forward to the base constructor shape");
		assertTrue(inheritedCtorSubLines.indexOf("InheritedCtorSub()") < 0,
			"C++ subclasses whose base needs constructor args should not emit an invalid default constructor");
		final qualifiedBase = new HxClassDecl("QualifiedBase", false, [], []);
		final qualifiedSub = new HxClassDecl("QualifiedSub", false, [], [], "demo.pkg.QualifiedBase");
		final qualifiedNames = new StringMap<Bool>();
		for (name in ["QualifiedBase", "QualifiedSub"])
			qualifiedNames.set(name, true);
		final qualifiedClasses = new StringMap<HxClassDecl>();
		qualifiedClasses.set("QualifiedBase", qualifiedBase);
		qualifiedClasses.set("QualifiedSub", qualifiedSub);
		final qualifiedLookup = {names: qualifiedNames, byName: qualifiedClasses};
		final qualifiedSubLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(qualifiedSub, qualifiedLookup).join("\n");
		assertContains(qualifiedSubLines, "struct QualifiedSub : public QualifiedBase {",
			"C++ helper inheritance should resolve package-qualified extends paths to emitted helper basenames");
		assertTrue(qualifiedSubLines.indexOf("demo_pkg_QualifiedBase") < 0,
			"C++ helper inheritance should not emit package-qualified synthetic base names when only the basename helper exists");
		final inferredGetterNode = new HxClassDecl("InferredGetterNode", false, [
			new HxFunctionDecl("get_height", Public, false, [], "", [SReturn(ETernary(EBool(false), EInt(0), EIdent("_height")), HxPos.unknown())], "")
		], [new HxFieldDecl("_height", Public, false, "Int", EInt(0))]);
		final inferredGetterNames = new StringMap<Bool>();
		inferredGetterNames.set("InferredGetterNode", true);
		final inferredGetterClasses = new StringMap<HxClassDecl>();
		inferredGetterClasses.set("InferredGetterNode", inferredGetterNode);
		final inferredGetterLookup = {names: inferredGetterNames, byName: inferredGetterClasses};
		final inferredGetterLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(inferredGetterNode, inferredGetterLookup).join("\n");
		assertContains(inferredGetterLines, "int get_height() {", "C++ inferred helper return types should preserve int/int ternary getter results");
		assertTrue(inferredGetterLines.indexOf("std::string get_height()") < 0,
			"C++ inferred helper return types should not fall back to string for int field ternaries");
		final defaultCtorBase = new HxClassDecl("DefaultCtorBase", false, [
			new HxFunctionDecl("new", Public, false, [
				new HxFunctionArg("s", "String", Default(EString("test")), false, false),
				new HxFunctionArg("i", "Int", Default(EInt(-5)), false, false),
				new HxFunctionArg("b", "Bool", Default(EBool(true)), false, false)
			], "Void", [], "")
		], []);
		final defaultCtorSub = new HxClassDecl("DefaultCtorSub", false, [
			new HxFunctionDecl("new", Public, false, [
				new HxFunctionArg("s", "String", Default(EString("test2")), false, false),
				new HxFunctionArg("i", "Int", Default(EInt(-6)), false, false)
			], "Void",
				[SExpr(ECall(ESuper, [EIdent("s"), EIdent("i"), EBool(true)]), HxPos.unknown())], "")
		], [], "DefaultCtorBase");
		final defaultCtorNames = new StringMap<Bool>();
		for (name in ["DefaultCtorBase", "DefaultCtorSub"])
			defaultCtorNames.set(name, true);
		final defaultCtorClasses = new StringMap<HxClassDecl>();
		defaultCtorClasses.set("DefaultCtorBase", defaultCtorBase);
		defaultCtorClasses.set("DefaultCtorSub", defaultCtorSub);
		final defaultCtorLookup = {names: defaultCtorNames, byName: defaultCtorClasses};
		final defaultCtorBaseLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(defaultCtorBase, defaultCtorLookup).join("\n");
		final defaultCtorSubLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(defaultCtorSub, defaultCtorLookup).join("\n");
		assertContains(defaultCtorBaseLines, "DefaultCtorBase(std::string s = \"test\", int i = -5, bool b = true) {",
			"C++ constructors should preserve ordinary String/Int/Bool default argument values");
		assertContains(defaultCtorSubLines, "DefaultCtorSub(std::string s = \"test2\", int i = -6) : DefaultCtorBase(s, i, true) {",
			"C++ subclass constructors should preserve defaults while forwarding explicit super args");
		final erasedForwardBase = new HxClassDecl("ErasedForwardBase", false, [
			new HxFunctionDecl("new", Public, false, [new HxFunctionArg("value", "Int", NoDefault, false, false)], "Void", [], "")
		], []);
		final erasedForwardSub = new HxClassDecl("ErasedForwardSub", false, [
			new HxFunctionDecl("new", Public, false, [new HxFunctionArg("value", "", NoDefault, false, false)], "Void", [
				SExpr(EBinop("=", EIdent("tag"), EString("ready")), HxPos.unknown()),
				SExpr(ECall(ESuper, [EIdent("value")]), HxPos.unknown())
			], "")
		], [new HxFieldDecl("tag", Public, false, "String", null)], "ErasedForwardBase");
		final erasedForwardNames = new StringMap<Bool>();
		for (name in ["ErasedForwardBase", "ErasedForwardSub"])
			erasedForwardNames.set(name, true);
		final erasedForwardClasses = new StringMap<HxClassDecl>();
		erasedForwardClasses.set("ErasedForwardBase", erasedForwardBase);
		erasedForwardClasses.set("ErasedForwardSub", erasedForwardSub);
		final erasedForwardLookup = {names: erasedForwardNames, byName: erasedForwardClasses};
		final erasedForwardSubLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperClass(erasedForwardSub, erasedForwardLookup).join("\n");
		assertContains(erasedForwardSubLines, "ErasedForwardSub(int value) : ErasedForwardBase(value) {",
			"C++ subclass constructors should recover erased parameter types from forwarded super arguments");
		assertTrue(erasedForwardSubLines.indexOf("base constructor call omitted") < 0,
			"C++ non-leading top-level super constructor calls should still become base initializer lists");
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
		final logFormatOutputLike = new HxFunctionDecl("formatOutput", Public, true, [
			new HxFunctionArg("str", "String", NoDefault, false, false),
			new HxFunctionArg("infos", "PosInfos", NoDefault, false, false)
		], "String", [
			SVar("pstr", "", EBinop("+", EBinop("+", EField(EIdent("infos"), "className"), EString(".")), EField(EIdent("infos"), "methodName")),
				HxPos.unknown()),
			SForIn("v", EField(EIdent("infos"), "customParams"), SExpr(EBinop("+=", EIdent("pstr"), EBinop("+", EString(","), EIdent("v"))), HxPos.unknown()),
				HxPos.unknown()),
			SReturn(EBinop("+", EBinop("+", EIdent("pstr"), EString(": ")), EIdent("str")), HxPos.unknown())
		], "");
		final logLike = new HxClassDecl("Log", false, [logFormatOutputLike], []);
		final posNames = new StringMap<Bool>();
		for (name in ["PosInfos", "PosException", "Log"])
			posNames.set(name, true);
		final posClasses = new StringMap<HxClassDecl>();
		posClasses.set("PosInfos", posInfos);
		posClasses.set("PosException", posException);
		posClasses.set("Log", logLike);
		final posLookup = {names: posNames, byName: posClasses};
		final posInfosLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(posInfos, posLookup).join("\n");
		final parsedPosInfosLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(new HxClassDecl("PosInfos", false, [], [
			new HxFieldDecl("fileName", Public, false, "String", null),
			new HxFieldDecl("lineNumber", Public, false, "Int", null),
			new HxFieldDecl("className", Public, false, "String", null),
			new HxFieldDecl("methodName", Public, false, "String", null)
		]), posLookup).join("\n");
		final posExceptionLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(posException, posLookup).join("\n");
		final logFormatOutputLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(logFormatOutputLike, logLike, posLookup).join("\n");
		assertContains(posInfosLines, "std::string fileName = std::string();", "C++ PosInfos typedef placeholders should render the stdlib position fields");
		assertContains(posInfosLines, "std::vector<std::string> customParams = {};",
			"C++ PosInfos support should include the stdlib customParams field used by Log.formatOutput");
		assertContains(parsedPosInfosLines, "PosInfos(std::string fileName, int lineNumber, std::string className, std::string methodName)",
			"C++ parsed PosInfos helpers should still expose the target-owned position constructor");
		assertContains(posExceptionLines, "std::shared_ptr<PosInfos> pos = nullptr", "C++ optional PosInfos args should stay nullable references");
		assertContains(posExceptionLines,
			"posInfos = std::make_shared<PosInfos>(std::string(\"(unknown)\"), 0, std::string(\"(unknown)\"), std::string(\"(unknown)\"));",
			"C++ assignments from matching position literals should wrap into PosInfos shared pointers");
		assertContains(posExceptionLines, "posInfos = pos;", "C++ PosInfos reference assignments should pass existing pointers through");
		assertContains(posExceptionLines, "return (posInfos->className);", "C++ PosInfos string fields should not be wrapped with std::to_string");
		assertContains(logFormatOutputLines, "for (auto v : (infos->customParams)) {",
			"C++ Log.formatOutput-like helpers should iterate PosInfos.customParams");
		assertContains(logFormatOutputLines, "return ((std::string(pstr) + std::string(\": \")) + std::string(str));",
			"C++ string accumulators should stay in string context when returned");
		assertTrue(logFormatOutputLines.indexOf("std::to_string(pstr)") < 0, "C++ string accumulators should not be wrapped in std::to_string");
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
		final genericBox = new HxClassDecl("GenericBox", false, [
			new HxFunctionDecl("new", Public, false, [new HxFunctionArg("value", "T", NoDefault, false, false)], "Void",
				[SExpr(EBinop("=", EField(EThis, "value"), EIdent("value")), HxPos.unknown())], "")
		], [new HxFieldDecl("value", Public, false, "T", null)]);
		final genericBoxOwner = new HxClassDecl("GenericBoxOwner", false, [
			new HxFunctionDecl("make", Public, false, [], "Void", [
				SVar("intBox", "", ENew("GenericBox", [EInt(12)]), HxPos.unknown()),
				SVar("stringBox", "", ENew("GenericBox", [EString("12")]), HxPos.unknown()),
				SVar("fnBox", "", ENew("GenericBox", [ELambda(["i"], EBinop("*", EIdent("i"), EIdent("i")))]), HxPos.unknown())
			], "")
		], []);
		final genericBoxNames = new StringMap<Bool>();
		for (name in ["GenericBox", "GenericBoxOwner"])
			genericBoxNames.set(name, true);
		final genericBoxClasses = new StringMap<HxClassDecl>();
		genericBoxClasses.set("GenericBox", genericBox);
		genericBoxClasses.set("GenericBoxOwner", genericBoxOwner);
		final genericBoxLookup = {names: genericBoxNames, byName: genericBoxClasses};
		final genericBoxLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(genericBox, genericBoxLookup).join("\n");
		final genericBoxOwnerLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(HxClassDecl.getFunctions(genericBoxOwner)[0],
			genericBoxOwner, genericBoxLookup)
			.join("\n");
		assertContains(genericBoxLines, "template<typename T>\nstruct GenericBox {",
			"C++ generic helper classes should render as templates instead of erasing T to std::string");
		assertContains(genericBoxLines, "T value;", "C++ generic helper fields should preserve the type parameter");
		assertContains(genericBoxLines, "GenericBox(T value) : value(value) {",
			"C++ generic helper constructors should initialize T fields without requiring default construction or assignment");
		assertTrue(genericBoxLines.indexOf("this->value = value;") < 0,
			"C++ generic helper constructors should not body-assign T fields because lambdas can delete copy assignment");
		assertContains(genericBoxLines, "std::shared_ptr<GenericBox<T>> __hxhx_make_shared_GenericBox(T value) {",
			"C++ generic helper classes should emit a factory that can deduce lambdas and anonymous value types");
		final genericDefaultNode = new HxClassDecl("GenericDefaultNode", false, [
			new HxFunctionDecl("new", Public, false, [
				new HxFunctionArg("item", "T", NoDefault, false, false),
				new HxFunctionArg("height", "Int", Default(EInt(-1)), false, false)
			], "Void", [], "")
		], [], "", ["__hxhx_type_params=T"]);
		genericBoxNames.set("GenericDefaultNode", true);
		genericBoxClasses.set("GenericDefaultNode", genericDefaultNode);
		final genericDefaultNodeFactoryDecl = @:privateAccess
			backend.cpp.CppTargetCore.renderGenericClassFactoryDeclaration(genericDefaultNode, genericBoxLookup).join("\n");
		final genericDefaultNodeLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(genericDefaultNode, genericBoxLookup).join("\n");
		assertContains(genericDefaultNodeFactoryDecl,
			"std::shared_ptr<GenericDefaultNode<T>> __hxhx_make_shared_GenericDefaultNode(T item, int height = -1);",
			"C++ generic factory declarations may carry constructor defaults");
		assertContains(genericDefaultNodeLines, "std::shared_ptr<GenericDefaultNode<T>> __hxhx_make_shared_GenericDefaultNode(T item, int height) {",
			"C++ generic factory definitions should omit defaults because declarations already provide them");
		assertTrue(genericDefaultNodeLines.indexOf("__hxhx_make_shared_GenericDefaultNode(T item, int height = -1)") < 0,
			"C++ generic factory definitions must not redeclare default arguments");
		assertContains(genericBoxOwnerLines, "auto intBox = __hxhx_make_shared_GenericBox(12);",
			"C++ generic helper construction should use the deducing factory for primitive values");
		assertContains(genericBoxOwnerLines, "auto stringBox = __hxhx_make_shared_GenericBox(\"12\");",
			"C++ generic helper construction should use the deducing factory for string values");
		assertContains(genericBoxOwnerLines, "auto fnBox = __hxhx_make_shared_GenericBox([&](auto i) { return (i * i); });",
			"C++ generic helper construction should use the deducing factory for function values");
		assertTrue(genericBoxOwnerLines.indexOf("std::make_shared<GenericBox>(") < 0,
			"C++ generic helper construction should not instantiate the erased non-template class shape");
		final templateSurfaceKind = new HxClassDecl("TemplateSurfaceKind", false, [], [
			new HxFieldDecl("Alpha", Public, true, "String", EString("alpha")),
			new HxFieldDecl("Beta", Public, true, "String", EString("beta"))
		]);
		final templateSurfaceBox = new HxClassDecl("TemplateSurfaceBox", false, [], [new HxFieldDecl("kind", Public, false, "TemplateSurfaceKind<T>", null)],
			"", ["__hxhx_type_params=T"]);
		genericBoxNames.set("TemplateSurfaceKind", true);
		genericBoxNames.set("TemplateSurfaceBox", true);
		genericBoxClasses.set("TemplateSurfaceKind", templateSurfaceKind);
		genericBoxClasses.set("TemplateSurfaceBox", templateSurfaceBox);
		final templateSurfaceKindLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperClass(templateSurfaceKind, genericBoxLookup).join("\n");
		final templateSurfaceBoxLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(templateSurfaceBox, genericBoxLookup).join("\n");
		assertContains(templateSurfaceKindLines, "struct TemplateSurfaceKind {",
			"C++ enum-kind-style helper classes with static values should render as non-template structs");
		assertTrue(templateSurfaceKindLines.indexOf("template<typename T>\nstruct TemplateSurfaceKind") < 0,
			"C++ enum-kind-style helper classes should not gain fake template params");
		assertContains(templateSurfaceBoxLines, "std::shared_ptr<TemplateSurfaceKind> kind = nullptr;",
			"C++ fields typed as non-template helper classes with generic-looking hints should drop invalid template args");
		assertTrue(templateSurfaceBoxLines.indexOf("TemplateSurfaceKind<T>") < 0,
			"C++ non-template helper class references must not leak source generic args into generated C++");
		final nestedGenericHolder = new HxClassDecl("NestedGenericHolder", false, [
			new HxFunctionDecl("new", Public, false, [new HxFunctionArg("box", "GenericBox<T>", NoDefault, false, false)], "Void",
				[SExpr(EBinop("=", EField(EThis, "box"), EIdent("box")), HxPos.unknown())], "")
		], [new HxFieldDecl("box", Public, false, "GenericBox<T>", null)]);
		genericBoxNames.set("NestedGenericHolder", true);
		genericBoxClasses.set("NestedGenericHolder", nestedGenericHolder);
		final nestedGenericHolderLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(nestedGenericHolder, genericBoxLookup).join("\n");
		assertContains(nestedGenericHolderLines, "template<typename T>\nstruct NestedGenericHolder {",
			"C++ helper classes should infer class template params from nested field and constructor type hints");
		assertContains(nestedGenericHolderLines, "std::shared_ptr<GenericBox<T>> box = nullptr;",
			"C++ nested generic helper fields should preserve template arguments");
		final selfGenericNode = new HxClassDecl("SelfGenericNode", false, [
			new HxFunctionDecl("new", Public, false, [
				new HxFunctionArg("item", "T", NoDefault, false, false),
				new HxFunctionArg("next", "SelfGenericNode<T>", NoDefault, false, false)
			], "Void", [
				SExpr(EBinop("=", EField(EThis, "item"), EIdent("item")), HxPos.unknown()),
				SExpr(EBinop("=", EField(EThis, "next"), EIdent("next")), HxPos.unknown())
			], "")
		], [
			new HxFieldDecl("item", Public, false, "T", null),
			new HxFieldDecl("next", Public, false, "SelfGenericNode<T>", null)
		]);
		final selfGenericList = new HxClassDecl("SelfGenericList", false, [
			new HxFunctionDecl("new", Public, false, [], "Void", [], ""),
			new HxFunctionDecl("filter", Public, false, [new HxFunctionArg("f", "T -> Bool", NoDefault, false, false)], "SelfGenericList<T>", [
				SVar("l2", "", ENew("SelfGenericList", []), HxPos.unknown()),
				SReturn(EIdent("l2"), HxPos.unknown())
			], ""),
			new HxFunctionDecl("rawFilter", Public, false, [], "SelfGenericList", [
				SVar("l3", "", ENew("SelfGenericList", []), HxPos.unknown()),
				SReturn(EIdent("l3"), HxPos.unknown())
			], "")
		], [new HxFieldDecl("h", Public, false, "SelfGenericNode<T>", null)]);
		for (name in ["SelfGenericNode", "SelfGenericList"])
			genericBoxNames.set(name, true);
		genericBoxClasses.set("SelfGenericNode", selfGenericNode);
		genericBoxClasses.set("SelfGenericList", selfGenericList);
		final selfGenericNodeLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(selfGenericNode, genericBoxLookup).join("\n");
		final selfGenericListLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(selfGenericList, genericBoxLookup).join("\n");
		assertContains(selfGenericNodeLines, "template<typename T>\nstruct SelfGenericNode {",
			"C++ self-referential generic helper classes should stay templates instead of forward-declaring fake T");
		assertContains(selfGenericNodeLines, "std::shared_ptr<SelfGenericNode<T>> next = nullptr;",
			"C++ self-referential generic helper fields should preserve the owner template argument");
		assertContains(selfGenericListLines, "template<typename T>\nstruct SelfGenericList {",
			"C++ generic containers with self-returning methods should stay templates");
		assertContains(selfGenericListLines, "std::shared_ptr<SelfGenericList<T>> filter(std::function<bool(T)> f) {",
			"C++ generic container methods should preserve owner template parameters in returns and function args");
		assertContains(selfGenericListLines, "std::shared_ptr<SelfGenericList<T>> rawFilter() {",
			"C++ raw generic return hints inside a matching generic scope should preserve owner template parameters");
		assertContains(selfGenericListLines, "auto l2 = __hxhx_make_shared_SelfGenericList<T>();",
			"C++ zero-arg construction inside a generic owner should pass explicit template args to the deducing factory");
		final stringGenericListOwner = new HxClassDecl("StringGenericListOwner", false, [
			new HxFunctionDecl("make", Public, false, [], "SelfGenericList<String>", [
				SVar("list", "", ENew("SelfGenericList", []), HxPos.unknown()),
				SReturn(EIdent("list"), HxPos.unknown())
			], "")
		], []);
		genericBoxNames.set("StringGenericListOwner", true);
		genericBoxClasses.set("StringGenericListOwner", stringGenericListOwner);
		final stringGenericListOwnerLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperMethod(HxClassDecl.getFunctions(stringGenericListOwner)[0], stringGenericListOwner, genericBoxLookup)
				.join("\n");
		assertContains(stringGenericListOwnerLines, "auto list = __hxhx_make_shared_SelfGenericList<std::string>();",
			"C++ zero-arg generic construction should use the expected return type when constructor arguments cannot deduce T");
		final genericBase = new HxClassDecl("GenericBase", false, [new HxFunctionDecl("new", Public, false, [], "Void", [], "")],
			[new HxFieldDecl("value", Public, false, "T", null)], "", ["__hxhx_type_params=T"]);
		final genericSub = new HxClassDecl("GenericSub", false, [], [], "GenericBase<T>", ["__hxhx_type_params=T"]);
		final genericRawSub = new HxClassDecl("GenericRawSub", false, [
			new HxFunctionDecl("copyValue", Public, false, [], "Void", [
				SVar("copied", "GenericRawSub<T>", ENew("GenericRawSub", []), HxPos.unknown()),
				SExpr(EBinop("=", EField(EIdent("copied"), "value"), EIdent("value")), HxPos.unknown())
			], "")
		], [], "GenericBase", ["__hxhx_type_params=T"]);
		genericBoxNames.set("GenericBase", true);
		genericBoxNames.set("GenericSub", true);
		genericBoxNames.set("GenericRawSub", true);
		genericBoxClasses.set("GenericBase", genericBase);
		genericBoxClasses.set("GenericSub", genericSub);
		genericBoxClasses.set("GenericRawSub", genericRawSub);
		final genericSubLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(genericSub, genericBoxLookup).join("\n");
		final genericRawSubLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(genericRawSub, genericBoxLookup).join("\n");
		final genericRawSubFactoryDecl = @:privateAccess
			backend.cpp.CppTargetCore.renderGenericClassFactoryDeclaration(genericRawSub, genericBoxLookup).join("\n");
		assertContains(genericSubLines, "template<typename T>\nstruct GenericSub : public GenericBase<T> {",
			"C++ generic subclasses should preserve template arguments in their base type");
		assertContains(genericRawSubLines, "template<typename T>\nstruct GenericRawSub : public GenericBase<T> {",
			"C++ raw generic base hints inside a matching generic scope should preserve template arguments");
		assertContains(genericRawSubFactoryDecl, "std::shared_ptr<GenericRawSub<T>> __hxhx_make_shared_GenericRawSub();",
			"C++ generic classes with implicit constructors should still declare zero-arg factories");
		assertContains(genericRawSubLines, "std::shared_ptr<GenericRawSub<T>> __hxhx_make_shared_GenericRawSub() {",
			"C++ generic classes with implicit constructors should still emit zero-arg factories");
		assertContains(genericRawSubLines, "(copied->value) = this->value;", "C++ generic subclasses should qualify inherited dependent-base field reads");
		final parsedListSortModule = new HxParser("class ListSortLike { public static function sort<T:{prev:T, next:T}>(list:T, cmp:T->T->Int):T { var p:T = list; var q:T = p; q = q.next; q.prev = p; return list; } }")
			.parseModule("ListSortLike");
		final parsedListSortOwner = HxModuleDecl.getMainClass(parsedListSortModule);
		final parsedListSortFn = HxClassDecl.getFunctions(parsedListSortOwner)[0];
		final parsedListSortNames = new StringMap<Bool>();
		parsedListSortNames.set("ListSortLike", true);
		final parsedListSortClasses = new StringMap<HxClassDecl>();
		parsedListSortClasses.set("ListSortLike", parsedListSortOwner);
		final parsedListSortLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperMethod(parsedListSortFn, parsedListSortOwner, {
				names: parsedListSortNames,
				byName: parsedListSortClasses
			}).join("\n");
		assertContains(parsedListSortLines, "template<typename T>\n  static T sort(T list, std::function<int(T, T)> cmp) {",
			"C++ function-level generic methods should preserve method type params instead of erasing T to string");
		assertContains(parsedListSortLines, "T p = list;", "C++ ListSort-like locals with T hints should stay typed as T");
		assertContains(parsedListSortLines, "T q = p;", "C++ ListSort-like dependent node locals should stay typed as T");
		assertContains(parsedListSortLines, "q = (q.next);", "C++ ListSort-like next field access should stay on the generic node type");
		assertContains(parsedListSortLines, "(q.prev) = p;", "C++ ListSort-like prev field access should stay on the generic node type");
		assertTrue(parsedListSortLines.indexOf("std::string list") < 0,
			"C++ ListSort-like method args should not collapse function-level generic T to std::string");
		final parsedListSortNullModule = new HxParser("class ListSortNullLike { public static function sort<T:{prev:T, next:T}>(list:T):T { return null; } }")
			.parseModule("ListSortNullLike");
		final parsedListSortNullOwner = HxModuleDecl.getMainClass(parsedListSortNullModule);
		final parsedListSortNullNames = new StringMap<Bool>();
		parsedListSortNullNames.set("ListSortNullLike", true);
		final parsedListSortNullClasses = new StringMap<HxClassDecl>();
		parsedListSortNullClasses.set("ListSortNullLike", parsedListSortNullOwner);
		final parsedListSortNullLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperMethod(HxClassDecl.getFunctions(parsedListSortNullOwner)[0], parsedListSortNullOwner, {
				names: parsedListSortNullNames,
				byName: parsedListSortNullClasses
			}).join("\n");
		assertContains(parsedListSortNullLines, "template<typename T>\n  static T sort(T list) {\n    return nullptr;\n  }",
			"C++ ListSort-like generic null returns should preserve nullable generic defaults");
		assertTrue(parsedListSortNullLines.indexOf("static_cast<int>(nullptr)") < 0,
			"C++ ListSort-like generic null returns should not collapse through the int fallback");
		final parsedFunctionNullModule = new HxParser("class DispatcherLike { public function remove(handler:String->Void):String->Void { return null; } }")
			.parseModule("DispatcherLike");
		final parsedFunctionNullOwner = HxModuleDecl.getMainClass(parsedFunctionNullModule);
		final parsedFunctionNullNames = new StringMap<Bool>();
		parsedFunctionNullNames.set("DispatcherLike", true);
		final parsedFunctionNullClasses = new StringMap<HxClassDecl>();
		parsedFunctionNullClasses.set("DispatcherLike", parsedFunctionNullOwner);
		final parsedFunctionNullLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(parsedFunctionNullOwner, {
			names: parsedFunctionNullNames,
			byName: parsedFunctionNullClasses
		}).join("\n");
		assertContains(parsedFunctionNullLines,
			"std::function<void(std::string)> remove(std::function<void(std::string)> handler) {\n    return nullptr;\n  }",
			"C++ function-typed null returns should use the callable default instead of numeric fallback casts");
		assertTrue(parsedFunctionNullLines.indexOf("static_cast<int>(nullptr)") < 0,
			"C++ function-typed null returns should not collapse through the int fallback");
		final parsedShadowGenericModule = new HxParser("class ShadowGenericOwner<T> { public var item:T; public function new(item:T) this.item = item; public function same<T>(value:T):T { return value; } }")
			.parseModule("ShadowGenericOwner");
		final parsedShadowGenericOwner = HxModuleDecl.getMainClass(parsedShadowGenericModule);
		final parsedShadowGenericNames = new StringMap<Bool>();
		parsedShadowGenericNames.set("ShadowGenericOwner", true);
		final parsedShadowGenericClasses = new StringMap<HxClassDecl>();
		parsedShadowGenericClasses.set("ShadowGenericOwner", parsedShadowGenericOwner);
		final parsedShadowGenericLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperClass(parsedShadowGenericOwner, {
				names: parsedShadowGenericNames,
				byName: parsedShadowGenericClasses
			}).join("\n");
		assertContains(parsedShadowGenericLines, "template<typename T>\nstruct ShadowGenericOwner {",
			"C++ owner generic should keep the source template parameter");
		assertContains(parsedShadowGenericLines, "template<typename T__fn>\n  T__fn same(T__fn value) {",
			"C++ method generics that shadow owner generics should be renamed instead of emitting illegal nested typename T");
		assertTrue(parsedShadowGenericLines.indexOf("template<typename T>\n  T same(T value)") < 0,
			"C++ method generics must not shadow the owner template parameter name");
		final parsedForwardedStringModule = new HxParser("class PolyBuf { public function new() {} public function add<T>(x:T):Void {} } class JoinOwner<T> { public function join(sep:String):String { var b = new PolyBuf(); b.add(sep); return sep; } }")
			.parseModule("JoinOwner");
		final parsedForwardedStringNames = new StringMap<Bool>();
		final parsedForwardedStringClasses = new StringMap<HxClassDecl>();
		for (cls in HxModuleDecl.getClasses(parsedForwardedStringModule)) {
			final name = HxClassDecl.getName(cls);
			parsedForwardedStringNames.set(name, true);
			parsedForwardedStringClasses.set(name, cls);
		}
		final parsedForwardedStringOwner = parsedForwardedStringClasses.get("JoinOwner");
		final parsedForwardedStringLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperClass(parsedForwardedStringOwner, {
				names: parsedForwardedStringNames,
				byName: parsedForwardedStringClasses
			}).join("\n");
		assertContains(parsedForwardedStringLines, "std::string join(std::string sep) {",
			"C++ callable inference must keep String args string-shaped when forwarding into another class' polymorphic helper");
		assertTrue(parsedForwardedStringLines.indexOf("join(T__fn sep)") < 0,
			"C++ callable inference must not borrow the current owner generic for unrelated receiver method type params");
		final methodGenericBuffer = new HxClassDecl("MethodGenericBuffer", false, [
			new HxFunctionDecl("new", Public, false, [], "Void", [], ""),
			new HxFunctionDecl("add", Public, false, [new HxFunctionArg("x", "T", NoDefault, false, false)], "Void",
				[SExpr(EBinop("+=", EField(EThis, "b"), EIdent("x")), HxPos.unknown())], "")
		], [new HxFieldDecl("b", Public, false, "String", null)]);
		final methodGenericBufferOwner = new HxClassDecl("MethodGenericBufferOwner", false, [
			new HxFunctionDecl("make", Public, false, [], "Void", [
				SVar("buf", "", ENew("MethodGenericBuffer", []), HxPos.unknown()),
				SExpr(ECall(EField(EIdent("buf"), "add"), [EString("x")]), HxPos.unknown())
			], "")
		], []);
		final methodGenericBufferNames = new StringMap<Bool>();
		for (name in ["MethodGenericBuffer", "MethodGenericBufferOwner"])
			methodGenericBufferNames.set(name, true);
		final methodGenericBufferClasses = new StringMap<HxClassDecl>();
		methodGenericBufferClasses.set("MethodGenericBuffer", methodGenericBuffer);
		methodGenericBufferClasses.set("MethodGenericBufferOwner", methodGenericBufferOwner);
		final methodGenericBufferLookup = {names: methodGenericBufferNames, byName: methodGenericBufferClasses};
		final methodGenericBufferLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperClass(methodGenericBuffer, methodGenericBufferLookup).join("\n");
		final methodGenericBufferOwnerLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperMethod(HxClassDecl.getFunctions(methodGenericBufferOwner)[0], methodGenericBufferOwner,
				methodGenericBufferLookup)
				.join("\n");
		assertContains(methodGenericBufferLines, "struct MethodGenericBuffer {",
			"C++ method-local generic-looking args should not make the helper class a template");
		assertTrue(methodGenericBufferLines.indexOf("template<typename T>\nstruct MethodGenericBuffer") < 0,
			"C++ should not over-template StringBuf-shaped classes whose T appears only on methods");
		assertContains(methodGenericBufferOwnerLines, "auto buf = std::make_shared<MethodGenericBuffer>();",
			"C++ zero-arg construction of method-generic utility classes should not require template deduction");
		final staticGenericFacade = new HxClassDecl("StaticGenericFacade", false, [
			new HxFunctionDecl("is", Public, true, [
				new HxFunctionArg("v", "S", NoDefault, false, false),
				new HxFunctionArg("t", "T", NoDefault, false, false)
			], "Bool", [SReturn(EBool(true), HxPos.unknown())], "")
		], []);
		final staticGenericFacadeOwner = new HxClassDecl("StaticGenericFacadeOwner", false, [
			new HxFunctionDecl("check", Public, false, [], "Bool", [
				SReturn(ECall(EField(EIdent("StaticGenericFacade"), "is"), [EString("v"), EString("t")]), HxPos.unknown())
			], "")
		], []);
		final staticGenericFacadeNames = new StringMap<Bool>();
		for (name in ["StaticGenericFacade", "StaticGenericFacadeOwner"])
			staticGenericFacadeNames.set(name, true);
		final staticGenericFacadeClasses = new StringMap<HxClassDecl>();
		staticGenericFacadeClasses.set("StaticGenericFacade", staticGenericFacade);
		staticGenericFacadeClasses.set("StaticGenericFacadeOwner", staticGenericFacadeOwner);
		final staticGenericFacadeLookup = {names: staticGenericFacadeNames, byName: staticGenericFacadeClasses};
		final staticGenericFacadeLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperClass(staticGenericFacade, staticGenericFacadeLookup).join("\n");
		final staticGenericFacadeOwnerLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperMethod(HxClassDecl.getFunctions(staticGenericFacadeOwner)[0], staticGenericFacadeOwner,
				staticGenericFacadeLookup)
				.join("\n");
		assertContains(staticGenericFacadeLines, "struct StaticGenericFacade {",
			"C++ static utility facades should stay normal classes even with generic-looking method args");
		assertTrue(staticGenericFacadeLines.indexOf("template<typename") < 0, "C++ should not over-template Std-shaped static utility facades");
		assertContains(staticGenericFacadeOwnerLines, "return StaticGenericFacade::is(\"v\", \"t\");",
			"C++ static facade calls should not require class template arguments");
		final parsedClassParamModule = new HxParser("class ParsedMisc { public static function isOfType<T>(v:Dynamic, t:Class<T>):Bool { return true; } }")
			.parseModule("ParsedMisc");
		final parsedClassParamOwner = HxModuleDecl.getMainClass(parsedClassParamModule);
		final parsedClassParamNames = new StringMap<Bool>();
		parsedClassParamNames.set("ParsedMisc", true);
		final parsedClassParamClasses = new StringMap<HxClassDecl>();
		parsedClassParamClasses.set("ParsedMisc", parsedClassParamOwner);
		final parsedClassParamLookup = {names: parsedClassParamNames, byName: parsedClassParamClasses};
		final parsedClassParamLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperClass(parsedClassParamOwner, parsedClassParamLookup).join("\n");
		assertContains(parsedClassParamLines, "struct ParsedMisc {",
			"C++ parsed method-generic facades should stay normal classes when the generic only belongs to a static method");
		assertContains(parsedClassParamLines, "static bool isOfType(std::string v, std::shared_ptr<Class> t)",
			"C++ parsed Class<T> method params should preserve the Class meta-value parameter");
		final dynamicIsOfTypeOwner = new HxClassDecl("DynamicIsOfTypeOwner", false, [
			new HxFunctionDecl("isOfType", Public, true, [
				new HxFunctionArg("v", "Dynamic", NoDefault, false, false),
				new HxFunctionArg("t", "Dynamic", NoDefault, false, false)
			], "Bool", [SReturn(EBool(true), HxPos.unknown())], "")
		], []);
		final dynamicIsOfTypeNames = new StringMap<Bool>();
		dynamicIsOfTypeNames.set("DynamicIsOfTypeOwner", true);
		final dynamicIsOfTypeClasses = new StringMap<HxClassDecl>();
		dynamicIsOfTypeClasses.set("DynamicIsOfTypeOwner", dynamicIsOfTypeOwner);
		final dynamicIsOfTypeLookup = {names: dynamicIsOfTypeNames, byName: dynamicIsOfTypeClasses};
		final dynamicIsOfTypeLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperClass(dynamicIsOfTypeOwner, dynamicIsOfTypeLookup).join("\n");
		assertContains(dynamicIsOfTypeLines, "template<typename TValue, typename TType>\n  static bool isOfType(const TValue& v, const TType& t)",
			"C++ Dynamic/Dynamic isOfType-style helpers should accept class meta-values without erasing the second arg to std::string");
		final staticFieldOwner = new HxClassDecl("StaticFieldOwner", false, [
			new HxFunctionDecl("set", Public, true, [new HxFunctionArg("v", "String", NoDefault, false, false)], "Void", [
				SExpr(EBinop("=", EIdent("store"), EIdent("v")), HxPos.unknown()),
				SExpr(EBinop("=", EField(EIdent("StaticFieldOwner"), "store"), EString("class")), HxPos.unknown())
			], "")
		], [new HxFieldDecl("store", Public, true, "String", EString("init"))]);
		final staticFieldNames = new StringMap<Bool>();
		staticFieldNames.set("StaticFieldOwner", true);
		final staticFieldClasses = new StringMap<HxClassDecl>();
		staticFieldClasses.set("StaticFieldOwner", staticFieldOwner);
		final staticFieldLookup = {names: staticFieldNames, byName: staticFieldClasses};
		final staticFieldLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(staticFieldOwner, staticFieldLookup).join("\n");
		assertContains(staticFieldLines, "inline static std::string store = std::string(\"init\");",
			"C++ helper classes should emit static fields instead of dropping them from the struct");
		assertContains(staticFieldLines, "store = v;", "C++ static methods should type unqualified same-owner static field access");
		assertContains(staticFieldLines, "StaticFieldOwner::store = \"class\";", "C++ static field access through the owner type should use scope resolution");
		final staticHookOwner = new HxClassDecl("StaticHookOwner", false, [
			new HxFunctionDecl("bind", Public, false, [new HxFunctionArg("hook", "Void->Void", NoDefault, false, false)], "Void", [
				SExpr(EBinop("=", EField(EIdent("Assert"), "createAsync"), EIdent("hook")), HxPos.unknown())
			], ""),
			new HxFunctionDecl("bindInstance", Public, false, [], "Void", [
				SExpr(EBinop("=", EField(EIdent("Assert"), "createAsync"), EField(EThis, "addAsync")), HxPos.unknown())
			], ""),
			new HxFunctionDecl("addAsync", Public, false, [
				new HxFunctionArg("f", "Void->Void", NoDefault, true, false),
				new HxFunctionArg("timeout", "Int", NoDefault, true, false)
			], "Void->Void", [SReturn(ELambda([], ENull), HxPos.unknown())], "")
		], []);
		final staticHookNames = new StringMap<Bool>();
		staticHookNames.set("StaticHookOwner", true);
		final staticHookClasses = new StringMap<HxClassDecl>();
		staticHookClasses.set("StaticHookOwner", staticHookOwner);
		final staticHookLookup = {names: staticHookNames, byName: staticHookClasses};
		final staticHookLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(staticHookOwner, staticHookLookup).join("\n");
		assertContains(staticHookLines, "Assert::createAsync = hook;",
			"C++ assignment to type-shaped static extern fields should use scope resolution even when the extern class is not in the local registry");
		assertContains(staticHookLines, "Assert::createAsync = [&](auto f, auto timeout) { return this->addAsync(f, timeout); };",
			"C++ instance method values assigned to static hooks should lower to callable wrappers");
		assertTrue(staticHookLines.indexOf("Assert::createAsync = this->addAsync;") < 0,
			"C++ instance method values must not render as uncalled member references");
		assertTrue(staticHookLines.indexOf("(Assert.createAsync) = hook") < 0,
			"C++ static extern field assignments must not preserve Haxe dotted field syntax");
		final sysToolsOwner = new HxClassDecl("SysTools", false, [
			new HxFunctionDecl("needsEscape", Public, true, [new HxFunctionArg("c", "Int", NoDefault, false, false)], "Bool", [
				SReturn(EBinop(">=", ECall(EField(EIdent("winMetaCharacters"), "indexOf"), [EIdent("c")]), EInt(0)), HxPos.unknown())
			], ""),
			new HxFunctionDecl("quoteUnixArg", Public, true, [new HxFunctionArg("argument", "String", NoDefault, false, false)], "String", [
				SReturn(EBinop("+", EString("'"), ECall(EField(EIdent("StringTools"), "replace"), [EIdent("argument"), EString("'"), EString("'\"'\"'")])),
					HxPos.unknown())
			], "")
		], [
			new HxFieldDecl("winMetaCharacters", Public, true, "ReadOnlyArray<Int>", EArrayDecl([EInt(32)]))
		]);
		final stringToolsOwner = new HxClassDecl("StringTools", false, [], [
			new HxFieldDecl("winMetaCharacters", Public, true, "Array<Int>", EField(EField(EIdent("haxe"), "SysTools"), "winMetaCharacters"))
		]);
		final timerOwner = new HxClassDecl("Timer", false, [
			new HxFunctionDecl("stamp", Public, true, [], "Float", [SReturn(EFloat(0.0), HxPos.unknown())], "")
		], []);
		final qualifiedStdNames = new StringMap<Bool>();
		for (name in ["SysTools", "StringTools", "Timer"])
			qualifiedStdNames.set(name, true);
		final qualifiedStdClasses = new StringMap<HxClassDecl>();
		qualifiedStdClasses.set("SysTools", sysToolsOwner);
		qualifiedStdClasses.set("StringTools", stringToolsOwner);
		qualifiedStdClasses.set("Timer", timerOwner);
		final sysToolsLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(sysToolsOwner,
			{names: qualifiedStdNames, byName: qualifiedStdClasses})
			.join("\n");
		final stringToolsLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(stringToolsOwner,
			{names: qualifiedStdNames, byName: qualifiedStdClasses})
			.join("\n");
		assertContains(sysToolsLines, "inline static std::vector<int> winMetaCharacters = std::vector<int>{32};",
			"C++ SysTools.winMetaCharacters should erase ReadOnlyArray<Int> to vector<int> for native field initialization");
		assertContains(sysToolsLines, "return (__hxhx_index_of(winMetaCharacters, c, 0) >= 0);",
			"C++ indexOf on winMetaCharacters should pass the integer needle directly");
		assertContains(sysToolsLines, "__hxhx_replace(std::string(argument),",
			"C++ SysTools helpers should lower StringTools.replace through target support instead of requiring StringTools definition order");
		assertTrue(sysToolsLines.indexOf("StringTools::replace(argument") < 0,
			"C++ SysTools helpers should not depend on a fully declared StringTools helper for replace");
		assertContains(stringToolsLines, "inline static std::vector<int> winMetaCharacters = SysTools::winMetaCharacters;",
			"C++ StringTools.winMetaCharacters should consume the SysTools vector<int> field directly");
		final qualifiedStdScope = @:privateAccess backend.cpp.CppTargetCore.renderScope(sysToolsOwner,
			{names: qualifiedStdNames, byName: qualifiedStdClasses}, "void");
		assertTrue(@:privateAccess
			backend.cpp.CppTargetCore.renderExpr(EField(EField(EIdent("haxe"), "SysTools"), "winMetaCharacters"),
				qualifiedStdScope) == "SysTools::winMetaCharacters",
			"C++ qualified stdlib static field access should lower to the generated helper type");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.renderExpr(ECall(EField(EField(EIdent("haxe"), "Timer"), "stamp"), []),
			qualifiedStdScope) == "Timer::stamp()",
			"C++ qualified stdlib static calls should lower to the generated helper type");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.shouldForwardDeclareMissingType("EventArg", staticFieldLookup),
			"C++ forward declarations should include referenced non-core type hints even when the class is not emitted as a helper");
		assertTrue(! @:privateAccess backend.cpp.CppTargetCore.shouldForwardDeclareMissingType("String", staticFieldLookup),
			"C++ forward declarations should not emit primitive/core type hints");
		final redeclaredLocalOwner = new HxClassDecl("RedeclaredLocalOwner", false, [
			new HxFunctionDecl("pick", Public, false, [], "String", [
				SVar("mg", "", EInt(12), HxPos.unknown()),
				SVar("mg", "", EString("12"), HxPos.unknown()),
				SReturn(EIdent("mg"), HxPos.unknown())
			], "")
		], []);
		final redeclaredLocalNames = new StringMap<Bool>();
		redeclaredLocalNames.set("RedeclaredLocalOwner", true);
		final redeclaredLocalClasses = new StringMap<HxClassDecl>();
		redeclaredLocalClasses.set("RedeclaredLocalOwner", redeclaredLocalOwner);
		final redeclaredLocalLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(HxClassDecl.getFunctions(redeclaredLocalOwner)[0],
			redeclaredLocalOwner, {
				names: redeclaredLocalNames,
				byName: redeclaredLocalClasses
			})
			.join("\n");
		assertContains(redeclaredLocalLines, "auto mg = 12;", "C++ local emission should keep the first Haxe local name stable");
		assertContains(redeclaredLocalLines, "auto mg_2 = std::string(\"12\");", "C++ local emission should uniquify same-scope Haxe local redeclarations");
		assertContains(redeclaredLocalLines, "return std::string(mg_2);",
			"C++ identifier emission should resolve to the latest same-name Haxe local after redeclaration");
		final restIterator = new HxClassDecl("RestIterator", false, [
			new HxFunctionDecl("new", Public, false, [new HxFunctionArg("args", "Rest", NoDefault, false, false)], "Void",
				[SExpr(EBinop("=", EField(EThis, "args"), EIdent("args")), HxPos.unknown())], "")
		], [new HxFieldDecl("args", Public, false, "Rest", null)]);
		final rest = new HxClassDecl("Rest", false, [
			new HxFunctionDecl("iterator", Public, false, [], "RestIterator", [SReturn(ENew("RestIterator", [EThis]), HxPos.unknown())], "")
		], [new HxFieldDecl("length", Public, false, "Int", null)]);
		final restNames = new StringMap<Bool>();
		for (name in ["Rest", "RestIterator"])
			restNames.set(name, true);
		final restClasses = new StringMap<HxClassDecl>();
		restClasses.set("Rest", rest);
		restClasses.set("RestIterator", restIterator);
		final restLookup = {names: restNames, byName: restClasses};
		final restIteratorLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(restIterator, restLookup).join("\n");
		final restLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(rest, restLookup).join("\n");
		assertContains(restIteratorLines, "RestIterator(std::shared_ptr<Rest> args) : args(args) {",
			"C++ helper constructors should keep class-typed parameters as reference handles");
		assertContains(restLines, "return std::make_shared<RestIterator>(__hxhx_borrowed_shared<Rest>(this));",
			"C++ helper constructors should pass `this` through the expected class reference handle");
		assertTrue(restLines.indexOf("std::make_shared<RestIterator>((*this))") < 0,
			"C++ helper constructors should not pass the current object by value to shared_ptr-backed parameters");
		final genericRest = new HxClassDecl("Rest", false, [
			new HxFunctionDecl("new", Public, false, [new HxFunctionArg("array", "Array<T>", NoDefault, false, false)], "Void", [], ""),
			new HxFunctionDecl("copy", Public, false, [], "Array<T>", [SReturn(EThis, HxPos.unknown())], ""),
			new HxFunctionDecl("append", Public, false, [new HxFunctionArg("item", "T", NoDefault, false, false)], "Rest<T>", [
				SVar("result", "", ECall(EField(EThis, "copy"), []), HxPos.unknown()),
				SExpr(ECall(EField(EIdent("result"), "push"), [EIdent("item")]), HxPos.unknown()),
				SReturn(ENew("Rest", [EIdent("result")]), HxPos.unknown())
			], "")
		], [new HxFieldDecl("length", Public, false, "Int", null)], "",
			["__hxhx_type_params=T"]);
		final genericRestNames = new StringMap<Bool>();
		genericRestNames.set("Rest", true);
		final genericRestClasses = new StringMap<HxClassDecl>();
		genericRestClasses.set("Rest", genericRest);
		final genericRestLookup = {names: genericRestNames, byName: genericRestClasses};
		final genericRestLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(genericRest, genericRestLookup).join("\n");
		assertContains(genericRestLines, "std::vector<T> __values;", "C++ Rest<T> support should own vector storage");
		assertContains(genericRestLines, "std::vector<T> copy() const { return __values; }", "C++ Rest<T> support should provide copy()");
		assertContains(genericRestLines, "result.push_back(item);", "C++ Rest<T>.append support should use vector push_back");
		assertContains(genericRestLines, "std::shared_ptr<Rest<T>> __hxhx_make_shared_Rest(std::vector<T> array)",
			"C++ Rest<T> support should preserve the generic factory used by constructor lowering");
		final vectorPushMethod = new HxFunctionDecl("cloneInto", Public, true, [
			new HxFunctionArg("seed", "", NoDefault, false, false),
			new HxFunctionArg("items", "", NoDefault, false, false)
		], "", [
			SVar("clone", "", EIdent("seed"), HxPos.unknown()),
			SExpr(ECall(EField(EIdent("items"), "push"), [EIdent("clone")]), HxPos.unknown()),
			SReturn(EIdent("items"), HxPos.unknown())
		], "");
		final vectorPushLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperMethod(vectorPushMethod, genericReturnOwner, genericReturnLookup).join("\n");
		assertContains(vectorPushLines, "static std::vector<std::string> cloneInto(std::string seed, std::vector<std::string> items) {",
			"C++ helper methods should infer untyped args mutated via push as value vectors");
		assertContains(vectorPushLines, "items.push_back(clone);", "C++ vector push inference should render push_back on the inferred vector");
		assertContains(vectorPushLines, "return items;", "C++ vector push inference should return the vector instead of stringifying it");
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
		final throwExprMethod = new HxFunctionDecl("failAsString", Public, true, [], "String",
			[SReturn(ECall(EIdent("__hxhx_throw"), [EString("nope")]), HxPos.unknown())], "");
		final throwExprLines = @:privateAccess
			backend.cpp.CppTargetCore.renderHelperMethod(throwExprMethod, exprBodyOwner, exprBodyLookup).join("\n");
		assertContains(throwExprLines, "static std::string failAsString() {\n    return __hxhx_throw_as<std::string>(\"nope\");\n  }",
			"C++ throw expressions should compile in string-valued return contexts through target-owned bottom support");
		assertTrue(throwExprLines.indexOf("std::to_string(__hxhx_throw") < 0,
			"C++ throw expressions in string contexts should not be wrapped in numeric std::to_string");
		final dateToolsMake = new HxFunctionDecl("make", Public, true, [
			new HxFunctionArg("o", "{ ms:Float, seconds:Int, minutes:Int, hours:Int, days:Int }", NoDefault, false, false)
		], "", [
			SReturn(EBinop("+", EField(EIdent("o"), "ms"), EField(EIdent("o"), "seconds")), HxPos.unknown())
		], "");
		final dateToolsMakeUtc = new HxFunctionDecl("makeUtc", Public, true, [
			new HxFunctionArg("year", "Int", NoDefault, false, false),
			new HxFunctionArg("month", "Int", NoDefault, false, false),
			new HxFunctionArg("day", "Int", NoDefault, false, false),
			new HxFunctionArg("hour", "Int", NoDefault, false, false),
			new HxFunctionArg("min", "Int", NoDefault, false, false),
			new HxFunctionArg("sec", "Int", NoDefault, false, false)
		], "Float", [
			SReturn(EBinop("*", ECall(EField(EIdent("__global__"), "__hxcpp_utc_date"), [
				EIdent("year"),
				EIdent("month"),
				EIdent("day"),
				EIdent("hour"),
				EIdent("min"),
				EIdent("sec")
			]), EFloat(1000.0)), HxPos.unknown())
		], "");
		final dateToolsOwner = new HxClassDecl("DateToolsLike", false, [dateToolsMake, dateToolsMakeUtc], []);
		final dateToolsNames = new StringMap<Bool>();
		dateToolsNames.set("DateToolsLike", true);
		final dateToolsClasses = new StringMap<HxClassDecl>();
		dateToolsClasses.set("DateToolsLike", dateToolsOwner);
		final dateToolsLookup = {names: dateToolsNames, byName: dateToolsClasses};
		final dateToolsMakeLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(dateToolsMake, dateToolsOwner, dateToolsLookup).join("\n");
		assertContains(dateToolsMakeLines, "static double make(__hxhx_anon_ms_double__seconds_int__minutes_int__hours_int__days_int_ o) {",
			"C++ structural argument hints should render as concrete aggregate parameters, not strings");
		assertContains(dateToolsMakeLines, "return ((o.ms) + (o.seconds));", "C++ structural argument fields should be read through value field access");
		assertTrue(dateToolsMakeLines.indexOf("make(std::string o)") < 0, "C++ structural argument hints should not collapse to std::string");
		final dateToolsMakeUtcLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(dateToolsMakeUtc, dateToolsOwner, dateToolsLookup)
			.join("\n");
		assertContains(dateToolsMakeUtcLines, "return (__hxhx_utc_date(year, month, day, hour, min, sec) * 1000);",
			"C++ DateTools.makeUtc-like helper should lower hxcpp UTC date support instead of unresolved __global__");
		assertTrue(dateToolsMakeUtcLines.indexOf("__global__") < 0, "C++ DateTools.makeUtc-like helper should not leak __global__");
		final anyOwner = new HxClassDecl("Any", false, [
			new HxFunctionDecl("__promote", Public, false, [], "T", [SReturn(EThis, HxPos.unknown())], ""),
			new HxFunctionDecl("toString", Public, false, [], "String", [SReturn(ECall(EField(EIdent("Std"), "string"), [EThis]), HxPos.unknown())], "")
		], []);
		final anyNames = new StringMap<Bool>();
		anyNames.set("Any", true);
		final anyClasses = new StringMap<HxClassDecl>();
		anyClasses.set("Any", anyOwner);
		final anyLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(anyOwner, {names: anyNames, byName: anyClasses}).join("\n");
		assertContains(anyLines, "struct Any {", "C++ Any should render as a target-owned support surface");
		assertContains(anyLines, "std::any __value;", "C++ Any support should carry the erased payload instead of casting the wrapper");
		assertContains(anyLines, "std::any_cast<T>(__value)", "C++ Any.__promote should extract from the payload");
		assertTrue(anyLines.indexOf("static_cast<int>((*this))") < 0, "C++ Any.__promote must not cast the wrapper object itself");

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
		assertContains(source, "#include <cstdint>", "C++ smoke should include fixed-width integer types for bit reinterpret helpers");
		assertContains(source, "static double __hxhx_reinterpret_le_int32_as_float32(int value)",
			"C++ smoke should include target-owned hxcpp FP reinterpret support");
		assertContains(source, "auto suffix = std::string(\"smoke\");", "C++ smoke should emit string local vars as std::string");
		assertContains(source, "std::cout << (std::string(\"cpp-native:\") + std::string(suffix)) << std::endl;", "C++ smoke should emit println");
		assertContains(source, "std::cout << (std::string(\"trace:\") + std::string(suffix)) << std::endl;", "C++ smoke should emit trace");
		assertContains(source, "static std::string __hxhx_stringify(bool value)", "C++ smoke should include target-owned stringify support");
		assertContains(source, "static std::shared_ptr<T> __hxhx_borrowed_shared(T* value)",
			"C++ smoke should include target-owned borrowed receiver handle support");
		assertContains(source, "__hxhx_args(argc, argv)", "C++ smoke should emit Sys.args helper call");
		assertContains(source, "__hxhx_index_of(\"abc\", std::string(\"b\"), 0)", "C++ smoke should emit string indexOf helper call");
		assertContains(source, "__hxhx_index_of(args, std::string(\"needle\"), 0)", "C++ smoke should emit vector indexOf helper call");
		assertContains(source, "std::vector<std::string>{std::string(\"alpha\"), std::string(\"beta\")}", "C++ smoke should emit string array literal");
		assertContains(source, "static int helper(int x) {", "C++ smoke should emit main-class static helper function");
		assertContains(source, "helper(4)", "C++ smoke should lower direct identifier function call");
		assertContains(source, "template<typename T>\n  static std::string q(const T& v)", "C++ smoke should emit Assert.q as a template");
		assertContains(source, "Assert::q(1.5)", "C++ smoke should allow numeric Assert.q calls");
		assertContains(source, "static std::string __hxhx_stringify(const __HxMacroExpr& value)",
			"C++ smoke should stringify macro-expression values without falling through to ostream fallback");
		assertContains(source, "static double __hxhx_utc_date(int year, int month, int day, int hour, int min, int sec)",
			"C++ smoke should include target-owned hxcpp UTC date support");
		assertContains(source, "struct __hxhx_is_streamable", "C++ stringify support should detect non-streamable values before using ostream fallback");
		assertContains(source, "return __hxhx_type_name(value);", "C++ stringify support should fall back for non-streamable closure values");
		assertContains(source, "struct __hxhx_throw_bottom", "C++ smoke should include target-owned throw-expression bottom support");
		assertContains(source, "static __hxhx_throw_bottom __hxhx_throw(const T& value)", "C++ smoke should include target-owned throw-expression helper");
		assertContains(source, "static TResult __hxhx_throw_as(const T& value)", "C++ smoke should include target-owned typed throw-expression helper");
		assertContains(source, "template<typename T>\nstruct RawConstPointer {",
			"C++ smoke should expose cpp.RawConstPointer<T> as a target-owned generic support surface");
		assertContains(source, "template<typename T>\nstruct ConstPointer {",
			"C++ smoke should expose cpp.ConstPointer<T> as a target-owned generic support surface");
		assertContains(source, "struct __hxhx_anon_ms_double__seconds_int__minutes_int__hours_int__days_int_ {",
			"C++ smoke should declare structural type-hint aggregates even when the shape is used as an argument");
		assertContains(source, "static double make(__hxhx_anon_ms_double__seconds_int__minutes_int__hours_int__days_int_ o) {",
			"C++ smoke should preserve DateTools-like structural argument hints instead of emitting std::string parameters");
		assertTrue(source.indexOf("make(std::string o)") < 0, "C++ smoke should not collapse structural DateTools-like arguments to strings");
		assertContains(source, "struct LikeStatus {", "C++ smoke should emit named structural typedef helpers as concrete structs");
		assertContains(source, "std::string expectedValue = std::string();", "C++ smoke should retain LikeStatus expectedValue field");
		assertContains(source, "std::string actualValue = std::string();", "C++ smoke should retain LikeStatus actualValue field");
		assertContains(source, "std::string error = std::string();", "C++ smoke should retain LikeStatus error field");
		assertContains(source, "std::string path = std::string();", "C++ smoke should retain LikeStatus path field");
		assertContains(source, "bool recursive = false;", "C++ smoke should retain LikeStatus recursive field");
		assertContains(source, "struct MetadataDescription {", "C++ smoke should emit optional-metadata structural typedef helpers");
		assertContains(source, "std::string metadata = std::string();", "C++ smoke should retain MetadataDescription metadata field");
		assertContains(source, "std::string doc = std::string();", "C++ smoke should retain MetadataDescription doc field");
		assertContains(source, "std::vector<std::string> links = {};", "C++ smoke should preserve @:optional links field name");
		assertContains(source, "std::vector<std::string> params = {};", "C++ smoke should preserve @:optional params field name");
		assertContains(source, "std::vector<std::shared_ptr<Platform>> platforms = {};", "C++ smoke should preserve @:optional platforms field name");
		assertContains(source, "std::vector<std::shared_ptr<MetadataTarget>> targets = {};", "C++ smoke should preserve @:optional targets field name");
		assertTrue(source.indexOf("std::vector<std::string> optional =") < 0, "C++ smoke should not render metadata name optional as a structural field");
		assertContains(source, "std::any parseRec()", "C++ smoke should erase Dynamic returns as std::any for JsonParser-shaped flows");
		assertContains(source, "std::any doParseLike()",
			"C++ smoke should propagate erased Dynamic through same-owner parseRec-style calls before return inference recurses");
		assertContains(source, "static std::any parse(std::string str)",
			"C++ smoke should propagate erased Dynamic through new Parser(str).doParse()-style static wrappers");
		assertContains(source, "return __hxhx_stringify(JsonParserLike::parse(s));",
			"C++ smoke should stringify erased Dynamic parser results only at String-expected call sites");
		assertTrue(source.indexOf("static std::string parse(std::string str)") < 0,
			"C++ smoke should not collapse Dynamic parser wrappers to string-returning helpers");
		assertContains(source, "std::any parseRecScopeLike()", "C++ smoke should include JsonParser-shaped nested switch/while scope regression coverage");
		assertContains(source, "return parseNumberLike(c);", "C++ smoke should preserve outer switch locals after nested branches introduce same-named locals");
		assertTrue(source.indexOf("return parseNumberLike(c_") < 0, "C++ smoke should not leak nested C++ block-local names into later switch branches");
		assertContains(source, "int uc = __hxhx_parse_int((std::string(\"0x\") + str.substr(pos, 4))).value_or(0);",
			"C++ smoke should unwrap optional Std.parseInt results when initializing concrete Int locals");
		assertTrue(source.indexOf("int uc = __hxhx_parse_int((std::string(\"0x\") + str.substr(pos, 4)));") < 0,
			"C++ smoke should not assign std::optional<int> directly to int locals");
		assertContains(source, "std::function<std::string(std::string, std::string)> replacer = nullptr;",
			"C++ smoke should preserve JsonPrinter-shaped replacer callback signatures");
		assertContains(source, "void write(std::string k, std::any v)", "C++ smoke should keep reassigned JsonPrinter Dynamic parameters erased");
		assertContains(source, "v = valueLike();", "C++ smoke should keep JsonPrinter Dynamic parameter reassignment erased");
		assertContains(source, "v = replacer(k, __hxhx_stringify(v));", "C++ smoke should stringify erased Dynamic when calling string-shaped function values");
		assertContains(source, "write(std::to_string(i), (values[i]));",
			"C++ smoke should stringify JsonPrinter array index keys at String-shaped recursive write call sites");
		assertTrue(source.indexOf("write(i, (values[i]))") < 0, "C++ smoke should not pass raw Int array indexes to String-shaped recursive write call sites");
		assertContains(source, "if (c == std::string(\"StringMap\"))",
			"C++ smoke should lower JsonPrinter class-path comparisons to class-name values, not C++ field access");
		assertTrue(source.indexOf("((haxe.ds).StringMap)") < 0, "C++ smoke should not render haxe.ds.StringMap class constants as nested field access");
		assertContains(source, "template<typename V>\nstruct StringMap {",
			"C++ smoke should emit target-owned StringMap support when upstream-shaped code references haxe.ds.StringMap locally");
		assertContains(source, "struct Date {", "C++ smoke should emit target-owned Date support for JsonPrinter Date branches");
		assertContains(source, "std::any_cast<std::shared_ptr<StringMap<std::string>>>(v)",
			"C++ smoke should extract erased Dynamic values when a JsonPrinter class branch narrows to StringMap");
		assertContains(source, "auto __hxhx_iter_key = map->keys();", "C++ smoke should lower StringMap.keys() for-in through the Haxe iterator protocol");
		assertContains(source, "objString(__hxhx_stringify(obj));",
			"C++ smoke should stringify JsonPrinter anonymous objects at String-shaped helper call sites");
		final stdlibSupportDupDir = Path.join([root, "stdlib-support-duplication-source-only"]);
		final stdlibSupportDupEmit = BackendRegistry.createForTarget("cpp-native")
			.emit(stdlibSupportDuplicationProgram(), context(stdlibSupportDupDir, true, true));
		final stdlibSupportDupSource = File.getContent(stdlibSupportDupEmit.entryPath);
		assertTrue(countOccurrences(stdlibSupportDupSource, "struct StringMap {") == 1,
			"C++ should not emit both fallback and generated StringMap bodies when StringMap exists in the program");
		assertTrue(countOccurrences(stdlibSupportDupSource, "struct Date {") == 1,
			"C++ should not emit both fallback and generated Date bodies when Date exists in the program");
		assertContains(source, "void inferredString(std::string s)", "C++ smoke should infer JsonPrinter helper parameters forwarded to String helpers");
		assertContains(source, "inferredString(__hxhx_stringify(v));",
			"C++ smoke should stringify erased Dynamic for inferred String-typed same-owner helper calls");
		assertContains(source, "add(__hxhx_stringify(v));", "C++ smoke should stringify erased Dynamic for String-typed same-owner helper calls");
		assertContains(source, "quote(__hxhx_stringify(v));", "C++ smoke should stringify erased Dynamic for JsonPrinter quote helpers");
		assertContains(source, "objString(__hxhx_stringify(v));", "C++ smoke should stringify erased Dynamic for JsonPrinter object helper calls");
		assertContains(source, "std::isfinite(__hxhx_any_double(v))", "C++ smoke should unwrap numeric erased Dynamic before Math.isFinite");
		assertTrue(source.indexOf("replacer(k, v)") < 0, "C++ smoke should not pass raw std::any to string-shaped replacer callbacks");
		assertTrue(source.indexOf("std::isfinite(v)") < 0, "C++ smoke should not pass raw std::any to numeric Math intrinsics");
		assertContains(source, "std::any parseObjectLike()", "C++ smoke should erase Dynamic object returns as std::any");
		assertContains(source, "static std::string callStack()",
			"C++ smoke should keep string-shaped Dynamic native stack traces compatible with toHaxe(String)");
		assertContains(source, "return toHaxe(callStack());",
			"C++ smoke should pass NativeStackTrace-like Dynamic stubs to String-typed toHaxe without std::any conversion errors");
		assertContains(source, "auto field = std::string();", "C++ smoke should infer null-then-string grouped locals as strings instead of std::nullptr_t");
		assertContains(source, "std::optional<bool> comma = std::nullopt;", "C++ smoke should preserve grouped Null<Bool> locals instead of dropping comma");
		assertContains(source, "__hxhx_reflect_set_field(obj, std::string(field), parseRec());",
			"C++ smoke should lower Reflect.setField through backend-owned erased reflection support");
		assertTrue(source.indexOf("Reflect::setField(obj, field, parseRec())") < 0,
			"C++ smoke should not call the string-only parsed Reflect.setField helper for Dynamic object writes");
		assertContains(source, "auto arr = std::vector<std::any>{};", "C++ smoke should infer Dynamic pushes into empty arrays as std::vector<std::any>");
		assertContains(source, "arr.push_back(parseRec());", "C++ smoke should keep Dynamic array pushes compile-safe");
		assertContains(source,
			"template<typename TExpected, typename TValue, typename TStatus>\n  static bool sameAs(const TExpected& expected, const TValue& value, TStatus& status, double approx)",
			"C++ smoke should keep Assert.sameAs Dynamic expected/value args and status values polymorphic");
		assertContains(source, "__hxhx_same_as(expected, value, __hxhx_same_as_approx)",
			"C++ smoke should compare Assert.sameAs Dynamic values through the compile-safe helper");
		assertContains(source, "(__hxhx_status.expectedValue) = __hxhx_stringify(expected);", "C++ smoke should stringify retained structural status fields");
		assertContains(source, "struct Class;", "C++ smoke should forward-declare Class when Class-valued parameters are emitted");
		final genericNodeFactoryDecl = "std::shared_ptr<GenericListNode<T>> __hxhx_make_shared_GenericListNode(T item, std::shared_ptr<GenericListNode<T>> next);";
		final genericNodeStruct = "template<typename T>\nstruct GenericListNode {";
		final genericNodeFactoryBody = "std::shared_ptr<GenericListNode<T>> __hxhx_make_shared_GenericListNode(T item, std::shared_ptr<GenericListNode<T>> next) {";
		final genericImplicitNodeFactoryDecl = "std::shared_ptr<GenericImplicitNode<T>> __hxhx_make_shared_GenericImplicitNode();";
		final genericImplicitNodeStruct = "template<typename T>\nstruct GenericImplicitNode {";
		final genericImplicitNodeFactoryBody = "std::shared_ptr<GenericImplicitNode<T>> __hxhx_make_shared_GenericImplicitNode() {";
		assertContains(source, genericNodeFactoryDecl, "C++ smoke should forward-declare generic factories before template bodies can call them");
		assertTrue(source.indexOf(genericNodeFactoryDecl) < source.indexOf(genericNodeStruct),
			"C++ generic factory declarations should appear before generic class template definitions");
		assertTrue(source.indexOf(genericNodeStruct) < source.indexOf(genericNodeFactoryBody),
			"C++ generic factory bodies should remain after the generic class template definition");
		assertContains(source, genericImplicitNodeFactoryDecl, "C++ smoke should forward-declare zero-arg generic factories for implicit constructors");
		assertTrue(source.indexOf(genericImplicitNodeFactoryDecl) < source.indexOf(genericImplicitNodeStruct),
			"C++ zero-arg generic factory declarations should appear before implicit-constructor template definitions");
		assertTrue(source.indexOf(genericImplicitNodeStruct) < source.indexOf(genericImplicitNodeFactoryBody),
			"C++ zero-arg generic factory bodies should remain after implicit-constructor template definitions");
		final parsedRunnerGenericModule = new HxParser([
			"class Dispatcher<T> {",
			"  var handlers:Array<T->Void>;",
			"  public function new() {",
			"    handlers = new Array();",
			"  }",
			"  public function clear():Void {",
			"    handlers = new Array();",
			"  }",
			"  public function add(h:T->Void):T->Void {",
			"    handlers.push(h);",
			"    return h;",
			"  }",
			"  public function dispatch(e) {",
			"    var list = handlers.copy();",
			"    for (l in list) {",
			"      l(e);",
			"    }",
			"    return true;",
			"  }",
			"}",
			"class TestFixture {",
			"  public var isITest:Bool = false;",
			"  public var target:String = \"\";",
			"  public function new() {}",
			"}",
			"class TestHandler<T> {",
			"  public var fixture:T;",
			"  public var onComplete:Dispatcher<TestHandler<T>>;",
			"  public var onPrecheck:Dispatcher<TestHandler<T>>;",
			"  public function new(fixture:T) {",
			"    this.fixture = fixture;",
			"    onComplete = new Dispatcher();",
			"    onPrecheck = new Dispatcher();",
			"  }",
			"}",
			"class TestResult {",
			"  public function new() {}",
			"  public static function ofHandler(handler:TestHandler<Dynamic>):TestResult {",
			"    return new TestResult();",
			"  }",
			"}",
			"class ArrayDynamicLike {",
			"  public static function createInstance(args:Array<Dynamic>):Dynamic {",
			"    return args[0];",
			"  }",
			"  public function compareArgs(a1:Array<Dynamic>, a2:Array<Dynamic>):Int {",
			"    return a1[0] == a2[0] ? 0 : 1;",
			"  }",
			"}",
			"class RunnerGenericLike {",
			"  var fixtures(default, null):Array<TestFixture> = [];",
			"  public var fixtureList:List<TestFixture>;",
			"  public var onProgress:Dispatcher<{result:TestResult,done:Int,totals:Int}>;",
			"  public var onRunner:Dispatcher<RunnerGenericLike>;",
			"  public var onPrecheck:Dispatcher<TestHandler<TestFixture>>;",
			"  var pos:Int = 0;",
			"  public function new() {",
			"    fixtureList = new List();",
			"    onProgress = new Dispatcher();",
			"    onRunner = new Dispatcher();",
			"    onPrecheck = new Dispatcher();",
			"  }",
			"  public function runSelf():Void {",
			"    onRunner.dispatch(this);",
			"  }",
			"  public function isTestFixtureName(prefixes:Array<String>):Bool {",
			"    return true;",
			"  }",
			"  public function usePrefix(prefix:String):Bool {",
			"    return isTestFixtureName([prefix]);",
			"  }",
			"  public function runFixtures():Void {",
			"    var fixture = fixtures[pos++];",
			"    if (fixture.isITest) return;",
			"    var arrayTarget = fixture.target;",
			"    for (fixture in fixtureList) {",
			"      if (fixture.isITest) {}",
			"      var t = fixture.target;",
			"    }",
			"  }",
			"  public function runNext(finishedHandler:TestHandler<TestFixture>):Void {}",
			"  public function wireHandler(handler:TestHandler<TestFixture>):Void {",
			"    handler.onComplete.add(runNext);",
			"    handler.onPrecheck.add(onPrecheck.dispatch);",
			"  }",
			"  public function resultOf(handler:TestHandler<TestFixture>):TestResult {",
			"    return TestResult.ofHandler(handler);",
			"  }",
			"  public function emitProgress(handler:TestHandler<TestFixture>):Void {",
			"    onProgress.dispatch({result:TestResult.ofHandler(handler), done:1, totals:2});",
			"  }",
			"  public function makeHandler(fixture:TestFixture):TestHandler<TestFixture> {",
			"    var handler = new TestHandler(fixture);",
			"    return handler;",
			"  }",
			"  public function isMethod(test:Dynamic, name:String) {",
			"    try return Reflect.isFunction(Reflect.field(test, name));",
			"    catch(e:Dynamic) return false;",
			"  }",
			"  public function guardMethod(test:Dynamic, name:String):Void {",
			"    if (!isMethod(test, name)) return;",
			"  }",
			"}"
		].join("\n")).parseModule("RunnerGenericLike");
		final parsedRunnerGenericOwner = HxModuleDecl.getMainClass(parsedRunnerGenericModule);
		final parsedRunnerGenericNames = new StringMap<Bool>();
		final parsedRunnerGenericClasses = new StringMap<HxClassDecl>();
		for (cls in HxModuleDecl.getClasses(parsedRunnerGenericModule)) {
			parsedRunnerGenericNames.set(HxClassDecl.getName(cls), true);
			parsedRunnerGenericClasses.set(HxClassDecl.getName(cls), cls);
		}
		final parsedRunnerGenericLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(parsedRunnerGenericOwner, {
			names: parsedRunnerGenericNames,
			byName: parsedRunnerGenericClasses
		}).join("\n");
		final parsedRunnerGenericScope = @:privateAccess backend.cpp.CppTargetCore.renderScope(parsedRunnerGenericOwner, {
			names: parsedRunnerGenericNames,
			byName: parsedRunnerGenericClasses
		}, "String");
		final fixturesCppType = @:privateAccess backend.cpp.CppTargetCore.exprCppType(EIdent("fixtures"), parsedRunnerGenericScope);
		assertTrue(fixturesCppType == "std::vector<std::shared_ptr<TestFixture>>",
			"C++ owner field type lookup should recover Array<TestFixture> fields, got " + fixturesCppType);
		final fixtureAccessCppType = @:privateAccess
			backend.cpp.CppTargetCore.inferExprCppType(EArrayAccess(EIdent("fixtures"), EUnop("post++", EIdent("pos"))), parsedRunnerGenericScope);
		assertTrue(fixtureAccessCppType == "std::shared_ptr<TestFixture>",
			"C++ Array<T> access inference should recover reference element type, got " + fixtureAccessCppType);
		assertContains(parsedRunnerGenericLines, "std::vector<std::shared_ptr<TestFixture>> fixtures = std::vector<std::shared_ptr<TestFixture>>{};",
			"C++ typed empty Array fields should render with the declared element type instead of vector<int>");
		assertContains(parsedRunnerGenericLines, "auto fixture = (fixtures[(pos++)]);",
			"C++ unhinted locals initialized from Array<T> access may use auto while keeping the inferred reference element type in scope");
		assertContains(parsedRunnerGenericLines, "if ((fixture->isITest))",
			"C++ Array<T> access locals should keep reference element types for pointer field access");
		assertContains(parsedRunnerGenericLines, "auto arrayTarget = (fixture->target);",
			"C++ Array<T> access locals should use pointer field access for reference element fields");
		assertContains(parsedRunnerGenericLines, "(handler->onComplete)->add(std::function<void(std::shared_ptr<TestHandler<std::shared_ptr<TestFixture>>>)>",
			"C++ same-owner method values passed to typed function params should lower to typed std::function lambdas");
		assertContains(parsedRunnerGenericLines,
			"[&](std::shared_ptr<TestHandler<std::shared_ptr<TestFixture>>> finishedHandler) { this->runNext(finishedHandler); }",
			"C++ same-owner method callback lambdas should use the instantiated handler payload type");
		assertContains(parsedRunnerGenericLines, "(handler->onPrecheck)->add(std::function<void(std::shared_ptr<TestHandler<std::shared_ptr<TestFixture>>>)>",
			"C++ field receiver method values passed to typed function params should lower to typed std::function lambdas");
		assertContains(parsedRunnerGenericLines, "[&](std::shared_ptr<TestHandler<std::shared_ptr<TestFixture>>> e) { onPrecheck->dispatch(e); }",
			"C++ field receiver method callback lambdas should bind the receiver and use the expected payload type");
		assertContains(parsedRunnerGenericLines, "return TestResult::ofHandler(handler);",
			"C++ static generic calls should accept TestHandler<TestFixture> without specializing the parameter to string");
		assertContains(parsedRunnerGenericLines, "auto handler = __hxhx_make_shared_TestHandler<std::shared_ptr<TestFixture>>(fixture);",
			"C++ unhinted locals returned from generic-return functions should pass expected template args into constructors");
		assertContains(parsedRunnerGenericLines, "if ((fixture->isITest))",
			"C++ List<T> loop locals should keep reference element types for pointer field access");
		assertContains(parsedRunnerGenericLines, "auto t = (fixture->target);",
			"C++ List<T> loop locals should use pointer field access for reference element fields");
		assertTrue(parsedRunnerGenericLines.indexOf("fixture.isITest") < 0, "C++ List<T> loop locals should not fall back to dot access for reference fields");
		final progressShapeName = "__hxhx_anon_result_std__shared_ptr_TestResult__done_int__totals_int_";
		assertContains(parsedRunnerGenericLines, "std::shared_ptr<Dispatcher<" + progressShapeName + ">> onProgress",
			"C++ structural Dispatcher fields should preserve anonymous payload type");
		assertContains(parsedRunnerGenericLines, "onProgress = __hxhx_make_shared_Dispatcher<" + progressShapeName + ">();",
			"C++ zero-arg structural Dispatcher constructor assignments should infer template args from the destination field type");
		assertContains(parsedRunnerGenericLines, "onProgress->dispatch(" + progressShapeName + "{TestResult::ofHandler(handler), 1, 2});",
			"C++ structural Dispatcher.dispatch should accept matching anonymous record payloads");
		assertTrue(parsedRunnerGenericLines.indexOf("std::shared_ptr<Dispatcher<std::string>> onProgress") < 0,
			"C++ structural Dispatcher fields should not collapse to Dispatcher<string>");
		assertContains(parsedRunnerGenericLines, "onRunner = __hxhx_make_shared_Dispatcher<std::shared_ptr<RunnerGenericLike>>();",
			"C++ zero-arg generic constructor assignments should infer reference template args from the destination field type");
		final parsedDispatcherLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(parsedRunnerGenericClasses.get("Dispatcher"), {
			names: parsedRunnerGenericNames,
			byName: parsedRunnerGenericClasses
		}).join("\n");
		final parsedTestHandlerLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(parsedRunnerGenericClasses.get("TestHandler"), {
			names: parsedRunnerGenericNames,
			byName: parsedRunnerGenericClasses
		}).join("\n");
		assertContains(parsedTestHandlerLines, "onComplete = __hxhx_make_shared_Dispatcher<std::shared_ptr<TestHandler<T>>>();",
			"C++ generic class constructors should infer nested generic field constructor args from the destination field type");
		assertContains(parsedTestHandlerLines, "onPrecheck = __hxhx_make_shared_Dispatcher<std::shared_ptr<TestHandler<T>>>();",
			"C++ generic class constructors should not use the ambient T directly for Dispatcher<TestHandler<T>> fields");
		assertTrue(parsedTestHandlerLines.indexOf("onComplete = __hxhx_make_shared_Dispatcher<T>();") < 0,
			"C++ nested generic field constructors should not collapse Dispatcher<TestHandler<T>> to Dispatcher<T>");
		assertContains(parsedDispatcherLines, "std::vector<std::function<void(T)>> handlers",
			"C++ generic function-vector fields should preserve the function element type");
		assertContains(parsedDispatcherLines, "handlers = std::vector<std::function<void(T)>>{};",
			"C++ generic function-vector assignments should use the destination field element type");
		assertContains(parsedDispatcherLines, "bool dispatch(T e) {", "C++ generic function-vector calls should infer unhinted dispatch args as T");
		assertTrue(parsedDispatcherLines.indexOf("bool dispatch(std::string e)") < 0,
			"C++ generic function-vector calls should not leave dispatch args as string");
		final parsedTestResultLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(parsedRunnerGenericClasses.get("TestResult"), {
			names: parsedRunnerGenericNames,
			byName: parsedRunnerGenericClasses
		}).join("\n");
		assertContains(parsedTestResultLines, "template<typename TDynamic>", "C++ generic Dynamic function args should render a method template wildcard");
		assertContains(parsedTestResultLines, "static std::shared_ptr<TestResult> ofHandler(std::shared_ptr<TestHandler<TDynamic>> handler)",
			"C++ generic Dynamic helper method params should accept concrete generic payloads");
		assertTrue(parsedTestResultLines.indexOf("ofHandler(std::shared_ptr<TestHandler<std::string>> handler)") < 0,
			"C++ generic Dynamic helper methods should not specialize wildcard params to String");
		final parsedArrayDynamicLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(parsedRunnerGenericClasses.get("ArrayDynamicLike"), {
			names: parsedRunnerGenericNames,
			byName: parsedRunnerGenericClasses
		}).join("\n");
		assertContains(parsedArrayDynamicLines, "createInstance(std::vector<std::string> args)",
			"C++ Array<Dynamic> function args should keep target-owned vector lowering");
		assertContains(parsedArrayDynamicLines, "compareArgs(std::vector<std::string> a1, std::vector<std::string> a2)",
			"C++ Array<Dynamic> instance args should not render shared_ptr<Array<TDynamic>>");
		assertContains(parsedArrayDynamicLines, "(a1[0])", "C++ Array<Dynamic> indexing should lower to vector indexing, not Array helper pointer indexing");
		assertTrue(parsedArrayDynamicLines.indexOf("std::shared_ptr<Array<TDynamic>>") < 0,
			"C++ Array<Dynamic> args should not use generic Dynamic wildcard helper classes");
		assertContains(parsedRunnerGenericLines, "onRunner->dispatch(__hxhx_borrowed_shared<RunnerGenericLike>(this));",
			"C++ generic method calls should instantiate T from the receiver and pass this as a borrowed reference payload");
		assertTrue(parsedDispatcherLines.indexOf("handlers = std::vector<std::string>{};") < 0,
			"C++ generic function-vector assignments should not fall back to string arrays");
		assertContains(parsedRunnerGenericLines, "return isTestFixtureName(std::vector<std::string>{std::string(prefix)});",
			"C++ array literals passed to typed Array parameters should render with the parameter element type");
		assertContains(parsedRunnerGenericLines, "bool isMethod(std::string test, std::string name) {",
			"C++ try/catch return inference should preserve bool helpers instead of falling back to string");
		assertContains(parsedRunnerGenericLines, "return __hxhx_reflect_is_function(__hxhx_reflect_field(test, std::string(name)));",
			"C++ bool-returning Reflect.isFunction probes should return bool directly");
		assertTrue(parsedRunnerGenericLines.indexOf("std::string isMethod(") < 0, "C++ try/catch bool helper inference should not stringify boolean returns");
		final runnerAddCases = new HxClassDecl("Runner", false, [
			new HxFunctionDecl("addCases", Public, false, [
				new HxFunctionArg("eThis", "haxe.macro.Expr", NoDefault, false, false),
				new HxFunctionArg("path", "haxe.macro.Expr", NoDefault, false, false),
				new HxFunctionArg("recursive", "Bool", Default(EBool(true)), true, false)
			], "haxe.macro.Expr",
				[SExpr(EUnsupported("body_parse_error"), HxPos.unknown())], "", ["macro"])
		]);
		final runnerAddCasesNames = new StringMap<Bool>();
		runnerAddCasesNames.set("Runner", true);
		runnerAddCasesNames.set("Expr", true);
		final runnerAddCasesClasses = new StringMap<HxClassDecl>();
		runnerAddCasesClasses.set("Runner", runnerAddCases);
		runnerAddCasesClasses.set("Expr", new HxClassDecl("Expr", false));
		final runnerAddCasesLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(runnerAddCases, {
			names: runnerAddCasesNames,
			byName: runnerAddCasesClasses
		}).join("\n");
		assertContains(runnerAddCasesLines, "std::shared_ptr<Expr> addCases(std::shared_ptr<Expr> eThis, std::shared_ptr<Expr> path",
			"C++ utest Runner.addCases macro helper should keep a callable runtime signature");
		assertContains(runnerAddCasesLines, "return nullptr;", "C++ utest Runner.addCases macro helper should emit a neutral runtime stub");
		assertTrue(runnerAddCasesLines.indexOf("body_parse_error") < 0, "C++ utest Runner.addCases should not emit its macro-only body");
		assertContains(source, "static bool isOfType(std::string v, std::shared_ptr<Class> t)",
			"C++ smoke should preserve Class-valued helper parameters instead of falling back to strings");
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
		assertContains(source, "Box(int value) : value(value) {", "C++ smoke should emit direct constructor field initialization");
		assertTrue(source.indexOf("this->value = value;") < 0, "C++ smoke should not body-assign direct constructor field initializers");
		assertContains(source, "int getHeight() {", "C++ smoke should emit helper class method");
		assertContains(source, "return static_cast<int>(value);", "C++ smoke should emit helper method return");
		assertContains(source, "auto box = std::make_shared<Box>(41);", "C++ smoke should lower class construction to nullable references");
		assertContains(source, "auto boxInfo = __hxhx_anon_box_std__shared_ptr_Box_{box};",
			"C++ smoke should lower anonymous objects containing class references");
		assertTrue(source.indexOf("struct Box;") < source.indexOf("struct __hxhx_anon_box_std__shared_ptr_Box_ {"),
			"C++ smoke should emit helper forward declarations before anonymous structs that reference helpers");
		assertContains(source, "box->getHeight()", "C++ smoke should lower class receiver method calls through reference access");
		assertContains(source, "std::shared_ptr<RefNode> next = nullptr;", "C++ smoke should type nullable class fields as C++ references");
		assertContains(source, "std::shared_ptr<ReturnIfNode> firstNode(std::shared_ptr<ReturnIfNode> t) {",
			"C++ smoke should infer value returns through nested return-if/else-if helpers");
		assertContains(source, "return t;", "C++ smoke should preserve nested return-if value branches as returns");
		assertContains(source, "return firstNode((t->left));", "C++ smoke should preserve nested return-if recursive value branches as returns");
		assertTrue(source.indexOf("void firstNode(std::shared_ptr<ReturnIfNode> t)") < 0,
			"C++ smoke should not infer nested return-if helpers as void from throw-only branches");
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
			"auto next() {\n    auto val = (head->item);\n    head = (head->next);\n    return __hxhx_anon_value_std__string_key_int_{__hxhx_stringify(val), (idx++)};\n  }",
			"C++ smoke should lower generic key/value iterator structural returns through C++ auto");
		assertContains(source, "template<typename T>\nstruct GenericListKeyValueIterator {",
			"C++ smoke should preserve helper class type parameters declared in parsed class headers");
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
		assertContains(source, "return __hxhx_join(__hxhx_vector_map_string(items, [&](auto item) { return this->printItem(item); }), std::string(\", \"));",
			"C++ smoke should lower vector map/join chains with same-owner method callbacks to support helpers");
		assertTrue(source.indexOf(".map(printItem).join") < 0, "C++ smoke should not emit nonexistent std::vector map/join chains");
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
		assertContains(source, "return __hxhx_replace(std::string(s), std::string(\"na\"), std::string(\"X\"));",
			"C++ smoke should lower StringTools.replace to target support helpers");
		assertContains(source,
			"return __hxhx_replace(__hxhx_replace(__hxhx_replace(std::string(s), std::string(\"\\\\\"), std::string(\"\\\\\\\\\")), std::string(\"\\n\"), std::string(\"\\\\n\")), std::string(\"\\t\"), std::string(\"\\\\t\"));",
			"C++ smoke should lower chained String.replace calls to target support helpers");
		assertContains(source, "static std::string __hxhx_replace(", "C++ smoke should include target support for StringTools.replace");
		assertTrue(source.indexOf("StringTools::replace(std::string(s)") < 0,
			"C++ smoke should not emit generated StringTools static calls for replace intrinsic lowering");
		assertTrue(source.indexOf(".replace(std::string(\"\\\\\"), std::string(\"\\\\\\\\\"))") < 0,
			"C++ smoke should not emit C++ std::string replace overload calls for Haxe String.replace");
		assertContains(source, "__hxhx_last_index_of(s, std::string(start), 0)", "C++ smoke should lower String.lastIndexOf to target support helpers");
		assertContains(source, "auto c = static_cast<int>(static_cast<unsigned char>(s[pos]));",
			"C++ smoke should lower String.charCodeAt to direct code-point reads");
		assertContains(source, "return s.substr(1, 2);", "C++ smoke should preserve std::string substr results without stringifying");
		assertContains(source, "return __hxhx_substring(s, 1, 3);", "C++ smoke should lower Haxe substring to target support helpers");
		assertContains(source, "return ltrim(rtrim(s));", "C++ smoke should preserve same-class string-returning static calls");
		assertTrue(source.indexOf("std::to_string(ltrim(rtrim(s)))") < 0, "C++ smoke should not stringify same-class String helper results");
		assertContains(source, "return __hxhx_quote_unix_arg(std::string(argument));",
			"C++ smoke should lower haxe.SysTools.quoteUnixArg to a target support helper");
		assertContains(source, "return __hxhx_quote_win_arg(std::string(argument), escapeMetaCharacters);",
			"C++ smoke should lower haxe.SysTools.quoteWinArg to a target support helper");
		assertTrue(source.indexOf("(haxe.SysTools).quote") < 0, "C++ smoke should not leak qualified haxe.SysTools static syntax");
		assertTrue(source.indexOf("std::to_string(__hxhx_quote_") < 0, "C++ smoke should not stringify haxe.SysTools quote helper results");
		assertContains(source, "auto s = std::string(\"\");", "C++ smoke should infer mutable literal string locals as std::string");
		assertContains(source, "__hxhx_char_at(hexChars, (n & 15)) + s", "C++ smoke should lower String.charAt to target support helpers");
		assertContains(source, "return static_cast<int>(static_cast<int>(static_cast<unsigned char>(\"0\"[0])));",
			"C++ smoke should lower String literal .code to a code-point read");
		assertTrue(source.indexOf(".split(") < 0, "C++ smoke should not emit nonexistent std::string split calls");
		assertTrue(source.indexOf(".lastIndexOf(") < 0, "C++ smoke should not emit nonexistent std::string lastIndexOf calls");
		assertTrue(source.indexOf(".charCodeAt(") < 0, "C++ smoke should not emit nonexistent std::string charCodeAt calls");
		assertTrue(source.indexOf(".substring(") < 0, "C++ smoke should not emit nonexistent std::string substring calls");
		assertTrue(source.indexOf("std::to_string(s.substr") < 0, "C++ smoke should not stringify std::string substr results");
		assertContains(source, "static std::string fromBuffer() {", "C++ smoke should keep Input.readLine-like helpers returning strings");
		assertContains(source, "std::string s = std::string();", "C++ smoke should infer no-init locals assigned from String expressions as std::string");
		assertContains(source, "static_cast<int>(static_cast<unsigned char>(s[((s.size()) - 1)]))",
			"C++ smoke should lower string operations on no-init locals after assignment inference");
		assertContains(source, "s = s.substr(0, (-1));", "C++ smoke should preserve String.substr reassignment on no-init locals");
		assertTrue(source.indexOf("auto s = 0;") < 0, "C++ smoke should not default no-init String locals to integer auto");
		assertContains(source, "static int inferredNoInitInt() {", "C++ smoke should keep integer no-init local inference working");
		assertContains(source, "int x = 0;", "C++ smoke should infer no-init locals assigned from Int expressions as int");
		assertContains(source, "static long long parseStringLike(std::string sParam) {", "C++ smoke should erase Int64 helper returns to primitive values");
		assertContains(source, "auto base = static_cast<long long>(10);",
			"C++ smoke should lower Int64.ofInt directly instead of calling an incomplete helper class");
		assertContains(source, "current = (current + (multiplier * static_cast<long long>(digitInt)));",
			"C++ smoke should lower Int64 add/mul helper calls as primitive value operations");
		assertContains(source, "auto noFractions = (f - std::fmod(f, 1));", "C++ smoke should lower Float modulo through std::fmod");
		assertContains(source, "auto curr = std::fmod(rest, 2);", "C++ smoke should remember double arithmetic locals for later Float modulo");
		assertContains(source, "if ((current < 0)) {", "C++ smoke should lower Int64.isNeg as a primitive comparison");
		assertContains(source, "auto s = __hxhx_trim(std::string(sParam));", "C++ smoke should infer StringTools.trim string-return locals");
		assertContains(source, "__hxhx_char_at(s, 0)", "C++ smoke should lower string locals initialized from same-owner calls");
		assertContains(source, "__hxhx_substring(s, 1, (s.size()))", "C++ smoke should preserve string-local type through reassignment paths");
		assertContains(source, "return current;", "C++ smoke should return Int64 primitive values without narrowing to int");
		assertContains(source, "return Int64Helper::parseString(std::string(s));", "C++ smoke should lower Int64.parseString through Int64Helper");
		assertContains(source, "return Int64Helper::fromFloat(f);", "C++ smoke should lower Int64.fromFloat through Int64Helper");
		assertContains(source, "struct __hxhx_anon_quotient_long_long_modulus_long_long {",
			"C++ smoke should declare the Int64.divMod anonymous result aggregate");
		assertContains(source, "auto result = __hxhx_anon_quotient_long_long_modulus_long_long{(a / b), (a % b)};",
			"C++ smoke should lower Int64.divMod as a primitive quotient/modulus aggregate");
		assertContains(source, "return (result.quotient);", "C++ smoke should preserve Int64.divMod quotient field access");
		assertContains(source, "return static_cast<int>(((a < b) ? -1 : ((a > b) ? 1 : 0)));",
			"C++ smoke should lower Int64.compare to primitive signed ordering");
		assertContains(source,
			"return static_cast<int>(((static_cast<unsigned long long>(a) < static_cast<unsigned long long>(b)) ? -1 : ((static_cast<unsigned long long>(a) > static_cast<unsigned long long>(b)) ? 1 : 0)));",
			"C++ smoke should lower Int64.ucompare to primitive unsigned ordering");
		assertTrue(source.indexOf("struct Int64Helper") < source.indexOf("struct CppInt64StaticUseLike"),
			"C++ smoke should order Int64Helper before helper classes that call Int64.parseString/fromFloat");
		assertTrue(source.indexOf("Int64::ofInt") < 0, "C++ smoke should not emit incomplete Int64 static helper calls");
		assertContains(source, "auto __hxhx_iter_code = std::make_shared<StringIteratorUnicode>(s);",
			"C++ smoke should bind Haxe iterator protocol objects before looping");
		assertContains(source, "static std::shared_ptr<StringIteratorUnicode> unicodeIterator(std::string s)",
			"C++ smoke should type StringIteratorUnicode.unicodeIterator as an iterator-object factory");
		assertContains(source, "static std::shared_ptr<StringKeyValueIteratorUnicode> unicodeKeyValueIterator(std::string s)",
			"C++ smoke should type StringKeyValueIteratorUnicode.unicodeKeyValueIterator as an iterator-object factory");
		assertTrue(source.indexOf("static  unicodeIterator") < 0, "C++ smoke should not emit untyped unicode iterator factories");
		assertTrue(source.indexOf("return static_cast<int>(std::make_shared<StringIteratorUnicode>(s));") < 0,
			"C++ smoke should not narrow unicode iterator factories to int");
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
		assertContains(source, "auto macroQuote = __hxhx_macro_expr(", "C++ smoke should lower macro quotes to structural macro objects");
		assertContains(source, "__hxhx_macro_enum(\"EParenthesis\"", "C++ smoke should preserve macro quote wrappers structurally");
		assertContains(source, "auto macroType = std::string(\"X -> Y\");", "C++ smoke should lower macro type quotes to stable text");
		assertContains(source, "auto switched = ([&]() -> std::string {", "C++ smoke should lower switch expressions through an explicitly typed IIFE");
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
		assertContains(source, "Child(int value) : Base(), value(value) {",
			"C++ smoke should lower bare super constructor calls and direct field initialization to initializer lists");
		assertTrue(source.indexOf("/* base constructor call omitted */") < 0, "C++ leading super constructor calls should not remain as omitted body comments");
		assertContains(source, "auto parent = (*this);", "C++ smoke should lower bare super expressions to the current base-backed object");
		assertContains(source, "__hxhx_json_min_field_from_file(platformsJson)",
			"C++ smoke should lower hxcpp Android platform-min try/catch expressions through target runtime support");
		assertContains(source, "__hxhx_join(words, \",\")", "C++ smoke should lower array join try/catch expressions through target runtime support");
		assertContains(source, "static bool __hxhx_is_type(int, const std::string& type)", "C++ smoke should include Haxe is-expression helper overloads");
		assertContains(source, "static std::string __hxhx_type_name(int)", "C++ smoke should include Haxe type-name helper overloads");
		assertContains(source, "auto __hxhx_null_coalesce(std::nullptr_t, F fallback)", "C++ smoke should include Haxe null-coalescing helper overloads");

		final missingIMapDir = Path.join([root, "missing-imap-source-only"]);
		final missingIMapEmit = BackendRegistry.createForTarget("cpp-native").emit(missingIMapProgram(), context(missingIMapDir, true, true));
		final missingIMapSource = File.getContent(missingIMapEmit.entryPath);
		assertContains(missingIMapSource, "template<typename K, typename V>\nstruct IMap {",
			"C++ missing haxe.Constraints.IMap references should emit an abstract interface declaration, not a bare forward declaration");
		assertTrue(missingIMapSource.indexOf("struct KeyValueIterator {") < missingIMapSource.indexOf("template<typename K, typename V>\nstruct IMap {"),
			"C++ missing IMap declarations should emit KeyValueIterator before methods reference it");
		assertContains(missingIMapSource, "virtual std::shared_ptr<__hxhx_iterator<K>> keys() = 0;",
			"C++ missing IMap declarations should expose keys() for MapKeyValueIterator-style consumers");
		assertTrue(missingIMapSource.indexOf("template<typename K, typename V>\nstruct IMap {") < missingIMapSource.indexOf("struct UsesMissingIMap {"),
			"C++ missing IMap declaration should appear before helper classes that call IMap methods");
		assertTrue(missingIMapSource.indexOf("struct IMap;\n") < 0, "C++ missing IMap should not be emitted only as a bare forward declaration");
		assertContains(missingIMapSource, "return __hxhx_anon_value_std__string_key_std__string{map->get(key).value_or(std::string()), std::string(key)};",
			"C++ fallback IMap method typing should unwrap optional get values into key/value iterator records");
		assertTrue(missingIMapSource.indexOf("struct __hxhx_anon_value_int__key_std__string") < 0,
			"C++ fallback IMap key/value iterator records should not predeclare optional values as Int");

		final mapKeyValueDir = Path.join([root, "imap-key-value-iterator-source-only"]);
		final mapKeyValueEmit = BackendRegistry.createForTarget("cpp-native").emit(mapKeyValueIteratorProgram(), context(mapKeyValueDir, true, true));
		final mapKeyValueSource = File.getContent(mapKeyValueEmit.entryPath);
		assertContains(mapKeyValueSource, "struct KeyValueIterator {",
			"C++ structural KeyValueIterator typedef support should emit a target-owned marker declaration");
		assertTrue(mapKeyValueSource.indexOf("struct KeyValueIterator {") < mapKeyValueSource.indexOf("template<typename K, typename V>\nstruct MapKeyValueIterator : public KeyValueIterator {"),
			"C++ KeyValueIterator marker should be declared before structural key/value iterator helpers inherit it");
		assertContains(mapKeyValueSource, "struct __hxhx_anon_value_std__string_key_std__string {",
			"C++ anon predeclaration collection should preserve generic IMap key/value iterator field types");
		assertContains(mapKeyValueSource, "template<typename K, typename V>\nstruct MapKeyValueIterator : public KeyValueIterator {",
			"C++ generic IMap key/value iterator helpers should be upcastable to KeyValueIterator");
		assertContains(mapKeyValueSource,
			"return __hxhx_anon_value_std__string_key_std__string{map->get(key).value_or(std::string()), __hxhx_stringify(key)};",
			"C++ generic IMap key/value iterators should unwrap optional values when the key local is inferred from Iterator.next()");
		assertTrue(mapKeyValueSource.indexOf("struct __hxhx_anon_value_int__key_std__string") < 0,
			"C++ generic IMap key/value iterator records should not predeclare optional values as Int");

		final macroRefDir = Path.join([root, "macro-ref-type-source-only"]);
		final macroRefEmit = BackendRegistry.createForTarget("cpp-native").emit(macroRefTypeProgram(), context(macroRefDir, true, true));
		final macroRefSource = File.getContent(macroRefEmit.entryPath);
		assertContains(macroRefSource, "template<typename T>\nstruct Ref;",
			"C++ generic typedef helper placeholders should remain generic forward declarations");
		assertContains(macroRefSource, "static std::shared_ptr<Ref<std::shared_ptr<ClassType>>> getLocalClass()",
			"C++ macro Ref<ClassType> return types should preserve generic type arguments");
		assertContains(macroRefSource, "static std::vector<std::shared_ptr<Ref<std::shared_ptr<ClassType>>>> getLocalUsing()",
			"C++ Array<Ref<ClassType>> return types should preserve nested generic type arguments");
		assertContains(macroRefSource, "static std::string TClassDecl(std::shared_ptr<Ref<std::shared_ptr<ClassType>>> c)",
			"C++ enum constructor payloads should preserve generic Ref<T> type arguments");
		assertContains(macroRefSource, "std::shared_ptr<Ref<std::shared_ptr<ClassType>>> final_type = nullptr;",
			"C++ intersection typedef fields should preserve generic Ref<T> type arguments");
		assertContains(macroRefSource, "std::shared_ptr<Ref<std::vector<std::shared_ptr<ClassType>>>> fields = nullptr;",
			"C++ intersection typedef fields should preserve nested generic Ref<Array<T>> type arguments");
		assertContains(macroRefSource, "std::shared_ptr<Ref<std::shared_ptr<ClassType>>> type;",
			"C++ structural final fields should strip the final modifier and preserve generic Ref<T> type arguments");
		assertTrue(macroRefSource.indexOf("finaltype") < 0, "C++ structural final fields should not merge modifiers into field names");
		assertTrue(macroRefSource.indexOf("std::shared_ptr<Ref>") < 0, "C++ generic class-like type hints should not erase template arguments to raw Ref");
		assertTrue(macroRefSource.indexOf("public_") < 0, "C++ typedef function surfaces should not be mis-scanned as duplicate public_ fields");

		final macroCompilerNullDir = Path.join([root, "macro-compiler-null-surface-source-only"]);
		final macroCompilerNullEmit = BackendRegistry.createForTarget("cpp-native")
			.emit(macroCompilerNullSurfaceProgram(), context(macroCompilerNullDir, true, true));
		final macroCompilerNullSource = File.getContent(macroCompilerNullEmit.entryPath);
		assertContains(macroCompilerNullSource, "static std::any getDisplayPos()",
			"C++ macro Compiler.getDisplayPos should erase to macro API data instead of requiring a fake Null carrier");
		assertContains(macroCompilerNullSource, "return __hxhx_call_macro_api<std::any>(std::string(\"get_display_pos\"), 0);",
			"C++ macro Compiler.getDisplayPos should route through erased macro API plumbing");
		assertContains(macroCompilerNullSource, "static std::any getMalformedBareNull()",
			"C++ malformed bare Null hints should erase instead of emitting std::shared_ptr<Null>");
		assertContains(macroCompilerNullSource, "static std::any getDecodedStaleNullPointer()",
			"C++ stale target-shaped Null pointer hints from native decode should erase before method signatures");
		assertContains(macroCompilerNullSource, "static __HxMacroExpr getDefine(std::string key)",
			"C++ macro expression helper returns should preserve the native macro expression carrier");
		assertContains(macroCompilerNullSource, "return __hxhx_macro_expr(",
			"C++ macro expression helper returns should return the structural macro object directly");
		assertContains(macroCompilerNullSource, "static void include(std::string pack, std::optional<bool> rec = true",
			"C++ macro Compiler.include should preserve the public helper signature");
		assertContains(macroCompilerNullSource, "__hxhx_call_macro_api<void>(std::string(\"include\"), 5, pack, rec, ignore, classPaths, strict);",
			"C++ macro Compiler.include should lower to target-owned macro API plumbing instead of recursive local lambdas");
		assertContains(macroCompilerNullSource, "static void exclude(std::string pack, std::optional<bool> rec = true)",
			"C++ macro Compiler.exclude should preserve the public helper signature");
		assertContains(macroCompilerNullSource, "__hxhx_call_macro_api<void>(std::string(\"exclude\"), 2, pack, rec);",
			"C++ macro Compiler.exclude should lower to target-owned macro API plumbing");
		assertContains(macroCompilerNullSource, "static void excludeFile(std::string fileName)",
			"C++ macro Compiler.excludeFile should preserve the public helper signature");
		assertContains(macroCompilerNullSource, "__hxhx_call_macro_api<void>(std::string(\"exclude_file\"), 1, fileName);",
			"C++ macro Compiler.excludeFile should lower to target-owned macro API plumbing");
		assertContains(macroCompilerNullSource, "static void excludeBaseType(std::shared_ptr<BaseType> baseType)",
			"C++ macro Compiler.excludeBaseType should preserve its helper signature");
		assertContains(macroCompilerNullSource, "static void patchTypes(std::string file)",
			"C++ macro Compiler.patchTypes should preserve its public helper signature");
		assertContains(macroCompilerNullSource, "__hxhx_call_macro_api<void>(std::string(\"patch_types\"), 1, file);",
			"C++ macro Compiler.patchTypes should lower to macro API plumbing instead of stdlib file parser helpers");
		assertContains(macroCompilerNullSource, "static void keep(std::optional<std::string> path = std::nullopt",
			"C++ macro Compiler.keep should preserve optional public helper arguments");
		assertContains(macroCompilerNullSource, "__hxhx_call_macro_api<void>(std::string(\"keep\"), 3, path, paths, recursive);",
			"C++ macro Compiler.keep should lower to macro API plumbing instead of mutating optional arrays directly");
		assertContains(macroCompilerNullSource, "__hxhx_call_macro_api<void>(std::string(\"null_safety\"), 3, path, mode, recursive);",
			"C++ macro Compiler.nullSafety should lower to macro API plumbing");
		assertContains(macroCompilerNullSource,
			"__hxhx_call_macro_api<void>(std::string(\"add_global_metadata_impl\"), 5, pathFilter, meta, recursive, toTypes, toFields);",
			"C++ macro Compiler.addGlobalMetadata should use the compiler-owned metadata RPC seam");
		assertContains(macroCompilerNullSource, "__hxhx_call_macro_api<void>(std::string(\"register_metadata_description_file\"), 2, path, source);",
			"C++ macro Compiler.registerMetadataDescriptionFile should not emit typed Json.parse helper bodies");
		assertContains(macroCompilerNullSource, "__hxhx_call_macro_api<void>(std::string(\"register_defines_description_file\"), 2, path, source);",
			"C++ macro Compiler.registerDefinesDescriptionFile should not emit typed Json.parse helper bodies");
		assertContains(macroCompilerNullSource, "__hxhx_call_macro_api<std::string>(std::string(\"load\"), 2, f, nargs);",
			"C++ macro Compiler.load should avoid callable Dynamic body emission");
		assertContains(macroCompilerNullSource, "__hxhx_call_macro_api<void>(std::string(\"flush_disk_cache\"), 0);",
			"C++ macro Compiler.flushDiskCache should lower to macro API plumbing");
		assertContains(macroCompilerNullSource, "__hxhx_call_macro_api<std::string>(std::string(\"include_file\"), 2, file, position);",
			"C++ macro Compiler.includeFile should not emit target-specific macro expression construction");
		assertTrue(macroCompilerNullSource.indexOf("__hxhx_optional_lambda") < 0,
			"C++ macro Compiler API shims should not emit recursive optional-lambda helper bodies");
		assertTrue(macroCompilerNullSource.indexOf("__hxhx_for_in") < 0, "C++ macro Compiler API shims should not leak expression-only for-in markers");
		assertTrue(macroCompilerNullSource.indexOf("baseType->meta") < 0,
			"C++ macro Compiler.excludeBaseType shim should not force incomplete MetaAccess/BaseType member lowering");
		assertTrue(macroCompilerNullSource.indexOf(".shift()") < 0, "C++ macro Compiler.patchTypes shim should not emit Array.shift against std::vector");
		assertTrue(macroCompilerNullSource.indexOf("paths.value().push") < 0,
			"C++ macro Compiler.keep shim should not emit Haxe Array.push against std::vector");
		assertTrue(macroCompilerNullSource.indexOf("Json::parse") < 0,
			"C++ macro Compiler metadata registration shims should not require typed Json.parse support");
		assertTrue(macroCompilerNullSource.indexOf("position->toLowerCase") < 0,
			"C++ macro Compiler.includeFile shim should not treat IncludePosition as a string object");
		assertTrue(macroCompilerNullSource.indexOf("std::shared_ptr<Null>") < 0, "C++ macro Compiler surfaces should not emit fake Null runtime references");
		assertTrue(macroCompilerNullSource.indexOf("return static_cast<int>(__hxhx_macro_expr(") < 0,
			"C++ macro expression helper returns should not fall through to the Int fallback cast");
		final staleDisplayPosCompiler = new HxClassDecl("Compiler", false, [
			new HxFunctionDecl("getDisplayPos", Public, true, [], "std::shared_ptr<Null>", [
				SReturn(ECall(EIdent("callMacroApi"), [EString("get_display_pos"), EInt(0)]), HxPos.unknown())
			], "")
		]);
		final staleDisplayPosNames = new StringMap<Bool>();
		staleDisplayPosNames.set("Compiler", true);
		final staleDisplayPosClasses = new StringMap<HxClassDecl>();
		staleDisplayPosClasses.set("Compiler", staleDisplayPosCompiler);
		final staleDisplayPosLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperMethod(HxClassDecl.getFunctions(staleDisplayPosCompiler)[0],
			staleDisplayPosCompiler, {
				names: staleDisplayPosNames,
				byName: staleDisplayPosClasses
			})
			.join("\n");
		assertContains(staleDisplayPosLines, "static std::any getDisplayPos()", "C++ stale macro Compiler.getDisplayPos return hints should erase to std::any");
		assertContains(staleDisplayPosLines, "__hxhx_call_macro_api<std::any>(std::string(\"get_display_pos\"), 0);",
			"C++ stale macro Compiler.getDisplayPos should still route through macro API plumbing");
		assertTrue(staleDisplayPosLines.indexOf("std::shared_ptr<Null>") < 0,
			"C++ stale macro Compiler.getDisplayPos should not emit fake Null runtime references");

		final enumCarrierDir = Path.join([root, "enum-carrier-name-collision-source-only"]);
		final enumCarrierEmit = BackendRegistry.createForTarget("cpp-native").emit(enumCarrierNameCollisionProgram(), context(enumCarrierDir, true, true));
		final enumCarrierSource = File.getContent(enumCarrierEmit.entryPath);
		assertContains(enumCarrierSource, "struct Constant;", "C++ enum carrier forward declarations should preserve non-generic Constant as a plain type");
		assertContains(enumCarrierSource, "struct Binop;", "C++ enum carrier forward declarations should preserve non-generic Binop as a plain type");
		assertTrue(enumCarrierSource.indexOf("template<typename T>\nstruct Constant;") < 0,
			"C++ enum carrier forward declarations should not guess a generic Constant<T>");
		assertTrue(enumCarrierSource.indexOf("template<typename K, typename V>\nstruct Binop;") < 0,
			"C++ enum carrier forward declarations should not guess a generic Binop<K,V>");

		final enumCtorCarrierDir = Path.join([root, "enum-constructor-carrier-collision-source-only"]);
		final enumCtorCarrierEmit = BackendRegistry.createForTarget("cpp-native")
			.emit(enumConstructorCarrierCollisionProgram(), context(enumCtorCarrierDir, true, true));
		final enumCtorCarrierSource = File.getContent(enumCtorCarrierEmit.entryPath);
		assertContains(enumCtorCarrierSource,
			"static std::string TFor(std::shared_ptr<::TVar> v, std::shared_ptr<TypedExpr> e1, std::shared_ptr<TypedExpr> e2)",
			"C++ enum constructor payload types should qualify carrier names that collide with owner constructor members");
		assertTrue(enumCtorCarrierSource.indexOf("static std::string TFor(std::shared_ptr<TVar> v") < 0,
			"C++ enum constructor payload types should not resolve TVar through TypedExprDef::TVar");

		final contextLoadCallableDir = Path.join([root, "context-load-callable-source-only"]);
		final contextLoadCallableEmit = BackendRegistry.createForTarget("cpp-native")
			.emit(contextLoadCallableProgram(), context(contextLoadCallableDir, true, true));
		final contextLoadCallableSource = File.getContent(contextLoadCallableEmit.entryPath);
		assertContains(contextLoadCallableSource, "return __hxhx_call_macro_api<std::string>(std::string(\"error\"), 2, msg, pos, depth);",
			"C++ Context.load immediate calls in string-returning methods should lower through a typed macro API callable seam");
		assertContains(contextLoadCallableSource, "__hxhx_call_macro_api<void>(std::string(\"report_error\"), 2, msg, pos, depth);",
			"C++ Context.load immediate calls used as statements should lower through a void macro API callable seam");
		assertContains(contextLoadCallableSource, "return __hxhx_call_macro_api<std::vector<std::shared_ptr<Message>>>(std::string(\"get_messages\"), 0);",
			"C++ direct Context.load calls in vector-returning helpers should use the helper return type");
		assertContains(contextLoadCallableSource, "return __hxhx_call_macro_api<bool>(std::string(\"init_macros_done\"), 0);",
			"C++ direct Context.load calls in bool-returning helpers should use the helper return type");
		assertContains(contextLoadCallableSource,
			"std::shared_ptr<Type> l = __hxhx_call_macro_api<std::shared_ptr<Type>>(std::string(\"get_local_type\"), 0);",
			"C++ direct Context.load calls in typed local initializers should use the declared local type");
		assertTrue(contextLoadCallableSource.indexOf("(load(\"error\", 2))(") < 0,
			"C++ Context.load immediate calls should not emit a call against the string-returning load helper");
		assertTrue(contextLoadCallableSource.indexOf("__hxhx_call_macro_api<std::any>(std::string(\"get_messages\"), 0)") < 0,
			"C++ direct Context.load calls should not use std::any when the expected return type is known");
		assertTrue(contextLoadCallableSource.indexOf("std::to_string((load(\"error\", 2))(") < 0,
			"C++ Context.load immediate calls in string contexts should not fall through to generic std::to_string wrapping");

		final switchExpectedRefDir = Path.join([root, "switch-expected-ref-source-only"]);
		final switchExpectedRefEmit = BackendRegistry.createForTarget("cpp-native")
			.emit(switchExpectedRefProgram(), context(switchExpectedRefDir, true, true));
		final switchExpectedRefSource = File.getContent(switchExpectedRefEmit.entryPath);
		assertContains(switchExpectedRefSource, "return ([&]() -> std::shared_ptr<Ref<std::shared_ptr<ClassType>>> {",
			"C++ switch expressions in reference-returning methods should emit an explicitly typed IIFE");
		assertContains(switchExpectedRefSource, "std::shared_ptr<Ref<std::shared_ptr<ClassType>>> c = nullptr;",
			"C++ enum-pattern binders returned directly from an expected reference switch should use the expected branch type");
		assertTrue(switchExpectedRefSource.indexOf("  return 0;\n})()") < 0,
			"C++ switch expression fallback in an expected reference context should not return int zero");

		final macroAbstractShapeDir = Path.join([root, "macro-abstract-operator-shape-source-only"]);
		final macroAbstractShapeEmit = BackendRegistry.createForTarget("cpp-native")
			.emit(macroAbstractOperatorShapeProgram(), context(macroAbstractShapeDir, true, true));
		final macroAbstractShapeSource = File.getContent(macroAbstractShapeEmit.entryPath);
		final binopShapeName = "__hxhx_anon_op_std__shared_ptr_Binop__field_std__shared_ptr_ClassField_";
		final unopShapeName = "__hxhx_anon_op_std__shared_ptr_Unop__postFix_bool__field_std__shared_ptr_ClassField_";
		assertContains(macroAbstractShapeSource, "struct " + binopShapeName + " {",
			"C++ structural arrays should declare the Binop/ClassField aggregate before AbstractType uses it");
		assertContains(macroAbstractShapeSource, "struct " + unopShapeName + " {",
			"C++ structural arrays should declare the Unop/postFix/ClassField aggregate before AbstractType uses it");
		assertContains(macroAbstractShapeSource, "std::vector<" + binopShapeName + "> binops = {};",
			"C++ structural arrays should preserve AbstractType.binops as a typed aggregate vector");
		assertContains(macroAbstractShapeSource, "std::vector<" + unopShapeName + "> unops = {};",
			"C++ structural arrays should preserve AbstractType.unops as a typed aggregate vector");
		assertContains(macroAbstractShapeSource, "static std::vector<" + binopShapeName + "> emptyBinops() {",
			"C++ structural array returns should preserve typed aggregate vectors");
		assertTrue(macroAbstractShapeSource.indexOf("struct " + binopShapeName + " {") < macroAbstractShapeSource.indexOf("struct AbstractType {"),
			"C++ structural array aggregates should be declared before the typedef helper that stores them");
		assertTrue(macroAbstractShapeSource.indexOf("std::vector<std::string> binops") < 0,
			"C++ structural arrays should not collapse macro AbstractType.binops to string vectors");

		final mainLoopDir = Path.join([root, "main-loop-runtime-source-only"]);
		final mainLoopEmit = BackendRegistry.createForTarget("cpp-native").emit(mainLoopRuntimeProgram(), context(mainLoopDir, true, true));
		final mainLoopSource = File.getContent(mainLoopEmit.entryPath);
		assertContains(mainLoopSource, "#include <chrono>", "C++ Timer.stamp support should include chrono");
		assertContains(mainLoopSource, "struct Timer {", "C++ Timer should be provided by target-owned runtime support");
		assertContains(mainLoopSource, "struct Lock {", "C++ Lock should be provided by target-owned runtime support");
		assertContains(mainLoopSource, "struct Mutex {", "C++ Mutex should be provided by target-owned runtime support");
		assertContains(mainLoopSource, "struct MainEvent {", "C++ MainEvent should be provided by target-owned runtime support");
		assertContains(mainLoopSource, "struct MainLoop {", "C++ MainLoop should be provided by target-owned runtime support");
		assertContains(mainLoopSource, "struct EntryPoint {", "C++ EntryPoint should be provided by target-owned runtime support");
		assertTrue(mainLoopSource.indexOf("struct Timer {") < mainLoopSource.indexOf("EntryPoint::runInMainThread"),
			"C++ target-owned Timer support should appear before generated calls use it");
		assertContains(mainLoopSource, "inline static std::vector<std::function<void()>> pending = {};",
			"C++ EntryPoint.pending should be a function queue, not a bool or ArrayVoid expression");
		assertContains(mainLoopSource, "inline static std::shared_ptr<MainEvent> pending = nullptr;",
			"C++ MainLoop.pending should be a MainEvent link, not an erased scalar");
		assertContains(mainLoopSource, "std::shared_ptr<MainEvent> prev = nullptr;", "C++ MainEvent.prev should retain the linked-list reference type");
		assertContains(mainLoopSource, "std::shared_ptr<MainEvent> next = nullptr;", "C++ MainEvent.next should retain the linked-list reference type");
		assertContains(mainLoopSource, "static T __hxhx_shift(std::vector<T>& values)",
			"C++ function queues should have a target-owned shift helper for Array.shift lowering");
		assertContains(mainLoopSource, "EntryPoint::runInMainThread([&]() {", "C++ generated code should call the target-owned EntryPoint support class");
		assertContains(mainLoopSource, "MainLoop::add([&]() {", "C++ generated code should call the target-owned MainLoop support class");
		assertContains(mainLoopSource, "event->delay(0);", "C++ generated code should call MainEvent support methods through shared_ptr");
		assertTrue(mainLoopSource.indexOf("ArrayVoid") < 0, "C++ event queue support should not leak ArrayVoid into generated source");
		assertTrue(mainLoopSource.indexOf("inline static bool pending =") < 0, "C++ event queue support should not infer pending as bool");

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
				"auto next() {\n    auto val = (head->item);\n    head = (head->next);\n    return __hxhx_anon_value_std__string_key_int_{__hxhx_stringify(val), (idx++)};\n  }",
				"C++ smoke should preserve upstream ListKeyValueIterator.next key/value return body");
		}
		assertVendorBalancedTreeReturnTypesWhenAvailable();
		final vendorBalancedTreeProgram = vendorBalancedTreeProgramWhenAvailable();
		if (vendorBalancedTreeProgram != null) {
			final vendorBalancedTreeDir = Path.join([root, "vendor-balancedtree-source-only"]);
			final vendorBalancedTreeEmit = BackendRegistry.createForTarget("cpp-native")
				.emit(vendorBalancedTreeProgram, context(vendorBalancedTreeDir, true, true));
			final vendorBalancedTreeSource = File.getContent(vendorBalancedTreeEmit.entryPath);
			assertContains(vendorBalancedTreeSource, "struct BalancedTree {", "C++ smoke should emit upstream haxe.ds.BalancedTree as a helper");
			assertContains(vendorBalancedTreeSource, "std::shared_ptr<TreeNode<K, V>> setLoop",
				"C++ smoke should keep BalancedTree.setLoop return typing concrete without recursive inference");
		}
		assertVendorJsonParserReturnTypesWhenAvailable();
		assertVendorExprToolsReturnTypesWhenAvailable();
		assertVendorTemplateReturnTypesWhenAvailable();
		final vendorTemplateProgram = vendorTemplateProgramWhenAvailable();
		if (vendorTemplateProgram != null) {
			final vendorTemplateDir = Path.join([root, "vendor-template-source-only"]);
			final vendorTemplateEmit = BackendRegistry.createForTarget("cpp-native").emit(vendorTemplateProgram, context(vendorTemplateDir, true, true));
			final vendorTemplateSource = File.getContent(vendorTemplateEmit.entryPath);
			assertContains(vendorTemplateSource, "struct Template {", "C++ smoke should emit upstream haxe.Template as a helper");
			assertContains(vendorTemplateSource, "std::shared_ptr<TemplateExpr> parse(",
				"C++ smoke should keep Template.parse return typing concrete without recursive inference");
		}
		final vendorReadOnlyArrayProgram = vendorReadOnlyArrayProgramWhenAvailable();
		if (vendorReadOnlyArrayProgram != null) {
			final vendorReadOnlyArrayDir = Path.join([root, "vendor-readonlyarray-source-only"]);
			final vendorReadOnlyArrayEmit = BackendRegistry.createForTarget("cpp-native")
				.emit(vendorReadOnlyArrayProgram, context(vendorReadOnlyArrayDir, true, true));
			final vendorReadOnlyArraySource = File.getContent(vendorReadOnlyArrayEmit.entryPath);
			assertContains(vendorReadOnlyArraySource, "struct ReadOnlyArray {", "C++ smoke should emit upstream haxe.ds.ReadOnlyArray as a helper");
			assertTrue(vendorReadOnlyArraySource.indexOf("template<typename T>\nstruct ReadOnlyArray;") < 0,
				"C++ ReadOnlyArray forward declarations should match the current non-template target-owned support shape");
			assertTrue(vendorReadOnlyArraySource.indexOf("ReadOnlyArray<T>") < 0,
				"C++ ReadOnlyArray helper methods should not render target-owned ReadOnlyArray as a C++ template");
			assertContains(vendorReadOnlyArraySource, "auto operator[](int index) const { return __values[index]; }",
				"C++ smoke should expose operator[] for upstream haxe.ds.ReadOnlyArray array access");
			assertContains(vendorReadOnlyArraySource, "((*this)[i])", "C++ smoke should preserve upstream ReadOnlyArray.get through the wrapper operator[]");
		}
		final vendorVectorProgram = vendorVectorProgramWhenAvailable();
		if (vendorVectorProgram != null) {
			final vendorVectorDir = Path.join([root, "vendor-vector-source-only"]);
			final vendorVectorEmit = BackendRegistry.createForTarget("cpp-native").emit(vendorVectorProgram, context(vendorVectorDir, true, true));
			final vendorVectorSource = File.getContent(vendorVectorEmit.entryPath);
			assertContains(vendorVectorSource, "struct Vector {", "C++ smoke should emit target-owned haxe.ds.Vector support");
			assertTrue(vendorVectorSource.indexOf("template<typename T>\nstruct Vector;") < 0,
				"C++ Vector forward declarations should match the current non-template target-owned support shape");
			assertContains(vendorVectorSource, "Vector(int length) : __values(length), length(length) {}",
				"C++ smoke should render haxe.ds.Vector through target-owned support, not upstream inactive branches");
			assertContains(vendorVectorSource, "std::string unsafeGet(int index) const { return __values[index]; }",
				"C++ smoke should expose haxe.ds.Vector unsafeGet through native vector storage");
			assertContains(vendorVectorSource, "std::string join(std::string sep) const { return __hxhx_join(__values, sep); }",
				"C++ smoke should keep haxe.ds.Vector.join separator string-shaped even though upstream declares method-level <T>");
			assertTrue(vendorVectorSource.indexOf("join(T__fn sep)") < 0,
				"C++ smoke should not leak renamed method generics into haxe.ds.Vector.join separator type");
			assertTrue(vendorVectorSource.indexOf("(*this) = std::make_shared<Vector>") < 0,
				"C++ smoke should not emit inactive non-C++ haxe.ds.Vector constructor branches");
			assertTrue(vendorVectorSource.indexOf("((python.internal).ArrayImpl)") < 0, "C++ smoke should not emit inactive Python haxe.ds.Vector branches");
		}
		final vendorNativeArrayProgram = vendorNativeArrayProgramWhenAvailable();
		if (vendorNativeArrayProgram != null) {
			final vendorNativeArrayDir = Path.join([root, "vendor-nativearray-source-only"]);
			final vendorNativeArrayEmit = BackendRegistry.createForTarget("cpp-native")
				.emit(vendorNativeArrayProgram, context(vendorNativeArrayDir, true, true));
			final vendorNativeArraySource = File.getContent(vendorNativeArrayEmit.entryPath);
			assertTrue(vendorNativeArraySource.indexOf("struct NativeArray {") < 0, "C++ smoke should not emit cpp.NativeArray externs as fake helper structs");
		}

		final vendorLambdaProgram = vendorLambdaProgramWhenAvailable();
		if (vendorLambdaProgram != null) {
			final vendorLambdaDir = Path.join([root, "vendor-lambda-source-only"]);
			final vendorLambdaEmit = BackendRegistry.createForTarget("cpp-native").emit(vendorLambdaProgram, context(vendorLambdaDir, true, true));
			final vendorLambdaSource = File.getContent(vendorLambdaEmit.entryPath);
			assertContains(vendorLambdaSource,
				"template<typename A, typename B>\n  static std::vector<B> mapi(std::vector<A> it, std::function<B(int, A)> f) {",
				"C++ smoke should preserve upstream Lambda.mapi method-level generic callback shape");
			assertTrue(vendorLambdaSource.indexOf("struct T;\n") < 0
				&& vendorLambdaSource.indexOf("struct A;\n") < 0
				&& vendorLambdaSource.indexOf("struct B;\n") < 0,
				"C++ smoke should not forward-declare method-level generic type params as fake classes");
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
			assertTrue(run.stdout == "cpp-native:smoke\ntrace:smoke\n1\n-1\n1\nneedle\n0\n2\nbeta\n0\ntrue\n3\n4\nfalse\n10\nq:1.5:true:ok\n11\n5\n3\n9\ntry:body\ntry:catch\n3\n1\n8\n4\n2147483647\n-2\n42\n41\nroot\nref:null\n0\n1\n1\n0\n2\n2\n1\n2\n4\n2\n15\n3\nalpha\nbeta\n0\nalpha\n1\nbeta\n2\n10\nif:then\nor:true\nand:true\nnot:true\nMacro\nenum:eq\ntrue\ntrue\nIgnore\n7\nEParenthesis(EConst(CString(macro:value)))\nmacro:value\nX -> Y\ntwo\nswitch:seven\n7\n-3\nternary:yes\n5\n42\n3\n4\nalpha,beta\n",
				"unexpected C++ smoke stdout: "
				+ run.stdout);
		}

		deleteRecursive(root);
	}
}
