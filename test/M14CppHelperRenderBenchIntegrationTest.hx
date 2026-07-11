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

typedef BytesReferenceCallBenchResult = {
	var elapsed:Float;
	var calls:Int;
	var sample:String;
}

typedef BytesStringArgPhaseBenchResult = {
	var calls:Int;
	var valueElapsed:Float;
	var stringElapsed:Float;
	var directElapsed:Float;
	var valueSample:String;
	var stringSample:String;
	var directSample:String;
}

typedef FreshERegReturnBenchResult = {
	var calls:Int;
	var elapsed:Float;
	var sample:String;
}

typedef FreshERegFieldCallPhaseBenchResult = {
	var calls:Int;
	var fullElapsed:Float;
	var constructorElapsed:Float;
	var argsElapsed:Float;
	var fullSample:String;
	var constructorSample:String;
	var argsSample:String;
	var shapeSample:String;
}

typedef FreshERegLocalDeclPhaseBenchResult = {
	var calls:Int;
	var typeElapsed:Float;
	var hintElapsed:Float;
	var initElapsed:Float;
	var constructorElapsed:Float;
	var typeSample:String;
	var hintSample:String;
	var initSample:String;
	var constructorSample:String;
	var shapeSample:String;
}

typedef TypedERegSplitPhaseBenchResult = {
	var calls:Int;
	var inferElapsed:Float;
	var renderElapsed:Float;
	var argsElapsed:Float;
	var lengthElapsed:Float;
	var lengthVectorElapsed:Float;
	var lengthPrimitiveElapsed:Float;
	var lengthMethodValueElapsed:Float;
	var lengthReferenceElapsed:Float;
	var lengthClassPreflightElapsed:Float;
	var lengthPropertyElapsed:Float;
	var lengthJsonElapsed:Float;
	var joinElapsed:Float;
	var joinBoundElapsed:Float;
	var joinQualifiedElapsed:Float;
	var joinReceiverTypeElapsed:Float;
	var joinTemplateElapsed:Float;
	var joinFieldCallElapsed:Float;
	var inferSample:String;
	var renderSample:String;
	var argsSample:String;
	var lengthSample:String;
	var lengthEqSample:String;
	var lengthVectorSample:Bool;
	var lengthPrimitiveSample:Bool;
	var lengthMethodValueSample:Bool;
	var lengthReferenceSample:Bool;
	var lengthClassPreflightSample:Bool;
	var lengthPropertySample:Bool;
	var lengthJsonSample:Bool;
	var joinSample:String;
	var concatSample:String;
	var concatEqSample:String;
	var joinBoundSample:Bool;
	var joinQualifiedSample:Bool;
	var joinReceiverTypeSample:String;
	var joinTemplateSample:Bool;
	var joinFieldCallSample:String;
}

typedef MatchedStringCallArgPhaseBenchResult = {
	var calls:Int;
	var fullElapsed:Float;
	var declaredEnumElapsed:Float;
	var enumElapsed:Float;
	var structuralElapsed:Float;
	var actualTypeElapsed:Float;
	var renderElapsed:Float;
	var fullSample:String;
	var declaredEnumSample:Bool;
	var enumSample:Bool;
	var structuralSample:Bool;
	var actualTypeSample:String;
	var renderSample:String;
}

typedef ResidualStructuralProbeBenchResult = {
	var calls:Int;
	var intProbeElapsed:Float;
	var stringProbeElapsed:Float;
	var vectorProbeElapsed:Float;
	var unaryArgElapsed:Float;
	var concatArgElapsed:Float;
	var localStringElapsed:Float;
	var intProbeSample:Bool;
	var stringProbeSample:Bool;
	var vectorProbeSample:Bool;
	var namedStructuralSample:Bool;
	var genericStructuralSample:Bool;
	var ordinaryUserSample:Bool;
	var unaryArgSample:String;
	var concatArgSample:String;
	var localStringSample:String;
}

