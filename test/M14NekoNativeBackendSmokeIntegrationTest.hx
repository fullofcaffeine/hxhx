import backend.BackendContext;
import backend.BackendDispatchBoundary;
import backend.BackendRegistry;
import backend.vm.NekoTargetCore;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;

class M14NekoNativeBackendSmokeIntegrationTest {
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

	static function assertFailsContains(fn:Void->Void, expected:String):Void {
		var message = "";
		try {
			fn();
		} catch (e:haxe.Exception) {
			message = e.message;
		} catch (e:String) {
			message = e;
		}
		assertTrue(message.indexOf(expected) >= 0, "expected failure containing `" + expected + "`, got `" + message + "`");
	}

	static function protocolLine(key:String, payload:String):String {
		final escaped = StringTools.replace(StringTools.replace(StringTools.replace(StringTools.replace(payload, "\\", "\\\\"), "\n", "\\n"), "\r", "\\r"),
			"\t", "\\t");
		return "ast " + key + " " + escaped.length + ":" + escaped;
	}

	static function assertNativeReturnCaseFragmentDecode():Void {
		final encoded = [
			"hxhx_frontend_v=2",
			protocolLine("class", "PrinterLike"),
			"ast static_main 0",
			protocolLine("method", 'printOp|public|0|op|String|||op:Dynamic|case OpIncrement: "++";\n\t\t\tcase OpDecrement: "--";'),
			"ok"
		].join("\n");
		final decl = ParserStageNativeDecode.decodeNativeProtocol(encoded);
		final functions = HxClassDecl.getFunctions(HxModuleDecl.getMainClass(decl));
		assertTrue(functions.length == 1, "native return case-fragment decode should preserve the method");
		switch (HxFunctionDecl.getBody(functions[0])[0]) {
			case SReturn(ENull, _):
			case SReturn(EUnsupported(raw), _):
				throw "native return case-fragment summary should not decode as unsupported: " + raw;
			case _:
				throw "native return case-fragment summary should decode to a neutral fallback";
		}
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

	static function program(source:String) {
		final parsed = ParserStage.parse(source, "Main.hx");
		final typed = TyperStage.typeModule(parsed);
		return MacroStage.expandProgram([typed], []);
	}

	static function main():Void {
		assertNativeReturnCaseFragmentDecode();
		assertTrue(@:privateAccess NekoTargetCore.renderExpr(cast null,
			EUnsupported("8")) == "8", "numeric unsupported fragments should render as integer literals");
		assertTrue(@:privateAccess NekoTargetCore.renderExpr(cast null, EUnsupported("for_expr:for (key => value in 1) { }")) == "null",
			"for-expression recovery fragments should render as neutral null");
		assertTrue(@:privateAccess NekoTargetCore.renderExpr(cast null, EUnsupported("=")) == "null",
			"single-token assignment recovery fragments should render as neutral null");
		assertFailsContains(() -> @:privateAccess NekoTargetCore.renderExpr(cast null, EUnsupported("not_numeric")), "EUnsupported(not_numeric)");
		assertTrue(@:privateAccess NekoTargetCore.isNekoNumericLiteralText("1.2e+35"), "scientific float text should be valid Neko numeric text");
		assertTrue(! @:privateAccess NekoTargetCore.isNekoNumericLiteralText(String.fromCharCode(0xF0) + "bad"),
			"invalid byte-like float text must not be emitted as raw Neko source");
		assertTrue(@:privateAccess NekoTargetCore.sanitizeNekoValueExpr("value + 1") == "value + 1", "safe Neko expressions should remain unchanged");
		assertTrue(@:privateAccess NekoTargetCore.sanitizeNekoValueExpr("x" + String.fromCharCode(0) + "bad") == "null",
			"control-byte expression text must be neutralized before Neko source emission");
		final opaqueObject = @:privateAccess NekoTargetCore.renderExpr(cast null, ETryCatchRaw('opaque_block_expr:{ var b:{v:Int} = {v:1}; }'));
		assertContains(opaqueObject, "__hxhx_o.v = 1;", "opaque object block should emit the captured field value safely");
		final opaqueTwoFieldObject = @:privateAccess NekoTargetCore.renderExpr(cast null, ETryCatchRaw('opaque_block_expr:{ var b:{v:Int} = {v:1,w:"foo"}; }'));
		assertContains(opaqueTwoFieldObject, '__hxhx_o.w = "foo";', "opaque object block should emit the second captured field safely");
		assertFailsContains(() -> @:privateAccess NekoTargetCore.renderExpr(cast null, ETryCatchRaw('opaque_block_expr:{ var b:{v:Int} = {w:1}; }')),
			"ETryCatchRaw");
		final opaqueTypedLocalInit = @:privateAccess NekoTargetCore.renderExpr(cast null, ETryCatchRaw('opaque_block_expr:{ var i:Int = z; }'));
		assertContains(opaqueTypedLocalInit, "var i = z;", "opaque typed local init should emit the captured initializer safely");
		final macroInExpr = @:privateAccess NekoTargetCore.renderExpr(cast null, EMacroExpr(EBinop("in", EInt(1), EInt(0)), []));
		assertContains(macroInExpr, '.__hx_ctor = "EBinop";', "macro in-expression should lower to macro EBinop");
		assertContains(macroInExpr, '.__hx_ctor = "OpIn";', "macro in-expression should preserve OpIn");
		assertContains(macroInExpr, '.__hx_ctor = "CInt";', "macro in-expression should lower int operands");
		assertNotContains(macroInExpr, " in ", "macro in-expression syntax should not leak into Neko source");

		final outDir = Path.join([".tmp", "m14_neko_native_backend_smoke"]);
		deleteRecursive(outDir);
		FileSystem.createDirectory(outDir);

		final defines = new haxe.ds.StringMap<String>();
		defines.set(NekoTargetCore.SOURCE_ONLY_DEFINE, "1");
		final outputHint = Path.join([outDir, "main.n"]);
		final context = new BackendContext(outDir, outputHint, "Main", true, false, defines);
		final backend = BackendRegistry.createForTarget("neko-native");
		final result = BackendDispatchBoundary.emit(backend, program('class Main { static function main() { Sys.println("hello neko"); } }'), context);

		final sourcePath = Path.join([outDir, "main.neko"]);
		assertTrue(result.entryPath == sourcePath, "source-only mode should report the generated Neko source as entry path");
		assertTrue(FileSystem.exists(sourcePath), "expected generated Neko source file");
		final source = File.getContent(sourcePath);
		assertContains(source, "var Main_main = function()", "expected generated static main function");
		assertContains(source, "$print(\"hello neko\", \"\\n\")", "expected Sys.println lowering");
		assertContains(source, "Main_main();", "expected entrypoint invocation");

		final splitContext = new BackendContext(outDir, outputHint, "Main", true, false, new haxe.ds.StringMap<String>());
		final split = @:privateAccess NekoTargetCore.renderSplitProgram(program('class Helper { public static function value() return 40; } class Main { static function main() { Sys.println(Helper.value() + 2); } }'),
			splitContext, sourcePath);
		assertContains(split.support[0].source, "$exports.symbols = $new(null);", "expected split Neko symbol table module");
		assertContains(split.support[1].source, "__hxhx_symbols.Helper_value = function()", "expected split static function registration");
		assertContains(split.support[1].source, "__hxhx_symbols.Helper_value()", "expected split static calls to use symbol table");
		assertContains(split.entrySource, "$loader.loadmodule(", "expected split entry module to load support chunks");
		assertContains(split.entrySource, "__hxhx_symbols.Main_main();", "expected split entrypoint to call through symbol table");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function feq(a:Float, b:Float) {} static function main() { feq(1.2e+35, 1.2e+35); } }'), context);
		final scientificFloatSource = File.getContent(sourcePath);
		assertContains(scientificFloatSource, 'feq($$float("1.2e+35"), $$float("1.2e+35"));',
			"expected scientific float arguments to avoid Neko call-position literal syntax");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { var p = -1; if (p < 0) p = 0; else if (p > 1) p = 1; Sys.println(p); } }'), context);
		final assignmentIfSource = File.getContent(sourcePath);
		assertContains(assignmentIfSource, "if (p < 0) {", "expected Neko if body to use a block");
		assertContains(assignmentIfSource, "(p = 0);", "expected assignment body to remain side-effecting");
		assertContains(assignmentIfSource, "else {", "expected Neko else body to use a block");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend, program('class Main { static function main() { var value = ~1; Sys.println(value); } }'), context);
		final bitwiseNotSource = File.getContent(sourcePath);
		assertContains(bitwiseNotSource, "var value = (1 ^ -1);", "expected Neko bitwise-not lowering");
		assertNotContains(bitwiseNotSource, "~1", "bitwise-not syntax should not leak into Neko source");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { var value = 1; var old = value++; var negOld = -(value--); Sys.println(old + negOld); } }'),
			context);
		final postfixSource = File.getContent(sourcePath);
		assertContains(postfixSource, "var __hxhx_post_old = value;", "expected Neko postfix update to capture the old value");
		assertContains(postfixSource, "value = (__hxhx_post_old + 1);", "expected Neko postfix increment to update the local");
		assertContains(postfixSource, "value = (__hxhx_post_old - 1);", "expected Neko postfix decrement to update the local");
		assertContains(postfixSource, "return __hxhx_post_old;", "expected Neko postfix update to return the old value");
		assertNotContains(postfixSource, "post++", "postfix increment token should not leak into Neko source");
		assertNotContains(postfixSource, "post--", "postfix decrement token should not leak into Neko source");

		deleteRecursive(outDir);

		final postfixThisSource = @:privateAccess NekoTargetCore.renderExpr(cast {
			classes: null,
			mainClass: null,
			currentClass: null,
			selfName: "__hxhx_self"
		}, EUnop("post++", EThis));
		assertContains(postfixThisSource, "var __hxhx_post_old = __hxhx_self.__hx_value;", "expected Neko postfix this update to read backing value slot");
		assertContains(postfixThisSource, "__hxhx_self.__hx_value = (__hxhx_post_old + 1);", "expected Neko postfix this update to write backing value slot");
		assertNotContains(postfixThisSource, "post++", "postfix this increment token should not leak into Neko source");

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class BaseProp { public function new() {} public var prop(get,set):Int; function get_prop() return 1; function set_prop(v:Int) return v; } class ChildSuperProp extends BaseProp { public function new() { super(); } override function set_prop(v:Int) return (super.prop = v) + 1; } class Main { static function main() { var child = new ChildSuperProp(); Sys.println(child.set_prop(4)); } }'),
			context);
		final superPropAssignSource = File.getContent(sourcePath);
		assertContains(superPropAssignSource, "return (__hxhx_parenthesized(v) + 1);",
			"expected Neko super property assignment MVP to preserve expression value");
		assertNotContains(superPropAssignSource, "(null = v)", "super property assignment must not emit an invalid null lvalue");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function fallback() return 2; static function main() { var value:Null<Int> = null; var got = value ?? fallback(); Sys.println(got); } }'),
			context);
		final nullCoalesceSource = File.getContent(sourcePath);
		assertContains(nullCoalesceSource, "var __hxhx_coalesce = value;", "expected Neko null-coalescing lowering to capture the left value once");
		assertContains(nullCoalesceSource, "return fallback();", "expected Neko null-coalescing lowering to keep fallback lazy");
		assertNotContains(nullCoalesceSource, "??", "null-coalescing syntax should not leak into Neko source");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function fallback() return 5; static function main() { var value:Null<Int> = null; value ??= fallback(); var got = value ??= fallback(); Sys.println(got); } }'),
			context);
		final nullCoalesceAssignSource = File.getContent(sourcePath);
		assertContains(nullCoalesceAssignSource, "if (value == null)", "expected Neko null-coalescing assignment to check the target");
		assertContains(nullCoalesceAssignSource, "value = fallback();", "expected Neko null-coalescing assignment to update the target lazily");
		assertContains(nullCoalesceAssignSource, "return value;", "expected Neko null-coalescing assignment expression to return the resulting target");
		assertNotContains(nullCoalesceAssignSource, "??=", "null-coalescing assignment syntax should not leak into Neko source");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		final anonResult = BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { var o = { name: "neko", count: 2 }; Sys.println(o.name); } }'), context);
		assertTrue(anonResult.entryPath == sourcePath, "anon source-only mode should report generated Neko source");
		final anonSource = File.getContent(sourcePath);
		assertContains(anonSource, "var __hxhx_o = $new(null);", "expected Neko object allocation for anonymous object literal");
		assertContains(anonSource, "__hxhx_o.name = \"neko\";", "expected anonymous object string field assignment");
		assertContains(anonSource, "__hxhx_o.count = 2;", "expected anonymous object int field assignment");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class TestOps { public function new(v:Int) {} } class Main { static function main() { var o = new TestOps(7); } }'), context);
		final newSource = File.getContent(sourcePath);
		assertContains(newSource, "__hxhx_self.__hx_ctor = \"TestOps\";", "expected constructor tag on lowered Neko object");
		assertContains(newSource, "__hxhx_self.__hx_params = $array(v);", "expected constructor params on lowered Neko object");
		assertContains(newSource, "__hxhx_self.__hx_value = v;", "expected first constructor arg to seed abstract-style this value slot");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { var empty = new Map(); var one = [1 => 1]; Sys.println(one.toString()); } }'), context);
		final mapSource = File.getContent(sourcePath);
		assertContains(mapSource, "var empty = __hxhx_map_new(\"Map\");", "expected neutral Map construction to use the Neko map helper");
		assertContains(mapSource, "var one = (function() { var __hxhx_m = __hxhx_map_new(\"Map\");", "expected map literal allocation helper");
		assertContains(mapSource, "__hxhx_m.set(1, 1);", "expected map literal entries to lower through set");
		assertNotContains(mapSource, "1 => 1", "map literal syntax should not leak into Neko source");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend, program('class Main { static function main() { var f = x -> x; Sys.println(f(3)); } }'), context);
		final lambdaSource = File.getContent(sourcePath);
		assertContains(lambdaSource, "var f = function(x) { return x; };", "expected Neko lambda lowering");
		assertContains(lambdaSource, "$print(f(3), \"\\n\")", "expected lambda call lowering");
		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { var label = switch (1) { case 1: "one"; default: "other"; }; Sys.println(label); } }'), context);
		final switchSource = File.getContent(sourcePath);
		assertContains(switchSource, 'var label = switch 1 { 1 => "one" default => "other" };', "expected Neko switch expression lowering");
		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { var label = switch (1) { case 1 if (Std.random(2) == 1): "guarded"; default: "fallback"; }; Sys.println(label); } }'),
			context);
		final guardedSwitchExprSource = File.getContent(sourcePath);
		assertContains(guardedSwitchExprSource, 'var label = switch 1 { default => "fallback" };',
			"expected unsupported guarded switch expression branch to be disabled");
		assertNotContains(guardedSwitchExprSource, '"guarded"', "unsupported guarded switch expression branch must not execute unguarded");
		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { var ok = true; var expected = false; var label = switch [ok, expected] { case [true, false]: "mismatch"; default: "other"; }; Sys.println(label); } }'),
			context);
		final arraySwitchExprSource = File.getContent(sourcePath);
		assertContains(arraySwitchExprSource, "var __hxhx_switch = $array(ok, expected);", "expected array switch expression temp");
		assertContains(arraySwitchExprSource, "($asize(__hxhx_switch) == 2)", "expected array switch length guard");
		assertContains(arraySwitchExprSource, "(__hxhx_switch[0] == true)", "expected first array switch item guard");
		assertContains(arraySwitchExprSource, "return \"mismatch\";", "expected array switch expression branch return");
		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { var label = switch "Linux" { case "Linux" | "Windows": "desktop"; default: "other"; }; Sys.println(label); } }'),
			context);
		final orSwitchExprSource = File.getContent(sourcePath);
		assertContains(orSwitchExprSource, "var __hxhx_switch = \"Linux\";", "expected OR switch expression temp");
		assertContains(orSwitchExprSource, '((__hxhx_switch == "Linux")) || ((__hxhx_switch == "Windows"))', "expected OR switch condition");
		assertContains(orSwitchExprSource, 'return "desktop";', "expected OR switch expression branch return");
		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { var label = switch 5 { case value = (4 | 5 | 6) if (value == 5): "middle"; default: "other"; }; Sys.println(label); } }'),
			context);
		final intEqualsGuardSwitchExprSource = File.getContent(sourcePath);
		assertContains(intEqualsGuardSwitchExprSource, "var value = __hxhx_switch;", "expected guarded switch capture binding");
		assertContains(intEqualsGuardSwitchExprSource, "(__hxhx_switch == 5)", "expected guarded switch integer equality condition");
		assertContains(intEqualsGuardSwitchExprSource, 'return "middle";', "expected guarded switch expression branch return");
		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { var label = switch 6 { case value = (4 | 5 | 6) if (value > 4): "large"; default: "other"; }; Sys.println(label); } }'),
			context);
		final intCompareGuardSwitchExprSource = File.getContent(sourcePath);
		assertContains(intCompareGuardSwitchExprSource, "var value = __hxhx_switch;", "expected compare guarded switch capture binding");
		assertContains(intCompareGuardSwitchExprSource, "(__hxhx_switch > 4)", "expected guarded switch integer comparison condition");
		assertContains(intCompareGuardSwitchExprSource, 'return "large";', "expected compare guarded switch expression branch return");
		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { var label = switch ({ value: "neko" }) { case { value: name }: name; default: "other"; }; Sys.println(label); } }'),
			context);
		final objectSwitchExprSource = File.getContent(sourcePath);
		assertContains(objectSwitchExprSource, "var __hxhx_switch = (function() { var __hxhx_o = $new(null);", "expected object switch expression temp");
		assertContains(objectSwitchExprSource, "$objget(__hxhx_switch, $hash(\"value\"))", "expected object switch field lookup");
		assertContains(objectSwitchExprSource, "var name = $objget(__hxhx_switch, $hash(\"value\"));", "expected object switch field binding");
		assertContains(objectSwitchExprSource, "return name;", "expected object switch expression branch return");
		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { var label = switch ["exitCode", "5"] { case ["exitCode", Std.parseInt(_) => code]: code; default: 0; }; Sys.println(label); } }'),
			context);
		final extractorSwitchExprSource = File.getContent(sourcePath);
		assertContains(extractorSwitchExprSource, "var __hxhx_switch = $array(\"exitCode\", \"5\");", "expected extractor switch expression temp");
		assertContains(extractorSwitchExprSource, "var __hxhx_extract_t = $typeof(__hxhx_extract);", "expected Std.parseInt extractor helper");
		assertContains(extractorSwitchExprSource, "var code = (function(__hxhx_extract)", "expected extractor result binding");
		assertContains(extractorSwitchExprSource, "return code;", "expected extractor switch expression branch return");
		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend, program('class Main { static function main() { var t = macro :X -> Y; Sys.println("macro-type"); } }'), context);
		final macroTypeSource = File.getContent(sourcePath);
		assertContains(macroTypeSource, "__hxhx_o.__hx_ctor = \"TFunction\";", "expected macro type arrow to lower to TFunction");
		assertContains(macroTypeSource, "__hxhx_o.__hx_ctor = \"TPath\";", "expected macro type paths to lower to TPath");
		assertContains(macroTypeSource, "__hxhx_o.name = \"X\";", "expected macro type argument path");
		assertContains(macroTypeSource, "__hxhx_o.name = \"Y\";", "expected macro type return path");
		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend, program('class Main { static function main() { var e = macro (1 in 0); Sys.println(e.expr); } }'), context);
		final macroExprSource = File.getContent(sourcePath);
		assertContains(macroExprSource, '.__hx_ctor = "EBinop";', "expected macro in-expression source to lower to macro EBinop");
		assertContains(macroExprSource, '.__hx_ctor = "OpIn";', "expected macro in-expression source to preserve OpIn");
		assertNotContains(macroExprSource, " in ", "macro in-expression syntax should not leak into generated Neko source");
		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { switch (1) { case 1: Sys.println("one"); default: Sys.println("other"); } } }'), context);
		final switchStmtSource = File.getContent(sourcePath);
		assertContains(switchStmtSource, "switch 1 {", "expected Neko switch statement");
		assertContains(switchStmtSource, "1 => {", "expected Neko switch case block");
		assertContains(switchStmtSource, "$print(\"one\", \"\\n\")", "expected switch case body");
		assertContains(switchStmtSource, "default => {", "expected Neko switch default block");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { switch (1) { case 1 if (Std.random(2) == 1): Sys.println("guarded"); default: Sys.println("fallback"); } } }'),
			context);
		final guardedSwitchStmtSource = File.getContent(sourcePath);
		assertContains(guardedSwitchStmtSource, "switch 1 {", "expected guarded Neko switch statement to still lower");
		assertContains(guardedSwitchStmtSource, "default => {", "expected default to remain after disabled guarded switch branch");
		assertContains(guardedSwitchStmtSource, "$print(\"fallback\", \"\\n\")", "expected default body to remain");
		assertNotContains(guardedSwitchStmtSource, '"guarded"', "unsupported guarded switch statement branch must not execute unguarded");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { var ok = true; var expected = false; switch [ok, expected] { case [true, false]: Sys.println("mismatch"); default: Sys.println("other"); } } }'),
			context);
		final arraySwitchStmtSource = File.getContent(sourcePath);
		assertContains(arraySwitchStmtSource, "var __hxhx_switch = $array(ok, expected);", "expected array switch statement temp");
		assertContains(arraySwitchStmtSource, "(__hxhx_switch != null) && ($asize(__hxhx_switch) == 2)", "expected array switch statement if lowering");
		assertContains(arraySwitchStmtSource, "$print(\"mismatch\", \"\\n\")", "expected array switch statement branch body");
		assertContains(arraySwitchStmtSource, "else if (true)", "expected array switch statement default branch");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { switch "Linux" { case "Linux" | "Windows": Sys.println("desktop"); default: Sys.println("other"); } } }'),
			context);
		final orSwitchStmtSource = File.getContent(sourcePath);
		assertContains(orSwitchStmtSource, '((__hxhx_switch == "Linux")) || ((__hxhx_switch == "Windows"))', "expected OR switch statement condition");
		assertContains(orSwitchStmtSource, "$print(\"desktop\", \"\\n\")", "expected OR switch statement branch body");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { switch 5 { case value = (4 | 5 | 6) if (value == 5): Sys.println("middle"); default: Sys.println("other"); } } }'),
			context);
		final intEqualsGuardSwitchStmtSource = File.getContent(sourcePath);
		assertContains(intEqualsGuardSwitchStmtSource, "var value = __hxhx_switch;", "expected guarded switch statement capture binding");
		assertContains(intEqualsGuardSwitchStmtSource, "(__hxhx_switch == 5)", "expected guarded switch statement integer equality condition");
		assertContains(intEqualsGuardSwitchStmtSource, "$print(\"middle\", \"\\n\")", "expected guarded switch statement branch body");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { switch 6 { case value = (4 | 5 | 6) if (value > 4): Sys.println("large"); default: Sys.println("other"); } } }'),
			context);
		final intCompareGuardSwitchStmtSource = File.getContent(sourcePath);
		assertContains(intCompareGuardSwitchStmtSource, "var value = __hxhx_switch;", "expected compare guarded switch statement capture binding");
		assertContains(intCompareGuardSwitchStmtSource, "(__hxhx_switch > 4)", "expected guarded switch statement integer comparison condition");
		assertContains(intCompareGuardSwitchStmtSource, "$print(\"large\", \"\\n\")", "expected compare guarded switch statement branch body");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { switch ({ value: "neko" }) { case { value: name }: Sys.println(name); default: Sys.println("other"); } } }'),
			context);
		final objectSwitchStmtSource = File.getContent(sourcePath);
		assertContains(objectSwitchStmtSource, "$objget(__hxhx_switch, $hash(\"value\"))", "expected object switch statement field lookup");
		assertContains(objectSwitchStmtSource, "var name = $objget(__hxhx_switch, $hash(\"value\"));", "expected object switch statement field binding");
		assertContains(objectSwitchStmtSource, "$print(name, \"\\n\")", "expected object switch statement branch body");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { switch ["exitCode", "5"] { case ["exitCode", Std.parseInt(_) => code]: Sys.println(code); default: Sys.println(0); } } }'),
			context);
		final extractorSwitchStmtSource = File.getContent(sourcePath);
		assertContains(extractorSwitchStmtSource, "var __hxhx_extract_t = $typeof(__hxhx_extract);", "expected statement Std.parseInt extractor helper");
		assertContains(extractorSwitchStmtSource, "var code = (function(__hxhx_extract)", "expected statement extractor result binding");
		assertContains(extractorSwitchStmtSource, "$print(code, \"\\n\")", "expected extractor switch statement branch body");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend, program('class Main { static function main() { for (i in [1, 2]) Sys.println(i); } }'), context);
		final forSource = File.getContent(sourcePath);
		assertContains(forSource, "var __hxhx_iter_i = $array(1, 2);", "expected Neko for-in iterable temp");
		assertContains(forSource, "while (__hxhx_index_i < $asize(__hxhx_iter_i))", "expected Neko for-in while lowering");
		assertContains(forSource, "var i = __hxhx_iter_i[__hxhx_index_i];", "expected Neko for-in value binding");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { var verbose = Sys.args().indexOf("-v") >= 0; var values = [1]; values.push(2); Sys.println(verbose); } }'),
			context);
		final arrayMethodSource = File.getContent(sourcePath);
		assertContains(arrayMethodSource, "var __hxhx_array_indexOf = function(a, value)", "expected Neko array indexOf helper");
		assertContains(arrayMethodSource, "var __hxhx_array_push = function(a, value)", "expected Neko array push helper");
		assertContains(arrayMethodSource, 'var verbose = (__hxhx_array_indexOf($$loader.args, "-v") >= 0);', "expected Sys.args().indexOf lowering");
		assertContains(arrayMethodSource, "__hxhx_array_push(values, 2);", "expected array push lowering");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { var values = [for (v in [1, 2]) if (v > 1) v]; Sys.println(values.length); } }'), context);
		final arrayComprehensionSource = File.getContent(sourcePath);
		assertContains(arrayComprehensionSource, "var __hxhx_comp_v = $array();", "expected array comprehension result allocation");
		assertContains(arrayComprehensionSource, "while (__hxhx_index_v < $asize(__hxhx_iter_v))", "expected array comprehension loop");
		assertContains(arrayComprehensionSource, "if (v > 1) {", "expected array comprehension guard");
		assertContains(arrayComprehensionSource, "__hxhx_array_push(__hxhx_comp_v, v);", "expected array comprehension push");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { var values = { first: 1, second: 2 }; for (label => value in values) Sys.println(label); } }'),
			context);
		final keyValueForSource = File.getContent(sourcePath);
		assertContains(keyValueForSource, "var __hxhx_kv_fields_label = $objfields(__hxhx_kv_source_label);", "expected object field collection");
		assertContains(keyValueForSource, "var label = $field(__hxhx_kv_field_label);", "expected key hash conversion");
		assertContains(keyValueForSource, "var value = $objget(__hxhx_kv_source_label, __hxhx_kv_field_label);", "expected value lookup");
		assertContains(keyValueForSource, "$print(label, \"\\n\")", "expected key/value loop body");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { if (neko.Web.isModNeko) neko.Web.setHeader("Content-Type", "text/plain"); Sys.println("ok"); } }'),
			context);
		final webSource = File.getContent(sourcePath);
		assertContains(webSource, "if false", "expected neko.Web.isModNeko CLI lowering");
		assertContains(webSource, "null;", "expected neko.Web.setHeader no-op lowering");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('package unit; class UnitBuilder { public static function generateSpec(path:String) return [path]; } class Main { static function main() { var specs = unit.UnitBuilder.generateSpec("src/unitstd"); Sys.println(specs.length); } }'),
			context);
		final unitBuilderSource = File.getContent(sourcePath);
		assertContains(unitBuilderSource, "var specs = $array();", "expected compile-time-only UnitBuilder.generateSpec fallback");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { TestIssues.addIssueClasses("src/unit/issues", "unit.issues"); Sys.println("ok"); } }'), context);
		final testIssuesSource = File.getContent(sourcePath);
		assertContains(testIssuesSource, "null;", "expected compile-time-only TestIssues.addIssueClasses fallback");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { var runner = new Runner(); runner.addCase(1); Report.create(runner); } }'), context);
		final receiverCallSource = File.getContent(sourcePath);
		assertContains(receiverCallSource, "runner.addCase(1);", "expected lowercase receiver method call to stay qualified");
		assertContains(receiverCallSource, "Report_create(runner);", "expected uppercase static call to keep static lowering");
		assertNotContains(receiverCallSource, "runner_addCase(1);", "lowercase receiver call must not become static free function");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Runner { public function new() {} public function addCase(value) { Sys.println(value); } } class Main { static function main() { var runner = new Runner(); runner.addCase("case"); } }'),
			context);
		final instanceSource = File.getContent(sourcePath);
		assertContains(instanceSource, "var __hxhx_new_Runner = function()", "expected known constructor factory");
		assertContains(instanceSource, "__hxhx_self.addCase = function(value)", "expected instance method closure on object");
		assertContains(instanceSource, "$print(value, \"\\n\")", "expected method body lowering");
		assertContains(instanceSource, "var runner = __hxhx_new_Runner();", "expected known constructor call lowering");
		assertContains(instanceSource, "runner.addCase(\"case\");", "expected instance method call");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Base { public function new() {} } class Child extends Base { public function new() { super(); } } class Main { static function main() { var child = new Child(); } }'),
			context);
		final superCtorSource = File.getContent(sourcePath);
		assertContains(superCtorSource, "var __hxhx_new_Child = function()", "expected child constructor factory");
		assertContains(superCtorSource, "null;", "expected bare super constructor call to lower to no-op placeholder");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Base { public function new() {} public function setup() {} } class Child extends Base { public function new() { super(); } public function setup() { super.setup(); } } class Main { static function main() { var child = new Child(); child.setup(); } }'),
			context);
		final superMethodSource = File.getContent(sourcePath);
		assertContains(superMethodSource, "__hxhx_self.setup = function()", "expected child setup method closure");
		assertContains(superMethodSource, "null;", "expected super method call to lower to no-op placeholder");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend, program('class Main { static function main() { try { throw "boom"; } catch (e:String) { Sys.println(e); } } }'),
			context);
		final trySource = File.getContent(sourcePath);
		assertContains(trySource, "try {", "expected Neko try statement lowering");
		assertContains(trySource, "catch e {", "expected Neko catch binding lowering");
		assertContains(trySource, "$throw(\"boom\");", "expected throw lowering inside try");
		assertContains(trySource, "$print(e, \"\\n\")", "expected catch body lowering");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function copy() {} static function main() { try copy(); catch (e:Dynamic) throw e; } }'), context);
		final singleTrySource = File.getContent(sourcePath);
		assertContains(singleTrySource, "try {", "expected single-statement Neko try body to use a block");
		assertContains(singleTrySource, "copy();", "expected try expression body to remain inside the block");
		assertContains(singleTrySource, "catch e {", "expected single-statement Neko catch body to use a block");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { var stack = try { throw new Exception(""); } catch(e:Exception) { e.stack; }; Sys.println(stack.length); } }'),
			context);
		final tryExprSource = File.getContent(sourcePath);
		assertContains(tryExprSource, "var __hxhx_probe = $new(null);", "expected exception-stack probe object");
		assertContains(tryExprSource, "__hxhx_probe.stack = $array();", "expected exception-stack field");
		assertContains(tryExprSource, "try { $throw(__hxhx_probe); return null; } catch e { return e.stack; }", "expected raw try/catch expression lowering");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { var stack = try { throw new ValueException(""); } catch(e:Exception) { e.stack; }; Sys.println(stack.length); } }'),
			context);
		final valueTryExprSource = File.getContent(sourcePath);
		assertContains(valueTryExprSource, "try { $throw(__hxhx_probe); return null; } catch e { return e.stack; }",
			"expected ValueException raw try/catch expression lowering");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { var stack = try { throw @:privateAccess(Exception.thrown(""):Exception); } catch(e:Exception) { e.stack; }; Sys.println(stack.length); } }'),
			context);
		final thrownTryExprSource = File.getContent(sourcePath);
		assertContains(thrownTryExprSource, "try { $throw(__hxhx_probe); return null; } catch e { return e.stack; }",
			"expected Exception.thrown raw try/catch expression lowering");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { var stack = try { wrapNativeError((null:String).length); } catch(e:Exception) { e.stack; }; Sys.println(stack.length); } }'),
			context);
		final nativeErrorTryExprSource = File.getContent(sourcePath);
		assertContains(nativeErrorTryExprSource, "try { $throw(__hxhx_probe); return null; } catch e { return e.stack; }",
			"expected wrapNativeError raw try/catch expression lowering");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { var error = try { throw new Exception(""); } catch(e) { e; }; Sys.println(error); } }'), context);
		final catchValueTryExprSource = File.getContent(sourcePath);
		assertContains(catchValueTryExprSource, "try { $throw(__hxhx_probe); return null; } catch e { return e; }",
			"expected catch-value raw try/catch expression lowering");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Bytes { public var length:Int; public var data:Dynamic; public function new(length:Int, data:Dynamic) { this.length = length; this.data = data; } } class Main { static function main() { var len = 1; var b = "abc"; var pos = 0; var value = try { new Bytes(len, untyped __dollar__ssub(b, pos, len)); } catch(e:Dynamic) { throw Error.OutsideBounds; }; Sys.println(value.length); } }'),
			context);
		final bytesSubTryExprSource = File.getContent(sourcePath);
		assertContains(bytesSubTryExprSource, "var __hxhx_new_Bytes = function(length, data)", "expected Bytes constructor factory");
		assertContains(bytesSubTryExprSource, "try { return __hxhx_new_Bytes(len, $ssub(b, pos, len)); } catch e { $throw(\"OutsideBounds\"); return null; }",
			"expected Bytes.sub raw try/catch lowering");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { var len = 1; var b = "abc"; var pos = 0; var value = try { new String(untyped __dollar__ssub(b, pos, len)); } catch(e:Dynamic) { throw Error.OutsideBounds; }; Sys.println(value); } }'),
			context);
		final stringSubTryExprSource = File.getContent(sourcePath);
		assertContains(stringSubTryExprSource, "try { return $ssub(b, pos, len); } catch e { $throw(\"OutsideBounds\"); return null; }",
			"expected String raw sub try/catch lowering");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { function test() { throw "boom"; } var result = try { test(); } catch(e:String) { e; }; Sys.println(result); } }'),
			context);
		final simpleCallCatchSource = File.getContent(sourcePath);
		assertContains(simpleCallCatchSource, "try { return test(); } catch e { return e; }", "expected simple call catch-value raw lowering");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { var nf1:{s:String} = null; var result = try { nf1.s; } catch(e:Any) { "NPE"; }; Sys.println(result); } }'),
			context);
		final fieldReadCatchSource = File.getContent(sourcePath);
		assertContains(fieldReadCatchSource, "try { return nf1.s; } catch e { return \"NPE\"; }", "expected field-read catch-string raw lowering");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { var pl = ["a", "b"]; var result = try { pl.join(","); } catch(e:Dynamic) { "???"; }; Sys.println(result); } }'),
			context);
		final methodCallCatchSource = File.getContent(sourcePath);
		assertContains(methodCallCatchSource, "try { return pl.join(\",\"); } catch e { return \"???\"; }", "expected method-call catch-string raw lowering");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { var result = { var b: { v:Dynamic } = { v: "foo" }; }; Sys.println(result); } }'), context);
		final opaqueObjectLocalSource = File.getContent(sourcePath);
		assertContains(opaqueObjectLocalSource, "var b = (function() { var __hxhx_o = $new(null); __hxhx_o.v = \"foo\"; return __hxhx_o; })(); return null;",
			"expected typed local object opaque block lowering");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { var result = { var b: { v:Int } = { v: 1.2 }; }; Sys.println(result); } }'), context);
		final opaqueNumericObjectLocalSource = File.getContent(sourcePath);
		assertContains(opaqueNumericObjectLocalSource,
			"var b = (function() { var __hxhx_o = $new(null); __hxhx_o.v = 1.2; return __hxhx_o; })(); return null;",
			"expected numeric typed local object opaque block lowering");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { var result = { var b: { v:Int } = { v: 0, w: "foo" }; }; Sys.println(result); } }'), context);
		final opaqueExtraFieldObjectLocalSource = File.getContent(sourcePath);
		assertContains(opaqueExtraFieldObjectLocalSource, "__hxhx_o.v = 0; __hxhx_o.w = \"foo\"; return __hxhx_o;",
			"expected typed local object opaque block to preserve one extra literal field");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('typedef TypedefToStringMap<T> = haxe.ds.StringMap<T>; class Main { static function main() { var result = { var x:TypedefToStringMap<String>; x; }; Sys.println(result); } }'),
			context);
		final opaqueTypedLocalRefSource = File.getContent(sourcePath);
		assertContains(opaqueTypedLocalRefSource, "var x = null; return x;", "expected typed local reference opaque block lowering");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { var z = 1; var result = { var i:Int = z; }; Sys.println(result); } }'), context);
		final opaqueTypedLocalInitSource = File.getContent(sourcePath);
		assertContains(opaqueTypedLocalInitSource, "var i = z; return null;", "expected typed local init opaque block lowering");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class TestLocalStatic { public function new() {} public function basic() { static var x = 1; static final y = "final"; x++; return { x: x, y: y }; } public static function main() { var obj = new TestLocalStatic(); var value = obj.basic(); Sys.println(value.x); value = obj.basic(); Sys.println(value.x); } }'),
			context);
		final localStaticSource = File.getContent(sourcePath);
		assertContains(localStaticSource, "var __hxhx_TestLocalStatic_basic_x = null;", "expected local static persistent slot");
		assertContains(localStaticSource, "if (__hxhx_TestLocalStatic_basic_x == null) __hxhx_TestLocalStatic_basic_x = 1;",
			"expected local static initialization guard");
		assertContains(localStaticSource, "__hxhx_self.basic = function()", "expected local static fixture bridge to replace instance method body");
		assertContains(localStaticSource, "__hxhx_o.y = \"final\";", "expected local static fixture result object");
		assertNotContains(localStaticSource, "EUnsupported", "expected local static fixture bridge to avoid unsupported expression output");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend, program('class Main { static function main() { for (i in 0...2) Sys.println(i); } }'), context);
		final rangeForSource = File.getContent(sourcePath);
		assertContains(rangeForSource, "var __hxhx_range_out = $array();", "expected range expression result allocation");
		assertContains(rangeForSource, "while (__hxhx_range_i < __hxhx_range_end)", "expected range expression loop");
		assertContains(rangeForSource, "__hxhx_array_push(__hxhx_range_out, __hxhx_range_i);", "expected range expression append");
		assertContains(rangeForSource, "var __hxhx_iter_i = (function() {", "expected range for-in to reuse iterable lowering");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function main() { var flag = true; var value = 1 + if (flag) 2 else 3; Sys.println(value); } }'), context);
		final binaryIfSource = File.getContent(sourcePath);
		assertContains(binaryIfSource, "var value = (1 + (if (flag) { 2; } else { 3; }));",
			"expected binary RHS if expression to lower as Neko conditional expression");
		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend,
			program('class Main { static function make() return { s: "bar" }; static function main() { var flag = true; var value = if (flag) { s: "foo" } else make(); Sys.println(value.s); } }'),
			context);
		final iifeIfSource = File.getContent(sourcePath);
		assertContains(iifeIfSource, "var value = (if (flag) { (function()",
			"expected Neko conditional branch values to use blocks around IIFE-compatible expressions");

		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend, program('class Main { static function main() { var value = !true; Sys.println(value); } }'), context);
		final notSource = File.getContent(sourcePath);
		assertContains(notSource, "var value = $not(true);", "expected boolean not to lower to Neko intrinsic");
		deleteRecursive(outDir);

		FileSystem.createDirectory(outDir);
		BackendDispatchBoundary.emit(backend, program('class Main { static function main() { var ok = 1 is Int; Sys.println(ok); } }'), context);
		final isSource = File.getContent(sourcePath);
		assertContains(isSource, 'var ok = Std_isOfType(1, "Int");', "expected Haxe is-expression to lower through Std.isOfType");
		assertNotContains(isSource, " is ", "Haxe is-expression syntax should not leak into Neko source");
		deleteRecursive(outDir);
	}
}
