import backend.GenIrProgram;
import HxExpr;
import haxe.ds.StringMap;

typedef HelperRenderBenchResult = {
	var elapsed:Float;
	var rendered:String;
	var lines:Int;
	var classTimings:Array<String>;
}

typedef PrimitiveCallArgBenchResult = {
	var elapsed:Float;
	var calls:Int;
	var sample:String;
}

/**
	Renderer-only latency probe for the C++ helper-class frontier.

	The slow `cpp-numeric-only` diagnostic now times out before it emits the C++
	artifact. Recent timing logs show the delay around shared helper classes such
	as `List`, `TestHandler`, and `TestResult`, not the numeric-cast test body
	itself. This bench keeps that work local and cheap: it parses a small,
	repo-owned utest-like fixture and measures only `CppTargetCore.renderHelperClass`.

	This is not an end-to-end C++ runtime proof. It is a fast guard for the helper
	rendering path so we can make and validate renderer changes without spending
	many minutes on the full upstream-derived workload after every edit.
**/
class M14CppHelperRenderBenchIntegrationTest {
	static inline final DEFAULT_EXTRA_METHODS = 16;
	static inline final DEFAULT_REPS = 2;
	static inline final DEFAULT_PRIMITIVE_ARG_CALLS = 250;

	static function assertTrue(cond:Bool, message:String):Void {
		if (!cond)
			throw message;
	}

	static function assertContains(haystack:String, needle:String, message:String):Void {
		if (haystack.indexOf(needle) < 0)
			throw message + " (missing `" + needle + "`)";
	}

