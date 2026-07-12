import HxExpr;
import HxStmt;
import haxe.ds.StringMap;

typedef CppDynamicLocalPrepFixture = {
	var scope:backend.cpp.CppRenderScope;
}

/**
	Focused attribution probe for C++ dynamic-local method preparation.

	The fixture is repo-owned and only mirrors the strict frontier's scale: an
	88-statement method with late explicit EReg callback evidence. Selectable
	fresh-process phases separate the cheap syntax guard, candidate recognition,
	declared callable typing, override writes, and the complete state-restoring
	inference pass.
**/
class M14CppDynamicLocalPrepBenchIntegrationTest {
	static inline final DEFAULT_CALLS = 250;
	static inline final EXPECTED_CALLBACK_TYPE = "std::function<std::string(std::shared_ptr<EReg>)>";

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

	static function selectedBench(name:String):Bool {
		final only = Sys.getEnv("HXHX_CPP_DYNAMIC_LOCAL_PREP_BENCH_ONLY");
		return only == null || StringTools.trim(only).length == 0 || only == name;
	}

	static function elapsed(calls:Int, action:Void->Void):Float {
		final start = Sys.time();
		for (_ in 0...calls)
			action();
		return Sys.time() - start;
	}

	static function elapsedNamed(name:String, calls:Int, action:Void->Void):Float {
		action();
		return selectedBench(name) ? elapsed(calls, action) : -1.;
	}

	static function elapsedIndexedNamed(name:String, calls:Int, action:Int->Void):Float {
		action(0);
		if (!selectedBench(name))
			return -1.;
		final start = Sys.time();
		for (i in 0...calls)
			action(i + 1);
		return Sys.time() - start;
	}

	static function indexedMapCount(name:String, calls:Int):Int {
		return selectedBench(name) ? calls + 1 : 1;
	}

	static function fixture():CppDynamicLocalPrepFixture {
		final names = new StringMap<Bool>();
		final classes = new StringMap<HxClassDecl>();
		final all = new Array<HxClassDecl>();
		final eReg = new HxClassDecl("EReg", false, [], []);
		final owner = new HxClassDecl("DynamicLocalPrepOwner", false, [], []);
		for (cls in [eReg, owner]) {
			final name = HxClassDecl.getName(cls);
			names.set(name, true);
			classes.set(name, cls);
			all.push(cls);
		}
		for (i in 0...280) {
			final cls = new HxClassDecl("DynamicLocalPrepDummy" + i, false, [], []);
			final name = HxClassDecl.getName(cls);
			names.set(name, true);
			classes.set(name, cls);
			all.push(cls);
		}
		return {
			scope: @:privateAccess backend.cpp.CppTargetCore.renderScope(owner, {names: names, byName: classes, all: all}, "void")
		};
	}

	static function cppDynamicTypeHint(typeHint:String):Bool {
		return @:privateAccess backend.cpp.CppTargetCore.isDynamicLikeTypeHint(typeHint);
	}

	/** Replay the pre-gate free-call work for a same-source branch-disabled comparison. **/
	static function replayOldFreeCallCandidateLookup(args:Array<HxExpr>, scope:backend.cpp.CppRenderScope, candidates:StringMap<Bool>):Void {
		@:privateAccess backend.cpp.CppTargetCore.collectSameOwnerDeclaredArgTypeOverrides("eq", args, scope, candidates);
		@:privateAccess backend.cpp.CppTargetCore.collectForwardedCallArgTypeOverrides(EIdent("eq"), args, scope, candidates);
	}

	/** Build a late-candidate method with the strict frontier's statement count. **/
	static function testERegShapedFunction(callback:HxExpr, forwardedCalls:Bool):HxFunctionDecl {
		final body = new Array<HxStmt>();
		for (i in 0...11)
			body.push(SVar("regex" + i, "EReg", ENew("EReg", [EString("p" + i), EString(i % 2 == 0 ? "g" : "")]), HxPos.unknown()));
		for (i in 0...57)
			body.push(SExpr(ECall(EIdent("eq"), [EInt(i), EInt(i)]), HxPos.unknown()));
		body.push(SVar("callback", "EReg->String", callback, HxPos.unknown()));
		for (i in 0...19) {
			final mapCall = ECall(EField(EIdent("regex" + (i % 11)), "map"), [EString("value" + i), EIdent("callback")]);
			final expr = forwardedCalls ? ECall(EIdent("eq"), [mapCall, EString("mapped" + i)]) : EInt(100 + i);
			body.push(SExpr(expr, HxPos.unknown()));
		}
		assertTrue(body.length == 88, "dynamic-local attribution fixture should retain 88 statements");
		return new HxFunctionDecl("test", Public, false, [], "Void", body, "");
	}

