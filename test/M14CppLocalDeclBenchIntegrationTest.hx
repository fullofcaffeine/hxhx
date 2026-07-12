import HxExpr;
import HxStmt;
import haxe.ds.StringMap;

typedef CppLocalDeclFixture = {
	var scope:backend.cpp.CppRenderScope;
	var owner:HxClassDecl;
}

/**
	Focused attribution probe for C++ local-declaration rendering.

	Strict Cpp timing identifies explicit String literals, typed callbacks, and
	fresh EReg construction as stable statement hotspots. This probe separates
	declared-type discovery, initializer and constructor rendering, complete
	declarations, and buffered statement instrumentation while retaining controls
	that must continue through the general local-declaration pipeline.
**/
class M14CppLocalDeclBenchIntegrationTest {
	static inline final DEFAULT_CALLS = 250;

	static function assertTrue(cond:Bool, message:String):Void {
		if (!cond)
			throw message;
	}

	static function envInt(name:String, fallback:Int):Int {
		final raw = Sys.getEnv(name);
		if (raw == null || StringTools.trim(raw).length == 0)
			return fallback;
		final parsed = Std.parseInt(raw);
		return parsed == null || parsed <= 0 ? fallback : parsed;
	}

	static function fixture():CppLocalDeclFixture {
		final names = new StringMap<Bool>();
		final classes = new StringMap<HxClassDecl>();
		final all = new Array<HxClassDecl>();
		final stringAlias = new HxClassDecl("StringAlias", false, [], [], "", ["__hxhx_abstract", "__hxhx_abstract_underlying=String"]);
		final eReg = new HxClassDecl("EReg", false, [], []);
		final otherCallbackArg = new HxClassDecl("OtherCallbackArg", false, [], []);
		final owner = new HxClassDecl("LocalDeclBenchOwner", false, [], [new HxFieldDecl("value", Public, false, "String", null)]);
		for (cls in [stringAlias, eReg, otherCallbackArg, owner]) {
			final name = HxClassDecl.getName(cls);
			names.set(name, true);
			classes.set(name, cls);
			all.push(cls);
		}
		for (i in 0...280) {
			final cls = new HxClassDecl("LocalDeclDummy" + i, false, [], []);
			final name = HxClassDecl.getName(cls);
			names.set(name, true);
			classes.set(name, cls);
			all.push(cls);
		}
		return {
			scope: @:privateAccess backend.cpp.CppTargetCore.renderScope(owner, {names: names, byName: classes, all: all}, "void"),
			owner: owner
		};
	}

	static function elapsed(calls:Int, action:Void->Void):Float {
		final start = Sys.time();
		for (_ in 0...calls)
			action();
		return Sys.time() - start;
	}

	static function elapsedIndexed(calls:Int, action:Int->Void):Float {
		final start = Sys.time();
		for (i in 0...calls)
			action(i);
		return Sys.time() - start;
	}

	static function selectedBench(name:String):Bool {
		final only = Sys.getEnv("HXHX_CPP_LOCAL_DECL_BENCH_ONLY");
		return only == null || StringTools.trim(only).length == 0 || only == name;
	}

	static function elapsedNamed(name:String, calls:Int, action:Void->Void):Float {
		action();
		return selectedBench(name) ? elapsed(calls, action) : -1.;
	}

	static function elapsedIndexedNamed(name:String, calls:Int, action:Int->Void):Float {
		action(0);
		return selectedBench(name) ? elapsedIndexed(calls, i -> action(i + 1)) : -1.;
	}

	static function indexedBenchFixtureCount(name:String, calls:Int):Int {
		return selectedBench(name) ? calls + 1 : 1;
	}

	static function resetTimingCaches():Void {
		@:privateAccess backend.cpp.CppTargetCore.traceCppTimingsEnabledCache = -1;
		@:privateAccess backend.cpp.CppTargetCore.traceCppTimingMethodFilterCache = null;
	}

