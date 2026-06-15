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
		BackendDispatchBoundary.emit(backend, program('class Main { static function main() { var o = new TestOps(7); } }'), context);
		final newSource = File.getContent(sourcePath);
		assertContains(newSource, "__hxhx_o.__hx_ctor = \"TestOps\";", "expected constructor tag on lowered Neko object");
		assertContains(newSource, "__hxhx_o.__hx_params = $array(7);", "expected constructor args on lowered Neko object");

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
			program('class Main { static function main() { switch (1) { case 1: Sys.println("one"); default: Sys.println("other"); } } }'), context);
		final switchStmtSource = File.getContent(sourcePath);
		assertContains(switchStmtSource, "switch 1 {", "expected Neko switch statement");
		assertContains(switchStmtSource, "1 => {", "expected Neko switch case block");
		assertContains(switchStmtSource, "$print(\"one\", \"\\n\")", "expected switch case body");
		assertContains(switchStmtSource, "default => {", "expected Neko switch default block");

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
		BackendDispatchBoundary.emit(backend, program('class Main { static function main() { try { throw "boom"; } catch (e:String) { Sys.println(e); } } }'),
			context);
		final trySource = File.getContent(sourcePath);
		assertContains(trySource, "try\n  {", "expected Neko try statement lowering");
		assertContains(trySource, "catch e\n  {", "expected Neko catch binding lowering");
		assertContains(trySource, "$throw(\"boom\");", "expected throw lowering inside try");
		assertContains(trySource, "$print(e, \"\\n\")", "expected catch body lowering");

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
	}
}
