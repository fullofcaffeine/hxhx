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

typedef NegativePrimitiveCallArgPhaseBenchResult = {
	var calls:Int;
	var fullElapsed:Float;
	var literalTypeElapsed:Float;
	var directElapsed:Float;
	var declaredTypeElapsed:Float;
	var primitiveGateElapsed:Float;
	var abstractProbeElapsed:Float;
	var fullSample:String;
	var literalTypeSample:Null<String>;
	var directSample:Null<String>;
	var positiveDirectSample:Null<String>;
	var negativeFloatSample:String;
	var negativeFloatDirectSample:Null<String>;
	var nonLiteralSample:String;
	var nonLiteralDirectSample:Null<String>;
	var stringDirectSample:Null<String>;
	var dynamicDirectSample:Null<String>;
	var primitiveGateSample:Bool;
	var abstractGateSample:Bool;
	var abstractSample:String;
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

typedef FreshERegMapReplacePhaseBenchResult = {
	var calls:Int;
	var mapRenderElapsed:Float;
	var replaceRenderElapsed:Float;
	var mapInferElapsed:Float;
	var replaceInferElapsed:Float;
	var mapEqualityElapsed:Float;
	var replaceEqualityElapsed:Float;
	var constructorElapsed:Float;
	var stringArgElapsed:Float;
	var callbackArgElapsed:Float;
	var genericMapArgsElapsed:Float;
	var genericReplaceArgsElapsed:Float;
	var mapRenderSample:String;
	var replaceRenderSample:String;
	var mapInferSample:String;
	var replaceInferSample:String;
	var mapEqualitySample:String;
	var replaceEqualitySample:String;
	var constructorSample:String;
	var stringArgSample:String;
	var callbackArgSample:String;
	var genericMapArgsSample:String;
	var genericReplaceArgsSample:String;
	var conversionSample:String;
	var declineSample:String;
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
	var concatRenderElapsed:Float;
	var concatStringElapsed:Float;
	var concatLeftStringElapsed:Float;
	var concatRightStringElapsed:Float;
	var concatEqArgElapsed:Float;
	var concatAnyAddElapsed:Float;
	var concatStringSelectElapsed:Float;
	var concatPrimitiveAbstractElapsed:Float;
	var concatClassAbstractElapsed:Float;
	var concatExplicitTypeElapsed:Float;
	var concatClassMetadataElapsed:Float;
	var concatInferElapsed:Float;
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
	var concatStringSample:String;
	var concatLeftStringSample:String;
	var concatRightStringSample:String;
	var concatEqArgSample:String;
	var concatAnyAddSample:Bool;
	var concatStringSelectSample:Bool;
	var concatPrimitiveAbstractSample:Bool;
	var concatClassAbstractSample:Bool;
	var concatExplicitTypeSample:String;
	var concatClassMetadataSample:Bool;
	var concatInferSample:String;
}

typedef TypedERegMatchedPosPhaseBenchResult = {
	var calls:Int;
	var renderElapsed:Float;
	var inferElapsed:Float;
	var eqArgElapsed:Float;
	var callRenderElapsed:Float;
	var callInferElapsed:Float;
	var callExplicitTypeElapsed:Float;
	var fieldAccessElapsed:Float;
	var fieldTypeElapsed:Float;
	var primitiveElapsed:Float;
	var methodValueElapsed:Float;
	var referenceElapsed:Float;
	var classPreflightElapsed:Float;
	var propertyElapsed:Float;
	var jsonElapsed:Float;
	var posSample:String;
	var lenSample:String;
	var inferSample:String;
	var eqArgSample:String;
	var callRenderSample:String;
	var callInferSample:String;
	var callExplicitTypeSample:String;
	var fieldAccessSample:String;
	var fieldTypeSample:String;
	var primitiveSample:Bool;
	var methodValueSample:Bool;
	var referenceSample:Bool;
	var classPreflightSample:Bool;
	var propertySample:Bool;
	var jsonSample:Bool;
}

typedef TypedERegMatchSubPhaseBenchResult = {
	var calls:Int;
	var twoRenderElapsed:Float;
	var threeRenderElapsed:Float;
	var twoInferElapsed:Float;
	var threeInferElapsed:Float;
	var twoArgsElapsed:Float;
	var threeArgsElapsed:Float;
	var twoInstanceArgsElapsed:Float;
	var threeInstanceArgsElapsed:Float;
	var twoExpectedBoolElapsed:Float;
	var threeExpectedBoolElapsed:Float;
	var knownReturnElapsed:Float;
	var instanceReturnElapsed:Float;
	var receiverTypeElapsed:Float;
	var stringArgElapsed:Float;
	var posArgElapsed:Float;
	var optionalMatchElapsed:Float;
	var lenArgElapsed:Float;
	var twoRenderSample:String;
	var threeRenderSample:String;
	var twoInferSample:String;
	var threeInferSample:String;
	var twoArgsSample:String;
	var threeArgsSample:String;
	var twoInstanceArgsSample:String;
	var threeInstanceArgsSample:String;
	var twoExpectedBoolSample:String;
	var threeExpectedBoolSample:String;
	var knownReturnSample:String;
	var instanceReturnSample:String;
	var receiverTypeSample:String;
	var stringArgSample:String;
	var posArgSample:String;
	var optionalMatchSample:Bool;
	var lenArgSample:String;
}

typedef TypedERegMatchedStringPhaseBenchResult = {
	var calls:Int;
	var matchedRenderElapsed:Float;
	var sideRenderElapsed:Float;
	var matchedInferElapsed:Float;
	var sideInferElapsed:Float;
	var matchedEqualityElapsed:Float;
	var sideEqualityElapsed:Float;
	var genericArgsElapsed:Float;
	var intArgElapsed:Float;
	var matchedRenderSample:String;
	var sideRenderSample:String;
	var matchedInferSample:String;
	var sideInferSample:String;
	var matchedEqualitySample:String;
	var sideEqualitySample:String;
	var genericArgsSample:String;
	var intArgSample:String;
	var conversionSample:String;
	var declineSample:String;
}

typedef ERegMatchPhaseBenchResult = {
	var calls:Int;
	var typedRenderElapsed:Float;
	var freshRenderElapsed:Float;
	var typedInferElapsed:Float;
	var freshInferElapsed:Float;
	var typedBoolElapsed:Float;
	var freshBoolElapsed:Float;
	var constructorElapsed:Float;
	var stringArgElapsed:Float;
	var genericArgsElapsed:Float;
	var typedRenderSample:String;
	var freshRenderSample:String;
	var typedInferSample:String;
	var freshInferSample:String;
	var typedBoolSample:String;
	var freshBoolSample:String;
	var constructorSample:String;
	var stringArgSample:String;
	var genericArgsSample:String;
	var conversionSample:String;
	var declineSample:String;
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
	var typedInlineMapElapsed:Float;
	var typedNamedMapElapsed:Float;
	var typedInferElapsed:Float;
	var typedKnownReturnElapsed:Float;
	var typedInstanceReturnElapsed:Float;
	var typedInlineEqElapsed:Float;
	var typedNamedEqElapsed:Float;
	var typedInlineArgsElapsed:Float;
	var typedNamedArgsElapsed:Float;
	var typedStringArgElapsed:Float;
	var typedInlineCallbackElapsed:Float;
	var typedNamedCallbackElapsed:Float;
	var typedReceiverTypeElapsed:Float;
	var expectedFunctionElapsed:Float;
	var identityPreflightElapsed:Float;
	var boundPreflightElapsed:Float;
	var varArgsPreflightElapsed:Float;
	var lambdaElapsed:Float;
	var nestedLambdaElapsed:Float;
	var directBodyElapsed:Float;
	var nestedBodyElapsed:Float;
	var isolatedBodyElapsed:Float;
	var leafElapsed:Float;
	var nestedLeafElapsed:Float;
	var bodyElapsed:Float;
	var stringElapsed:Float;
	var renderElapsed:Float;
	var inferElapsed:Float;
	var mapSample:String;
	var argsSample:String;
	var typedInlineMapSample:String;
	var typedNamedMapSample:String;
	var typedInferSample:String;
	var typedKnownReturnSample:String;
	var typedInstanceReturnSample:String;
	var typedInlineEqSample:String;
	var typedNamedEqSample:String;
	var typedInlineArgsSample:String;
	var typedNamedArgsSample:String;
	var typedStringArgSample:String;
	var typedInlineCallbackSample:String;
	var typedNamedCallbackSample:String;
	var typedReceiverTypeSample:String;
	var expectedFunctionSample:String;
	var lambdaSample:String;
	var nestedLambdaSample:String;
	var directBodySample:String;
	var nestedBodySample:String;
	var isolatedBodySample:String;
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
	static inline final DEFAULT_NEGATIVE_PRIMITIVE_ARG_CALLS = 10;
	static inline final DEFAULT_BYTES_REFERENCE_CALLS = 10;
	static inline final DEFAULT_BYTES_STRING_ARG_CALLS = 100;
	static inline final DEFAULT_FRESH_EREG_RETURN_CALLS = 10;
	static inline final DEFAULT_FRESH_EREG_FIELD_CALLS = 10;
	static inline final DEFAULT_FRESH_EREG_MAP_REPLACE_CALLS = 10;
	static inline final DEFAULT_FRESH_EREG_LOCAL_DECL_CALLS = 10;
	static inline final DEFAULT_TYPED_EREG_SPLIT_CALLS = 10;
	static inline final DEFAULT_TYPED_EREG_MATCHED_POS_CALLS = 10;
	static inline final DEFAULT_TYPED_EREG_MATCH_SUB_CALLS = 10;
	static inline final DEFAULT_TYPED_EREG_MATCHED_STRING_CALLS = 10;
	static inline final DEFAULT_EREG_MATCH_CALLS = 10;
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

	/** Attribute negative numeric literal adaptation without treating arbitrary unary expressions as literals. **/
	static function renderNegativePrimitiveCallArgPhases(callCount:Int):NegativePrimitiveCallArgPhaseBenchResult {
		final intAbstract = new HxClassDecl("IntAbstract", false, [], [], "", ["__hxhx_abstract", "__hxhx_abstract_underlying=Int"]);
		final owner = new HxClassDecl("NegativePrimitiveArgBenchOwner", false, [], []);
		final names = new StringMap<Bool>();
		final classes = new StringMap<HxClassDecl>();
		for (cls in [intAbstract, owner]) {
			final name = HxClassDecl.getName(cls);
			names.set(name, true);
			classes.set(name, cls);
		}
		final scope = @:privateAccess backend.cpp.CppTargetCore.renderScope(owner, {names: names, byName: classes}, "void");
		scope.localNames.set("number", "number");
		scope.localTypes.set("number", "int");
		final intParam = new HxFunctionArg("value", "Int", NoDefault, false, false);
		final floatParam = new HxFunctionArg("value", "Float", NoDefault, false, false);
		final abstractParam = new HxFunctionArg("value", "IntAbstract", NoDefault, false, false);
		final negativeInt = EUnop(HxUnaryOperator.Negate, HxUnaryFixity.Prefix, EInt(1));
		final negativeFloat = EUnop(HxUnaryOperator.Negate, HxUnaryFixity.Prefix, EFloat(1.5));
		final nonLiteral = EUnop(HxUnaryOperator.Negate, HxUnaryFixity.Prefix, EIdent("number"));
		resetRendererCaches();
		final fullStart = Sys.time();
		var fullSample = "";
		for (_ in 0...callCount)
			fullSample = @:privateAccess backend.cpp.CppTargetCore.callArgExprForParam(negativeInt, intParam, scope, "int");
		final fullElapsed = Sys.time() - fullStart;
		resetRendererCaches();
		final literalTypeStart = Sys.time();
		var literalTypeSample:Null<String> = null;
		for (_ in 0...callCount)
			literalTypeSample = @:privateAccess backend.cpp.CppTargetCore.primitiveLiteralCallArgCppType(negativeInt);
		final literalTypeElapsed = Sys.time() - literalTypeStart;
		resetRendererCaches();
		final directStart = Sys.time();
		var directSample:Null<String> = null;
		for (_ in 0...callCount)
			directSample = @:privateAccess backend.cpp.CppTargetCore.directPrimitiveLiteralCallArgExprForExpectedType(negativeInt, "int", scope);
		final directElapsed = Sys.time() - directStart;
		resetRendererCaches();
		final declaredTypeStart = Sys.time();
		for (_ in 0...callCount)
			@:privateAccess backend.cpp.CppTargetCore.cppFunctionArgType(intParam, scope);
		final declaredTypeElapsed = Sys.time() - declaredTypeStart;
		resetRendererCaches();
		final primitiveGateStart = Sys.time();
		var primitiveGateSample = false;
		for (_ in 0...callCount)
			primitiveGateSample = @:privateAccess backend.cpp.CppTargetCore.primitiveBackedAbstractCallArgMayNeedConversion(intParam, "int", scope);
		final primitiveGateElapsed = Sys.time() - primitiveGateStart;
		resetRendererCaches();
		final abstractProbeStart = Sys.time();
		var abstractGateSample = false;
		for (_ in 0...callCount)
			abstractGateSample = @:privateAccess backend.cpp.CppTargetCore.primitiveBackedAbstractCallArgMayNeedConversion(abstractParam, "int", scope);
		final abstractProbeElapsed = Sys.time() - abstractProbeStart;
		return {
			calls: callCount,
			fullElapsed: fullElapsed,
			literalTypeElapsed: literalTypeElapsed,
			directElapsed: directElapsed,
			declaredTypeElapsed: declaredTypeElapsed,
			primitiveGateElapsed: primitiveGateElapsed,
			abstractProbeElapsed: abstractProbeElapsed,
			fullSample: fullSample,
			literalTypeSample: literalTypeSample,
			directSample: directSample,
			positiveDirectSample: @:privateAccess backend.cpp.CppTargetCore.directPrimitiveLiteralCallArgExprForExpectedType(EInt(1), "int", scope),
			negativeFloatSample: @:privateAccess backend.cpp.CppTargetCore.callArgExprForParam(negativeFloat, floatParam, scope, "double"),
			negativeFloatDirectSample: @:privateAccess
			backend.cpp.CppTargetCore.directPrimitiveLiteralCallArgExprForExpectedType(negativeFloat, "double", scope),
			nonLiteralSample: @:privateAccess backend.cpp.CppTargetCore.callArgExprForParam(nonLiteral, intParam, scope, "int"),
			nonLiteralDirectSample: @:privateAccess
			backend.cpp.CppTargetCore.directPrimitiveLiteralCallArgExprForExpectedType(nonLiteral, "int", scope),
			stringDirectSample: @:privateAccess
			backend.cpp.CppTargetCore.directPrimitiveLiteralCallArgExprForExpectedType(negativeInt, "std::string", scope),
			dynamicDirectSample: @:privateAccess
			backend.cpp.CppTargetCore.directPrimitiveLiteralCallArgExprForExpectedType(negativeInt, "std::any", scope),
			primitiveGateSample: primitiveGateSample,
			abstractGateSample: abstractGateSample,
			abstractSample: @:privateAccess backend.cpp.CppTargetCore.callArgExprForParam(negativeInt, abstractParam, scope, "int")
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
			new HxFunctionDecl("matchSub", Public, false, [
				new HxFunctionArg("s", "String", NoDefault, false, false),
				new HxFunctionArg("pos", "Int", NoDefault, false, false),
				new HxFunctionArg("len", "Int", NoDefault, true, false)
			],
				"Bool", [], ""),
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
			new HxFunctionDecl("matchedRight", Public, false, [], "String", [], ""),
			new HxFunctionDecl("matchedPos", Public, false, [], "{pos:Int,len:Int}", [], "")
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

	/** Separate fresh EReg map/replace rendering from inference, equality, and the retained generic argument path. **/
	static function renderFreshERegMapReplacePhases(callCount:Int):FreshERegMapReplacePhaseBenchResult {
		final scope = eRegBenchScope();
		for (name in ["prefix", "typedText", "dynamicText", "number", "replacement", "callback"])
			scope.localNames.set(name, name);
		scope.localTypes.set("prefix", "std::string");
		scope.localTypes.set("typedText", "std::string");
		scope.localTypes.set("dynamicText", "std::any");
		scope.localTypes.set("number", "int");
		scope.localTypes.set("replacement", "std::string");
		scope.localTypes.set("callback", "std::function<std::string(std::shared_ptr<EReg>)>");
		scope.localTypeHints.set("prefix", "String");
		scope.localTypeHints.set("typedText", "String");
		scope.localTypeHints.set("dynamicText", "Dynamic");
		scope.localTypeHints.set("number", "Int");
		scope.localTypeHints.set("replacement", "String");
		final fresh = ENew("EReg", [EString("z?"), EString("g")]);
		final qualifiedFresh = ENew("fixture.regex.EReg", [EString("z?"), EString("g")]);
		final callback = ELambda(["r"], EBinop("+", EIdent("prefix"), ECall(EField(EIdent("r"), "matched"), [EInt(0)])));
		final mapArgs = [EString("ab"), callback];
		final replaceArgs = [EString("baacaa"), EString("X")];
		final map = ECall(EField(fresh, "map"), mapArgs);
		final replace = ECall(EField(fresh, "replace"), replaceArgs);
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.isFreshERegFieldCall(fresh, "map",
			2) && @:privateAccess backend.cpp.CppTargetCore.isFreshERegFieldCall(fresh, "replace",
				2) && @:privateAccess backend.cpp.CppTargetCore.isFreshERegFieldCall(qualifiedFresh, "map", 2),
			"Fresh EReg map/replace calls should use only their exact target-owned two-argument contracts");
		final declineSample = [@:privateAccess
			backend.cpp.CppTargetCore.isFreshERegFieldCall(EIdent("regex"), "map", 2), @:privateAccess
			backend.cpp.CppTargetCore.isFreshERegFieldCall(fresh, "map", 1), @:privateAccess
			backend.cpp.CppTargetCore.isFreshERegFieldCall(fresh, "map", 3), @:privateAccess
			backend.cpp.CppTargetCore.isFreshERegFieldCall(fresh, "replace", 1), @:privateAccess
			backend.cpp.CppTargetCore.isFreshERegFieldCall(fresh, "split", 1)
		].map(Std.string).join(",");
		assertTrue(declineSample == "false,false,false,false,false",
			"Non-fresh receivers, wrong arities, and unrelated EReg methods should retain general field-call discovery");
		final conversionSample = [@:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ECall(EField(fresh, "replace"), [EIdent("typedText"), EIdent("replacement")]), scope), @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ECall(EField(fresh, "replace"), [EIdent("dynamicText"), EIdent("replacement")]), scope), @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ECall(EField(fresh, "replace"), [EIdent("number"), EIdent("replacement")]), scope), @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ECall(EField(fresh, "map"), [EIdent("typedText"), EIdent("callback")]), scope)
		].join("\n");
		resetRendererCaches();
		final mapRenderStart = Sys.time();
		var mapRenderSample = "";
		for (_ in 0...callCount)
			mapRenderSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(map, scope);
		final mapRenderElapsed = Sys.time() - mapRenderStart;
		resetRendererCaches();
		final replaceRenderStart = Sys.time();
		var replaceRenderSample = "";
		for (_ in 0...callCount)
			replaceRenderSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(replace, scope);
		final replaceRenderElapsed = Sys.time() - replaceRenderStart;
		resetRendererCaches();
		final mapInferStart = Sys.time();
		var mapInferSample = "";
		for (_ in 0...callCount)
			mapInferSample = @:privateAccess backend.cpp.CppTargetCore.inferExprCppType(map, scope);
		final mapInferElapsed = Sys.time() - mapInferStart;
		resetRendererCaches();
		final replaceInferStart = Sys.time();
		var replaceInferSample = "";
		for (_ in 0...callCount)
			replaceInferSample = @:privateAccess backend.cpp.CppTargetCore.inferExprCppType(replace, scope);
		final replaceInferElapsed = Sys.time() - replaceInferStart;
		resetRendererCaches();
		final mapEqualityStart = Sys.time();
		var mapEqualitySample = "";
		for (_ in 0...callCount)
			mapEqualitySample = @:privateAccess backend.cpp.CppTargetCore.renderEqCallArgs([map, EString("mapped")], scope).join(", ");
		final mapEqualityElapsed = Sys.time() - mapEqualityStart;
		resetRendererCaches();
		final replaceEqualityStart = Sys.time();
		var replaceEqualitySample = "";
		for (_ in 0...callCount)
			replaceEqualitySample = @:privateAccess backend.cpp.CppTargetCore.renderEqCallArgs([replace, EString("replaced")], scope).join(", ");
		final replaceEqualityElapsed = Sys.time() - replaceEqualityStart;
		resetRendererCaches();
		final constructorStart = Sys.time();
		var constructorSample = "";
		for (_ in 0...callCount)
			constructorSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(fresh, scope);
		final constructorElapsed = Sys.time() - constructorStart;
		resetRendererCaches();
		final stringArgStart = Sys.time();
		var stringArgSample = "";
		for (_ in 0...callCount)
			stringArgSample = @:privateAccess backend.cpp.CppTargetCore.eRegStringCallArgExpr(mapArgs[0], scope);
		final stringArgElapsed = Sys.time() - stringArgStart;
		resetRendererCaches();
		final callbackArgStart = Sys.time();
		var callbackArgSample = "";
		for (_ in 0...callCount)
			callbackArgSample = @:privateAccess backend.cpp.CppTargetCore.eRegMapCallbackArgExpr(mapArgs[1], scope);
		final callbackArgElapsed = Sys.time() - callbackArgStart;
		resetRendererCaches();
		final genericMapArgsStart = Sys.time();
		var genericMapArgsSample = "";
		for (_ in 0...callCount)
			genericMapArgsSample = @:privateAccess backend.cpp.CppTargetCore.renderFieldCallArgs("std::shared_ptr<EReg>", "map", mapArgs, scope).join(", ");
		final genericMapArgsElapsed = Sys.time() - genericMapArgsStart;
		resetRendererCaches();
		final genericReplaceArgsStart = Sys.time();
		var genericReplaceArgsSample = "";
		for (_ in 0...callCount)
			genericReplaceArgsSample = @:privateAccess backend.cpp.CppTargetCore.renderFieldCallArgs("std::shared_ptr<EReg>", "replace", replaceArgs, scope)
				.join(", ");
		return {
			calls: callCount,
			mapRenderElapsed: mapRenderElapsed,
			replaceRenderElapsed: replaceRenderElapsed,
			mapInferElapsed: mapInferElapsed,
			replaceInferElapsed: replaceInferElapsed,
			mapEqualityElapsed: mapEqualityElapsed,
			replaceEqualityElapsed: replaceEqualityElapsed,
			constructorElapsed: constructorElapsed,
			stringArgElapsed: stringArgElapsed,
			callbackArgElapsed: callbackArgElapsed,
			genericMapArgsElapsed: genericMapArgsElapsed,
			genericReplaceArgsElapsed: Sys.time() - genericReplaceArgsStart,
			mapRenderSample: mapRenderSample,
			replaceRenderSample: replaceRenderSample,
			mapInferSample: mapInferSample,
			replaceInferSample: replaceInferSample,
			mapEqualitySample: mapEqualitySample,
			replaceEqualitySample: replaceEqualitySample,
			constructorSample: constructorSample,
			stringArgSample: stringArgSample,
			callbackArgSample: callbackArgSample,
			genericMapArgsSample: genericMapArgsSample,
			genericReplaceArgsSample: genericReplaceArgsSample,
			conversionSample: conversionSample,
			declineSample: declineSample
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
		final concatPrefix = EString("parts:");
		final concatLeft = EBinop("+", concatPrefix, join);
		final concatRight = EString(":done");
		final concat = EBinop("+", concatLeft, concatRight);
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
		final typedStringJoin = ECall(EField(split, "join"), [EIdent("text")]);
		final dynamicStringJoin = ECall(EField(split, "join"), [EIdent("dynamicText")]);
		final numericStringJoin = ECall(EField(split, "join"), [EIdent("number")]);
		final typedStringJoinSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(typedStringJoin, scope);
		final dynamicStringJoinSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(dynamicStringJoin, scope);
		final numericStringJoinSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(numericStringJoin, scope);
		assertTrue(typedStringJoinSample == '__hxhx_join(block->split("a"), std::string(text))'
			&& dynamicStringJoinSample == '__hxhx_join(block->split("a"), __hxhx_stringify(dynamicText))'
			&& numericStringJoinSample == '__hxhx_join(block->split("a"), std::to_string(number))',
			"Typed-local EReg split join should preserve typed, erased, and scalar separator adaptation, got typed="
			+ typedStringJoinSample
			+ " dynamic="
			+ dynamicStringJoinSample
			+ " numeric="
			+ numericStringJoinSample);
		final directTypedOuter = @:privateAccess
			backend.cpp.CppTargetCore.directTypedLocalERegSplitJoinConcatExpr(EBinop("+", EIdent("text"), join), scope);
		final directTypedDelimiter = @:privateAccess
			backend.cpp.CppTargetCore.directTypedLocalERegSplitJoinConcatExpr(EBinop("+", EString("typed:"), typedStringJoin), scope);
		final directDynamicDelimiter = @:privateAccess
			backend.cpp.CppTargetCore.directTypedLocalERegSplitJoinConcatExpr(EBinop("+", EString("dynamic:"), dynamicStringJoin), scope);
		final directNumericDelimiter = @:privateAccess
			backend.cpp.CppTargetCore.directTypedLocalERegSplitJoinConcatExpr(EBinop("+", EString("numeric:"), numericStringJoin), scope);
		assertTrue(directTypedOuter == '(std::string(text) + __hxhx_join(block->split("a"), std::string("|")))'
			&& directTypedDelimiter == '(std::string("typed:") + __hxhx_join(block->split("a"), std::string(text)))'
			&& directDynamicDelimiter == '(std::string("dynamic:") + __hxhx_join(block->split("a"), __hxhx_stringify(dynamicText)))'
			&& directNumericDelimiter == '(std::string("numeric:") + __hxhx_join(block->split("a"), std::to_string(number)))',
			"Direct typed-local EReg split/join concatenation should reuse established String separator and local adaptation");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.isTypedLocalERegSplitJoinConcatExpr(concat, scope)
			&& @:privateAccess
			backend.cpp.CppTargetCore.isTypedLocalERegSplitJoinConcatExpr(EBinop("+", EString("typed:"), typedStringJoin), scope)
			&& @:privateAccess
			backend.cpp.CppTargetCore.isTypedLocalERegSplitJoinConcatExpr(EBinop("+", EString("dynamic:"), dynamicStringJoin), scope)
			&& @:privateAccess backend.cpp.CppTargetCore.isTypedLocalERegSplitJoinConcatExpr(EBinop("+", EString("numeric:"), numericStringJoin), scope),
			"Exact typed-local EReg split/join concatenations should expose their fixed String type without rendering");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.directTypedLocalERegSplitJoinConcatExpr(EBinop("+", EString("unknown:"), unknownJoin),
			scope) == null
			&& ! @:privateAccess
			backend.cpp.CppTargetCore.isTypedLocalERegSplitJoinConcatExpr(EBinop("+", EString("unknown:"), unknownJoin), scope)
			&& @:privateAccess
			backend.cpp.CppTargetCore.directTypedLocalERegSplitJoinConcatExpr(EBinop("+", EIdent("dynamicText"), join), scope) == null
			&& @:privateAccess
			backend.cpp.CppTargetCore.directTypedLocalERegSplitJoinConcatExpr(EBinop("+", EIdent("number"), join), scope) == null
			&& @:privateAccess
			backend.cpp.CppTargetCore.directTypedLocalERegSplitJoinConcatExpr(EBinop("+", EString("wrong:"), ECall(EField(split, "join"), [])), scope) == null
			&& @:privateAccess backend.cpp.CppTargetCore.directTypedLocalERegSplitJoinConcatExpr(join, scope) == null,
			"Unknown split receivers, Dynamic/scalar concat leaves, wrong join arity, and bare joins should retain general String rendering");
		assertTrue(! @:privateAccess
			backend.cpp.CppTargetCore.isTypedLocalERegSplitJoinConcatExpr(EBinop("+", EIdent("dynamicText"), join), scope)
			&& ! @:privateAccess
			backend.cpp.CppTargetCore.isTypedLocalERegSplitJoinConcatExpr(EBinop("+", EIdent("number"), join), scope)
			&& ! @:privateAccess
			backend.cpp.CppTargetCore.isTypedLocalERegSplitJoinConcatExpr(EBinop("+", EString("wrong:"), ECall(EField(split, "join"), [])), scope)
			&& ! @:privateAccess backend.cpp.CppTargetCore.isTypedLocalERegSplitJoinConcatExpr(join, scope),
			"Dynamic/scalar outer leaves, wrong join arity, and bare joins should retain general type inference");
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
		resetRendererCaches();
		final concatRenderStart = Sys.time();
		var concatSample = "";
		for (_ in 0...callCount)
			concatSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(concat, scope);
		final concatRenderElapsed = Sys.time() - concatRenderStart;
		resetRendererCaches();
		final concatStringStart = Sys.time();
		var concatStringSample = "";
		for (_ in 0...callCount)
			concatStringSample = @:privateAccess backend.cpp.CppTargetCore.stringExpr(concat, scope);
		final concatStringElapsed = Sys.time() - concatStringStart;
		resetRendererCaches();
		final concatLeftStringStart = Sys.time();
		var concatLeftStringSample = "";
		for (_ in 0...callCount)
			concatLeftStringSample = @:privateAccess backend.cpp.CppTargetCore.stringExpr(concatLeft, scope);
		final concatLeftStringElapsed = Sys.time() - concatLeftStringStart;
		resetRendererCaches();
		final concatRightStringStart = Sys.time();
		var concatRightStringSample = "";
		for (_ in 0...callCount)
			concatRightStringSample = @:privateAccess backend.cpp.CppTargetCore.stringExpr(concatRight, scope);
		final concatRightStringElapsed = Sys.time() - concatRightStringStart;
		resetRendererCaches();
		final concatEqArgStart = Sys.time();
		var concatEqArgSample = "";
		for (_ in 0...callCount)
			concatEqArgSample = @:privateAccess backend.cpp.CppTargetCore.eqComparableArgExpr(concat, "std::string", "std::string", scope);
		final concatEqArgElapsed = Sys.time() - concatEqArgStart;
		resetRendererCaches();
		final concatAnyAddStart = Sys.time();
		var concatAnyAddSample = false;
		for (_ in 0...callCount)
			concatAnyAddSample = @:privateAccess backend.cpp.CppTargetCore.anyAddExpr(concatLeft, concatRight, scope) != null;
		final concatAnyAddElapsed = Sys.time() - concatAnyAddStart;
		resetRendererCaches();
		final concatStringSelectStart = Sys.time();
		var concatStringSelectSample = false;
		for (_ in 0...callCount)
			concatStringSelectSample = @:privateAccess backend.cpp.CppTargetCore.isCppStringExpr(concatLeft, scope)
				|| @:privateAccess backend.cpp.CppTargetCore.isCppStringExpr(concatRight, scope);
		final concatStringSelectElapsed = Sys.time() - concatStringSelectStart;
		resetRendererCaches();
		final concatPrimitiveAbstractStart = Sys.time();
		var concatPrimitiveAbstractSample = false;
		for (_ in 0...callCount)
			concatPrimitiveAbstractSample = @:privateAccess backend.cpp.CppTargetCore.primitiveBackedAbstractToStringExpr(concat, scope) != null;
		final concatPrimitiveAbstractElapsed = Sys.time() - concatPrimitiveAbstractStart;
		resetRendererCaches();
		final concatClassAbstractStart = Sys.time();
		var concatClassAbstractSample = false;
		for (_ in 0...callCount)
			concatClassAbstractSample = @:privateAccess backend.cpp.CppTargetCore.classBackedAbstractToStringExpr(concat, scope) != null;
		final concatClassAbstractElapsed = Sys.time() - concatClassAbstractStart;
		resetRendererCaches();
		final concatExplicitTypeStart = Sys.time();
		var concatExplicitTypeSample = "";
		for (_ in 0...callCount)
			concatExplicitTypeSample = @:privateAccess backend.cpp.CppTargetCore.exprCppType(concat, scope);
		final concatExplicitTypeElapsed = Sys.time() - concatExplicitTypeStart;
		resetRendererCaches();
		final concatClassMetadataStart = Sys.time();
		var concatClassMetadataSample = false;
		for (_ in 0...callCount)
			concatClassMetadataSample = @:privateAccess backend.cpp.CppTargetCore.isCppEnumCarrierReferenceType("", scope)
				|| @:privateAccess backend.cpp.CppTargetCore.classNameFromCppExprType("", scope) != null
				|| @:privateAccess backend.cpp.CppTargetCore.classReferencePathText(concat, scope) != null;
		final concatClassMetadataElapsed = Sys.time() - concatClassMetadataStart;
		resetRendererCaches();
		final concatInferStart = Sys.time();
		var concatInferSample = "";
		for (_ in 0...callCount)
			concatInferSample = @:privateAccess backend.cpp.CppTargetCore.inferExprCppType(concat, scope);
		final concatInferElapsed = Sys.time() - concatInferStart;
		final lengthEqSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(lengthEq, scope);
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
			concatRenderElapsed: concatRenderElapsed,
			concatStringElapsed: concatStringElapsed,
			concatLeftStringElapsed: concatLeftStringElapsed,
			concatRightStringElapsed: concatRightStringElapsed,
			concatEqArgElapsed: concatEqArgElapsed,
			concatAnyAddElapsed: concatAnyAddElapsed,
			concatStringSelectElapsed: concatStringSelectElapsed,
			concatPrimitiveAbstractElapsed: concatPrimitiveAbstractElapsed,
			concatClassAbstractElapsed: concatClassAbstractElapsed,
			concatExplicitTypeElapsed: concatExplicitTypeElapsed,
			concatClassMetadataElapsed: concatClassMetadataElapsed,
			concatInferElapsed: concatInferElapsed,
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
			joinFieldCallSample: joinFieldCallSample,
			concatStringSample: concatStringSample,
			concatLeftStringSample: concatLeftStringSample,
			concatRightStringSample: concatRightStringSample,
			concatEqArgSample: concatEqArgSample,
			concatAnyAddSample: concatAnyAddSample,
			concatStringSelectSample: concatStringSelectSample,
			concatPrimitiveAbstractSample: concatPrimitiveAbstractSample,
			concatClassAbstractSample: concatClassAbstractSample,
			concatExplicitTypeSample: concatExplicitTypeSample,
			concatClassMetadataSample: concatClassMetadataSample,
			concatInferSample: concatInferSample
		};
	}

	/** Separate typed-local EReg matched-position field rendering from its structural and general field preflights. **/
	static function renderTypedERegMatchedPosPhases(callCount:Int):TypedERegMatchedPosPhaseBenchResult {
		final scope = eRegBenchScope();
		scope.localNames.set("r", "r");
		scope.localNames.set("unknown", "unknown");
		scope.localTypes.set("r", "std::shared_ptr<EReg>");
		final matchedPos = ECall(EField(EIdent("r"), "matchedPos"), []);
		final pos = EField(matchedPos, "pos");
		final len = EField(matchedPos, "len");
		final unknownMatchedPos = ECall(EField(EIdent("unknown"), "matchedPos"), []);
		final unknownPos = EField(unknownMatchedPos, "pos");
		final wrongArityPos = EField(ECall(EField(EIdent("r"), "matchedPos"), [EInt(0)]), "pos");
		final wrongField = EField(matchedPos, "other");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.isTypedLocalERegMatchedPosField(EIdent("r"), "matchedPos", 0, "pos",
			scope) && @:privateAccess backend.cpp.CppTargetCore.isTypedLocalERegMatchedPosField(EIdent("r"), "matchedPos", 0, "len", scope),
			"Typed-local EReg matchedPos pos/len fields should use the bounded target-owned path");
		assertTrue(! @:privateAccess
			backend.cpp.CppTargetCore.isTypedLocalERegMatchedPosField(EIdent("unknown"), "matchedPos", 0, "pos", scope)
			&& ! @:privateAccess backend.cpp.CppTargetCore.isTypedLocalERegMatchedPosField(EIdent("r"), "matchedPos", 1, "pos", scope)
			&& ! @:privateAccess backend.cpp.CppTargetCore.isTypedLocalERegMatchedPosField(EIdent("r"), "matchedPos", 0, "other", scope)
			&& ! @:privateAccess backend.cpp.CppTargetCore.isTypedLocalERegMatchedPosField(EIdent("r"), "matched", 0, "pos", scope),
			"Unknown receivers, wrong arity, unrelated fields, and other EReg methods should retain general field rendering");
		final unknownPosSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(unknownPos, scope);
		assertTrue(unknownPosSample == "(unknown.matchedPos().pos)",
			"Unknown matchedPos receivers should retain general field and call rendering, got " + unknownPosSample);
		final wrongAritySample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(wrongArityPos, scope);
		final wrongFieldSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(wrongField, scope);
		assertTrue(wrongAritySample == "(r->matchedPos(0).pos)" && wrongFieldSample == "(r->matchedPos().other)",
			"Wrong matchedPos arity and unrelated fields should retain general rendering");
		resetRendererCaches();
		final renderStart = Sys.time();
		var posSample = "";
		var lenSample = "";
		for (_ in 0...callCount) {
			posSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(pos, scope);
			lenSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(len, scope);
		}
		final renderElapsed = Sys.time() - renderStart;
		resetRendererCaches();
		final inferStart = Sys.time();
		var inferSample = "";
		for (_ in 0...callCount)
			inferSample = @:privateAccess backend.cpp.CppTargetCore.inferExprCppType(pos, scope);
		final inferElapsed = Sys.time() - inferStart;
		resetRendererCaches();
		final eqArgStart = Sys.time();
		var eqArgSample = "";
		for (_ in 0...callCount)
			eqArgSample = @:privateAccess backend.cpp.CppTargetCore.eqComparableArgExpr(pos, "int", "int", scope);
		final eqArgElapsed = Sys.time() - eqArgStart;
		resetRendererCaches();
		final callRenderStart = Sys.time();
		var callRenderSample = "";
		for (_ in 0...callCount)
			callRenderSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(matchedPos, scope);
		final callRenderElapsed = Sys.time() - callRenderStart;
		resetRendererCaches();
		final callInferStart = Sys.time();
		var callInferSample = "";
		for (_ in 0...callCount)
			callInferSample = @:privateAccess backend.cpp.CppTargetCore.inferExprCppType(matchedPos, scope);
		final callInferElapsed = Sys.time() - callInferStart;
		resetRendererCaches();
		final callExplicitTypeStart = Sys.time();
		var callExplicitTypeSample = "";
		for (_ in 0...callCount)
			callExplicitTypeSample = @:privateAccess backend.cpp.CppTargetCore.exprCppType(matchedPos, scope);
		final callExplicitTypeElapsed = Sys.time() - callExplicitTypeStart;
		resetRendererCaches();
		final fieldAccessStart = Sys.time();
		var fieldAccessSample = "";
		for (_ in 0...callCount)
			fieldAccessSample = @:privateAccess backend.cpp.CppTargetCore.fieldAccessOp(matchedPos, scope);
		final fieldAccessElapsed = Sys.time() - fieldAccessStart;
		resetRendererCaches();
		final fieldTypeStart = Sys.time();
		var fieldTypeSample = "";
		for (_ in 0...callCount)
			fieldTypeSample = @:privateAccess backend.cpp.CppTargetCore.anonStructFieldCppType("__hxhx_anon_pos_int__len_int_", "pos", scope);
		final fieldTypeElapsed = Sys.time() - fieldTypeStart;
		resetRendererCaches();
		final primitiveStart = Sys.time();
		var primitiveSample = false;
		for (_ in 0...callCount)
			primitiveSample = @:privateAccess backend.cpp.CppTargetCore.primitiveBackedAbstractPropertyExpr(matchedPos, "pos", scope) != null;
		final primitiveElapsed = Sys.time() - primitiveStart;
		resetRendererCaches();
		final methodValueStart = Sys.time();
		var methodValueSample = false;
		for (_ in 0...callCount)
			methodValueSample = @:privateAccess backend.cpp.CppTargetCore.instanceMethodValueExpr(pos, scope) != null;
		final methodValueElapsed = Sys.time() - methodValueStart;
		resetRendererCaches();
		final referenceStart = Sys.time();
		var referenceSample = false;
		for (_ in 0...callCount)
			referenceSample = @:privateAccess backend.cpp.CppTargetCore.exprHasReferenceType(matchedPos, scope);
		final referenceElapsed = Sys.time() - referenceStart;
		resetRendererCaches();
		final classPreflightStart = Sys.time();
		var classPreflightSample = false;
		for (_ in 0...callCount)
			classPreflightSample = @:privateAccess backend.cpp.CppTargetCore.staticEnumMethodValueExpr(matchedPos, "pos", scope) != null
				|| @:privateAccess backend.cpp.CppTargetCore.staticFieldExpr(matchedPos, "pos", scope) != null
				|| @:privateAccess backend.cpp.CppTargetCore.staticEnumTagValueExpr(matchedPos, "pos", scope) != null
				|| @:privateAccess backend.cpp.CppTargetCore.classReferenceValueExpr(pos, scope) != null;
		final classPreflightElapsed = Sys.time() - classPreflightStart;
		resetRendererCaches();
		final propertyStart = Sys.time();
		var propertySample = false;
		for (_ in 0...callCount)
			propertySample = @:privateAccess backend.cpp.CppTargetCore.typedPropertyGetReadExpr(matchedPos, "pos", scope) != null;
		final propertyElapsed = Sys.time() - propertyStart;
		resetRendererCaches();
		final jsonStart = Sys.time();
		var jsonSample = false;
		for (_ in 0...callCount)
			jsonSample = @:privateAccess backend.cpp.CppTargetCore.jsonAnyFieldReadExpr(matchedPos, "pos", scope) != null;
		final jsonElapsed = Sys.time() - jsonStart;
		return {
			calls: callCount,
			renderElapsed: renderElapsed,
			inferElapsed: inferElapsed,
			eqArgElapsed: eqArgElapsed,
			callRenderElapsed: callRenderElapsed,
			callInferElapsed: callInferElapsed,
			callExplicitTypeElapsed: callExplicitTypeElapsed,
			fieldAccessElapsed: fieldAccessElapsed,
			fieldTypeElapsed: fieldTypeElapsed,
			primitiveElapsed: primitiveElapsed,
			methodValueElapsed: methodValueElapsed,
			referenceElapsed: referenceElapsed,
			classPreflightElapsed: classPreflightElapsed,
			propertyElapsed: propertyElapsed,
			jsonElapsed: jsonElapsed,
			posSample: posSample,
			lenSample: lenSample,
			inferSample: inferSample,
			eqArgSample: eqArgSample,
			callRenderSample: callRenderSample,
			callInferSample: callInferSample,
			callExplicitTypeSample: callExplicitTypeSample,
			fieldAccessSample: fieldAccessSample,
			fieldTypeSample: fieldTypeSample,
			primitiveSample: primitiveSample,
			methodValueSample: methodValueSample,
			referenceSample: referenceSample,
			classPreflightSample: classPreflightSample,
			propertySample: propertySample,
			jsonSample: jsonSample
		};
	}

	/** Separate typed-local EReg matchSub rendering, inference, and fixed argument contracts. **/
	static function renderTypedERegMatchSubPhases(callCount:Int):TypedERegMatchSubPhaseBenchResult {
		final scope = eRegBenchScope();
		scope.localNames.set("regex", "regex");
		scope.localTypes.set("regex", "std::shared_ptr<EReg>");
		for (name in ["text", "dynamicText", "number", "position", "dynamicPosition", "optionalLength"])
			scope.localNames.set(name, name);
		scope.localTypes.set("text", "std::string");
		scope.localTypes.set("dynamicText", "std::any");
		scope.localTypes.set("number", "int");
		scope.localTypes.set("position", "int");
		scope.localTypes.set("dynamicPosition", "std::any");
		scope.localTypes.set("optionalLength", "std::optional<int>");
		final stringArg = EString("aa12");
		final posArg = EInt(1);
		final lenArg = EInt(2);
		final twoArgs = [stringArg, posArg];
		final threeArgs = [stringArg, posArg, lenArg];
		final twoCall = ECall(EField(EIdent("regex"), "matchSub"), twoArgs);
		final threeCall = ECall(EField(EIdent("regex"), "matchSub"), threeArgs);
		final stringParam = new HxFunctionArg("s", "String", NoDefault, false, false);
		final posParam = new HxFunctionArg("pos", "Int", NoDefault, false, false);
		final lenParam = new HxFunctionArg("len", "Int", NoDefault, true, false);
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.isTypedLocalERegMatchSubCall(EIdent("regex"), "matchSub", 2,
			scope) && @:privateAccess backend.cpp.CppTargetCore.isTypedLocalERegMatchSubCall(EIdent("regex"), "matchSub", 3, scope),
			"Typed-local EReg matchSub calls should use the exact target-owned two- or three-argument contract");
		assertTrue(! @:privateAccess backend.cpp.CppTargetCore.isTypedLocalERegMatchSubCall(EIdent("unknown"), "matchSub", 2, scope)
			&& ! @:privateAccess backend.cpp.CppTargetCore.isTypedLocalERegMatchSubCall(EIdent("regex"), "matchSub", 1, scope)
			&& ! @:privateAccess backend.cpp.CppTargetCore.isTypedLocalERegMatchSubCall(EIdent("regex"), "matchSub", 4, scope)
			&& ! @:privateAccess backend.cpp.CppTargetCore.isTypedLocalERegMatchSubCall(EIdent("regex"), "match", 2, scope),
			"Unknown receivers, unsupported arities, and other EReg methods should retain general field-call rendering");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.eRegIntCallArgExpr(EFloat(1.5), false, scope) == @:privateAccess
			backend.cpp.CppTargetCore.callArgExprForParam(EFloat(1.5), posParam, scope, "int"),
			"Uncommon EReg Int argument shapes should retain the general parameter adapter");
		final typedStringSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("regex"), "matchSub"),
			[EIdent("text"), EIdent("position")]), scope);
		final dynamicStringSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("regex"), "matchSub"),
			[EIdent("dynamicText"), EIdent("position")]), scope);
		final scalarStringSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("regex"), "matchSub"),
			[EIdent("number"), EIdent("position")]), scope);
		final dynamicPositionSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("regex"), "matchSub"),
			[EIdent("text"), EIdent("dynamicPosition")]), scope);
		final optionalLengthSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("regex"), "matchSub"),
			[EIdent("text"), EIdent("position"), EIdent("optionalLength")]), scope);
		final negativeLengthSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("regex"), "matchSub"), [
			EIdent("text"),
			EIdent("position"),
			EUnop(HxUnaryOperator.Negate, HxUnaryFixity.Prefix, EInt(1))
		]), scope);
		assertTrue(typedStringSample == "regex->matchSub(text, position)"
			&& dynamicStringSample == "regex->matchSub(__hxhx_stringify(dynamicText), position)"
			&& scalarStringSample == "regex->matchSub(std::to_string(number), position)"
			&& dynamicPositionSample == "regex->matchSub(text, static_cast<int>(__hxhx_any_double(dynamicPosition)))"
			&& optionalLengthSample == "regex->matchSub(text, position, optionalLength)"
			&& negativeLengthSample == "regex->matchSub(text, position, (-1))",
			"Typed-local EReg matchSub should preserve typed, erased, scalar, and optional argument adaptation");
		final unknownSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("unknown"), "matchSub"), twoArgs), scope);
		final wrongAritySample = @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("regex"), "matchSub"), [stringArg]), scope);
		final extraAritySample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("regex"), "matchSub"),
			[stringArg, posArg, lenArg, EInt(3)]), scope);
		final otherMethodSample = @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("regex"), "match"), [stringArg]), scope);
		assertTrue(unknownSample == 'unknown.matchSub("aa12", 1)'
			&& wrongAritySample == 'regex->matchSub("aa12")'
			&& extraAritySample == 'regex->matchSub("aa12", 1, 2, 3)'
			&& otherMethodSample == 'regex->match("aa12")',
			"Unknown receivers, wrong matchSub arity, and other EReg methods should retain general field-call rendering");
		resetRendererCaches();
		final twoRenderStart = Sys.time();
		var twoRenderSample = "";
		for (_ in 0...callCount)
			twoRenderSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(twoCall, scope);
		final twoRenderElapsed = Sys.time() - twoRenderStart;
		resetRendererCaches();
		final threeRenderStart = Sys.time();
		var threeRenderSample = "";
		for (_ in 0...callCount)
			threeRenderSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(threeCall, scope);
		final threeRenderElapsed = Sys.time() - threeRenderStart;
		resetRendererCaches();
		final twoInferStart = Sys.time();
		var twoInferSample = "";
		for (_ in 0...callCount)
			twoInferSample = @:privateAccess backend.cpp.CppTargetCore.inferExprCppType(twoCall, scope);
		final twoInferElapsed = Sys.time() - twoInferStart;
		resetRendererCaches();
		final threeInferStart = Sys.time();
		var threeInferSample = "";
		for (_ in 0...callCount)
			threeInferSample = @:privateAccess backend.cpp.CppTargetCore.inferExprCppType(threeCall, scope);
		final threeInferElapsed = Sys.time() - threeInferStart;
		resetRendererCaches();
		final twoArgsStart = Sys.time();
		var twoArgsSample = "";
		for (_ in 0...callCount)
			twoArgsSample = @:privateAccess
				backend.cpp.CppTargetCore.renderFieldCallArgs("std::shared_ptr<EReg>", "matchSub", twoArgs, scope).join(", ");
		final twoArgsElapsed = Sys.time() - twoArgsStart;
		resetRendererCaches();
		final threeArgsStart = Sys.time();
		var threeArgsSample = "";
		for (_ in 0...callCount)
			threeArgsSample = @:privateAccess
				backend.cpp.CppTargetCore.renderFieldCallArgs("std::shared_ptr<EReg>", "matchSub", threeArgs, scope).join(", ");
		final threeArgsElapsed = Sys.time() - threeArgsStart;
		resetRendererCaches();
		final twoInstanceArgsStart = Sys.time();
		var twoInstanceArgsSample = "";
		for (_ in 0...callCount)
			twoInstanceArgsSample = @:privateAccess
				backend.cpp.CppTargetCore.renderInstanceMethodCallArgs("std::shared_ptr<EReg>", "matchSub", twoArgs, scope).join(", ");
		final twoInstanceArgsElapsed = Sys.time() - twoInstanceArgsStart;
		resetRendererCaches();
		final threeInstanceArgsStart = Sys.time();
		var threeInstanceArgsSample = "";
		for (_ in 0...callCount)
			threeInstanceArgsSample = @:privateAccess
				backend.cpp.CppTargetCore.renderInstanceMethodCallArgs("std::shared_ptr<EReg>", "matchSub", threeArgs, scope).join(", ");
		final threeInstanceArgsElapsed = Sys.time() - threeInstanceArgsStart;
		resetRendererCaches();
		final twoExpectedBoolStart = Sys.time();
		var twoExpectedBoolSample = "";
		for (_ in 0...callCount)
			twoExpectedBoolSample = @:privateAccess backend.cpp.CppTargetCore.functionTypeArgExpr(twoCall, "bool", scope);
		final twoExpectedBoolElapsed = Sys.time() - twoExpectedBoolStart;
		resetRendererCaches();
		final threeExpectedBoolStart = Sys.time();
		var threeExpectedBoolSample = "";
		for (_ in 0...callCount)
			threeExpectedBoolSample = @:privateAccess backend.cpp.CppTargetCore.functionTypeArgExpr(threeCall, "bool", scope);
		final threeExpectedBoolElapsed = Sys.time() - threeExpectedBoolStart;
		resetRendererCaches();
		final knownReturnStart = Sys.time();
		var knownReturnSample = "";
		for (_ in 0...callCount)
			knownReturnSample = @:privateAccess
				backend.cpp.CppTargetCore.knownFieldCallReturnCppType(EIdent("regex"), "matchSub", threeArgs, scope);
		final knownReturnElapsed = Sys.time() - knownReturnStart;
		resetRendererCaches();
		final instanceReturnStart = Sys.time();
		var instanceReturnSample = "";
		for (_ in 0...callCount)
			instanceReturnSample = @:privateAccess backend.cpp.CppTargetCore.classMethodCppReturnType("EReg", "matchSub", false, scope);
		final instanceReturnElapsed = Sys.time() - instanceReturnStart;
		resetRendererCaches();
		final receiverTypeStart = Sys.time();
		var receiverTypeSample = "";
		for (_ in 0...callCount)
			receiverTypeSample = @:privateAccess backend.cpp.CppTargetCore.exprCppType(EIdent("regex"), scope);
		final receiverTypeElapsed = Sys.time() - receiverTypeStart;
		resetRendererCaches();
		final stringArgStart = Sys.time();
		var stringArgSample = "";
		for (_ in 0...callCount)
			stringArgSample = @:privateAccess backend.cpp.CppTargetCore.callArgExprForParam(stringArg, stringParam, scope, "std::string");
		final stringArgElapsed = Sys.time() - stringArgStart;
		resetRendererCaches();
		final posArgStart = Sys.time();
		var posArgSample = "";
		for (_ in 0...callCount)
			posArgSample = @:privateAccess backend.cpp.CppTargetCore.callArgExprForParam(posArg, posParam, scope, "int");
		final posArgElapsed = Sys.time() - posArgStart;
		resetRendererCaches();
		final optionalMatchStart = Sys.time();
		var optionalMatchSample = false;
		for (_ in 0...callCount)
			optionalMatchSample = @:privateAccess backend.cpp.CppTargetCore.callArgMatchesParam(lenArg, lenParam, scope);
		final optionalMatchElapsed = Sys.time() - optionalMatchStart;
		resetRendererCaches();
		final lenArgStart = Sys.time();
		var lenArgSample = "";
		for (_ in 0...callCount)
			lenArgSample = @:privateAccess backend.cpp.CppTargetCore.callArgExprForParam(lenArg, lenParam, scope, "std::optional<int>");
		final lenArgElapsed = Sys.time() - lenArgStart;
		return {
			calls: callCount,
			twoRenderElapsed: twoRenderElapsed,
			threeRenderElapsed: threeRenderElapsed,
			twoInferElapsed: twoInferElapsed,
			threeInferElapsed: threeInferElapsed,
			twoArgsElapsed: twoArgsElapsed,
			threeArgsElapsed: threeArgsElapsed,
			twoInstanceArgsElapsed: twoInstanceArgsElapsed,
			threeInstanceArgsElapsed: threeInstanceArgsElapsed,
			twoExpectedBoolElapsed: twoExpectedBoolElapsed,
			threeExpectedBoolElapsed: threeExpectedBoolElapsed,
			knownReturnElapsed: knownReturnElapsed,
			instanceReturnElapsed: instanceReturnElapsed,
			receiverTypeElapsed: receiverTypeElapsed,
			stringArgElapsed: stringArgElapsed,
			posArgElapsed: posArgElapsed,
			optionalMatchElapsed: optionalMatchElapsed,
			lenArgElapsed: lenArgElapsed,
			twoRenderSample: twoRenderSample,
			threeRenderSample: threeRenderSample,
			twoInferSample: twoInferSample,
			threeInferSample: threeInferSample,
			twoArgsSample: twoArgsSample,
			threeArgsSample: threeArgsSample,
			twoInstanceArgsSample: twoInstanceArgsSample,
			threeInstanceArgsSample: threeInstanceArgsSample,
			twoExpectedBoolSample: twoExpectedBoolSample,
			threeExpectedBoolSample: threeExpectedBoolSample,
			knownReturnSample: knownReturnSample,
			instanceReturnSample: instanceReturnSample,
			receiverTypeSample: receiverTypeSample,
			stringArgSample: stringArgSample,
			posArgSample: posArgSample,
			optionalMatchSample: optionalMatchSample,
			lenArgSample: lenArgSample
		};
	}

	/** Separate typed-local EReg matched String rendering, inference, equality adaptation, and index conversion. **/
	static function renderTypedERegMatchedStringPhases(callCount:Int):TypedERegMatchedStringPhaseBenchResult {
		final scope = eRegBenchScope();
		for (name in ["regex", "index", "dynamicIndex"])
			scope.localNames.set(name, name);
		scope.localTypes.set("regex", "std::shared_ptr<EReg>");
		scope.localTypes.set("index", "int");
		scope.localTypes.set("dynamicIndex", "std::any");
		final matchedArgs = [EInt(1)];
		final matched = ECall(EField(EIdent("regex"), "matched"), matchedArgs);
		final matchedLeft = ECall(EField(EIdent("regex"), "matchedLeft"), []);
		final matchedRight = ECall(EField(EIdent("regex"), "matchedRight"), []);
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.isTypedLocalERegCaptureCall(EIdent("regex"), "matched", 1,
			scope) && @:privateAccess backend.cpp.CppTargetCore.isTypedLocalERegCaptureCall(EIdent("regex"), "matchedLeft", 0,
				scope) && @:privateAccess backend.cpp.CppTargetCore.isTypedLocalERegCaptureCall(EIdent("regex"), "matchedRight", 0, scope),
			"Typed-local EReg capture calls should use only their exact target-owned nullable/indexed or String side contracts");
		assertTrue(! @:privateAccess backend.cpp.CppTargetCore.isTypedLocalERegCaptureCall(EIdent("unknown"), "matched", 1, scope)
			&& ! @:privateAccess backend.cpp.CppTargetCore.isTypedLocalERegCaptureCall(EIdent("regex"), "matched", 0, scope)
			&& ! @:privateAccess backend.cpp.CppTargetCore.isTypedLocalERegCaptureCall(EIdent("regex"), "matched", 2, scope)
			&& ! @:privateAccess backend.cpp.CppTargetCore.isTypedLocalERegCaptureCall(EIdent("regex"), "matchedLeft", 1, scope)
			&& ! @:privateAccess backend.cpp.CppTargetCore.isTypedLocalERegCaptureCall(EIdent("regex"), "match", 1, scope),
			"Unknown receivers, wrong arities, and unrelated methods should retain general EReg call discovery");
		final conversionSample = [@:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("regex"), "matched"), [EIdent("index")]), scope), @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("regex"), "matched"), [EIdent("dynamicIndex")]), scope), @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("regex"), "matched"), [EUnop(HxUnaryOperator.Negate, HxUnaryFixity.Prefix, EInt(1))]),
				scope)
		].join("\n");
		final declineSample = [@:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("unknown"), "matched"), matchedArgs), scope), @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("regex"), "matched"), []), scope), @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("regex"), "matched"), [EInt(0), EInt(1)]), scope), @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("regex"), "matchedLeft"), [EInt(0)]), scope), @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("regex"), "match"), [EString("a")]), scope)
		].join("\n");
		resetRendererCaches();
		final matchedRenderStart = Sys.time();
		var matchedRenderSample = "";
		for (_ in 0...callCount)
			matchedRenderSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(matched, scope);
		final matchedRenderElapsed = Sys.time() - matchedRenderStart;
		resetRendererCaches();
		final sideRenderStart = Sys.time();
		var sideRenderSample = "";
		for (_ in 0...callCount)
			sideRenderSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(matchedLeft, scope)
				+ "|"
				+ @:privateAccess backend.cpp.CppTargetCore.renderExpr(matchedRight, scope);
		final sideRenderElapsed = Sys.time() - sideRenderStart;
		resetRendererCaches();
		final matchedInferStart = Sys.time();
		var matchedInferSample = "";
		for (_ in 0...callCount)
			matchedInferSample = @:privateAccess backend.cpp.CppTargetCore.inferExprCppType(matched, scope);
		final matchedInferElapsed = Sys.time() - matchedInferStart;
		resetRendererCaches();
		final sideInferStart = Sys.time();
		var sideInferSample = "";
		for (_ in 0...callCount)
			sideInferSample = @:privateAccess backend.cpp.CppTargetCore.inferExprCppType(matchedLeft, scope)
				+ "|"
				+ @:privateAccess backend.cpp.CppTargetCore.inferExprCppType(matchedRight, scope);
		final sideInferElapsed = Sys.time() - sideInferStart;
		resetRendererCaches();
		final matchedEqualityStart = Sys.time();
		var matchedEqualitySample = "";
		for (_ in 0...callCount)
			matchedEqualitySample = @:privateAccess backend.cpp.CppTargetCore.renderEqCallArgs([matched, EString("capture")], scope).join(", ");
		final matchedEqualityElapsed = Sys.time() - matchedEqualityStart;
		resetRendererCaches();
		final sideEqualityStart = Sys.time();
		var sideEqualitySample = "";
		for (_ in 0...callCount)
			sideEqualitySample = @:privateAccess backend.cpp.CppTargetCore.renderEqCallArgs([matchedLeft, EString("left")], scope).join(", ")
				+ "|"
				+ @:privateAccess backend.cpp.CppTargetCore.renderEqCallArgs([matchedRight, EString("right")], scope).join(", ");
		final sideEqualityElapsed = Sys.time() - sideEqualityStart;
		resetRendererCaches();
		final genericArgsStart = Sys.time();
		var genericArgsSample = "";
		for (_ in 0...callCount)
			genericArgsSample = @:privateAccess
				backend.cpp.CppTargetCore.renderFieldCallArgs("std::shared_ptr<EReg>", "matched", matchedArgs, scope).join(", ");
		final genericArgsElapsed = Sys.time() - genericArgsStart;
		resetRendererCaches();
		final intArgStart = Sys.time();
		var intArgSample = "";
		for (_ in 0...callCount)
			intArgSample = @:privateAccess backend.cpp.CppTargetCore.eRegIntCallArgExpr(matchedArgs[0], false, scope);
		return {
			calls: callCount,
			matchedRenderElapsed: matchedRenderElapsed,
			sideRenderElapsed: sideRenderElapsed,
			matchedInferElapsed: matchedInferElapsed,
			sideInferElapsed: sideInferElapsed,
			matchedEqualityElapsed: matchedEqualityElapsed,
			sideEqualityElapsed: sideEqualityElapsed,
			genericArgsElapsed: genericArgsElapsed,
			intArgElapsed: Sys.time() - intArgStart,
			matchedRenderSample: matchedRenderSample,
			sideRenderSample: sideRenderSample,
			matchedInferSample: matchedInferSample,
			sideInferSample: sideInferSample,
			matchedEqualitySample: matchedEqualitySample,
			sideEqualitySample: sideEqualitySample,
			genericArgsSample: genericArgsSample,
			intArgSample: intArgSample,
			conversionSample: conversionSample,
			declineSample: declineSample
		};
	}

	/** Separate typed-local and fresh EReg match rendering from Bool inference and String argument discovery. **/
	static function renderERegMatchPhases(callCount:Int):ERegMatchPhaseBenchResult {
		final scope = eRegBenchScope();
		for (name in ["regex", "text", "dynamicText", "number"])
			scope.localNames.set(name, name);
		scope.localTypes.set("regex", "std::shared_ptr<EReg>");
		scope.localTypes.set("text", "std::string");
		scope.localTypes.set("dynamicText", "std::any");
		scope.localTypes.set("number", "int");
		final args = [EString("aa")];
		final fresh = ENew("EReg", [EString("a+"), EString("")]);
		final qualifiedFresh = ENew("fixture.regex.EReg", [EString("a+"), EString("")]);
		final typedCall = ECall(EField(EIdent("regex"), "match"), args);
		final freshCall = ECall(EField(fresh, "match"), args);
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.isTypedLocalERegMatchCall(EIdent("regex"), "match", 1,
			scope) && @:privateAccess backend.cpp.CppTargetCore.isFreshERegMatchCall(fresh, "match",
				1) && @:privateAccess backend.cpp.CppTargetCore.isFreshERegMatchCall(qualifiedFresh, "match", 1),
			"Typed-local and package-qualified fresh EReg match calls should use only the exact target-owned contract");
		assertTrue(! @:privateAccess backend.cpp.CppTargetCore.isTypedLocalERegMatchCall(EIdent("unknown"), "match", 1, scope)
			&& ! @:privateAccess backend.cpp.CppTargetCore.isTypedLocalERegMatchCall(EIdent("regex"), "match", 0, scope)
			&& ! @:privateAccess backend.cpp.CppTargetCore.isFreshERegMatchCall(fresh, "match", 2)
			&& ! @:privateAccess backend.cpp.CppTargetCore.isFreshERegMatchCall(fresh, "split", 1),
			"Unknown receivers, wrong arities, and unrelated fresh methods should retain general EReg discovery");
		final conversionSample = [@:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("regex"), "match"), [EIdent("text")]), scope), @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("regex"), "match"), [EIdent("dynamicText")]), scope), @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ECall(EField(fresh, "match"), [EIdent("number")]), scope)
		].join("\n");
		final declineSample = [@:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("unknown"), "match"), args), scope), @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("regex"), "match"), []), scope), @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ECall(EField(fresh, "match"), [EString("a"), EString("b")]), scope), @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ECall(EField(fresh, "split"), args), scope)
		].join("\n");
		resetRendererCaches();
		final typedRenderStart = Sys.time();
		var typedRenderSample = "";
		for (_ in 0...callCount)
			typedRenderSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(typedCall, scope);
		final typedRenderElapsed = Sys.time() - typedRenderStart;
		resetRendererCaches();
		final freshRenderStart = Sys.time();
		var freshRenderSample = "";
		for (_ in 0...callCount)
			freshRenderSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(freshCall, scope);
		final freshRenderElapsed = Sys.time() - freshRenderStart;
		resetRendererCaches();
		final typedInferStart = Sys.time();
		var typedInferSample = "";
		for (_ in 0...callCount)
			typedInferSample = @:privateAccess backend.cpp.CppTargetCore.inferExprCppType(typedCall, scope);
		final typedInferElapsed = Sys.time() - typedInferStart;
		resetRendererCaches();
		final freshInferStart = Sys.time();
		var freshInferSample = "";
		for (_ in 0...callCount)
			freshInferSample = @:privateAccess backend.cpp.CppTargetCore.inferExprCppType(freshCall, scope);
		final freshInferElapsed = Sys.time() - freshInferStart;
		resetRendererCaches();
		final typedBoolStart = Sys.time();
		var typedBoolSample = "";
		for (_ in 0...callCount)
			typedBoolSample = @:privateAccess backend.cpp.CppTargetCore.functionTypeArgExpr(typedCall, "bool", scope);
		final typedBoolElapsed = Sys.time() - typedBoolStart;
		resetRendererCaches();
		final freshBoolStart = Sys.time();
		var freshBoolSample = "";
		for (_ in 0...callCount)
			freshBoolSample = @:privateAccess backend.cpp.CppTargetCore.functionTypeArgExpr(freshCall, "bool", scope);
		final freshBoolElapsed = Sys.time() - freshBoolStart;
		resetRendererCaches();
		final constructorStart = Sys.time();
		var constructorSample = "";
		for (_ in 0...callCount)
			constructorSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(fresh, scope);
		final constructorElapsed = Sys.time() - constructorStart;
		resetRendererCaches();
		final stringArgStart = Sys.time();
		var stringArgSample = "";
		for (_ in 0...callCount)
			stringArgSample = @:privateAccess backend.cpp.CppTargetCore.eRegStringCallArgExpr(args[0], scope);
		final stringArgElapsed = Sys.time() - stringArgStart;
		resetRendererCaches();
		final genericArgsStart = Sys.time();
		var genericArgsSample = "";
		for (_ in 0...callCount)
			genericArgsSample = @:privateAccess backend.cpp.CppTargetCore.renderFieldCallArgs("std::shared_ptr<EReg>", "match", args, scope).join(", ");
		return {
			calls: callCount,
			typedRenderElapsed: typedRenderElapsed,
			freshRenderElapsed: freshRenderElapsed,
			typedInferElapsed: typedInferElapsed,
			freshInferElapsed: freshInferElapsed,
			typedBoolElapsed: typedBoolElapsed,
			freshBoolElapsed: freshBoolElapsed,
			constructorElapsed: constructorElapsed,
			stringArgElapsed: stringArgElapsed,
			genericArgsElapsed: Sys.time() - genericArgsStart,
			typedRenderSample: typedRenderSample,
			freshRenderSample: freshRenderSample,
			typedInferSample: typedInferSample,
			freshInferSample: freshInferSample,
			typedBoolSample: typedBoolSample,
			freshBoolSample: freshBoolSample,
			constructorSample: constructorSample,
			stringArgSample: stringArgSample,
			genericArgsSample: genericArgsSample,
			conversionSample: conversionSample,
			declineSample: declineSample
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
		final unary = EUnop(HxUnaryOperator.Negate, HxUnaryFixity.Prefix, EInt(1));
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
		scope.localNames.set("regex", "regex");
		scope.localTypes.set("regex", "std::shared_ptr<EReg>");
		scope.localNames.set("f", "f");
		scope.localTypes.set("f", expectedType);
		scope.localNames.set("text", "text");
		scope.localTypes.set("text", "std::string");
		scope.localNames.set("dynamicText", "dynamicText");
		scope.localTypes.set("dynamicText", "std::any");
		scope.localNames.set("number", "number");
		scope.localTypes.set("number", "int");
		scope.localNames.set("dynamicCallback", "dynamicCallback");
		scope.localTypes.set("dynamicCallback", "std::any");
		final typedInlineMap = ECall(EField(EIdent("regex"), "map"), mapArgs);
		final typedNamedArgs = [EString("aa"), EIdent("f")];
		final typedNamedMap = ECall(EField(EIdent("regex"), "map"), typedNamedArgs);
		final stringParam = new HxFunctionArg("s", "String", NoDefault, false, false);
		final callbackParam = new HxFunctionArg("f", "EReg->String", NoDefault, false, false);
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.isTypedLocalERegMapCall(EIdent("regex"), "map", 2, scope),
			"Typed-local EReg map calls should use the exact target-owned String/callback contract");
		assertTrue(! @:privateAccess backend.cpp.CppTargetCore.isTypedLocalERegMapCall(EIdent("unknown"), "map", 2, scope)
			&& ! @:privateAccess backend.cpp.CppTargetCore.isTypedLocalERegMapCall(EIdent("regex"), "map", 1, scope)
			&& ! @:privateAccess backend.cpp.CppTargetCore.isTypedLocalERegMapCall(EIdent("regex"), "replace", 2, scope),
			"Unknown receivers, wrong arity, and other EReg methods should retain general field-call rendering");
		final unknownMapSample = @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("unknown"), "map"), typedNamedArgs), scope);
		final wrongAritySample = @:privateAccess
			backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("regex"), "map"), [EString("aa")]), scope);
		final otherMethodSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("regex"), "replace"),
			[EString("aa"), EString("x")]), scope);
		assertTrue(unknownMapSample == 'unknown.map("aa", f)'
			&& wrongAritySample == 'regex->map("aa")'
			&& otherMethodSample == 'regex->replace("aa", "x")',
			"Declined EReg map shapes should preserve general field-call output");
		final typedStringMapSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("regex"), "map"),
			[EIdent("text"), EIdent("f")]), scope);
		final dynamicStringMapSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("regex"), "map"),
			[EIdent("dynamicText"), EIdent("f")]), scope);
		final scalarStringMapSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(ECall(EField(EIdent("regex"), "map"),
			[EIdent("number"), EIdent("f")]), scope);
		assertTrue(typedStringMapSample == "regex->map(text, f)"
			&& dynamicStringMapSample == "regex->map(__hxhx_stringify(dynamicText), f)"
			&& scalarStringMapSample == "regex->map(std::to_string(number), f)",
			"Typed-local EReg map should retain typed, erased, and scalar String argument adaptation");
		final dynamicCallback = EIdent("dynamicCallback");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.eRegMapCallbackArgExpr(dynamicCallback, scope) == @:privateAccess
			backend.cpp.CppTargetCore.valueExprForExpectedType(dynamicCallback, expectedType, scope),
			"Callbacks without the exact function type should retain general expected-value adaptation");
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
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.directIsolatedERegStringCallbackBodyExpr(matchedLeft, ["r"], ["std::shared_ptr<EReg>"],
			"std::string", scope) == "r->matchedLeft()"
			&& @:privateAccess backend.cpp.CppTargetCore.directIsolatedERegStringCallbackBodyExpr(matched, ["r"], ["std::shared_ptr<EReg>"], "std::string",
				scope) == "r->matched(0).value_or(std::string())"
			&& @:privateAccess backend.cpp.CppTargetCore.directIsolatedERegStringCallbackBodyExpr(ECall(EField(EIdent("r"), "matched"), [EIdent("number")]),
				["r"], ["std::shared_ptr<EReg>"], "std::string", scope) == null
			&& @:privateAccess backend.cpp.CppTargetCore.directIsolatedERegStringCallbackBodyExpr(ECall(EField(EIdent("other"), "matchedLeft"), []), ["r"],
				["std::shared_ptr<EReg>"], "std::string", scope) == null,
			"Scope-isolated EReg callback returns should accept exact capture leaves and decline dynamic indices or other receivers");
		final shadowScope = eRegBenchScope();
		shadowScope.localNames.set("r", "outer_r");
		shadowScope.localTypes.set("r", "std::string");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.lambdaExprForExpectedFunction(["r"], nestedBody, expectedType,
			shadowScope) == '[&](std::shared_ptr<EReg> r) -> std::string { return (std::string("match:") + r->matched(2).value().substr(3)); }' && shadowScope.localNames.get("r") == "outer_r" && shadowScope.localTypes.get("r") == "std::string",
			"Scope-isolated EReg callbacks should use the lambda argument and preserve an outer same-name local");
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
		final typedInlineMapStart = Sys.time();
		var typedInlineMapSample = "";
		for (_ in 0...callCount)
			typedInlineMapSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(typedInlineMap, scope);
		final typedInlineMapElapsed = Sys.time() - typedInlineMapStart;
		resetRendererCaches();
		final typedNamedMapStart = Sys.time();
		var typedNamedMapSample = "";
		for (_ in 0...callCount)
			typedNamedMapSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(typedNamedMap, scope);
		final typedNamedMapElapsed = Sys.time() - typedNamedMapStart;
		resetRendererCaches();
		final typedInferStart = Sys.time();
		var typedInferSample = "";
		for (_ in 0...callCount)
			typedInferSample = @:privateAccess backend.cpp.CppTargetCore.inferExprCppType(typedInlineMap, scope);
		final typedInferElapsed = Sys.time() - typedInferStart;
		resetRendererCaches();
		final typedKnownReturnStart = Sys.time();
		var typedKnownReturnSample = "";
		for (_ in 0...callCount)
			typedKnownReturnSample = @:privateAccess backend.cpp.CppTargetCore.knownFieldCallReturnCppType(EIdent("regex"), "map", mapArgs, scope);
		final typedKnownReturnElapsed = Sys.time() - typedKnownReturnStart;
		resetRendererCaches();
		final typedInstanceReturnStart = Sys.time();
		var typedInstanceReturnSample = "";
		for (_ in 0...callCount)
			typedInstanceReturnSample = @:privateAccess backend.cpp.CppTargetCore.classMethodCppReturnType("EReg", "map", false, scope);
		final typedInstanceReturnElapsed = Sys.time() - typedInstanceReturnStart;
		resetRendererCaches();
		final typedInlineEqStart = Sys.time();
		var typedInlineEqSample = "";
		for (_ in 0...callCount)
			typedInlineEqSample = @:privateAccess backend.cpp.CppTargetCore.eqComparableArgExpr(typedInlineMap, "std::string", "std::string", scope);
		final typedInlineEqElapsed = Sys.time() - typedInlineEqStart;
		resetRendererCaches();
		final typedNamedEqStart = Sys.time();
		var typedNamedEqSample = "";
		for (_ in 0...callCount)
			typedNamedEqSample = @:privateAccess backend.cpp.CppTargetCore.eqComparableArgExpr(typedNamedMap, "std::string", "std::string", scope);
		final typedNamedEqElapsed = Sys.time() - typedNamedEqStart;
		resetRendererCaches();
		final typedInlineArgsStart = Sys.time();
		var typedInlineArgsSample = "";
		for (_ in 0...callCount)
			typedInlineArgsSample = @:privateAccess
				backend.cpp.CppTargetCore.renderFieldCallArgs("std::shared_ptr<EReg>", "map", mapArgs, scope).join(", ");
		final typedInlineArgsElapsed = Sys.time() - typedInlineArgsStart;
		resetRendererCaches();
		final typedNamedArgsStart = Sys.time();
		var typedNamedArgsSample = "";
		for (_ in 0...callCount)
			typedNamedArgsSample = @:privateAccess
				backend.cpp.CppTargetCore.renderFieldCallArgs("std::shared_ptr<EReg>", "map", typedNamedArgs, scope).join(", ");
		final typedNamedArgsElapsed = Sys.time() - typedNamedArgsStart;
		resetRendererCaches();
		final typedStringArgStart = Sys.time();
		var typedStringArgSample = "";
		for (_ in 0...callCount)
			typedStringArgSample = @:privateAccess backend.cpp.CppTargetCore.callArgExprForParam(EString("aa"), stringParam, scope, "std::string");
		final typedStringArgElapsed = Sys.time() - typedStringArgStart;
		resetRendererCaches();
		final typedInlineCallbackStart = Sys.time();
		var typedInlineCallbackSample = "";
		for (_ in 0...callCount)
			typedInlineCallbackSample = @:privateAccess
				backend.cpp.CppTargetCore.callArgExprForParam(nestedCallback, callbackParam, scope, expectedType);
		final typedInlineCallbackElapsed = Sys.time() - typedInlineCallbackStart;
		resetRendererCaches();
		final typedNamedCallbackStart = Sys.time();
		var typedNamedCallbackSample = "";
		for (_ in 0...callCount)
			typedNamedCallbackSample = @:privateAccess
				backend.cpp.CppTargetCore.callArgExprForParam(EIdent("f"), callbackParam, scope, expectedType);
		final typedNamedCallbackElapsed = Sys.time() - typedNamedCallbackStart;
		resetRendererCaches();
		final typedReceiverTypeStart = Sys.time();
		var typedReceiverTypeSample = "";
		for (_ in 0...callCount)
			typedReceiverTypeSample = @:privateAccess backend.cpp.CppTargetCore.exprCppType(EIdent("regex"), scope);
		final typedReceiverTypeElapsed = Sys.time() - typedReceiverTypeStart;
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
		final isolatedBodyStart = Sys.time();
		var isolatedBodySample = "";
		for (_ in 0...callCount) {
			final rendered = @:privateAccess
				backend.cpp.CppTargetCore.directIsolatedERegStringCallbackBodyExpr(nestedBody, ["r"], ["std::shared_ptr<EReg>"], "std::string", scope);
			isolatedBodySample = rendered == null ? "" : rendered;
		}
		final isolatedBodyElapsed = Sys.time() - isolatedBodyStart;
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
			typedInlineMapElapsed: typedInlineMapElapsed,
			typedNamedMapElapsed: typedNamedMapElapsed,
			typedInferElapsed: typedInferElapsed,
			typedKnownReturnElapsed: typedKnownReturnElapsed,
			typedInstanceReturnElapsed: typedInstanceReturnElapsed,
			typedInlineEqElapsed: typedInlineEqElapsed,
			typedNamedEqElapsed: typedNamedEqElapsed,
			typedInlineArgsElapsed: typedInlineArgsElapsed,
			typedNamedArgsElapsed: typedNamedArgsElapsed,
			typedStringArgElapsed: typedStringArgElapsed,
			typedInlineCallbackElapsed: typedInlineCallbackElapsed,
			typedNamedCallbackElapsed: typedNamedCallbackElapsed,
			typedReceiverTypeElapsed: typedReceiverTypeElapsed,
			expectedFunctionElapsed: expectedFunctionElapsed,
			identityPreflightElapsed: identityPreflightElapsed,
			boundPreflightElapsed: boundPreflightElapsed,
			varArgsPreflightElapsed: varArgsPreflightElapsed,
			lambdaElapsed: lambdaElapsed,
			nestedLambdaElapsed: nestedLambdaElapsed,
			directBodyElapsed: directBodyElapsed,
			nestedBodyElapsed: nestedBodyElapsed,
			isolatedBodyElapsed: isolatedBodyElapsed,
			leafElapsed: leafElapsed,
			nestedLeafElapsed: nestedLeafElapsed,
			bodyElapsed: bodyElapsed,
			stringElapsed: stringElapsed,
			renderElapsed: renderElapsed,
			inferElapsed: Sys.time() - inferStart,
			mapSample: mapSample,
			argsSample: argsSample,
			typedInlineMapSample: typedInlineMapSample,
			typedNamedMapSample: typedNamedMapSample,
			typedInferSample: typedInferSample,
			typedKnownReturnSample: typedKnownReturnSample,
			typedInstanceReturnSample: typedInstanceReturnSample,
			typedInlineEqSample: typedInlineEqSample,
			typedNamedEqSample: typedNamedEqSample,
			typedInlineArgsSample: typedInlineArgsSample,
			typedNamedArgsSample: typedNamedArgsSample,
			typedStringArgSample: typedStringArgSample,
			typedInlineCallbackSample: typedInlineCallbackSample,
			typedNamedCallbackSample: typedNamedCallbackSample,
			typedReceiverTypeSample: typedReceiverTypeSample,
			expectedFunctionSample: expectedFunctionSample,
			lambdaSample: lambdaSample,
			nestedLambdaSample: nestedLambdaSample,
			directBodySample: directBodySample,
			nestedBodySample: nestedBodySample,
			isolatedBodySample: isolatedBodySample,
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

	static function assertStructuredUnaryEmission():Void {
		final prefix = EUnop(HxUnaryOperator.Increment, HxUnaryFixity.Prefix, EIdent("value"));
		final postfix = EUnop(HxUnaryOperator.Increment, HxUnaryFixity.Postfix, EIdent("value"));
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.renderExpr(prefix) == "(++value)", "C++ prefix increment should preserve prefix placement");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.renderExpr(postfix) == "(value++)", "C++ postfix increment should preserve postfix placement");

		final prefixMacro = backend.cpp.CppMacroExpr.macroExpr(prefix, []);
		final postfixMacro = backend.cpp.CppMacroExpr.macroExpr(postfix, []);
		final nullSafeMacro = backend.cpp.CppMacroExpr.macroExpr(ENullSafeField(EIdent("value"), "field"), []);
		assertContains(prefixMacro, "__hxhx_macro_enum(\"OpIncrement\")", "C++ macro quote should use the public unary enum constructor");
		assertContains(prefixMacro, "__hxhx_macro_bool(false)", "C++ macro quote should preserve prefix fixity as postFix=false");
		assertContains(postfixMacro, "__hxhx_macro_bool(true)", "C++ macro quote should preserve postfix fixity as postFix=true");
		assertContains(nullSafeMacro, "__hxhx_macro_enum(\"Safe\")", "C++ macro quote should preserve null-safe field access");
	}

	static function main():Void {
		assertCallableArgOverridePolicy();
		assertStructuredUnaryEmission();
		assertCompileTimeMacroApiBodiesStayDeclarationOnly();
		final extraMethods = envInt("HXHX_CPP_HELPER_RENDER_BENCH_EXTRA_METHODS", DEFAULT_EXTRA_METHODS);
		final reps = envInt("HXHX_CPP_HELPER_RENDER_BENCH_REPS", DEFAULT_REPS);
		final primitiveArgCalls = envInt("HXHX_CPP_PRIMITIVE_ARG_BENCH_CALLS", DEFAULT_PRIMITIVE_ARG_CALLS);
		final negativePrimitiveArgCalls = envInt("HXHX_CPP_NEGATIVE_PRIMITIVE_ARG_BENCH_CALLS", DEFAULT_NEGATIVE_PRIMITIVE_ARG_CALLS);
		final bytesReferenceCalls = envInt("HXHX_CPP_BYTES_REFERENCE_BENCH_CALLS", DEFAULT_BYTES_REFERENCE_CALLS);
		final bytesStringArgCalls = envInt("HXHX_CPP_BYTES_STRING_ARG_BENCH_CALLS", DEFAULT_BYTES_STRING_ARG_CALLS);
		final freshERegReturnCalls = envInt("HXHX_CPP_FRESH_EREG_RETURN_BENCH_CALLS", DEFAULT_FRESH_EREG_RETURN_CALLS);
		final freshERegFieldCalls = envInt("HXHX_CPP_FRESH_EREG_FIELD_CALL_BENCH_CALLS", DEFAULT_FRESH_EREG_FIELD_CALLS);
		final freshERegMapReplaceCalls = envInt("HXHX_CPP_FRESH_EREG_MAP_REPLACE_BENCH_CALLS", DEFAULT_FRESH_EREG_MAP_REPLACE_CALLS);
		final freshERegLocalDeclCalls = envInt("HXHX_CPP_FRESH_EREG_LOCAL_DECL_BENCH_CALLS", DEFAULT_FRESH_EREG_LOCAL_DECL_CALLS);
		final typedERegSplitCalls = envInt("HXHX_CPP_TYPED_EREG_SPLIT_BENCH_CALLS", DEFAULT_TYPED_EREG_SPLIT_CALLS);
		final typedERegMatchedPosCalls = envInt("HXHX_CPP_TYPED_EREG_MATCHED_POS_BENCH_CALLS", DEFAULT_TYPED_EREG_MATCHED_POS_CALLS);
		final typedERegMatchSubCalls = envInt("HXHX_CPP_TYPED_EREG_MATCH_SUB_BENCH_CALLS", DEFAULT_TYPED_EREG_MATCH_SUB_CALLS);
		final typedERegMatchedStringCalls = envInt("HXHX_CPP_TYPED_EREG_MATCHED_STRING_BENCH_CALLS", DEFAULT_TYPED_EREG_MATCHED_STRING_CALLS);
		final eRegMatchCalls = envInt("HXHX_CPP_EREG_MATCH_BENCH_CALLS", DEFAULT_EREG_MATCH_CALLS);
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
		final negativePrimitiveArgs = renderNegativePrimitiveCallArgPhases(negativePrimitiveArgCalls);
		assertTrue(negativePrimitiveArgs.fullSample == "(-1)"
			&& negativePrimitiveArgs.literalTypeSample == "int"
			&& negativePrimitiveArgs.directSample == "(-1)"
			&& negativePrimitiveArgs.positiveDirectSample == "1"
			&& negativePrimitiveArgs.negativeFloatSample == "(-1.5)"
			&& negativePrimitiveArgs.negativeFloatDirectSample == "(-1.5)"
			&& negativePrimitiveArgs.nonLiteralSample == "(-number)"
			&& negativePrimitiveArgs.nonLiteralDirectSample == null
			&& negativePrimitiveArgs.stringDirectSample == null
			&& negativePrimitiveArgs.dynamicDirectSample == null
			&& !negativePrimitiveArgs.primitiveGateSample,
			"Negative numeric arguments should preserve precedence while nonliteral unary and mismatched expected types remain generic");
		assertTrue(negativePrimitiveArgs.abstractGateSample && negativePrimitiveArgs.abstractSample == "(-1)",
			"Primitive-backed abstract parameters should retain their conversion gate and output");
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
		final freshERegMapReplacePhases = renderFreshERegMapReplacePhases(freshERegMapReplaceCalls);
		assertTrue(freshERegMapReplacePhases.mapInferSample == "std::string"
			&& freshERegMapReplacePhases.replaceInferSample == "std::string",
			"Fresh EReg map/replace inference should retain its known String results");
		final expectedFreshMap = 'std::make_shared<EReg>("z?", "g")->map("ab", [&](std::shared_ptr<EReg> r) -> std::string { return (std::string(prefix) + __hxhx_stringify(r->matched(0))); })';
		final expectedFreshReplace = 'std::make_shared<EReg>("z?", "g")->replace("baacaa", "X")';
		assertTrue(freshERegMapReplacePhases.mapRenderSample == expectedFreshMap
			&& freshERegMapReplacePhases.replaceRenderSample == expectedFreshReplace
			&& freshERegMapReplacePhases.mapEqualitySample == expectedFreshMap + ', std::string("mapped")'
			&& freshERegMapReplacePhases.replaceEqualitySample == expectedFreshReplace + ', std::string("replaced")',
			"Fresh EReg map/replace and equality phases should preserve exact generated output, got map="
			+ freshERegMapReplacePhases.mapRenderSample
			+ " replace="
			+ freshERegMapReplacePhases.replaceRenderSample
			+ " map_eq="
			+ freshERegMapReplacePhases.mapEqualitySample
			+ " replace_eq="
			+ freshERegMapReplacePhases.replaceEqualitySample);
		assertTrue(freshERegMapReplacePhases.stringArgSample == '"ab"'
			&& freshERegMapReplacePhases.genericMapArgsSample == freshERegMapReplacePhases.stringArgSample + ", " + freshERegMapReplacePhases.callbackArgSample
			&& freshERegMapReplacePhases.genericReplaceArgsSample == '"baacaa", "X"',
			"Fresh EReg focused phases should preserve exact String, callback, and retained generic-argument output");
		assertTrue(freshERegMapReplacePhases.conversionSample == 'std::make_shared<EReg>("z?", "g")->replace(typedText, replacement)\n'
			+ 'std::make_shared<EReg>("z?", "g")->replace(__hxhx_stringify(dynamicText), replacement)\n'
			+ 'std::make_shared<EReg>("z?", "g")->replace(std::to_string(number), replacement)\n'
			+ 'std::make_shared<EReg>("z?", "g")->map(typedText, callback)',
			"Fresh EReg map/replace should preserve typed, erased, and scalar String conversion plus named callbacks, got "
			+ freshERegMapReplacePhases.conversionSample);
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
			&& typedERegSplitPhases.concatSample == '((std::string("parts:") + __hxhx_join(block->split("a"), std::string("|"))) + std::string(":done"))'
			&& typedERegSplitPhases.concatStringSample == typedERegSplitPhases.concatSample
			&& typedERegSplitPhases.concatEqArgSample == typedERegSplitPhases.concatSample
			&& typedERegSplitPhases.concatLeftStringSample == '(std::string("parts:") + __hxhx_join(block->split("a"), std::string("|")))'
			&& typedERegSplitPhases.concatRightStringSample == 'std::string(":done")'
			&& typedERegSplitPhases.concatEqSample == 'eq(((std::string("parts:") + __hxhx_join(block->split("a"), std::string("|"))) + std::string(":done")), std::string("parts:a|b"))',
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
		assertTrue(!typedERegSplitPhases.concatAnyAddSample
			&& typedERegSplitPhases.concatStringSelectSample
			&& !typedERegSplitPhases.concatPrimitiveAbstractSample
			&& !typedERegSplitPhases.concatClassAbstractSample
			&& typedERegSplitPhases.concatExplicitTypeSample == "std::string"
			&& !typedERegSplitPhases.concatClassMetadataSample
			&& typedERegSplitPhases.concatInferSample == "std::string",
			"The exact typed-local EReg split concatenation should expose its String type while unrelated Any, abstract, and class preflights decline, got anyAdd="
			+ typedERegSplitPhases.concatAnyAddSample
			+ " stringSelect="
			+ typedERegSplitPhases.concatStringSelectSample
			+ " primitiveAbstract="
			+ typedERegSplitPhases.concatPrimitiveAbstractSample
			+ " classAbstract="
			+ typedERegSplitPhases.concatClassAbstractSample
			+ " explicitType="
			+ typedERegSplitPhases.concatExplicitTypeSample
			+ " classMetadata="
			+ typedERegSplitPhases.concatClassMetadataSample
			+ " infer="
			+ typedERegSplitPhases.concatInferSample);
		final typedERegMatchedPosPhases = renderTypedERegMatchedPosPhases(typedERegMatchedPosCalls);
		assertTrue(typedERegMatchedPosPhases.posSample == "(r->matchedPos().pos)"
			&& typedERegMatchedPosPhases.lenSample == "(r->matchedPos().len)"
			&& typedERegMatchedPosPhases.eqArgSample == typedERegMatchedPosPhases.posSample,
			"Typed-local EReg matched-position fields and equality adaptation should preserve exact output, got pos="
			+ typedERegMatchedPosPhases.posSample
			+ " len="
			+ typedERegMatchedPosPhases.lenSample
			+ " eq="
			+ typedERegMatchedPosPhases.eqArgSample);
		assertTrue(typedERegMatchedPosPhases.inferSample == "int"
			&& typedERegMatchedPosPhases.callRenderSample == "r->matchedPos()"
			&& typedERegMatchedPosPhases.callInferSample == "__hxhx_anon_pos_int__len_int_"
			&& typedERegMatchedPosPhases.callExplicitTypeSample == typedERegMatchedPosPhases.callInferSample
			&& typedERegMatchedPosPhases.fieldAccessSample == "."
			&& typedERegMatchedPosPhases.fieldTypeSample == "int",
			"Typed-local EReg matchedPos should retain its target-owned structural return and Int fields");
		assertTrue(!typedERegMatchedPosPhases.primitiveSample
			&& !typedERegMatchedPosPhases.methodValueSample
			&& !typedERegMatchedPosPhases.referenceSample
			&& !typedERegMatchedPosPhases.classPreflightSample
			&& !typedERegMatchedPosPhases.propertySample
			&& !typedERegMatchedPosPhases.jsonSample,
			"Typed-local EReg matched-position field reads should decline unrelated abstract, method, reference, class, property, and JSON preflights");
		final typedERegMatchSubPhases = renderTypedERegMatchSubPhases(typedERegMatchSubCalls);
		assertTrue(typedERegMatchSubPhases.twoRenderSample == 'regex->matchSub("aa12", 1)'
			&& typedERegMatchSubPhases.threeRenderSample == 'regex->matchSub("aa12", 1, 2)'
			&& typedERegMatchSubPhases.twoExpectedBoolSample == typedERegMatchSubPhases.twoRenderSample
			&& typedERegMatchSubPhases.threeExpectedBoolSample == typedERegMatchSubPhases.threeRenderSample,
			"Typed-local EReg matchSub calls and Bool-expected outer arguments should preserve omitted and explicit length output");
		assertTrue(typedERegMatchSubPhases.twoInferSample == "bool"
			&& typedERegMatchSubPhases.threeInferSample == "bool"
			&& typedERegMatchSubPhases.knownReturnSample == "bool"
			&& typedERegMatchSubPhases.instanceReturnSample == "bool"
			&& typedERegMatchSubPhases.receiverTypeSample == "std::shared_ptr<EReg>",
			"Typed-local EReg matchSub inference should retain its Bool result and EReg receiver carrier, got two="
			+ typedERegMatchSubPhases.twoInferSample
			+ " three="
			+ typedERegMatchSubPhases.threeInferSample
			+ " known="
			+ typedERegMatchSubPhases.knownReturnSample
			+ " instance="
			+ typedERegMatchSubPhases.instanceReturnSample
			+ " receiver="
			+ typedERegMatchSubPhases.receiverTypeSample);
		assertTrue(typedERegMatchSubPhases.twoArgsSample == '"aa12", 1'
			&& typedERegMatchSubPhases.threeArgsSample == '"aa12", 1, 2'
			&& typedERegMatchSubPhases.twoInstanceArgsSample == typedERegMatchSubPhases.twoArgsSample
			&& typedERegMatchSubPhases.threeInstanceArgsSample == typedERegMatchSubPhases.threeArgsSample
			&& typedERegMatchSubPhases.stringArgSample == '"aa12"'
			&& typedERegMatchSubPhases.posArgSample == "1"
			&& typedERegMatchSubPhases.optionalMatchSample
			&& typedERegMatchSubPhases.lenArgSample == "2",
			"Typed-local EReg matchSub argument phases should retain String, position, and optional-length contracts");
		final typedERegMatchedStringPhases = renderTypedERegMatchedStringPhases(typedERegMatchedStringCalls);
		assertTrue(typedERegMatchedStringPhases.matchedRenderSample == "regex->matched(1)"
			&& typedERegMatchedStringPhases.sideRenderSample == "regex->matchedLeft()|regex->matchedRight()"
			&& typedERegMatchedStringPhases.matchedInferSample == "std::optional<std::string>"
			&& typedERegMatchedStringPhases.sideInferSample == "std::string|std::string",
			"Typed-local EReg matched calls should preserve nullable indexed and non-nullable side-capture shapes");
		assertTrue(typedERegMatchedStringPhases.matchedEqualitySample == 'regex->matched(1), std::string("capture")'
			&& typedERegMatchedStringPhases.sideEqualitySample == 'regex->matchedLeft(), std::string("left")|regex->matchedRight(), std::string("right")',
			"Typed-local EReg matched calls should preserve exact String equality arguments");
		assertTrue(typedERegMatchedStringPhases.genericArgsSample == "1"
			&& typedERegMatchedStringPhases.intArgSample == "1"
			&& typedERegMatchedStringPhases.conversionSample == "regex->matched(index)\nregex->matched(static_cast<int>(__hxhx_any_double(dynamicIndex)))\nregex->matched((-1))",
			"Typed-local EReg matched index adaptation should preserve typed, erased, and negative Int values");
		assertTrue(typedERegMatchedStringPhases.declineSample == "unknown.matched(1)\nregex->matched()\nregex->matched(0, 1)\nregex->matchedLeft(0)\nregex->match(\"a\")",
			"Unknown receivers, wrong arities, and unrelated EReg methods should retain general call rendering");
		final eRegMatchPhases = renderERegMatchPhases(eRegMatchCalls);
		assertTrue(eRegMatchPhases.typedRenderSample == 'regex->match("aa")'
			&& eRegMatchPhases.freshRenderSample == 'std::make_shared<EReg>("a+", "")->match("aa")'
			&& eRegMatchPhases.typedInferSample == "bool"
			&& eRegMatchPhases.freshInferSample == "bool"
			&& eRegMatchPhases.typedBoolSample == eRegMatchPhases.typedRenderSample
			&& eRegMatchPhases.freshBoolSample == eRegMatchPhases.freshRenderSample,
			"Typed-local and fresh EReg match calls should preserve exact Bool call shapes");
		assertTrue(eRegMatchPhases.constructorSample == 'std::make_shared<EReg>("a+", "")'
			&& eRegMatchPhases.stringArgSample == '"aa"'
			&& eRegMatchPhases.genericArgsSample == '"aa"',
			"EReg match phases should preserve constructor and String argument output");
		assertTrue(eRegMatchPhases.conversionSample == "regex->match(text)\nregex->match(__hxhx_stringify(dynamicText))\nstd::make_shared<EReg>(\"a+\", \"\")->match(std::to_string(number))",
			"Typed-local and fresh EReg match should preserve typed, erased, and scalar String conversion");
		assertTrue(eRegMatchPhases.declineSample == "unknown.match(\"aa\")\nregex->match()\nstd::make_shared<EReg>(\"a+\", \"\")->match(\"a\", \"b\")\nstd::make_shared<EReg>(\"a+\", \"\")->split(\"aa\")",
			"Unknown receivers, wrong arities, and unrelated fresh EReg methods should retain general rendering");
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
		assertTrue(eRegLambdaPhases.lambdaSample == '[&](std::shared_ptr<EReg> r) -> std::string { return (((std::string("[") + r->matchedLeft()) + __hxhx_stringify(r->matched(0))) + r->matchedRight()); }',
			"EReg.map callback fixtures should keep their typed callback and concatenation shape");
		assertTrue(eRegLambdaPhases.mapSample == 'std::make_shared<EReg>("a+", "g")->map("aa", ' + eRegLambdaPhases.nestedLambdaSample + ')'
			&& eRegLambdaPhases.argsSample == '"aa", ' + eRegLambdaPhases.nestedLambdaSample,
			"Fresh EReg.map fixtures should preserve their exact target-owned call and callback argument shapes");
		assertTrue(eRegLambdaPhases.typedInlineMapSample == 'regex->map("aa", ' + eRegLambdaPhases.nestedLambdaSample + ')'
			&& eRegLambdaPhases.typedInlineEqSample == eRegLambdaPhases.typedInlineMapSample
			&& eRegLambdaPhases.typedNamedMapSample == 'regex->map("aa", f)'
			&& eRegLambdaPhases.typedNamedEqSample == eRegLambdaPhases.typedNamedMapSample,
			"Typed-local EReg.map calls and String equality adaptation should preserve inline and named callback output");
		assertTrue(eRegLambdaPhases.typedInferSample == "std::string"
			&& eRegLambdaPhases.typedKnownReturnSample == "std::string"
			&& eRegLambdaPhases.typedInstanceReturnSample == "std::string"
			&& eRegLambdaPhases.typedReceiverTypeSample == "std::shared_ptr<EReg>",
			"Typed-local EReg.map inference should retain its target-owned String result and EReg receiver carrier, got infer="
			+ eRegLambdaPhases.typedInferSample
			+ " known="
			+ eRegLambdaPhases.typedKnownReturnSample
			+ " instance="
			+ eRegLambdaPhases.typedInstanceReturnSample
			+ " receiver="
			+ eRegLambdaPhases.typedReceiverTypeSample);
		assertTrue(eRegLambdaPhases.typedInlineArgsSample == '"aa", ' + eRegLambdaPhases.nestedLambdaSample
			&& eRegLambdaPhases.typedNamedArgsSample == '"aa", f'
			&& eRegLambdaPhases.typedStringArgSample == '"aa"'
			&& eRegLambdaPhases.typedInlineCallbackSample == eRegLambdaPhases.nestedLambdaSample
			&& eRegLambdaPhases.typedNamedCallbackSample == "f",
			"Typed-local EReg.map argument phases should retain String and callback contracts");
		assertTrue(eRegLambdaPhases.directBodySample == '(((std::string("[") + r->matchedLeft()) + __hxhx_stringify(r->matched(0))) + r->matchedRight())'
			&& eRegLambdaPhases.leafSample == 'r->matchedLeft()|r->matched(0)|r->matchedRight()',
			"EReg.map callback fixtures should preserve exact direct-body and target-owned leaf call shapes, got body="
			+ eRegLambdaPhases.directBodySample
			+ " leaves="
			+ eRegLambdaPhases.leafSample);
		assertContains(eRegLambdaPhases.nestedBodySample, "r->matched(2).value()",
			"EReg.map callback fixtures should preserve the callback-owned matched/substr chain");
		assertTrue(eRegLambdaPhases.nestedLeafSample == "r->matched(2).value().substr(3)"
			&& eRegLambdaPhases.nestedBodySample == '(std::string("match:") + r->matched(2).value().substr(3))'
			&& eRegLambdaPhases.isolatedBodySample == eRegLambdaPhases.nestedBodySample
			&& eRegLambdaPhases.nestedLambdaSample == '[&](std::shared_ptr<EReg> r) -> std::string { return (std::string("match:") + r->matched(2).value().substr(3)); }'
			&& eRegLambdaPhases.expectedFunctionSample == eRegLambdaPhases.nestedLambdaSample,
			"EReg.map callback fixtures should preserve exact nested matched/substr and lambda shapes");
		assertTrue(@:privateAccess
			backend.cpp.CppTargetCore.directERegStringCallbackConcatLeafExpr(ECall(EField(EIdent("r"), "matchedLeft"), []), "r",
				eRegBenchScope()) == "r->matchedLeft()",
			"Typed EReg callbacks should use the bounded target-owned matched leaf path");
		assertTrue(@:privateAccess
			backend.cpp.CppTargetCore.directERegStringCallbackConcatLeafExpr(ECall(EField(ECall(EField(EIdent("r"), "matched"), [EInt(2)]), "substr"),
				[EInt(3)]), "r",
				eRegBenchScope()) == "r->matched(2).value().substr(3)",
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
		assertTrue(@:privateAccess
			backend.cpp.CppTargetCore.directIsolatedERegStringCallbackBodyExpr(EBinop("+", EIdent("prefix"),
				ECall(EField(EIdent("r"), "matched"), [EInt(0)])), ["r"], ["std::shared_ptr<EReg>"], "std::string",
				eRegBenchScope()) == null,
			"Captured callback leaves should retain general lambda scope registration and restoration");
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
			+ " negative_primitive_arg_calls="
			+ negativePrimitiveArgs.calls
			+ " negative_primitive_arg_seconds="
			+ negativePrimitiveArgs.fullElapsed
			+ " negative_primitive_literal_type_seconds="
			+ negativePrimitiveArgs.literalTypeElapsed
			+ " negative_primitive_direct_seconds="
			+ negativePrimitiveArgs.directElapsed
			+ " negative_primitive_declared_type_seconds="
			+ negativePrimitiveArgs.declaredTypeElapsed
			+ " negative_primitive_gate_seconds="
			+ negativePrimitiveArgs.primitiveGateElapsed
			+ " negative_primitive_abstract_probe_seconds="
			+ negativePrimitiveArgs.abstractProbeElapsed
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
			+ " fresh_ereg_map_replace_calls="
			+ freshERegMapReplacePhases.calls
			+ " fresh_ereg_map_render_seconds="
			+ freshERegMapReplacePhases.mapRenderElapsed
			+ " fresh_ereg_replace_render_seconds="
			+ freshERegMapReplacePhases.replaceRenderElapsed
			+ " fresh_ereg_map_infer_seconds="
			+ freshERegMapReplacePhases.mapInferElapsed
			+ " fresh_ereg_replace_infer_seconds="
			+ freshERegMapReplacePhases.replaceInferElapsed
			+ " fresh_ereg_map_equality_seconds="
			+ freshERegMapReplacePhases.mapEqualityElapsed
			+ " fresh_ereg_replace_equality_seconds="
			+ freshERegMapReplacePhases.replaceEqualityElapsed
			+ " fresh_ereg_map_replace_constructor_seconds="
			+ freshERegMapReplacePhases.constructorElapsed
			+ " fresh_ereg_map_replace_string_arg_seconds="
			+ freshERegMapReplacePhases.stringArgElapsed
			+ " fresh_ereg_map_callback_arg_seconds="
			+ freshERegMapReplacePhases.callbackArgElapsed
			+ " fresh_ereg_generic_map_args_seconds="
			+ freshERegMapReplacePhases.genericMapArgsElapsed
			+ " fresh_ereg_generic_replace_args_seconds="
			+ freshERegMapReplacePhases.genericReplaceArgsElapsed
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
			+ " typed_ereg_concat_render_seconds="
			+ typedERegSplitPhases.concatRenderElapsed
			+ " typed_ereg_concat_string_seconds="
			+ typedERegSplitPhases.concatStringElapsed
			+ " typed_ereg_concat_left_string_seconds="
			+ typedERegSplitPhases.concatLeftStringElapsed
			+ " typed_ereg_concat_right_string_seconds="
			+ typedERegSplitPhases.concatRightStringElapsed
			+ " typed_ereg_concat_eq_arg_seconds="
			+ typedERegSplitPhases.concatEqArgElapsed
			+ " typed_ereg_concat_any_add_seconds="
			+ typedERegSplitPhases.concatAnyAddElapsed
			+ " typed_ereg_concat_string_select_seconds="
			+ typedERegSplitPhases.concatStringSelectElapsed
			+ " typed_ereg_concat_primitive_abstract_seconds="
			+ typedERegSplitPhases.concatPrimitiveAbstractElapsed
			+ " typed_ereg_concat_class_abstract_seconds="
			+ typedERegSplitPhases.concatClassAbstractElapsed
			+ " typed_ereg_concat_explicit_type_seconds="
			+ typedERegSplitPhases.concatExplicitTypeElapsed
			+ " typed_ereg_concat_class_metadata_seconds="
			+ typedERegSplitPhases.concatClassMetadataElapsed
			+ " typed_ereg_concat_infer_seconds="
			+ typedERegSplitPhases.concatInferElapsed
			+ " typed_ereg_matched_pos_calls="
			+ typedERegMatchedPosPhases.calls
			+ " typed_ereg_matched_pos_render_seconds="
			+ typedERegMatchedPosPhases.renderElapsed
			+ " typed_ereg_matched_pos_infer_seconds="
			+ typedERegMatchedPosPhases.inferElapsed
			+ " typed_ereg_matched_pos_eq_arg_seconds="
			+ typedERegMatchedPosPhases.eqArgElapsed
			+ " typed_ereg_matched_pos_call_render_seconds="
			+ typedERegMatchedPosPhases.callRenderElapsed
			+ " typed_ereg_matched_pos_call_infer_seconds="
			+ typedERegMatchedPosPhases.callInferElapsed
			+ " typed_ereg_matched_pos_call_explicit_type_seconds="
			+ typedERegMatchedPosPhases.callExplicitTypeElapsed
			+ " typed_ereg_matched_pos_field_access_seconds="
			+ typedERegMatchedPosPhases.fieldAccessElapsed
			+ " typed_ereg_matched_pos_field_type_seconds="
			+ typedERegMatchedPosPhases.fieldTypeElapsed
			+ " typed_ereg_matched_pos_primitive_seconds="
			+ typedERegMatchedPosPhases.primitiveElapsed
			+ " typed_ereg_matched_pos_method_value_seconds="
			+ typedERegMatchedPosPhases.methodValueElapsed
			+ " typed_ereg_matched_pos_reference_seconds="
			+ typedERegMatchedPosPhases.referenceElapsed
			+ " typed_ereg_matched_pos_class_preflight_seconds="
			+ typedERegMatchedPosPhases.classPreflightElapsed
			+ " typed_ereg_matched_pos_property_seconds="
			+ typedERegMatchedPosPhases.propertyElapsed
			+ " typed_ereg_matched_pos_json_seconds="
			+ typedERegMatchedPosPhases.jsonElapsed
			+ " typed_ereg_match_sub_calls="
			+ typedERegMatchSubPhases.calls
			+ " typed_ereg_match_sub_two_render_seconds="
			+ typedERegMatchSubPhases.twoRenderElapsed
			+ " typed_ereg_match_sub_three_render_seconds="
			+ typedERegMatchSubPhases.threeRenderElapsed
			+ " typed_ereg_match_sub_two_infer_seconds="
			+ typedERegMatchSubPhases.twoInferElapsed
			+ " typed_ereg_match_sub_three_infer_seconds="
			+ typedERegMatchSubPhases.threeInferElapsed
			+ " typed_ereg_match_sub_two_args_seconds="
			+ typedERegMatchSubPhases.twoArgsElapsed
			+ " typed_ereg_match_sub_three_args_seconds="
			+ typedERegMatchSubPhases.threeArgsElapsed
			+ " typed_ereg_match_sub_two_instance_args_seconds="
			+ typedERegMatchSubPhases.twoInstanceArgsElapsed
			+ " typed_ereg_match_sub_three_instance_args_seconds="
			+ typedERegMatchSubPhases.threeInstanceArgsElapsed
			+ " typed_ereg_match_sub_two_expected_bool_seconds="
			+ typedERegMatchSubPhases.twoExpectedBoolElapsed
			+ " typed_ereg_match_sub_three_expected_bool_seconds="
			+ typedERegMatchSubPhases.threeExpectedBoolElapsed
			+ " typed_ereg_match_sub_known_return_seconds="
			+ typedERegMatchSubPhases.knownReturnElapsed
			+ " typed_ereg_match_sub_instance_return_seconds="
			+ typedERegMatchSubPhases.instanceReturnElapsed
			+ " typed_ereg_match_sub_receiver_type_seconds="
			+ typedERegMatchSubPhases.receiverTypeElapsed
			+ " typed_ereg_match_sub_string_arg_seconds="
			+ typedERegMatchSubPhases.stringArgElapsed
			+ " typed_ereg_match_sub_pos_arg_seconds="
			+ typedERegMatchSubPhases.posArgElapsed
			+ " typed_ereg_match_sub_optional_match_seconds="
			+ typedERegMatchSubPhases.optionalMatchElapsed
			+ " typed_ereg_match_sub_len_arg_seconds="
			+ typedERegMatchSubPhases.lenArgElapsed
			+ " typed_ereg_matched_string_calls="
			+ typedERegMatchedStringPhases.calls
			+ " typed_ereg_matched_render_seconds="
			+ typedERegMatchedStringPhases.matchedRenderElapsed
			+ " typed_ereg_matched_side_render_seconds="
			+ typedERegMatchedStringPhases.sideRenderElapsed
			+ " typed_ereg_matched_infer_seconds="
			+ typedERegMatchedStringPhases.matchedInferElapsed
			+ " typed_ereg_matched_side_infer_seconds="
			+ typedERegMatchedStringPhases.sideInferElapsed
			+ " typed_ereg_matched_equality_seconds="
			+ typedERegMatchedStringPhases.matchedEqualityElapsed
			+ " typed_ereg_matched_side_equality_seconds="
			+ typedERegMatchedStringPhases.sideEqualityElapsed
			+ " typed_ereg_matched_generic_args_seconds="
			+ typedERegMatchedStringPhases.genericArgsElapsed
			+ " typed_ereg_matched_int_arg_seconds="
			+ typedERegMatchedStringPhases.intArgElapsed
			+ " ereg_match_calls="
			+ eRegMatchPhases.calls
			+ " ereg_match_typed_render_seconds="
			+ eRegMatchPhases.typedRenderElapsed
			+ " ereg_match_fresh_render_seconds="
			+ eRegMatchPhases.freshRenderElapsed
			+ " ereg_match_typed_infer_seconds="
			+ eRegMatchPhases.typedInferElapsed
			+ " ereg_match_fresh_infer_seconds="
			+ eRegMatchPhases.freshInferElapsed
			+ " ereg_match_typed_bool_seconds="
			+ eRegMatchPhases.typedBoolElapsed
			+ " ereg_match_fresh_bool_seconds="
			+ eRegMatchPhases.freshBoolElapsed
			+ " ereg_match_constructor_seconds="
			+ eRegMatchPhases.constructorElapsed
			+ " ereg_match_string_arg_seconds="
			+ eRegMatchPhases.stringArgElapsed
			+ " ereg_match_generic_args_seconds="
			+ eRegMatchPhases.genericArgsElapsed
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
			+ " ereg_typed_inline_map_seconds="
			+ eRegLambdaPhases.typedInlineMapElapsed
			+ " ereg_typed_named_map_seconds="
			+ eRegLambdaPhases.typedNamedMapElapsed
			+ " ereg_typed_infer_seconds="
			+ eRegLambdaPhases.typedInferElapsed
			+ " ereg_typed_known_return_seconds="
			+ eRegLambdaPhases.typedKnownReturnElapsed
			+ " ereg_typed_instance_return_seconds="
			+ eRegLambdaPhases.typedInstanceReturnElapsed
			+ " ereg_typed_inline_eq_seconds="
			+ eRegLambdaPhases.typedInlineEqElapsed
			+ " ereg_typed_named_eq_seconds="
			+ eRegLambdaPhases.typedNamedEqElapsed
			+ " ereg_typed_inline_args_seconds="
			+ eRegLambdaPhases.typedInlineArgsElapsed
			+ " ereg_typed_named_args_seconds="
			+ eRegLambdaPhases.typedNamedArgsElapsed
			+ " ereg_typed_string_arg_seconds="
			+ eRegLambdaPhases.typedStringArgElapsed
			+ " ereg_typed_inline_callback_seconds="
			+ eRegLambdaPhases.typedInlineCallbackElapsed
			+ " ereg_typed_named_callback_seconds="
			+ eRegLambdaPhases.typedNamedCallbackElapsed
			+ " ereg_typed_receiver_type_seconds="
			+ eRegLambdaPhases.typedReceiverTypeElapsed
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
			+ " ereg_lambda_isolated_body_seconds="
			+ eRegLambdaPhases.isolatedBodyElapsed
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