	static function assertNotContains(haystack:String, needle:String, message:String):Void {
		if (haystack.indexOf(needle) >= 0)
			throw message + " (unexpected `" + needle + "`)";
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

	static function envInt(name:String, fallback:Int):Int {
		final raw = Sys.getEnv(name);
		if (raw == null || StringTools.trim(raw).length == 0)
			return fallback;
		final parsed = Std.parseInt(raw);
		return parsed == null || parsed <= 0 ? fallback : parsed;
	}

	static function fixtureSource(extraMethods:Int):String {
		final lines = [
			"class List<T> {",
			"  public var items:Array<T>;",
			"  public function new() {",
			"    items = new Array();",
			"  }",
			"  public function add(item:T):Void {",
			"    items.push(item);",
			"  }",
			"  public function push(item:T):Void {",
			"    items.push(item);",
			"  }",
			"  public function remove(item:T):Bool {",
			"    var removed = false;",
			"    var kept = new Array();",
			"    for (value in items) {",
			"      if (value == item) removed = true; else kept.push(value);",
			"    }",
			"    items = kept;",
			"    return removed;",
			"  }",
			"  public function join(sep:String):String {",
			"    var out = \"\";",
			"    var first = true;",
			"    for (item in items) {",
			"      if (first) first = false; else out += sep;",
			"      out += Std.string(item);",
			"    }",
			"    return out;",
			"  }",
			"  public function toString():String {",
			"    return \"{\" + join(\", \") + \"}\";",
			"  }",
			"  public function iterator():Iterator<T> {",
			"    return items.iterator();",
			"  }",
			"}",
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
			"  public function dispatch(e:T):Bool {",
			"    var list = handlers.copy();",
			"    for (h in list) {",
			"      h(e);",
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
			"  public var asyncStack:List<String>;",
			"  public var onComplete:Dispatcher<TestHandler<T>>;",
			"  public var onPrecheck:Dispatcher<TestHandler<T>>;",
			"  public function new(fixture:T) {",
			"    this.fixture = fixture;",
			"    asyncStack = new List();",
			"    onComplete = new Dispatcher();",
			"    onPrecheck = new Dispatcher();",
			"  }",
			"  public function addEvent(event:String):Void {",
			"    asyncStack.add(event);",
			"    addAsync(function() {",
			"      asyncStack.remove(event);",
			"    });",
			"  }",
			"  public function addAsync(f:Void->Void):Void {",
			"    f();",
			"  }",
			"  public function execute():Void {",
			"    var handler = this;",
			"    for (event in asyncStack) {",
			"      handler.asyncStack.remove(event);",
			"    }",
			"    onPrecheck.dispatch(this);",
			"    onComplete.dispatch(this);",
			"  }",
			"  public function dispatchSelf():Void {",
			"    onPrecheck.dispatch(this);",
			"  }",
			"  public function removeSelf(f:String):Void {",
			"    var handler = this;",
			"    handler.asyncStack.remove(f);",
			"  }"
		];
		for (i in 0...extraMethods) {
			lines.push("  public function extra" + i + "(event:String):Void {");
			lines.push("    asyncStack.add(event);");
			lines.push("    if (asyncStack.remove(event)) asyncStack.push(event);");
			lines.push("    onPrecheck.dispatch(this);");
			lines.push("  }");
		}
		lines.push("}");
		lines.push("class TestResult {");
		lines.push("  public function new() {}");
		lines.push("  public static function ofHandler(handler:TestHandler<Dynamic>):TestResult {");
		lines.push("    return new TestResult();");
		lines.push("  }");
		lines.push("}");
		lines.push("class RunnerGenericLike {");
		lines.push("  var fixtures(default, null):Array<TestFixture> = [];");
		lines.push("  public var fixtureList:List<TestFixture>;");
		lines.push("  public var onProgress:Dispatcher<{result:TestResult,done:Int,totals:Int}>;");
		lines.push("  public var onRunner:Dispatcher<RunnerGenericLike>;");
		lines.push("  public var onPrecheck:Dispatcher<TestHandler<TestFixture>>;");
		lines.push("  var pos:Int = 0;");
		lines.push("  public function new() {");
		lines.push("    fixtureList = new List();");
		lines.push("    onProgress = new Dispatcher();");
		lines.push("    onRunner = new Dispatcher();");
		lines.push("    onPrecheck = new Dispatcher();");
		lines.push("  }");
		lines.push("  public function wireHandler(handler:TestHandler<TestFixture>):Void {");
		lines.push("    handler.onComplete.add(runNext);");
		lines.push("    handler.onPrecheck.add(onPrecheck.dispatch);");
		lines.push("  }");
		lines.push("  public function runNext(finishedHandler:TestHandler<TestFixture>):Void {}");
		lines.push("  public function resultOf(handler:TestHandler<TestFixture>):TestResult {");
		lines.push("    return TestResult.ofHandler(handler);");
		lines.push("  }");
		lines.push("  public function emitProgress(handler:TestHandler<TestFixture>):Void {");
		lines.push("    onProgress.dispatch({result:TestResult.ofHandler(handler), done:1, totals:2});");
		lines.push("  }");
		lines.push("  public function makeHandler(fixture:TestFixture):TestHandler<TestFixture> {");
		lines.push("    var handler = new TestHandler(fixture);");
		lines.push("    return handler;");
		lines.push("  }");
		lines.push("}");
		return lines.join("\n");
	}

	static function buildLookup(extraMethods:Int):{lookup:backend.cpp.CppClassLookup, classes:StringMap<HxClassDecl>} {
		final decl = new HxParser(fixtureSource(extraMethods)).parseModule("RunnerGenericLike");
		final names = new StringMap<Bool>();
		final classes = new StringMap<HxClassDecl>();
		for (cls in HxModuleDecl.getClasses(decl)) {
			final name = HxClassDecl.getName(cls);
			names.set(name, true);
			classes.set(name, cls);
		}
		return {lookup: {names: names, byName: classes}, classes: classes};
	}

	static function typedSyntheticModule(filePath:String, decl:HxModuleDecl):TypedModule {
		final mainClass = HxModuleDecl.getMainClass(decl);
		final env = new TyModuleEnv(HxModuleDecl.getPackagePath(decl), HxModuleDecl.getImports(decl), new TyClassEnv(HxClassDecl.getName(mainClass), []));
		return new TypedModule(new ParsedModule("", decl, filePath), env);
	}

	static function renderStdListWhenAvailable():Null<HelperRenderBenchResult> {
		final path = "vendor/haxe/std/haxe/ds/List.hx";
		if (!sys.FileSystem.exists(path))
			return null;
		final source = sys.io.File.getContent(path);
		final decl = new HxParser(source).parseModule("List");
		final modules = [typedSyntheticModule(path, decl)];
		final topLevelAliasPath = "vendor/haxe/std/List.hx";
		if (sys.FileSystem.exists(topLevelAliasPath)) {
			final aliasDecl = new HxParser(sys.io.File.getContent(topLevelAliasPath)).parseModule("List");
			modules.push(typedSyntheticModule(topLevelAliasPath, aliasDecl));
		}
		var listClass:HxClassDecl = null;
		for (cls in HxModuleDecl.getClasses(decl))
			if (HxClassDecl.getName(cls) == "List")
				listClass = cls;
		assertTrue(listClass != null, "vendored haxe.ds.List source should contain List");
		final program = new GenIrProgram(modules, false);
		final lookup = @:privateAccess backend.cpp.CppTargetCore.collectClassLookup(program);
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.packagePathForRenderedClass(listClass, lookup) == "haxe.ds",
			"haxe.ds.List package identity should survive the top-level List typedef alias");
		final kind = @:privateAccess backend.cpp.CppTargetCore.helperClassRenderKind(listClass, lookup);
		final kindLabel = @:privateAccess backend.cpp.CppTargetCore.helperRenderKindLabel(kind);
		assertTrue(kindLabel == "runtime_module", "haxe.ds.List should render through target-owned runtime support");
		resetRendererCaches();
		final start = Sys.time();
		final lines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(listClass, lookup);
		final elapsed = Sys.time() - start;
		return {
			elapsed: elapsed,
			rendered: lines.join("\n"),
			lines: lines.length,
			classTimings: ["haxe.ds.List:" + elapsed]
		};
	}