	static function restoreEnv(name:String, value:Null<String>):Void {
		Sys.putEnv(name, value);
	}

	static function render(stmt:HxStmt, scope:backend.cpp.CppRenderScope):String {
		return @:privateAccess backend.cpp.CppTargetCore.renderStmt(stmt, "", scope).join("\n");
	}

	static function main():Void {
		final calls = envInt("HXHX_CPP_LOCAL_DECL_BENCH_CALLS", DEFAULT_CALLS);
		final literal = EString('{ test } "quoted"\nnext');
		final typedStmt = SVar("text", "String", literal, HxPos.unknown());
		final phaseFixture = fixture();
		var declaredTypeSample = "";
		final declaredTypeSeconds = elapsedNamed("string_declared_type", calls, () -> {
			declaredTypeSample = @:privateAccess
				backend.cpp.CppTargetCore.cppLocalDeclaredType("text", "String", literal, phaseFixture.scope, "text");
		});
		var initSample = "";
		final initSeconds = elapsedNamed("string_init", calls, () -> {
			initSample = @:privateAccess backend.cpp.CppTargetCore.renderLocalInitExpr(literal, "std::string", "std::string", phaseFixture.scope);
		});
		final fullFixtures = [for (_ in 0...indexedBenchFixtureCount("string_full", calls)) fixture()];
		var fullSample = "";
		final fullSeconds = elapsedIndexedNamed("string_full", calls, i -> {
			fullSample = render(typedStmt, fullFixtures[i].scope);
		});
		final callbackType = "std::function<std::string(std::shared_ptr<EReg>)>";
		final matchedLeft = ECall(EField(EIdent("r"), "matchedLeft"), []);
		final matched = ECall(EField(EIdent("r"), "matched"), [EInt(0)]);
		final matchedRight = ECall(EField(EIdent("r"), "matchedRight"), []);
		final callbackBody = EBinop("+", EBinop("+", EBinop("+", EString("["), matchedLeft), matched), matchedRight);
		final callback = ELambda(["r"], callbackBody);
		final callbackStmt = SVar("callback", "EReg->String", callback, HxPos.unknown());
		final callbackPhaseFixture = fixture();
		var callbackDeclaredTypeSample = "";
		final callbackDeclaredTypeSeconds = elapsedNamed("callback_declared_type", calls, () -> {
			callbackDeclaredTypeSample = @:privateAccess
				backend.cpp.CppTargetCore.cppLocalDeclaredType("callback", "EReg->String", callback, callbackPhaseFixture.scope, "callback");
		});
		var callbackExpectedSample = "";
		final callbackExpectedSeconds = elapsedNamed("callback_expected", calls, () -> {
			callbackExpectedSample = @:privateAccess backend.cpp.CppTargetCore.valueExprForExpectedType(callback, callbackType, callbackPhaseFixture.scope);
		});
		var callbackInitSample = "";
		final callbackInitSeconds = elapsedNamed("callback_init", calls, () -> {
			callbackInitSample = @:privateAccess
				backend.cpp.CppTargetCore.renderLocalInitExpr(callback, callbackType, callbackType, callbackPhaseFixture.scope);
		});
		var callbackLambdaSample = "";
		final callbackLambdaSeconds = elapsedNamed("callback_lambda", calls, () -> {
			callbackLambdaSample = @:privateAccess
				backend.cpp.CppTargetCore.lambdaExprForExpectedFunction(["r"], callbackBody, callbackType, callbackPhaseFixture.scope);
		});
		final callbackBodyFixture = fixture();
		callbackBodyFixture.scope.localNames.set("r", "r");
		callbackBodyFixture.scope.localTypes.set("r", "std::shared_ptr<EReg>");
		var callbackBodySample = "";
		final callbackBodySeconds = elapsedNamed("callback_body", calls, () -> {
			final rendered = @:privateAccess backend.cpp.CppTargetCore.directERegStringCallbackBodyExpr(callbackBody, ["r"], ["std::shared_ptr<EReg>"],
				"std::string", callbackBodyFixture.scope);
			callbackBodySample = rendered == null ? "" : rendered;
		});
		final callbackFullFixtures = [for (_ in 0...indexedBenchFixtureCount("callback_full", calls)) fixture()];
		var callbackFullSample = "";
		final callbackFullSeconds = elapsedIndexedNamed("callback_full", calls, i -> {
			callbackFullSample = render(callbackStmt, callbackFullFixtures[i].scope);
		});

		final eReg = ENew("EReg", [EString("a+"), EString("g")]);
		final eRegStmt = SVar("regex", "", eReg, HxPos.unknown());
		final eRegPhaseFixture = fixture();
		var eRegDeclaredTypeSample = "";
		final eRegDeclaredTypeSeconds = elapsedNamed("ereg_declared_type", calls, () -> {
			eRegDeclaredTypeSample = @:privateAccess
				backend.cpp.CppTargetCore.cppLocalDeclaredType("regex", "", eReg, eRegPhaseFixture.scope, "regex");
		});
		var eRegConstructorSample = "";
		final eRegConstructorSeconds = elapsedNamed("ereg_constructor", calls, () -> {
			eRegConstructorSample = @:privateAccess
				backend.cpp.CppTargetCore.newExpr("EReg", [EString("a+"), EString("g")], eRegPhaseFixture.scope, "std::shared_ptr<EReg>");
		});
		var eRegInitSample = "";
		final eRegInitSeconds = elapsedNamed("ereg_init", calls, () -> {
			eRegInitSample = @:privateAccess
				backend.cpp.CppTargetCore.renderLocalInitExpr(eReg, "auto", "std::shared_ptr<EReg>", eRegPhaseFixture.scope);
		});
		final eRegFullFixtures = [for (_ in 0...indexedBenchFixtureCount("ereg_full", calls)) fixture()];
		var eRegFullSample = "";
		final eRegFullSeconds = elapsedIndexedNamed("ereg_full", calls, i -> {
			eRegFullSample = render(eRegStmt, eRegFullFixtures[i].scope);
		});

		final timingEnv = "HXHX_TRACE_STAGE3_CPP_TIMINGS";
		final filterEnv = "HXHX_TRACE_STAGE3_CPP_METHOD_TIMING_FILTER";
		final priorTiming = Sys.getEnv(timingEnv);
		final priorFilter = Sys.getEnv(filterEnv);
		final eRegTracedFixtures = [for (_ in 0...indexedBenchFixtureCount("ereg_full_traced", calls)) fixture()];
		var eRegTracedSample = "";
		var eRegTracedLineCount = 0;
		var eRegTracedSeconds = -1.;
		try {
			Sys.putEnv(timingEnv, "1");
			Sys.putEnv(filterEnv, "LocalDeclBenchOwner.test");
			resetTimingCaches();
			eRegTracedSeconds = elapsedIndexedNamed("ereg_full_traced", calls, i -> {
				final measured = @:privateAccess backend.cpp.CppTargetCore.measureWithBufferedCppTimingPhases(() -> {
					eRegTracedSample = @:privateAccess
						backend.cpp.CppTargetCore.renderTimedHelperFunctionBody("LocalDeclBenchOwner", "test", [eRegStmt], "", eRegTracedFixtures[i].scope)
							.join("\n");
				});
				eRegTracedLineCount = measured.phases.length;
			});
		} catch (error:Dynamic) {
			restoreEnv(timingEnv, priorTiming);
			restoreEnv(filterEnv, priorFilter);
			resetTimingCaches();
			throw error;
		}
		restoreEnv(timingEnv, priorTiming);
		restoreEnv(filterEnv, priorFilter);
		resetTimingCaches();

		final controls = fixture();
		final untypedSample = render(SVar("untypedText", "", EString("literal"), HxPos.unknown()), controls.scope);
		final dynamicSample = render(SVar("dynamicText", "Dynamic", EString("literal"), HxPos.unknown()), controls.scope);
		final abstractSample = render(SVar("abstractText", "StringAlias", EString("literal"), HxPos.unknown()), controls.scope);
		final firstShadowSample = render(SVar("shadow", "String", EString("first"), HxPos.unknown()), controls.scope);
		final secondShadowSample = render(SVar("shadow", "String", EString("second"), HxPos.unknown()), controls.scope);
		final fieldShadowSample = render(SVar("value", "String", EIdent("value"), HxPos.unknown()), controls.scope);
		controls.scope.localNames.set("source", "source");
		controls.scope.localTypes.set("source", "std::string");
		controls.scope.localTypeHints.set("source", "String");
		final nonliteralSample = render(SVar("copied", "String", EIdent("source"), HxPos.unknown()), controls.scope);
		controls.scope.localNames.set("namedCallback", "namedCallback");
		controls.scope.localTypes.set("namedCallback", callbackType);
		final namedCallbackSample = render(SVar("callbackCopy", "EReg->String", EIdent("namedCallback"), HxPos.unknown()), controls.scope);
		final qualifiedCallbackTypeSample = @:privateAccess
			backend.cpp.CppTargetCore.cppLocalDeclaredType("qualifiedCallback", "fixture.regex.EReg->String", callback, controls.scope, "qualifiedCallback");
		final otherCallback = ELambda(["value"], EString("ok"));
		final otherCallbackTypeSample = @:privateAccess
			backend.cpp.CppTargetCore.cppLocalDeclaredType("otherCallback", "OtherCallbackArg->String", otherCallback, controls.scope, "otherCallback");
		final inferredCallbackSample = render(SVar("inferredCallback", "", ELambda([], EString("ok")), HxPos.unknown()), controls.scope);
		final nonFunctionDirectSample = @:privateAccess
			backend.cpp.CppTargetCore.directLambdaValueExprForExpectedFunction(callback, "std::string", controls.scope);
		controls.scope.localNames.set("pattern", "pattern");
		controls.scope.localNames.set("options", "options");
		controls.scope.localTypes.set("pattern", "std::string");
		controls.scope.localTypes.set("options", "std::string");
		final explicitERegSample = render(SVar("typedRegex", "EReg", eReg, HxPos.unknown()), controls.scope);
		final qualifiedERegSample = render(SVar("qualifiedRegex", "fixture.regex.EReg", eReg, HxPos.unknown()), controls.scope);
		final localArgERegSample = render(SVar("localRegex", "", ENew("EReg", [EIdent("pattern"), EIdent("options")]), HxPos.unknown()), controls.scope);
		final nonERegSample = render(SVar("other", "", ENew("OtherCallbackArg", []), HxPos.unknown()), controls.scope);

		assertTrue(declaredTypeSample == "std::string", "typed String literal locals should retain their declared C++ type");
		assertTrue(initSample == 'std::string("{ test } \\"quoted\\"\\nnext")',
			"typed String literal initialization should preserve braces, quotes, and newlines, got " + initSample);
		assertTrue(fullSample == "std::string text = " + initSample + ";", "typed String literal declarations should retain exact output, got " + fullSample);
		assertTrue(untypedSample == 'auto untypedText = std::string("literal");', "untyped String literal locals should retain auto declarations");
		assertTrue(dynamicSample == 'std::string dynamicText = std::string("literal");',
			"Dynamic-shaped String literal locals should retain their current carrier");
		assertTrue(abstractSample == 'std::string abstractText = std::string("literal");',
			"String-backed abstract locals should retain general conversion rendering");
		assertTrue(firstShadowSample == 'std::string shadow = std::string("first");'
			&& secondShadowSample == 'std::string shadow_2 = std::string("second");',
			"duplicate typed String locals should retain unique C++ names");
		assertTrue(fieldShadowSample == "std::string value = std::string(this->value);",
			"nonliteral same-name field initialization should retain explicit owner qualification");
		assertTrue(nonliteralSample == "std::string copied = std::string(source);",
			"ordinary nonliteral String initialization should remain on the general conversion path");
		final expectedCallbackBody = '(((std::string("[") + r->matchedLeft()) + __hxhx_stringify(r->matched(0))) + r->matchedRight())';
		final expectedCallback = '[&](std::shared_ptr<EReg> r) -> std::string { return ' + expectedCallbackBody + '; }';
		assertTrue(callbackDeclaredTypeSample == callbackType
			&& callbackBodySample == expectedCallbackBody
			&& callbackLambdaSample == expectedCallback
			&& callbackExpectedSample == expectedCallback
			&& callbackInitSample == expectedCallback,
			"typed callback local phases should preserve exact EReg callback output");
		assertTrue(callbackFullSample == callbackType + " callback = " + expectedCallback + ";",
			"typed callback local declarations should retain exact output, got " + callbackFullSample);
		assertTrue(eRegDeclaredTypeSample == "std::shared_ptr<EReg>"
			&& eRegConstructorSample == 'std::make_shared<EReg>("a+", "g")'
			&& eRegInitSample == eRegConstructorSample,
			"fresh EReg declaration phases should preserve their exact target-owned carrier and constructor");
		assertTrue(eRegFullSample == "auto regex = " + eRegConstructorSample + ";"
			&& eRegTracedSample == eRegFullSample
			&& eRegTracedLineCount == 8,
			"fresh EReg full and buffered-timing declarations should preserve output and eight timing records, got full="
			+ eRegFullSample
			+ " traced="
			+ eRegTracedSample
			+ " records="
			+ eRegTracedLineCount);
		assertTrue(explicitERegSample == 'std::shared_ptr<EReg> typedRegex = std::make_shared<EReg>("a+", "g");'
			&& qualifiedERegSample == 'std::shared_ptr<EReg> qualifiedRegex = std::make_shared<EReg>("a+", "g");'
			&& localArgERegSample == "auto localRegex = std::make_shared<EReg>(pattern, options);"
			&& nonERegSample == "auto other = std::make_shared<OtherCallbackArg>();",
			"explicit, qualified, local-argument, and non-EReg constructor controls should retain the general declaration contract");
		assertTrue(namedCallbackSample == callbackType + " callbackCopy = namedCallback;"
			&& qualifiedCallbackTypeSample == callbackType
			&& otherCallbackTypeSample == "std::function<std::string(std::shared_ptr<OtherCallbackArg>)>"
			&& inferredCallbackSample == 'auto inferredCallback = [&]() { return "ok"; };'
			&& nonFunctionDirectSample == null,
			"named, qualified, non-EReg, inferred, and non-function callback paths should retain their contracts: named="
			+ namedCallbackSample
			+ " qualified="
			+ qualifiedCallbackTypeSample
			+ " other="
			+ otherCallbackTypeSample
			+ " inferred="
			+ inferredCallbackSample);

		Sys.println("CPP_LOCAL_DECL_BENCH:PASS calls=" + calls + " declared_type_seconds=" + declaredTypeSeconds + " init_seconds=" + initSeconds
			+ " full_seconds=" + fullSeconds + " callback_declared_type_seconds=" + callbackDeclaredTypeSeconds + " callback_expected_seconds="
			+ callbackExpectedSeconds + " callback_init_seconds=" + callbackInitSeconds + " callback_lambda_seconds=" + callbackLambdaSeconds
			+ " callback_body_seconds=" + callbackBodySeconds + " callback_full_seconds=" + callbackFullSeconds + " ereg_declared_type_seconds="
			+ eRegDeclaredTypeSeconds + " ereg_constructor_seconds=" + eRegConstructorSeconds + " ereg_init_seconds=" + eRegInitSeconds
			+ " ereg_full_seconds=" + eRegFullSeconds + " ereg_full_traced_seconds=" + eRegTracedSeconds + " ereg_traced_lines=" + eRegTracedLineCount);
	}
}