	static function main():Void {
		final calls = envInt("HXHX_CPP_DYNAMIC_LOCAL_PREP_BENCH_CALLS", DEFAULT_CALLS);
		final callback = ELambda(["value"], ECall(EField(EIdent("value"), "matchedLeft"), []));
		final shapedFn = testERegShapedFunction(callback, true);
		final noForwardFn = testERegShapedFunction(callback, false);
		final phaseFixture = fixture();

		var guardSample = false;
		final guardSeconds = elapsedNamed("guard", calls, () -> {
			guardSample = backend.cpp.CppPrepLocalInferenceGuard.functionHasDynamicLocalInferenceEvidence(shapedFn, cppDynamicTypeHint);
		});
		var callableSample = false;
		final callableSeconds = elapsedNamed("callable_predicate", calls, () -> {
			callableSample = @:privateAccess backend.cpp.CppTargetCore.isLocalCallableInit(callback);
		});
		var declaredTypeSample = "";
		final declaredTypeSeconds = elapsedNamed("declared_type", calls, () -> {
			declaredTypeSample = @:privateAccess backend.cpp.CppTargetCore.cppLocalTypeHint("EReg->String", callback, phaseFixture.scope);
		});

		final overrideFixture = fixture();
		final overrideMaps = [for (_ in 0...indexedMapCount("override_write", calls)) new StringMap<String>()];
		var overrideSample = "";
		final overrideWriteSeconds = elapsedIndexedNamed("override_write", calls, i -> {
			overrideFixture.scope.localTypeOverrides = overrideMaps[i];
			@:privateAccess backend.cpp.CppTargetCore.setDynamicLocalTypeOverride(overrideFixture.scope, "callback", EXPECTED_CALLBACK_TYPE);
			overrideSample = overrideFixture.scope.localTypeOverrides.get("callback");
		});

		final completeFixture = fixture();
		final completeMaps = [for (_ in 0...indexedMapCount("complete", calls)) new StringMap<String>()];
		var completeSample = "";
		final completeSeconds = elapsedIndexedNamed("complete", calls, i -> {
			completeFixture.scope.localTypeOverrides = completeMaps[i];
			@:privateAccess backend.cpp.CppTargetCore.inferDynamicLocalTypeOverrides(completeFixture.scope, shapedFn);
			completeSample = completeFixture.scope.localTypeOverrides.get("callback");
		});
		final completeOldFixture = fixture();
		final completeOldCandidates = new StringMap<Bool>();
		completeOldCandidates.set("callback", true);
		final completeOldReplayArgs = [
			for (mapIndex in 0...19) [
				ECall(EField(EIdent("regex" + (mapIndex % 11)), "map"), [EString("value" + mapIndex), EIdent("callback")]),
				EString("mapped" + mapIndex)
			]
		];
		final completeOldMaps = [for (_ in 0...indexedMapCount("complete_old", calls)) new StringMap<String>()];
		var completeOldSample = "";
		final completeOldSeconds = elapsedIndexedNamed("complete_old", calls, i -> {
			completeOldFixture.scope.localTypeOverrides = completeOldMaps[i];
			@:privateAccess backend.cpp.CppTargetCore.inferDynamicLocalTypeOverrides(completeOldFixture.scope, shapedFn);
			for (args in completeOldReplayArgs)
				replayOldFreeCallCandidateLookup(args, completeOldFixture.scope, completeOldCandidates);
			completeOldSample = completeOldFixture.scope.localTypeOverrides.get("callback");
		});
		final noForwardFixture = fixture();
		final noForwardMaps = [
			for (_ in 0...indexedMapCount("complete_no_forward", calls))
				new StringMap<String>()
		];
		var noForwardSample:Null<String> = "unexpected";
		final noForwardSeconds = elapsedIndexedNamed("complete_no_forward", calls, i -> {
			noForwardFixture.scope.localTypeOverrides = noForwardMaps[i];
			@:privateAccess backend.cpp.CppTargetCore.inferDynamicLocalTypeOverrides(noForwardFixture.scope, noForwardFn);
			noForwardSample = noForwardFixture.scope.localTypeOverrides.get("callback");
		});

		final mapCall = ECall(EField(EIdent("regex0"), "map"), [EString("value"), EIdent("callback")]);
		final mapExpr = ECall(EIdent("eq"), [mapCall, EString("mapped")]);
		final mapFixture = fixture();
		mapFixture.scope.localNames.set("regex0", "regex0");
		mapFixture.scope.localNames.set("callback", "callback");
		mapFixture.scope.localTypes.set("regex0", "std::shared_ptr<EReg>");
		mapFixture.scope.localTypes.set("callback", EXPECTED_CALLBACK_TYPE);
		final mapCandidates = new StringMap<Bool>();
		mapCandidates.set("callback", true);
		var mapExprSample = "";
		final mapExprSeconds = elapsedNamed("map_expr", calls, () -> {
			@:privateAccess backend.cpp.CppTargetCore.collectDynamicLocalTypeOverridesFromExpr(mapExpr, mapFixture.scope, mapCandidates);
			mapExprSample = mapFixture.scope.localTypeOverrides.get("callback");
		});
		var mapExprOldSample = "";
		final mapExprOldSeconds = elapsedNamed("map_expr_old", calls, () -> {
			replayOldFreeCallCandidateLookup([mapCall, EString("mapped")], mapFixture.scope, mapCandidates);
			@:privateAccess backend.cpp.CppTargetCore.collectDynamicLocalTypeOverridesFromExpr(mapExpr, mapFixture.scope, mapCandidates);
			mapExprOldSample = mapFixture.scope.localTypeOverrides.get("callback");
		});
		var forwardedMapSample = "";
		final forwardedMapSeconds = elapsedNamed("forwarded_map", calls, () -> {
			@:privateAccess backend.cpp.CppTargetCore.collectForwardedCallArgTypeOverrides(EField(EIdent("regex0"), "map"),
				[EString("value"), EIdent("callback")], mapFixture.scope, mapCandidates);
			forwardedMapSample = mapFixture.scope.localTypeOverrides.get("callback");
		});

		final staleFn = new HxFunctionDecl("stale", Public, false, [], "Void", [
			SVar("callback", "String->String", ELambda(["value"], EIdent("value")), HxPos.unknown()),
			SExpr(ECall(EIdent("callback"), [EBool(true)]), HxPos.unknown())
		], "");
		final staleFixture = fixture();
		@:privateAccess backend.cpp.CppTargetCore.inferDynamicLocalTypeOverrides(staleFixture.scope, staleFn);
		final staleSample = staleFixture.scope.localTypeOverrides.get("callback");
		final openFn = new HxFunctionDecl("open", Public, false, [], "Void", [
			SVar("value", "Dynamic", ENull, HxPos.unknown()),
			SExpr(EBinop("=", EIdent("value"), EInt(7)), HxPos.unknown())
		], "");
		final openFixture = fixture();
		@:privateAccess backend.cpp.CppTargetCore.inferDynamicLocalTypeOverrides(openFixture.scope, openFn);
		final openSample = openFixture.scope.localTypeOverrides.get("value");
		final plainFn = new HxFunctionDecl("plain", Public, false, [], "Void", [
			SVar("count", "Int", EInt(1), HxPos.unknown()),
			SExpr(ECall(EIdent("eq"), [EIdent("count"), EInt(1)]), HxPos.unknown())
		], "");
		final plainEvidence = backend.cpp.CppPrepLocalInferenceGuard.functionHasDynamicLocalInferenceEvidence(plainFn, cppDynamicTypeHint);

		assertTrue(guardSample && callableSample, "late explicit EReg callback evidence should reach the dynamic-local pass");
		assertTrue(declaredTypeSample == EXPECTED_CALLBACK_TYPE, "explicit EReg callbacks should retain their exact declared callable type");
		assertTrue(overrideSample == EXPECTED_CALLBACK_TYPE && completeSample == EXPECTED_CALLBACK_TYPE,
			"isolated and complete override writes should retain the exact EReg callback type");
		assertTrue(completeOldSample == EXPECTED_CALLBACK_TYPE
			&& noForwardSample == null
			&& mapExprSample == EXPECTED_CALLBACK_TYPE
			&& mapExprOldSample == EXPECTED_CALLBACK_TYPE
			&& forwardedMapSample == EXPECTED_CALLBACK_TYPE,
			"no-forward, complete map-expression, and direct forwarded-map phases should retain their exact override contracts");
		assertTrue(staleSample == "std::function<std::string(bool)>" && openSample == "int" && !plainEvidence,
			"stale callable, open Dynamic, and ordinary local controls should retain their inference contracts");

		Sys.println("CPP_DYNAMIC_LOCAL_PREP_BENCH:PASS calls=" + calls + " guard_seconds=" + guardSeconds + " callable_predicate_seconds=" + callableSeconds
			+ " declared_type_seconds=" + declaredTypeSeconds + " override_write_seconds=" + overrideWriteSeconds + " complete_seconds=" + completeSeconds
			+ " complete_old_seconds=" + completeOldSeconds + " complete_no_forward_seconds=" + noForwardSeconds + " map_expr_seconds=" + mapExprSeconds
			+ " map_expr_old_seconds=" + mapExprOldSeconds + " forwarded_map_seconds=" + forwardedMapSeconds + " override=" + completeSample);
	}
}