	static function assertCompileTimeMacroApiBodiesStayDeclarationOnly():Void {
		final bodyOnly = new HxClassDecl("BodyOnly", false, [new HxFunctionDecl("new", Public, false, [], "Void", [], "")], []);
		final context = new HxClassDecl("Context", false, [
			new HxFunctionDecl("currentPos", Public, true, [], "{file:String,line:Int}", [
				SVar("bodyOnly", "BodyOnly", ENew("BodyOnly", []), HxPos.unknown()),
				SReturn(EAnon(["file", "line"], [EString("macro"), EInt(1)]), HxPos.unknown())
			], "")
		], []);
		final main = new HxClassDecl("Main", true, [new HxFunctionDecl("main", Public, true, [], "Void", [], "")], []);
		final program = new GenIrProgram([
			typedSyntheticModule("std/haxe/macro/Context.hx", new HxModuleDecl("haxe.macro", [], context, [context, bodyOnly], false, false)),
			typedSyntheticModule("Main.hx", new HxModuleDecl("", [], main, [main], false, false))
		], false);
		final lookup = @:privateAccess backend.cpp.CppTargetCore.collectClassLookup(program);
		final kind = @:privateAccess backend.cpp.CppTargetCore.helperClassRenderKind(context, lookup);
		final kindLabel = @:privateAccess backend.cpp.CppTargetCore.helperRenderKindLabel(kind);
		assertTrue(kindLabel == "declaration_only", "compile-time macro API helpers should not render runtime C++ bodies");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.renderHelperClass(context, lookup).length == 0,
			"compile-time macro API helpers should rely on forward declarations instead of full helper bodies");
		final deps = @:privateAccess backend.cpp.CppTargetCore.helperClassDependencies(context, lookup).join(",");
		assertTrue(deps.indexOf("BodyOnly") < 0, "compile-time macro API helper body dependencies should not enter runtime C++ reachability");
	}

	static function resetRendererCaches():Void {
		// Match the cache boundary used by CppTargetCore.renderProgram so each
		// repetition measures a cold render pass, while classes within one pass
		// can still share caches like the real helper renderer does.
		@:privateAccess backend.cpp.CppTargetCore.functionScopePrepCache = new StringMap();
		@:privateAccess backend.cpp.CppTargetCore.functionArgDeclaredTypeCache = new StringMap<String>();
		@:privateAccess backend.cpp.CppTargetCore.fieldCppTypeCache = new StringMap<String>();
		@:privateAccess backend.cpp.CppTargetCore.functionArgTypesCache = new StringMap<Array<String>>();
		@:privateAccess backend.cpp.CppTargetCore.functionReturnTypesCache = new StringMap<String>();
		@:privateAccess backend.cpp.CppTargetCore.erasedDynamicReturnCache = new StringMap<Bool>();
	}

	static function renderOnce(extraMethods:Int):HelperRenderBenchResult {
		final fixture = buildLookup(extraMethods);
		final classOrder = ["List", "Dispatcher", "TestHandler", "TestResult", "RunnerGenericLike"];
		resetRendererCaches();
		final start = Sys.time();
		final renderedParts = new Array<String>();
		final classTimings = new Array<String>();
		var lines = 0;
		for (name in classOrder) {
			final cls = fixture.classes.get(name);
			assertTrue(cls != null, "fixture should contain helper class " + name);
			final classStart = Sys.time();
			final classLines = @:privateAccess backend.cpp.CppTargetCore.renderHelperClass(cls, fixture.lookup);
			final classElapsed = Sys.time() - classStart;
			classTimings.push(name + ":" + classElapsed);
			lines += classLines.length;
			renderedParts.push(classLines.join("\n"));
		}
		return {
			elapsed: Sys.time() - start,
			rendered: renderedParts.join("\n"),
			lines: lines,
			classTimings: classTimings
		};
	}

	static function renderPrimitiveLiteralCallArgs(callCount:Int):PrimitiveCallArgBenchResult {
		final target = new HxFunctionDecl("target", Public, false, [
			new HxFunctionArg("s", "String", NoDefault, false, false),
			new HxFunctionArg("n", "Int", NoDefault, false, false),
			new HxFunctionArg("b", "Bool", NoDefault, false, false),
			new HxFunctionArg("f", "Float", NoDefault, false, false)
		], "Void", [], "");
		final owner = new HxClassDecl("PrimitiveCallArgBenchOwner", false, [target], []);
		final names = new StringMap<Bool>();
		final classes = new StringMap<HxClassDecl>();
		names.set("PrimitiveCallArgBenchOwner", true);
		classes.set("PrimitiveCallArgBenchOwner", owner);
		final scope = @:privateAccess backend.cpp.CppTargetCore.renderScope(owner, {names: names, byName: classes}, "void");
		final args = [EString("literal"), EInt(7), EBool(true), EFloat(1.25)];
		resetRendererCaches();
		final start = Sys.time();
		var sample = "";
		for (_ in 0...callCount)
			sample = @:privateAccess backend.cpp.CppTargetCore.directCallExpr("target", args, scope);
		return {
			elapsed: Sys.time() - start,
			calls: callCount,
			sample: sample
		};
	}

	static function assertCallableArgOverridePolicy():Void {
		final stringOnly = new HxFunctionDecl("stringOnly", Public, false, [new HxFunctionArg("event", "String", NoDefault, false, false)], "Void", [], "");
		final stringCallable = new HxFunctionDecl("stringCallable", Public, false, [new HxFunctionArg("f", "String", NoDefault, false, false)], "String",
			[SReturn(ECall(EIdent("f"), [EInt(0), EString("value")]), HxPos.unknown())], "");
		final dynamicArg = new HxFunctionDecl("dynamicArg", Public, false, [new HxFunctionArg("value", "Dynamic", NoDefault, false, false)], "Void", [], "");
		final untypedArg = new HxFunctionDecl("untypedArg", Public, false, [new HxFunctionArg("value", "", NoDefault, false, false)], "Void", [], "");
		assertTrue(! @:privateAccess backend.cpp.CppTargetCore.functionMayNeedCallableArgTypeOverrides(stringOnly),
			"explicit String helper methods should not run forwarded-argument override inference");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.functionMayNeedCallableArgTypeOverrides(stringCallable),
			"String-shaped erased callables should still run forwarded-argument override inference");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.functionMayNeedCallableArgTypeOverrides(dynamicArg),
			"Dynamic helper methods should still allow forwarded-argument override inference");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.functionMayNeedCallableArgTypeOverrides(untypedArg),
			"untyped helper methods should still allow forwarded-argument override inference");
	}

	static function main():Void {
		assertCallableArgOverridePolicy();
		assertCompileTimeMacroApiBodiesStayDeclarationOnly();
		final extraMethods = envInt("HXHX_CPP_HELPER_RENDER_BENCH_EXTRA_METHODS", DEFAULT_EXTRA_METHODS);
		final reps = envInt("HXHX_CPP_HELPER_RENDER_BENCH_REPS", DEFAULT_REPS);
		final primitiveArgCalls = envInt("HXHX_CPP_PRIMITIVE_ARG_BENCH_CALLS", DEFAULT_PRIMITIVE_ARG_CALLS);
		var best:HelperRenderBenchResult = null;
		var total = 0.0;
		for (_ in 0...reps) {
			final result = renderOnce(extraMethods);
			total += result.elapsed;
			if (best == null || result.elapsed < best.elapsed)
				best = result;
		}
		assertContains(best.rendered, "struct List", "helper-render bench should render the List helper");
		assertContains(best.rendered, "struct TestHandler", "helper-render bench should render the TestHandler helper");
		assertContains(best.rendered, "static std::shared_ptr<TestResult> ofHandler",
			"helper-render bench should keep the TestResult generic-Dynamic helper surface");
		assertTrue(countOccurrences(best.rendered, "extra") >= extraMethods, "helper-render bench should include the scaled TestHandler methods");
		final stdList = renderStdListWhenAvailable();
		if (stdList != null) {
			assertContains(stdList.rendered, "struct List {", "haxe.ds.List runtime support should keep the public List helper");
			assertContains(stdList.rendered, "std::vector<T> __values;", "haxe.ds.List runtime support should use target-owned storage");
			assertContains(stdList.rendered, "std::shared_ptr<List<T>> __hxhx_make_shared_List()",
				"haxe.ds.List runtime support should keep the generic factory used by new List()");
			assertNotContains(stdList.rendered, "ListNode::create", "haxe.ds.List runtime support should not render the parsed stdlib add/push body");
		}
		final primitiveArgs = renderPrimitiveLiteralCallArgs(primitiveArgCalls);
		assertTrue(primitiveArgs.sample == "target(\"literal\", 7, true, 1.25)",
			"primitive call-argument bench should keep direct literal call rendering stable");

		Sys.println("CPP_HELPER_RENDER_BENCH:PASS extra_methods="
			+ extraMethods
			+ " reps="
			+ reps
			+ " best_seconds="
			+ best.elapsed
			+ " total_seconds="
			+ total
			+ " lines="
			+ best.lines
			+ " class_seconds="
			+ best.classTimings.join(",")
			+ " primitive_arg_calls="
			+ primitiveArgs.calls
			+ " primitive_arg_seconds="
			+ primitiveArgs.elapsed
			+ (stdList == null ? "" : " std_list_seconds=" + stdList.elapsed + " std_list_lines=" + stdList.lines));
	}
}