typedef ERegLambdaPhaseBenchResult = {
	var calls:Int;
	var mapElapsed:Float;
	var argsElapsed:Float;
	var expectedFunctionElapsed:Float;
	var identityPreflightElapsed:Float;
	var boundPreflightElapsed:Float;
	var varArgsPreflightElapsed:Float;
	var lambdaElapsed:Float;
	var nestedLambdaElapsed:Float;
	var directBodyElapsed:Float;
	var nestedBodyElapsed:Float;
	var leafElapsed:Float;
	var nestedLeafElapsed:Float;
	var bodyElapsed:Float;
	var stringElapsed:Float;
	var renderElapsed:Float;
	var inferElapsed:Float;
	var mapSample:String;
	var argsSample:String;
	var expectedFunctionSample:String;
	var lambdaSample:String;
	var nestedLambdaSample:String;
	var directBodySample:String;
	var nestedBodySample:String;
	var leafSample:String;
	var nestedLeafSample:String;
	var bodySample:String;
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
	static inline final DEFAULT_BYTES_REFERENCE_CALLS = 10;
	static inline final DEFAULT_BYTES_STRING_ARG_CALLS = 100;
	static inline final DEFAULT_FRESH_EREG_RETURN_CALLS = 10;
	static inline final DEFAULT_FRESH_EREG_FIELD_CALLS = 10;
	static inline final DEFAULT_FRESH_EREG_LOCAL_DECL_CALLS = 10;
	static inline final DEFAULT_TYPED_EREG_SPLIT_CALLS = 10;
	static inline final DEFAULT_MATCHED_STRING_CALL_ARG_CALLS = 10;
	static inline final DEFAULT_RESIDUAL_STRUCTURAL_PROBE_CALLS = 10;
	static inline final DEFAULT_EREG_LAMBDA_CALLS = 10;

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

	static function renderBytesReferenceCalls(callCount:Int):BytesReferenceCallBenchResult {
		final bytes = new HxClassDecl("Bytes", false, [
			new HxFunctionDecl("ofString", Public, true, [new HxFunctionArg("value", "String", NoDefault, false, false)], "Bytes", [], ""),
			new HxFunctionDecl("sub", Public, false, [
				new HxFunctionArg("position", "Int", NoDefault, false, false),
				new HxFunctionArg("length", "Int", NoDefault, false, false)
			], "Bytes",
				[], ""),
			new HxFunctionDecl("compare", Public, false, [new HxFunctionArg("other", "Bytes", NoDefault, false, false)], "Int", [], "")
		], []);
		final owner = new HxClassDecl("BytesReferenceBenchOwner", false, [], []);
		final names = new StringMap<Bool>();
		final classes = new StringMap<HxClassDecl>();
		for (cls in [bytes, owner]) {
			final name = HxClassDecl.getName(cls);
			names.set(name, true);
			classes.set(name, cls);
		}
		final lookup = {names: names, byName: classes};
		final scope = @:privateAccess backend.cpp.CppTargetCore.renderScope(owner, lookup, "void");
		scope.localTypes.set("s1", "std::string");
		scope.localTypes.set("s2", "std::string");
		final omittedEncodingParams = @:privateAccess backend.cpp.CppTargetCore.knownStdlibMethodParamCppTypes("Bytes", "ofString", scope, lookup, 1);
		final explicitEncodingParams = @:privateAccess backend.cpp.CppTargetCore.knownStdlibMethodParamCppTypes("Bytes", "ofString", scope, lookup, 2);
		final declarationParams = @:privateAccess backend.cpp.CppTargetCore.knownStdlibMethodParamCppTypes("Bytes", "ofString", scope, lookup);
		assertTrue(omittedEncodingParams.length == 1 && omittedEncodingParams[0] == "std::string",
			"Bytes.ofString calls without Encoding should resolve only the supplied String parameter");
		assertTrue(explicitEncodingParams.length == 2 && declarationParams.join(",") == explicitEncodingParams.join(","),
			"Bytes.ofString declarations and explicit Encoding calls should keep the complete parameter shape");
		final literalCall = @:privateAccess backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("Bytes"), "ofString"), [EString("literal")]), scope);
		assertTrue(literalCall == "Bytes::ofString(std::string(\"literal\"))", "Bytes.ofString literal calls should keep the explicit std::string wrapper");
		final expression = ECall(EField(ECall(EField(ECall(EField(EIdent("Bytes"), "ofString"), [EIdent("s1")]), "sub"), [EInt(0), EInt(1)]), "compare"),
			[ECall(EField(EIdent("Bytes"), "ofString"), [EIdent("s2")])]);
		resetRendererCaches();
		final start = Sys.time();
		var sample = "";
		for (_ in 0...callCount)
			sample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(expression, scope);
		return {
			elapsed: Sys.time() - start,
			calls: callCount,
			sample: sample
		};
	}

	static function renderBytesStringArgPhases(callCount:Int):BytesStringArgPhaseBenchResult {
		final owner = new HxClassDecl("BytesStringArgBenchOwner", false, [], []);
		final names = new StringMap<Bool>();
		final classes = new StringMap<HxClassDecl>();
		names.set("BytesStringArgBenchOwner", true);
		classes.set("BytesStringArgBenchOwner", owner);
		final scope = @:privateAccess backend.cpp.CppTargetCore.renderScope(owner, {names: names, byName: classes}, "void");
		scope.localTypes.set("text", "std::string");
		scope.localTypes.set("inferred", "std::string");
		scope.localTypeHints.set("text", "String");
		final args = [EString("literal"), EIdent("text"), EIdent("inferred")];
		scope.localTypeHints.set("text", "Dynamic");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.directBytesOfStringArgExpr(EIdent("text"), scope) == null,
			"Bytes.ofString should keep Dynamic-shaped String locals on generic adaptation");
		scope.localTypeHints.set("text", "StringAbstract");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.directBytesOfStringArgExpr(EIdent("text"), scope) == null,
			"Bytes.ofString should keep primitive-backed String abstracts on generic adaptation");
		scope.localTypeHints.set("text", "String");
		resetRendererCaches();
		final valueStart = Sys.time();
		var valueSample = "";
		for (_ in 0...callCount)
			for (arg in args)
				valueSample = @:privateAccess backend.cpp.CppTargetCore.valueExprForExpectedType(arg, "std::string", scope);
		final valueElapsed = Sys.time() - valueStart;
		resetRendererCaches();
		final stringStart = Sys.time();
		var stringSample = "";
		for (_ in 0...callCount)
			for (arg in args)
				stringSample = @:privateAccess backend.cpp.CppTargetCore.stringExpr(arg, scope);
		final stringElapsed = Sys.time() - stringStart;
		resetRendererCaches();
		final directStart = Sys.time();
		var directSample = "";
		for (_ in 0...callCount)
			for (arg in args)
				directSample = @:privateAccess backend.cpp.CppTargetCore.directBytesOfStringArgExpr(arg, scope);
		return {
			calls: callCount,
			valueElapsed: valueElapsed,
			stringElapsed: stringElapsed,
			directElapsed: Sys.time() - directStart,
			valueSample: valueSample,
			stringSample: stringSample,
			directSample: directSample
		};
	}

	static function eRegBenchScope():backend.cpp.CppRenderScope {
		final eReg = new HxClassDecl("EReg", false, [
			new HxFunctionDecl("match", Public, false, [new HxFunctionArg("s", "String", NoDefault, false, false)], "Bool", [], ""),
			new HxFunctionDecl("split", Public, false, [new HxFunctionArg("s", "String", NoDefault, false, false)], "Array<String>", [], ""),
			new HxFunctionDecl("replace", Public, false, [
				new HxFunctionArg("s", "String", NoDefault, false, false),
				new HxFunctionArg("by", "String", NoDefault, false, false)
			], "String", [], ""),
			new HxFunctionDecl("map", Public, false, [
				new HxFunctionArg("s", "String", NoDefault, false, false),
				new HxFunctionArg("f", "EReg->String", NoDefault, false, false)
			],
				"String", [], ""),
			new HxFunctionDecl("matched", Public, false, [new HxFunctionArg("n", "Int", NoDefault, false, false)], "String", [], ""),
			new HxFunctionDecl("matchedLeft", Public, false, [], "String", [], ""),
			new HxFunctionDecl("matchedRight", Public, false, [], "String", [], "")
		], []);
		final owner = new HxClassDecl("ERegBenchOwner", false, [], []);
		final structuralValue = new HxClassDecl("ResidualStructuralValue", false, [], [new HxFieldDecl("value", Public, false, "Int", null)], "",
			["__hxhx_typedef"]);
		final genericStructuralValue = new HxClassDecl("ResidualStructuralGeneric", false, [], [new HxFieldDecl("value", Public, false, "Int", null)], "",
			["__hxhx_typedef", "__hxhx_type_params=T"]);
		final ordinaryUserClass = new HxClassDecl("ResidualStructuralUserClass", false, [
			new HxFunctionDecl("read", Public, false, [], "Int", [SReturn(EInt(1), HxPos.unknown())], "")
		], []);
		final names = new StringMap<Bool>();
		final classes = new StringMap<HxClassDecl>();
		final all = new Array<HxClassDecl>();
		for (cls in [eReg, owner, structuralValue, genericStructuralValue, ordinaryUserClass]) {
			final name = HxClassDecl.getName(cls);
			names.set(name, true);
			classes.set(name, cls);
			all.push(cls);
		}
		for (i in 0...280) {
			final cls = new HxClassDecl("FreshERegDummy" + i, false, [], []);
			final name = HxClassDecl.getName(cls);
			names.set(name, true);
			classes.set(name, cls);
			all.push(cls);
		}
		return @:privateAccess backend.cpp.CppTargetCore.renderScope(owner, {names: names, byName: classes, all: all}, "void");
	}

	static function inferFreshERegReturns(callCount:Int):FreshERegReturnBenchResult {
		final scope = eRegBenchScope();
		final fresh = ENew("EReg", [EString("a+"), EString("g")]);
		final replace = ECall(EField(fresh, "replace"), [EString("aa"), EString("x")]);
		final map = ECall(EField(fresh, "map"), [EString("aa"), ELambda(["r"], ECall(EField(EIdent("r"), "matchedLeft"), []))]);
		resetRendererCaches();
		final start = Sys.time();
		var sample = "";
		for (_ in 0...callCount)
			sample = @:privateAccess backend.cpp.CppTargetCore.inferExprCppType(replace, scope)
				+ ","
				+ @:privateAccess backend.cpp.CppTargetCore.inferExprCppType(map, scope);
		return {calls: callCount, elapsed: Sys.time() - start, sample: sample};
	}

	/** Measure immediate EReg field-call setup separately from the constructor and known-owner argument paths. **/
	static function renderFreshERegFieldCallPhases(callCount:Int):FreshERegFieldCallPhaseBenchResult {
		final scope = eRegBenchScope();
		final fresh = ENew("EReg", [EString("a+"), EString("g")]);
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.isFreshERegFieldCall(fresh, "match",
			1), "Fresh EReg match should use the bounded direct field-call path");
		assertTrue(! @:privateAccess backend.cpp.CppTargetCore.isFreshERegFieldCall(EIdent("r"), "match", 1),
			"Non-fresh EReg receivers should keep general field-call discovery");
		assertTrue(! @:privateAccess backend.cpp.CppTargetCore.isFreshERegFieldCall(fresh, "match", 2),
			"Fresh EReg calls with the wrong arity should keep general field-call discovery");
		assertTrue(! @:privateAccess backend.cpp.CppTargetCore.isFreshERegFieldCall(fresh, "split", 1),
			"Fresh EReg methods outside the bounded match/map/replace surface should keep general field-call discovery");
		final matchArgs = [EString("aa")];
		final match = ECall(EField(fresh, "match"), matchArgs);
		final replace = ECall(EField(fresh, "replace"), [EString("aa"), EString("x")]);
		final map = ECall(EField(fresh, "map"), [EString("aa"), ELambda(["r"], ECall(EField(EIdent("r"), "matchedLeft"), []))]);
		resetRendererCaches();
		final fullStart = Sys.time();
		var fullSample = "";
		for (_ in 0...callCount)
			fullSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(match, scope);
		final fullElapsed = Sys.time() - fullStart;
		resetRendererCaches();
		final constructorStart = Sys.time();
		var constructorSample = "";
		for (_ in 0...callCount)
			constructorSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(fresh, scope);
		final constructorElapsed = Sys.time() - constructorStart;
		resetRendererCaches();
		final argsStart = Sys.time();
		var argsSample = "";
		for (_ in 0...callCount)
			argsSample = @:privateAccess backend.cpp.CppTargetCore.renderFieldCallArgs("std::shared_ptr<EReg>", "match", matchArgs, scope).join(", ");
		final argsElapsed = Sys.time() - argsStart;
		resetRendererCaches();
		final shapeSample = [@:privateAccess
			backend.cpp.CppTargetCore.renderExpr(match, scope), @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(replace, scope), @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(map, scope)
		].join("\n");
		return {
			calls: callCount,
			fullElapsed: fullElapsed,
			constructorElapsed: constructorElapsed,
			argsElapsed: argsElapsed,
			fullSample: fullSample,
			constructorSample: constructorSample,
			argsSample: argsSample,
			shapeSample: shapeSample
		};
	}

	/** Separate fresh EReg local type selection and initializer adaptation from direct construction. **/
	static function renderFreshERegLocalDeclPhases(callCount:Int):FreshERegLocalDeclPhaseBenchResult {
		final scope = eRegBenchScope();
		final fresh = ENew("EReg", [EString("a+"), EString("g")]);
		final qualifiedFresh = ENew("fixture.regex.EReg", [EString("a+"), EString("g")]);
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.renderExpr(qualifiedFresh, scope) == 'std::make_shared<EReg>("a+", "g")',
			"Package-qualified EReg construction should retain the target-owned carrier");
		assertTrue(@:privateAccess
			backend.cpp.CppTargetCore.newExpr("EReg", [EString("a+"), EString("g")], scope, "std::shared_ptr<EReg>") == 'std::make_shared<EReg>("a+", "g")',
			"Explicit expected EReg types should retain exact target-owned construction");
		scope.localNames.set("pattern", "pattern");
		scope.localNames.set("options", "options");
		scope.localTypes.set("pattern", "std::string");
		scope.localTypes.set("options", "std::string");
		final localArgs = [EIdent("pattern"), EIdent("options")];
		final discoveredLocalArgs = @:privateAccess backend.cpp.CppTargetCore.renderConstructorArgs("EReg", localArgs, scope).join(", ");
		assertTrue(discoveredLocalArgs == "pattern, options"
			&& @:privateAccess backend.cpp.CppTargetCore.newExpr("EReg", localArgs, scope) == "std::make_shared<EReg>(" + discoveredLocalArgs + ")",
			"Target-owned EReg construction should preserve ordinary typed String-local argument rendering");
		assertTrue(@:privateAccess
			backend.cpp.CppTargetCore.newExpr("FreshERegDummy0", [], scope, "std::shared_ptr<FreshERegDummy0>") == "std::make_shared<FreshERegDummy0>()",
			"Non-EReg constructors should retain general class and expected-type discovery");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.cppLocalDeclaredType("typed", "EReg", fresh, scope, "typed") == "std::shared_ptr<EReg>",
			"Explicit EReg local hints should retain their reference carrier");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.cppLocalDeclaredType("count", "", EInt(1), scope, "count") == "int",
			"Non-EReg local declarations should retain general type inference");
		scope.localTypeOverrides.set("r", "std::any");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.cppLocalDeclaredType("r", "", fresh, scope, "r") == "std::any",
			"Fresh EReg inference should retain prepared source-local overrides");
		scope.localTypeOverrides.remove("r");
		scope.localTypeOverrides.set("r_2", "std::any");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.cppLocalDeclaredType("r", "", fresh, scope, "r_2") == "std::any",
			"Fresh EReg inference should retain prepared renamed-local overrides");
		scope.localTypeOverrides.remove("r_2");
		resetRendererCaches();
		final typeStart = Sys.time();
		var typeSample = "";
		for (_ in 0...callCount)
			typeSample = @:privateAccess backend.cpp.CppTargetCore.cppLocalDeclaredType("r", "", fresh, scope, "r");
		final typeElapsed = Sys.time() - typeStart;
		resetRendererCaches();
		final hintStart = Sys.time();
		var hintSample = "";
		for (_ in 0...callCount)
			hintSample = @:privateAccess backend.cpp.CppTargetCore.cppTypeHint("EReg", scope);
		final hintElapsed = Sys.time() - hintStart;
		resetRendererCaches();
		final initStart = Sys.time();
		var initSample = "";
		for (_ in 0...callCount)
			initSample = @:privateAccess backend.cpp.CppTargetCore.renderLocalInitExpr(fresh, "auto", "std::shared_ptr<EReg>", scope);
		final initElapsed = Sys.time() - initStart;
		resetRendererCaches();
		final constructorStart = Sys.time();
		var constructorSample = "";
		for (_ in 0...callCount)
			constructorSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(fresh, scope);
		final constructorElapsed = Sys.time() - constructorStart;
		final shapeScope = eRegBenchScope();
		final shapeSample = @:privateAccess backend.cpp.CppTargetCore.renderStmt(SVar("r", "", fresh, HxPos.unknown()), "", shapeScope).join("\n");
		assertTrue(@:privateAccess
			backend.cpp.CppTargetCore.renderStmt(SVar("typed", "EReg", fresh, HxPos.unknown()), "", shapeScope)
				.join("\n") == 'std::shared_ptr<EReg> typed = std::make_shared<EReg>("a+", "g");',
			"Explicit EReg local declarations should preserve their exact generated shape");
		return {
			calls: callCount,
			typeElapsed: typeElapsed,
			hintElapsed: hintElapsed,
			initElapsed: initElapsed,
			constructorElapsed: constructorElapsed,
			typeSample: typeSample,
			hintSample: hintSample,
			initSample: initSample,
			constructorSample: constructorSample,
			shapeSample: shapeSample
		};
	}

	/** Separate typed-local EReg split discovery from argument and vector-chain rendering. **/
	static function renderTypedERegSplitPhases(callCount:Int):TypedERegSplitPhaseBenchResult {
		final scope = eRegBenchScope();
		scope.localNames.set("block", "block");
		scope.localNames.set("unknown", "unknown");
		scope.localTypes.set("block", "std::shared_ptr<EReg>");
		scope.localTypes.set("text", "std::string");
		scope.localTypes.set("dynamicText", "std::any");
		scope.localTypes.set("number", "int");
		final args = [EString("a")];
		final split = ECall(EField(EIdent("block"), "split"), args);
		final length = EField(split, "length");
		final joinArgs = [EString("|")];
		final join = ECall(EField(split, "join"), joinArgs);
		final concat = EBinop("+", EString("parts:"), join);
		final lengthEq = ECall(EIdent("eq"), [length, EInt(1)]);
		final concatEq = ECall(EIdent("eq"), [concat, EString("parts:a|b")]);
		final unknownSplit = ECall(EField(EIdent("unknown"), "split"), args);
		final unknownLength = EField(unknownSplit, "length");
		final unknownJoin = ECall(EField(unknownSplit, "join"), joinArgs);
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.isTypedLocalERegSplitCall(EIdent("block"), "split", 1, scope),
			"Typed-local EReg split should use the bounded known-return path");
		assertTrue(! @:privateAccess backend.cpp.CppTargetCore.isTypedLocalERegSplitCall(EIdent("unknown"), "split", 1, scope)
			&& ! @:privateAccess backend.cpp.CppTargetCore.isTypedLocalERegSplitCall(EIdent("text"), "split", 1, scope)
			&& ! @:privateAccess backend.cpp.CppTargetCore.isTypedLocalERegSplitCall(EIdent("block"), "split", 2, scope)
			&& ! @:privateAccess backend.cpp.CppTargetCore.isTypedLocalERegSplitCall(EIdent("block"), "match", 1, scope),
			"Unknown and non-EReg locals, wrong arity, and non-split methods should retain general return discovery");
		final unknownLengthSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(unknownLength, scope);
		final unknownJoinSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(unknownJoin, scope);
		assertTrue(unknownLengthSample == '(unknown.split("a").size())' && unknownJoinSample == 'unknown.split("a").join("|")',
			"Unknown split receivers should retain general field and call rendering, got length="
			+ unknownLengthSample
			+ " join="
			+ unknownJoinSample);
		final typedStringSplit = @:privateAccess backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("block"), "split"), [EIdent("text")]), scope);
		final dynamicStringSplit = @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("block"), "split"), [EIdent("dynamicText")]), scope);
		final numericStringSplit = @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("block"), "split"), [EIdent("number")]), scope);
		assertTrue(typedStringSplit == "block->split(text)"
			&& dynamicStringSplit == "block->split(__hxhx_stringify(dynamicText))"
			&& numericStringSplit == "block->split(std::to_string(number))",
			"Typed-local EReg split should preserve typed, erased, and scalar String argument adaptation, got typed="
			+ typedStringSplit
			+ " dynamic="
			+ dynamicStringSplit
			+ " numeric="
			+ numericStringSplit);
		resetRendererCaches();
		final inferStart = Sys.time();
		var inferSample = "";
		for (_ in 0...callCount)
			inferSample = @:privateAccess backend.cpp.CppTargetCore.inferExprCppType(split, scope);
		final inferElapsed = Sys.time() - inferStart;
		resetRendererCaches();
		final renderStart = Sys.time();
		var renderSample = "";
		for (_ in 0...callCount)
			renderSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(split, scope);
		final renderElapsed = Sys.time() - renderStart;
		resetRendererCaches();
		final argsStart = Sys.time();
		var argsSample = "";
		for (_ in 0...callCount)
			argsSample = @:privateAccess backend.cpp.CppTargetCore.renderFieldCallArgs("std::shared_ptr<EReg>", "split", args, scope).join(", ");
		final argsElapsed = Sys.time() - argsStart;
		resetRendererCaches();
		final lengthStart = Sys.time();
		var lengthSample = "";
		for (_ in 0...callCount)
			lengthSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(length, scope);
		final lengthElapsed = Sys.time() - lengthStart;
		resetRendererCaches();
		final lengthVectorStart = Sys.time();
		var lengthVectorSample = false;
		for (_ in 0...callCount)
			lengthVectorSample = @:privateAccess backend.cpp.CppTargetCore.isCppVectorLengthExpr(length, scope);
		final lengthVectorElapsed = Sys.time() - lengthVectorStart;
		resetRendererCaches();
		final lengthPrimitiveStart = Sys.time();
		var lengthPrimitiveSample = false;
		for (_ in 0...callCount)
			lengthPrimitiveSample = @:privateAccess backend.cpp.CppTargetCore.primitiveBackedAbstractPropertyExpr(split, "length", scope) != null;
		final lengthPrimitiveElapsed = Sys.time() - lengthPrimitiveStart;
		resetRendererCaches();
		final lengthMethodValueStart = Sys.time();
		var lengthMethodValueSample = false;
		for (_ in 0...callCount)
			lengthMethodValueSample = @:privateAccess backend.cpp.CppTargetCore.instanceMethodValueExpr(length, scope) != null;
		final lengthMethodValueElapsed = Sys.time() - lengthMethodValueStart;
		resetRendererCaches();
		final lengthReferenceStart = Sys.time();
		var lengthReferenceSample = false;
		for (_ in 0...callCount)
			lengthReferenceSample = @:privateAccess backend.cpp.CppTargetCore.exprHasReferenceType(split, scope);
		final lengthReferenceElapsed = Sys.time() - lengthReferenceStart;
		resetRendererCaches();
		final lengthClassPreflightStart = Sys.time();
		var lengthClassPreflightSample = false;
		for (_ in 0...callCount)
			lengthClassPreflightSample = @:privateAccess backend.cpp.CppTargetCore.staticEnumMethodValueExpr(split, "length", scope) != null
				|| @:privateAccess backend.cpp.CppTargetCore.staticFieldExpr(split, "length", scope) != null
				|| @:privateAccess backend.cpp.CppTargetCore.staticEnumTagValueExpr(split, "length", scope) != null
				|| @:privateAccess backend.cpp.CppTargetCore.classReferenceValueExpr(length, scope) != null;
		final lengthClassPreflightElapsed = Sys.time() - lengthClassPreflightStart;
		resetRendererCaches();
		final lengthPropertyStart = Sys.time();
		var lengthPropertySample = false;
		for (_ in 0...callCount)
			lengthPropertySample = @:privateAccess backend.cpp.CppTargetCore.typedPropertyGetReadExpr(split, "length", scope) != null;
		final lengthPropertyElapsed = Sys.time() - lengthPropertyStart;
		resetRendererCaches();
		final lengthJsonStart = Sys.time();
		var lengthJsonSample = false;
		for (_ in 0...callCount)
			lengthJsonSample = @:privateAccess backend.cpp.CppTargetCore.jsonAnyFieldReadExpr(split, "length", scope) != null;
		final lengthJsonElapsed = Sys.time() - lengthJsonStart;
		resetRendererCaches();
		final joinStart = Sys.time();
		var joinSample = "";
		for (_ in 0...callCount)
			joinSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(join, scope);
		final joinElapsed = Sys.time() - joinStart;
		resetRendererCaches();
		final joinBoundStart = Sys.time();
		var joinBoundSample = false;
		for (_ in 0...callCount)
			joinBoundSample = @:privateAccess backend.cpp.CppTargetCore.boundFunctionCallExpr(EField(split, "join"), joinArgs, scope) != null;
		final joinBoundElapsed = Sys.time() - joinBoundStart;
		resetRendererCaches();
		final joinQualifiedStart = Sys.time();
		var joinQualifiedSample = false;
		for (_ in 0...callCount)
			joinQualifiedSample = @:privateAccess backend.cpp.CppTargetCore.qualifiedValueTypeCarrierCtorExpr(split, "join", joinArgs, scope) != null;
		final joinQualifiedElapsed = Sys.time() - joinQualifiedStart;
		resetRendererCaches();
		final joinReceiverTypeStart = Sys.time();
		var joinReceiverTypeSample = "";
		for (_ in 0...callCount)
			joinReceiverTypeSample = @:privateAccess backend.cpp.CppTargetCore.exprCppType(split, scope);
		final joinReceiverTypeElapsed = Sys.time() - joinReceiverTypeStart;
		resetRendererCaches();
		final joinTemplateStart = Sys.time();
		var joinTemplateSample = false;
		for (_ in 0...callCount)
			joinTemplateSample = @:privateAccess
				backend.cpp.CppTargetCore.templateWrapValueMethodCallExpr("std::vector<std::string>", split, "join", joinArgs, scope) != null;
		final joinTemplateElapsed = Sys.time() - joinTemplateStart;
		resetRendererCaches();
		final joinFieldCallStart = Sys.time();
		var joinFieldCallSample = "";
		for (_ in 0...callCount)
			joinFieldCallSample = @:privateAccess backend.cpp.CppTargetCore.fieldCallExpr(split, "join", joinArgs, scope);
		final joinFieldCallElapsed = Sys.time() - joinFieldCallStart;
		final lengthEqSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(lengthEq, scope);
		final concatSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(concat, scope);
		final concatEqSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(concatEq, scope);
		return {
			calls: callCount,
			inferElapsed: inferElapsed,
			renderElapsed: renderElapsed,
			argsElapsed: argsElapsed,
			lengthElapsed: lengthElapsed,
			lengthVectorElapsed: lengthVectorElapsed,
			lengthPrimitiveElapsed: lengthPrimitiveElapsed,
			lengthMethodValueElapsed: lengthMethodValueElapsed,
			lengthReferenceElapsed: lengthReferenceElapsed,
			lengthClassPreflightElapsed: lengthClassPreflightElapsed,
			lengthPropertyElapsed: lengthPropertyElapsed,
			lengthJsonElapsed: lengthJsonElapsed,
			joinElapsed: joinElapsed,
			joinBoundElapsed: joinBoundElapsed,
			joinQualifiedElapsed: joinQualifiedElapsed,
			joinReceiverTypeElapsed: joinReceiverTypeElapsed,
			joinTemplateElapsed: joinTemplateElapsed,
			joinFieldCallElapsed: joinFieldCallElapsed,
			inferSample: inferSample,
			renderSample: renderSample,
			argsSample: argsSample,
			lengthSample: lengthSample,
			lengthEqSample: lengthEqSample,
			lengthVectorSample: lengthVectorSample,
			lengthPrimitiveSample: lengthPrimitiveSample,
			lengthMethodValueSample: lengthMethodValueSample,
			lengthReferenceSample: lengthReferenceSample,
			lengthClassPreflightSample: lengthClassPreflightSample,
			lengthPropertySample: lengthPropertySample,
			lengthJsonSample: lengthJsonSample,
			joinSample: joinSample,
			concatSample: concatSample,
			concatEqSample: concatEqSample,
			joinBoundSample: joinBoundSample,
			joinQualifiedSample: joinQualifiedSample,
			joinReceiverTypeSample: joinReceiverTypeSample,
			joinTemplateSample: joinTemplateSample,
			joinFieldCallSample: joinFieldCallSample
		};
	}

	/** Separate a matched typed String identifier argument from its non-matching reference probes. **/
	static function renderMatchedStringCallArgPhases(callCount:Int):MatchedStringCallArgPhaseBenchResult {
		final scope = eRegBenchScope();
		scope.localNames.set("test", "test");
		scope.localTypes.set("test", "std::string");
		final arg = EIdent("test");
		final param = new HxFunctionArg("s", "String", HxDefaultValue.NoDefault);
		resetRendererCaches();
		final fullStart = Sys.time();
		var fullSample = "";
		for (_ in 0...callCount)
			fullSample = @:privateAccess backend.cpp.CppTargetCore.callArgExprForParam(arg, param, scope, "std::string");
		final fullElapsed = Sys.time() - fullStart;
		resetRendererCaches();
		final declaredEnumStart = Sys.time();
		var declaredEnumSample = false;
		for (_ in 0...callCount)
			declaredEnumSample = @:privateAccess backend.cpp.CppTargetCore.enumReferenceArgExprForExpectedType(arg, "std::string", scope) != null;
		final declaredEnumElapsed = Sys.time() - declaredEnumStart;
		resetRendererCaches();
		final enumStart = Sys.time();
		var enumSample = false;
		for (_ in 0...callCount)
			enumSample = @:privateAccess backend.cpp.CppTargetCore.enumReferenceArgExprForExpectedType(arg, "std::string", scope) != null;
		final enumElapsed = Sys.time() - enumStart;
		resetRendererCaches();
		final structuralStart = Sys.time();
		var structuralSample = false;
		for (_ in 0...callCount)
			structuralSample = @:privateAccess backend.cpp.CppTargetCore.structuralTypedefClassForCppType("std::string", scope) != null;
		final structuralElapsed = Sys.time() - structuralStart;
		resetRendererCaches();
		final actualTypeStart = Sys.time();
		var actualTypeSample = "";
		for (_ in 0...callCount)
			actualTypeSample = @:privateAccess backend.cpp.CppTargetCore.exprCppType(arg, scope);
		final actualTypeElapsed = Sys.time() - actualTypeStart;
		resetRendererCaches();
		final renderStart = Sys.time();
		var renderSample = "";
		for (_ in 0...callCount)
			renderSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(arg, scope);
		return {
			calls: callCount,
			fullElapsed: fullElapsed,
			declaredEnumElapsed: declaredEnumElapsed,
			enumElapsed: enumElapsed,
			structuralElapsed: structuralElapsed,
			actualTypeElapsed: actualTypeElapsed,
			renderElapsed: Sys.time() - renderStart,
			fullSample: fullSample,
			declaredEnumSample: declaredEnumSample,
			enumSample: enumSample,
			structuralSample: structuralSample,
			actualTypeSample: actualTypeSample,
			renderSample: renderSample
		};
	}

	/** Measure built-in structural probes across the residual EReg statement expression families. **/
	static function renderResidualStructuralProbePhases(callCount:Int):ResidualStructuralProbeBenchResult {
		final scope = eRegBenchScope();
		final intParam = new HxFunctionArg("n", "Int", HxDefaultValue.NoDefault);
		final stringParam = new HxFunctionArg("s", "String", HxDefaultValue.NoDefault);
		final unary = EUnop("-", EInt(1));
		final concat = EBinop("+", EString("left"), EString("right"));
		final localString = EString("{ local } value");
		resetRendererCaches();
		final intProbeStart = Sys.time();
		var intProbeSample = false;
		for (_ in 0...callCount)
			intProbeSample = @:privateAccess backend.cpp.CppTargetCore.structuralTypedefClassForCppType("int", scope) != null;
		final intProbeElapsed = Sys.time() - intProbeStart;
		resetRendererCaches();
		final stringProbeStart = Sys.time();
		var stringProbeSample = false;
		for (_ in 0...callCount)
			stringProbeSample = @:privateAccess backend.cpp.CppTargetCore.structuralTypedefClassForCppType("std::string", scope) != null;
		final stringProbeElapsed = Sys.time() - stringProbeStart;
		resetRendererCaches();
		final vectorProbeStart = Sys.time();
		var vectorProbeSample = false;
		for (_ in 0...callCount)
			vectorProbeSample = @:privateAccess backend.cpp.CppTargetCore.structuralTypedefClassForCppType("std::vector<std::string>", scope) != null;
		final vectorProbeElapsed = Sys.time() - vectorProbeStart;
		final namedStructuralSample = @:privateAccess
			backend.cpp.CppTargetCore.structuralTypedefClassForCppType("ResidualStructuralValue", scope) != null;
		final genericStructuralSample = @:privateAccess
			backend.cpp.CppTargetCore.structuralTypedefClassForCppType("ResidualStructuralGeneric<std::string>", scope) != null;
		final ordinaryUserSample = @:privateAccess
			backend.cpp.CppTargetCore.structuralTypedefClassForCppType("ResidualStructuralUserClass", scope) != null;
		resetRendererCaches();
		final unaryArgStart = Sys.time();
		var unaryArgSample = "";
		for (_ in 0...callCount)
			unaryArgSample = @:privateAccess backend.cpp.CppTargetCore.callArgExprForParam(unary, intParam, scope, "int");
		final unaryArgElapsed = Sys.time() - unaryArgStart;
		resetRendererCaches();
		final concatArgStart = Sys.time();
		var concatArgSample = "";
		for (_ in 0...callCount)
			concatArgSample = @:privateAccess backend.cpp.CppTargetCore.callArgExprForParam(concat, stringParam, scope, "std::string");
		final concatArgElapsed = Sys.time() - concatArgStart;
		resetRendererCaches();
		final localStringStart = Sys.time();
		var localStringSample = "";
		for (_ in 0...callCount)
			localStringSample = @:privateAccess backend.cpp.CppTargetCore.renderLocalInitExpr(localString, "std::string", "std::string", scope);
		return {
			calls: callCount,
			intProbeElapsed: intProbeElapsed,
			stringProbeElapsed: stringProbeElapsed,
			vectorProbeElapsed: vectorProbeElapsed,
			unaryArgElapsed: unaryArgElapsed,
			concatArgElapsed: concatArgElapsed,
			localStringElapsed: Sys.time() - localStringStart,
			intProbeSample: intProbeSample,
			stringProbeSample: stringProbeSample,
			vectorProbeSample: vectorProbeSample,
			namedStructuralSample: namedStructuralSample,
			genericStructuralSample: genericStructuralSample,
			ordinaryUserSample: ordinaryUserSample,
			unaryArgSample: unaryArgSample,
			concatArgSample: concatArgSample,
			localStringSample: localStringSample
		};
	}

	static function renderERegLambdaPhases(callCount:Int):ERegLambdaPhaseBenchResult {
		final scope = eRegBenchScope();
		final matchedLeft = ECall(EField(EIdent("r"), "matchedLeft"), []);
		final matched = ECall(EField(EIdent("r"), "matched"), [EInt(0)]);
		final matchedRight = ECall(EField(EIdent("r"), "matchedRight"), []);
		final body = EBinop("+", EBinop("+", EBinop("+", EString("["), matchedLeft), matched), matchedRight);
		final nestedLeaf = ECall(EField(ECall(EField(EIdent("r"), "matched"), [EInt(2)]), "substr"), [EInt(3)]);
		final nestedBody = EBinop("+", EString("match:"), nestedLeaf);
		final expectedType = "std::function<std::string(std::shared_ptr<EReg>)>";
		final nestedCallback = ELambda(["r"], nestedBody);
		final mapArgs = [EString("aa"), nestedCallback];
		final map = ECall(EField(ENew("EReg", [EString("a+"), EString("g")]), "map"), mapArgs);
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.directLambdaValueExprForExpectedFunction(nestedCallback, expectedType, scope) != null,
			"A raw lambda with an expected C++ function type should use direct typed-lambda adaptation");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.directLambdaValueExprForExpectedFunction(nestedCallback, "std::string", scope) == null
			&& @:privateAccess backend.cpp.CppTargetCore.directLambdaValueExprForExpectedFunction(EIdent("f"), expectedType, scope) == null
			&& @:privateAccess backend.cpp.CppTargetCore.directLambdaValueExprForExpectedFunction(ECall(EField(EIdent("f"), "bind"), []), expectedType,
				scope) == null
			&& @:privateAccess backend.cpp.CppTargetCore.directLambdaValueExprForExpectedFunction(ECall(EField(EIdent("Reflect"), "makeVarArgs"),
				[nestedCallback]), expectedType, scope) == null,
			"Non-function expectations, named/bound values, and Reflect varargs should retain general value adaptation");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.dynamicIdentityCallExprForExpectedFunction(nestedCallback, expectedType,
			scope) == null && @:privateAccess backend.cpp.CppTargetCore.boundFunctionValueExprForExpectedFunction(nestedCallback, expectedType,
				scope) == null && @:privateAccess backend.cpp.CppTargetCore.reflectMakeVarArgsExprForExpectedFunction(nestedCallback, expectedType, scope) == null,
			"Direct typed lambdas should decline identity, bind, and Reflect.makeVarArgs expected-function preflights");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.directERegStringCallbackBodyExpr(body, ["r"], ["std::string"], "std::string", scope) == null
			&& @:privateAccess
			backend.cpp.CppTargetCore.directERegStringCallbackBodyExpr(body, ["r"], ["std::shared_ptr<EReg>"], "int", scope) == null
			&& @:privateAccess backend.cpp.CppTargetCore.directERegStringCallbackBodyExpr(matchedLeft, ["r"], ["std::shared_ptr<EReg>"], "std::string",
				scope) == null,
			"Non-EReg arguments, non-String returns, and non-concatenation callbacks should retain general lambda rendering");
		resetRendererCaches();
		final mapStart = Sys.time();
		var mapSample = "";
		for (_ in 0...callCount)
			mapSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(map, scope);
		final mapElapsed = Sys.time() - mapStart;
		resetRendererCaches();
		final argsStart = Sys.time();
		var argsSample = "";
		for (_ in 0...callCount)
			argsSample = @:privateAccess backend.cpp.CppTargetCore.renderFieldCallArgs("std::shared_ptr<EReg>", "map", mapArgs, scope).join(", ");
		final argsElapsed = Sys.time() - argsStart;
		resetRendererCaches();
		final expectedFunctionStart = Sys.time();
		var expectedFunctionSample = "";
		for (_ in 0...callCount)
			expectedFunctionSample = @:privateAccess backend.cpp.CppTargetCore.valueExprForExpectedType(nestedCallback, expectedType, scope);
		final expectedFunctionElapsed = Sys.time() - expectedFunctionStart;
		resetRendererCaches();
		final identityPreflightStart = Sys.time();
		for (_ in 0...callCount)
			@:privateAccess backend.cpp.CppTargetCore.dynamicIdentityCallExprForExpectedFunction(nestedCallback, expectedType, scope);
		final identityPreflightElapsed = Sys.time() - identityPreflightStart;
		resetRendererCaches();
		final boundPreflightStart = Sys.time();
		for (_ in 0...callCount)
			@:privateAccess backend.cpp.CppTargetCore.boundFunctionValueExprForExpectedFunction(nestedCallback, expectedType, scope);
		final boundPreflightElapsed = Sys.time() - boundPreflightStart;
		resetRendererCaches();
		final varArgsPreflightStart = Sys.time();
		for (_ in 0...callCount)
			@:privateAccess backend.cpp.CppTargetCore.reflectMakeVarArgsExprForExpectedFunction(nestedCallback, expectedType, scope);
		final varArgsPreflightElapsed = Sys.time() - varArgsPreflightStart;
		resetRendererCaches();
		final lambdaStart = Sys.time();
		var lambdaSample = "";
		for (_ in 0...callCount)
			lambdaSample = @:privateAccess backend.cpp.CppTargetCore.lambdaExprForExpectedFunction(["r"], body, expectedType, scope);
		final lambdaElapsed = Sys.time() - lambdaStart;
		resetRendererCaches();
		final nestedLambdaStart = Sys.time();
		var nestedLambdaSample = "";
		for (_ in 0...callCount)
			nestedLambdaSample = @:privateAccess backend.cpp.CppTargetCore.lambdaExprForExpectedFunction(["r"], nestedBody, expectedType, scope);
		final nestedLambdaElapsed = Sys.time() - nestedLambdaStart;
		scope.localTypes.set("r", "std::shared_ptr<EReg>");
		scope.localNames.set("r", "r");
		resetRendererCaches();
		final directBodyStart = Sys.time();
		var directBodySample = "";
		for (_ in 0...callCount) {
			final rendered = @:privateAccess
				backend.cpp.CppTargetCore.directERegStringCallbackBodyExpr(body, ["r"], ["std::shared_ptr<EReg>"], "std::string", scope);
			directBodySample = rendered == null ? "" : rendered;
		}
		final directBodyElapsed = Sys.time() - directBodyStart;
		resetRendererCaches();
		final nestedBodyStart = Sys.time();
		var nestedBodySample = "";
		for (_ in 0...callCount) {
			final rendered = @:privateAccess
				backend.cpp.CppTargetCore.directERegStringCallbackBodyExpr(nestedBody, ["r"], ["std::shared_ptr<EReg>"], "std::string", scope);
			nestedBodySample = rendered == null ? "" : rendered;
		}
		final nestedBodyElapsed = Sys.time() - nestedBodyStart;
		resetRendererCaches();
		final leafStart = Sys.time();
		var leafSample = "";
		for (_ in 0...callCount)
			leafSample = [@:privateAccess
				backend.cpp.CppTargetCore.renderExpr(matchedLeft, scope), @:privateAccess
				backend.cpp.CppTargetCore.renderExpr(matched, scope), @:privateAccess
				backend.cpp.CppTargetCore.renderExpr(matchedRight, scope)
			].join("|");
		final leafElapsed = Sys.time() - leafStart;
		resetRendererCaches();
		final nestedLeafStart = Sys.time();
		var nestedLeafSample = "";
		for (_ in 0...callCount)
			nestedLeafSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(nestedLeaf, scope);
		final nestedLeafElapsed = Sys.time() - nestedLeafStart;
		resetRendererCaches();
		final bodyStart = Sys.time();
		var bodySample = "";
		for (_ in 0...callCount)
			bodySample = @:privateAccess backend.cpp.CppTargetCore.valueExprForExpectedType(body, "std::string", scope);
		final bodyElapsed = Sys.time() - bodyStart;
		resetRendererCaches();
		final stringStart = Sys.time();
		for (_ in 0...callCount)
			@:privateAccess backend.cpp.CppTargetCore.stringExpr(body, scope);
		final stringElapsed = Sys.time() - stringStart;
		resetRendererCaches();
		final renderStart = Sys.time();
		for (_ in 0...callCount)
			@:privateAccess backend.cpp.CppTargetCore.renderExpr(body, scope);
		final renderElapsed = Sys.time() - renderStart;
		resetRendererCaches();
		final inferStart = Sys.time();
		for (_ in 0...callCount)
			@:privateAccess backend.cpp.CppTargetCore.inferExprCppType(body, scope);
		return {
			calls: callCount,
			mapElapsed: mapElapsed,
			argsElapsed: argsElapsed,
			expectedFunctionElapsed: expectedFunctionElapsed,
			identityPreflightElapsed: identityPreflightElapsed,
			boundPreflightElapsed: boundPreflightElapsed,
			varArgsPreflightElapsed: varArgsPreflightElapsed,
			lambdaElapsed: lambdaElapsed,
			nestedLambdaElapsed: nestedLambdaElapsed,
			directBodyElapsed: directBodyElapsed,
			nestedBodyElapsed: nestedBodyElapsed,
			leafElapsed: leafElapsed,
			nestedLeafElapsed: nestedLeafElapsed,
			bodyElapsed: bodyElapsed,
			stringElapsed: stringElapsed,
			renderElapsed: renderElapsed,
			inferElapsed: Sys.time() - inferStart,
			mapSample: mapSample,
			argsSample: argsSample,
			expectedFunctionSample: expectedFunctionSample,
			lambdaSample: lambdaSample,
			nestedLambdaSample: nestedLambdaSample,
			directBodySample: directBodySample,
			nestedBodySample: nestedBodySample,
			leafSample: leafSample,
			nestedLeafSample: nestedLeafSample,
			bodySample: bodySample
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
		final bytesReferenceCalls = envInt("HXHX_CPP_BYTES_REFERENCE_BENCH_CALLS", DEFAULT_BYTES_REFERENCE_CALLS);
		final bytesStringArgCalls = envInt("HXHX_CPP_BYTES_STRING_ARG_BENCH_CALLS", DEFAULT_BYTES_STRING_ARG_CALLS);
		final freshERegReturnCalls = envInt("HXHX_CPP_FRESH_EREG_RETURN_BENCH_CALLS", DEFAULT_FRESH_EREG_RETURN_CALLS);
		final freshERegFieldCalls = envInt("HXHX_CPP_FRESH_EREG_FIELD_CALL_BENCH_CALLS", DEFAULT_FRESH_EREG_FIELD_CALLS);
		final freshERegLocalDeclCalls = envInt("HXHX_CPP_FRESH_EREG_LOCAL_DECL_BENCH_CALLS", DEFAULT_FRESH_EREG_LOCAL_DECL_CALLS);
		final typedERegSplitCalls = envInt("HXHX_CPP_TYPED_EREG_SPLIT_BENCH_CALLS", DEFAULT_TYPED_EREG_SPLIT_CALLS);
		final matchedStringCallArgCalls = envInt("HXHX_CPP_MATCHED_STRING_CALL_ARG_BENCH_CALLS", DEFAULT_MATCHED_STRING_CALL_ARG_CALLS);
		final residualStructuralProbeCalls = envInt("HXHX_CPP_RESIDUAL_STRUCTURAL_PROBE_BENCH_CALLS", DEFAULT_RESIDUAL_STRUCTURAL_PROBE_CALLS);
		final eRegLambdaCalls = envInt("HXHX_CPP_EREG_LAMBDA_BENCH_CALLS", DEFAULT_EREG_LAMBDA_CALLS);
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
		final bytesReferences = renderBytesReferenceCalls(bytesReferenceCalls);
		assertTrue(bytesReferences.sample == "Bytes::ofString(std::string(s1))->sub(0, 1)->compare(Bytes::ofString(std::string(s2)))",
			"Bytes reference bench should keep nested ofString/sub/compare rendering stable");
		final bytesStringArgs = renderBytesStringArgPhases(bytesStringArgCalls);
		assertTrue(bytesStringArgs.valueSample == "std::string(inferred)"
			&& bytesStringArgs.stringSample == bytesStringArgs.valueSample
			&& bytesStringArgs.directSample == bytesStringArgs.valueSample,
			"Bytes String argument phases should preserve the existing std::string wrapper for typed locals");
		final freshERegReturns = inferFreshERegReturns(freshERegReturnCalls);
		assertTrue(freshERegReturns.sample == "std::string,std::string", "Fresh EReg replace/map calls should keep their known String return types");
		final freshERegFieldCallPhases = renderFreshERegFieldCallPhases(freshERegFieldCalls);
		assertTrue(freshERegFieldCallPhases.shapeSample == 'std::make_shared<EReg>("a+", "g")->match("aa")\nstd::make_shared<EReg>("a+", "g")->replace("aa", "x")\nstd::make_shared<EReg>("a+", "g")->map("aa", [&](std::shared_ptr<EReg> r) -> std::string { return r->matchedLeft(); })',
			"Fresh EReg field-call phases should preserve exact match, replace, and typed map rendering");
		final freshERegLocalDeclPhases = renderFreshERegLocalDeclPhases(freshERegLocalDeclCalls);
		assertTrue(freshERegLocalDeclPhases.typeSample == "std::shared_ptr<EReg>"
			&& freshERegLocalDeclPhases.hintSample == freshERegLocalDeclPhases.typeSample,
			"Fresh EReg local declarations should retain the direct EReg reference type");
		assertTrue(freshERegLocalDeclPhases.initSample == 'std::make_shared<EReg>("a+", "g")'
			&& freshERegLocalDeclPhases.constructorSample == freshERegLocalDeclPhases.initSample,
			"Fresh EReg local initializer adaptation should preserve direct construction");
		assertTrue(freshERegLocalDeclPhases.shapeSample == 'auto r = std::make_shared<EReg>("a+", "g");',
			"Fresh EReg local declarations should preserve their exact generated shape");
		final typedERegSplitPhases = renderTypedERegSplitPhases(typedERegSplitCalls);
		assertTrue(typedERegSplitPhases.inferSample == "std::vector<std::string>",
			"Typed-local EReg split calls should retain their known String-vector result");
		assertTrue(typedERegSplitPhases.renderSample == 'block->split("a")' && typedERegSplitPhases.argsSample == '"a"',
			"Typed-local EReg split calls should preserve exact receiver and String-argument rendering");
		assertTrue(typedERegSplitPhases.lengthSample == '(block->split("a").size())'
			&& typedERegSplitPhases.joinSample == '__hxhx_join(block->split("a"), std::string("|"))',
			"Typed-local EReg split chains should preserve exact vector length and join rendering, got length="
			+ typedERegSplitPhases.lengthSample
			+ " join="
			+ typedERegSplitPhases.joinSample);
		assertTrue(typedERegSplitPhases.lengthEqSample == 'eq(static_cast<int>((block->split("a").size())), 1)'
			&& typedERegSplitPhases.concatSample == '(std::string("parts:") + __hxhx_join(block->split("a"), std::string("|")))'
			&& typedERegSplitPhases.concatEqSample == 'eq((std::string("parts:") + __hxhx_join(block->split("a"), std::string("|"))), std::string("parts:a|b"))',
			"Typed-local EReg split chains should preserve exact concatenation and equality rendering, got lengthEq="
			+ typedERegSplitPhases.lengthEqSample
			+ " concat="
			+ typedERegSplitPhases.concatSample
			+ " concatEq="
			+ typedERegSplitPhases.concatEqSample);
		assertTrue(!typedERegSplitPhases.lengthPrimitiveSample
			&& typedERegSplitPhases.lengthVectorSample
			&& !typedERegSplitPhases.lengthMethodValueSample
			&& !typedERegSplitPhases.lengthReferenceSample
			&& !typedERegSplitPhases.lengthClassPreflightSample
			&& !typedERegSplitPhases.lengthPropertySample
			&& !typedERegSplitPhases.lengthJsonSample,
			"Typed-local EReg split length should decline unrelated field-read preflights");
		assertTrue(!typedERegSplitPhases.joinBoundSample
			&& !typedERegSplitPhases.joinQualifiedSample
			&& typedERegSplitPhases.joinReceiverTypeSample == "std::vector<std::string>"
			&& !typedERegSplitPhases.joinTemplateSample
			&& typedERegSplitPhases.joinFieldCallSample == typedERegSplitPhases.joinSample,
			"Typed-local EReg split join should retain general vector lowering while unrelated call preflights decline");
		final matchedStringCallArgPhases = renderMatchedStringCallArgPhases(matchedStringCallArgCalls);
		assertTrue(matchedStringCallArgPhases.fullSample == "test"
			&& matchedStringCallArgPhases.actualTypeSample == "std::string"
			&& matchedStringCallArgPhases.renderSample == matchedStringCallArgPhases.fullSample,
			"Matched typed String identifier arguments should preserve their exact direct value shape");
		assertTrue(!matchedStringCallArgPhases.declaredEnumSample
			&& !matchedStringCallArgPhases.enumSample
			&& !matchedStringCallArgPhases.structuralSample,
			"Matched typed String identifier arguments should not become enum references or structural typedef values");
		final residualStructuralProbePhases = renderResidualStructuralProbePhases(residualStructuralProbeCalls);
		assertTrue(!residualStructuralProbePhases.intProbeSample
			&& !residualStructuralProbePhases.stringProbeSample
			&& !residualStructuralProbePhases.vectorProbeSample,
			"Built-in Int, String, and String-vector types should not resolve as structural typedef values");
		assertTrue(residualStructuralProbePhases.namedStructuralSample
			&& residualStructuralProbePhases.genericStructuralSample
			&& !residualStructuralProbePhases.ordinaryUserSample,
			"Named and generic structural typedef values should retain lookup while ordinary user classes remain non-structural");
		assertTrue(backend.cpp.CppTypeModel.mayNameStructuralTypedefValueCppType("ResidualStructuralUserClass")
			&& backend.cpp.CppTypeModel.mayNameStructuralTypedefValueCppType("::ResidualStructuralValue"),
			"User-shaped and globally qualified generated C++ names should remain eligible for structural lookup");
		assertTrue(residualStructuralProbePhases.unaryArgSample == "(-1)"
			&& residualStructuralProbePhases.concatArgSample == '(std::string("left") + std::string("right"))'
			&& residualStructuralProbePhases.localStringSample == 'std::string("{ local } value")',
			"Residual structural-probe fixtures should preserve exact unary, concatenation, and String-local output");
		final eRegLambdaPhases = renderERegLambdaPhases(eRegLambdaCalls);
		assertTrue(eRegLambdaPhases.lambdaSample == '[&](std::shared_ptr<EReg> r) -> std::string { return (((std::string("[") + r->matchedLeft()) + r->matched(0)) + r->matchedRight()); }',
			"EReg.map callback fixtures should keep their typed callback and concatenation shape");
		assertTrue(eRegLambdaPhases.mapSample == 'std::make_shared<EReg>("a+", "g")->map("aa", ' + eRegLambdaPhases.nestedLambdaSample + ')'
			&& eRegLambdaPhases.argsSample == '"aa", ' + eRegLambdaPhases.nestedLambdaSample,
			"Fresh EReg.map fixtures should preserve their exact target-owned call and callback argument shapes");
		assertTrue(eRegLambdaPhases.directBodySample == '(((std::string("[") + r->matchedLeft()) + r->matched(0)) + r->matchedRight())'
			&& eRegLambdaPhases.leafSample == 'r->matchedLeft()|r->matched(0)|r->matchedRight()',
			"EReg.map callback fixtures should preserve exact direct-body and target-owned leaf call shapes, got body="
			+ eRegLambdaPhases.directBodySample
			+ " leaves="
			+ eRegLambdaPhases.leafSample);
		assertContains(eRegLambdaPhases.nestedBodySample, "r->matched(2)",
			"EReg.map callback fixtures should preserve the callback-owned matched/substr chain");
		assertTrue(eRegLambdaPhases.nestedLeafSample == "r->matched(2).substr(3)"
			&& eRegLambdaPhases.nestedBodySample == '(std::string("match:") + r->matched(2).substr(3))'
			&& eRegLambdaPhases.nestedLambdaSample == '[&](std::shared_ptr<EReg> r) -> std::string { return (std::string("match:") + r->matched(2).substr(3)); }'
			&& eRegLambdaPhases.expectedFunctionSample == eRegLambdaPhases.nestedLambdaSample,
			"EReg.map callback fixtures should preserve exact nested matched/substr and lambda shapes");
		assertTrue(@:privateAccess
			backend.cpp.CppTargetCore.directERegStringCallbackConcatLeafExpr(ECall(EField(EIdent("r"), "matchedLeft"), []), "r",
				eRegBenchScope()) == "r->matchedLeft()",
			"Typed EReg callbacks should use the bounded target-owned matched leaf path");
		assertTrue(@:privateAccess
			backend.cpp.CppTargetCore.directERegStringCallbackConcatLeafExpr(ECall(EField(ECall(EField(EIdent("r"), "matched"), [EInt(2)]), "substr"),
				[EInt(3)]), "r", eRegBenchScope()) == "r->matched(2).substr(3)",
			"Typed EReg callbacks should use the bounded target-owned matched/substr leaf path");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.directERegStringCallbackConcatLeafExpr(ECall(EField(EIdent("other"), "matchedLeft"), []), "r",
			eRegBenchScope()) == null && @:privateAccess backend.cpp.CppTargetCore.directERegStringCallbackConcatLeafExpr(ECall(EField(EIdent("r"), "match"),
				[EString("a")]), "r",
				eRegBenchScope()) == null && @:privateAccess backend.cpp.CppTargetCore.directERegStringCallbackConcatLeafExpr(ECall(EField(EIdent("r"),
				"matched"), [EIdent("index")]), "r", eRegBenchScope()) == null,
			"Other receivers, unsupported methods, and non-literal match indices should retain general String rendering");
		assertTrue(@:privateAccess
			backend.cpp.CppTargetCore.directERegStringCallbackConcatLeafExpr(ECall(EField(ECall(EField(EIdent("r"), "matched"), [EInt(2)]), "substr"),
				[EIdent("start")]), "r", eRegBenchScope()) == null,
			"Matched/substr callback chains with non-literal starts should retain general String rendering");
		assertContains(eRegLambdaPhases.bodySample, "r->matchedLeft()", "EReg.map callback fixtures should keep nested EReg body calls");

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
			+ " bytes_reference_calls="
			+ bytesReferences.calls
			+ " bytes_reference_seconds="
			+ bytesReferences.elapsed
			+ " bytes_string_arg_calls="
			+ bytesStringArgs.calls
			+ " bytes_string_value_seconds="
			+ bytesStringArgs.valueElapsed
			+ " bytes_string_string_seconds="
			+ bytesStringArgs.stringElapsed
			+ " bytes_string_direct_seconds="
			+ bytesStringArgs.directElapsed
			+ " fresh_ereg_return_calls="
			+ freshERegReturns.calls
			+ " fresh_ereg_return_seconds="
			+ freshERegReturns.elapsed
			+ " fresh_ereg_field_call_calls="
			+ freshERegFieldCallPhases.calls
			+ " fresh_ereg_field_call_seconds="
			+ freshERegFieldCallPhases.fullElapsed
			+ " fresh_ereg_constructor_seconds="
			+ freshERegFieldCallPhases.constructorElapsed
			+ " fresh_ereg_field_args_seconds="
			+ freshERegFieldCallPhases.argsElapsed
			+ " fresh_ereg_local_decl_calls="
			+ freshERegLocalDeclPhases.calls
			+ " fresh_ereg_local_type_seconds="
			+ freshERegLocalDeclPhases.typeElapsed
			+ " fresh_ereg_local_hint_seconds="
			+ freshERegLocalDeclPhases.hintElapsed
			+ " fresh_ereg_local_init_seconds="
			+ freshERegLocalDeclPhases.initElapsed
			+ " fresh_ereg_local_constructor_seconds="
			+ freshERegLocalDeclPhases.constructorElapsed
			+ " typed_ereg_split_calls="
			+ typedERegSplitPhases.calls
			+ " typed_ereg_split_infer_seconds="
			+ typedERegSplitPhases.inferElapsed
			+ " typed_ereg_split_render_seconds="
			+ typedERegSplitPhases.renderElapsed
			+ " typed_ereg_split_args_seconds="
			+ typedERegSplitPhases.argsElapsed
			+ " typed_ereg_split_length_seconds="
			+ typedERegSplitPhases.lengthElapsed
			+ " typed_ereg_split_length_vector_seconds="
			+ typedERegSplitPhases.lengthVectorElapsed
			+ " typed_ereg_split_length_primitive_seconds="
			+ typedERegSplitPhases.lengthPrimitiveElapsed
			+ " typed_ereg_split_length_method_value_seconds="
			+ typedERegSplitPhases.lengthMethodValueElapsed
			+ " typed_ereg_split_length_reference_seconds="
			+ typedERegSplitPhases.lengthReferenceElapsed
			+ " typed_ereg_split_length_class_preflight_seconds="
			+ typedERegSplitPhases.lengthClassPreflightElapsed
			+ " typed_ereg_split_length_property_seconds="
			+ typedERegSplitPhases.lengthPropertyElapsed
			+ " typed_ereg_split_length_json_seconds="
			+ typedERegSplitPhases.lengthJsonElapsed
			+ " typed_ereg_split_join_seconds="
			+ typedERegSplitPhases.joinElapsed
			+ " typed_ereg_split_join_bound_seconds="
			+ typedERegSplitPhases.joinBoundElapsed
			+ " typed_ereg_split_join_qualified_seconds="
			+ typedERegSplitPhases.joinQualifiedElapsed
			+ " typed_ereg_split_join_receiver_type_seconds="
			+ typedERegSplitPhases.joinReceiverTypeElapsed
			+ " typed_ereg_split_join_template_seconds="
			+ typedERegSplitPhases.joinTemplateElapsed
			+ " typed_ereg_split_join_field_call_seconds="
			+ typedERegSplitPhases.joinFieldCallElapsed
			+ " matched_string_call_arg_calls="
			+ matchedStringCallArgPhases.calls
			+ " matched_string_call_arg_seconds="
			+ matchedStringCallArgPhases.fullElapsed
			+ " matched_string_declared_enum_seconds="
			+ matchedStringCallArgPhases.declaredEnumElapsed
			+ " matched_string_enum_seconds="
			+ matchedStringCallArgPhases.enumElapsed
			+ " matched_string_structural_seconds="
			+ matchedStringCallArgPhases.structuralElapsed
			+ " matched_string_actual_type_seconds="
			+ matchedStringCallArgPhases.actualTypeElapsed
			+ " matched_string_render_seconds="
			+ matchedStringCallArgPhases.renderElapsed
			+ " residual_structural_probe_calls="
			+ residualStructuralProbePhases.calls
			+ " residual_structural_int_seconds="
			+ residualStructuralProbePhases.intProbeElapsed
			+ " residual_structural_string_seconds="
			+ residualStructuralProbePhases.stringProbeElapsed
			+ " residual_structural_vector_seconds="
			+ residualStructuralProbePhases.vectorProbeElapsed
			+ " residual_structural_unary_arg_seconds="
			+ residualStructuralProbePhases.unaryArgElapsed
			+ " residual_structural_concat_arg_seconds="
			+ residualStructuralProbePhases.concatArgElapsed
			+ " residual_structural_local_string_seconds="
			+ residualStructuralProbePhases.localStringElapsed
			+ " ereg_lambda_calls="
			+ eRegLambdaPhases.calls
			+ " ereg_lambda_map_seconds="
			+ eRegLambdaPhases.mapElapsed
			+ " ereg_lambda_args_seconds="
			+ eRegLambdaPhases.argsElapsed
			+ " ereg_lambda_expected_function_seconds="
			+ eRegLambdaPhases.expectedFunctionElapsed
			+ " ereg_lambda_identity_preflight_seconds="
			+ eRegLambdaPhases.identityPreflightElapsed
			+ " ereg_lambda_bound_preflight_seconds="
			+ eRegLambdaPhases.boundPreflightElapsed
			+ " ereg_lambda_varargs_preflight_seconds="
			+ eRegLambdaPhases.varArgsPreflightElapsed
			+ " ereg_lambda_seconds="
			+ eRegLambdaPhases.lambdaElapsed
			+ " ereg_lambda_nested_seconds="
			+ eRegLambdaPhases.nestedLambdaElapsed
			+ " ereg_lambda_direct_body_seconds="
			+ eRegLambdaPhases.directBodyElapsed
			+ " ereg_lambda_nested_body_seconds="
			+ eRegLambdaPhases.nestedBodyElapsed
			+ " ereg_lambda_leaf_seconds="
			+ eRegLambdaPhases.leafElapsed
			+ " ereg_lambda_nested_leaf_seconds="
			+ eRegLambdaPhases.nestedLeafElapsed
			+ " ereg_lambda_body_seconds="
			+ eRegLambdaPhases.bodyElapsed
			+ " ereg_lambda_string_seconds="
			+ eRegLambdaPhases.stringElapsed
			+ " ereg_lambda_render_seconds="
			+ eRegLambdaPhases.renderElapsed
			+ " ereg_lambda_infer_seconds="
			+ eRegLambdaPhases.inferElapsed
			+ (stdList == null ? "" : " std_list_seconds=" + stdList.elapsed + " std_list_lines=" + stdList.lines));
	}
}
