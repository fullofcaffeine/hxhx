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

	static function countKeys<T>(map:StringMap<T>):Int {
		var count = 0;
		for (_ in map.keys())
			count++;
		return count;
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

	/** Replay the pre-fast-path fresh EReg declaration work for a same-source comparison. **/
	static function replayOldFreshERegPrefix(stmt:HxStmt, scope:backend.cpp.CppRenderScope, candidates:StringMap<Bool>):Void {
		switch (stmt) {
			case SVar(name, typeHint, init, _):
				if (init != null)
					@:privateAccess backend.cpp.CppTargetCore.collectDynamicLocalTypeOverridesFromExpr(init, scope, candidates);
				final local = @:privateAccess backend.cpp.CppTargetCore.declareLocalName(name, scope);
				final localType = @:privateAccess backend.cpp.CppTargetCore.cppLocalTypeHint(typeHint, init, scope);
				if (@:privateAccess backend.cpp.CppTargetCore.isLocalCallableInit(init))
					throw "fresh EReg fixture unexpectedly became callable";
				if (@:privateAccess backend.cpp.CppTargetCore.inferredLocalCallableType(init, scope).length > 0)
					throw "fresh EReg fixture unexpectedly inferred a callable";
				if (@:privateAccess backend.cpp.CppTargetCore.isLocalCallableInit(init) && localType.length == 0)
					throw "fresh EReg fixture unexpectedly became an untyped callable";
				if (@:privateAccess backend.cpp.CppTargetCore.isLocalCallableInit(init) && localType.length == 0)
					throw "fresh EReg fixture unexpectedly became an open callable";
				if (@:privateAccess backend.cpp.CppTargetCore.isUnhintedNoInitLocal(typeHint, init)
					|| @:privateAccess backend.cpp.CppTargetCore.isUnhintedEmptyArray(typeHint, init)
					|| @:privateAccess backend.cpp.CppTargetCore.isUnhintedNullLocal(typeHint, init)
					|| @:privateAccess backend.cpp.CppTargetCore.isDynamicLikeTypeHint(typeHint))
					throw "fresh explicit EReg fixture unexpectedly became Dynamic";
				scope.localTypes.set(local, localType);
			case _:
		}
	}

	/** Replay the resolved EReg.map dispatch and inert-leaf descent skipped by the current collector. **/
	static function replayResolvedERegMapInferenceWork(callee:HxExpr, args:Array<HxExpr>, scope:backend.cpp.CppRenderScope, candidates:StringMap<Bool>):Void {
		@:privateAccess backend.cpp.CppTargetCore.collectForwardedCallArgTypeOverrides(callee, args, scope, candidates);
		@:privateAccess backend.cpp.CppTargetCore.collectDynamicLocalTypeOverridesFromExprWithCandidates(callee, scope, candidates);
		for (arg in args)
			@:privateAccess backend.cpp.CppTargetCore.collectDynamicLocalTypeOverridesFromExprWithCandidates(arg, scope, candidates);
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
		final shapedBody = HxFunctionDecl.getBody(shapedFn);
		final prefixStmts = shapedBody.slice(0, 68);
		final prefixVarStmts = prefixStmts.slice(0, 11);
		final prefixEqStmts = prefixStmts.slice(11);
		final callbackStmt = shapedBody[68];
		final postCandidateStmts = shapedBody.slice(69);
		final phaseFixture = fixture();
		final freshERegLocalGateSample = @:privateAccess backend.cpp.CppTargetCore.isFreshERegLocalInitializer(ENew("EReg", []));
		final qualifiedFreshERegLocalGateSample = @:privateAccess backend.cpp.CppTargetCore.isFreshERegLocalInitializer(ENew("haxe.EReg", []));
		final unrelatedFreshLocalGateSample = @:privateAccess backend.cpp.CppTargetCore.isFreshERegLocalInitializer(ENew("Other", []));

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
		var snapshotSample = 0;
		final snapshotSeconds = elapsedNamed("scope_snapshot", calls, () -> {
			final localTypes = @:privateAccess backend.cpp.CppTargetCore.copyStringMap(phaseFixture.scope.localTypes);
			final localNames = @:privateAccess backend.cpp.CppTargetCore.copyStringMap(phaseFixture.scope.localNames);
			final localNameCounts = @:privateAccess backend.cpp.CppTargetCore.copyIntMap(phaseFixture.scope.localNameCounts);
			snapshotSample = countKeys(localTypes) + countKeys(localNames) + countKeys(localNameCounts);
		});

		final prefixInitFixture = fixture();
		final prefixInitCandidates = new StringMap<Bool>();
		var prefixInitSample = 0;
		final prefixInitSeconds = elapsedNamed("prefix_init_walk", calls, () -> {
			for (stmt in prefixVarStmts)
				switch (stmt) {
					case SVar(_, _, init, _) if (init != null):
						@:privateAccess backend.cpp.CppTargetCore.collectDynamicLocalTypeOverridesFromExpr(init, prefixInitFixture.scope, prefixInitCandidates);
					case _:
				}
			prefixInitSample = countKeys(prefixInitCandidates) + countKeys(prefixInitFixture.scope.localTypes);
		});

		final prefixNameFixture = fixture();
		final prefixNameCount = indexedMapCount("prefix_names", calls);
		final prefixLocalNameMaps = [for (_ in 0...prefixNameCount) new StringMap<String>()];
		final prefixLocalNameCountMaps = [for (_ in 0...prefixNameCount) new StringMap<Int>()];
		var prefixNameSample = "";
		final prefixNameSeconds = elapsedIndexedNamed("prefix_names", calls, i -> {
			prefixNameFixture.scope.localNames = prefixLocalNameMaps[i];
			prefixNameFixture.scope.localNameCounts = prefixLocalNameCountMaps[i];
			for (stmt in prefixVarStmts)
				switch (stmt) {
					case SVar(name, _, _, _):
						@:privateAccess backend.cpp.CppTargetCore.declareLocalName(name, prefixNameFixture.scope);
					case _:
				}
			prefixNameSample = countKeys(prefixNameFixture.scope.localNames) + "/" + countKeys(prefixNameFixture.scope.localNameCounts);
		});

		final prefixTypeFixture = fixture();
		var prefixTypeSample = 0;
		final prefixTypeSeconds = elapsedNamed("prefix_types", calls, () -> {
			prefixTypeSample = 0;
			for (stmt in prefixVarStmts)
				switch (stmt) {
					case SVar(_, typeHint, init, _):
						if (@:privateAccess backend.cpp.CppTargetCore.cppLocalTypeHint(typeHint, init,
							prefixTypeFixture.scope) == "std::shared_ptr<EReg>") prefixTypeSample++;
					case _:
				}
		});

		var prefixPredicateSample = 0;
		final prefixPredicateSeconds = elapsedNamed("prefix_predicates", calls, () -> {
			prefixPredicateSample = 0;
			for (stmt in prefixVarStmts)
				switch (stmt) {
					case SVar(_, typeHint, init, _):
						for (_ in 0...3)
							if (@:privateAccess backend.cpp.CppTargetCore.isLocalCallableInit(init))
								prefixPredicateSample++;
						if (@:privateAccess backend.cpp.CppTargetCore.inferredLocalCallableType(init, prefixTypeFixture.scope).length > 0)
							prefixPredicateSample++;
						if (@:privateAccess backend.cpp.CppTargetCore.isUnhintedNoInitLocal(typeHint, init)
							|| @:privateAccess backend.cpp.CppTargetCore.isUnhintedEmptyArray(typeHint, init)
							|| @:privateAccess backend.cpp.CppTargetCore.isUnhintedNullLocal(typeHint, init)
							|| @:privateAccess backend.cpp.CppTargetCore.isDynamicLikeTypeHint(typeHint)) prefixPredicateSample++;
					case _:
				}
		});

		var prefixCallableSample = 0;
		final prefixCallableSeconds = elapsedNamed("prefix_callable_checks", calls, () -> {
			prefixCallableSample = 0;
			for (stmt in prefixVarStmts)
				switch (stmt) {
					case SVar(_, _, init, _):
						for (_ in 0...3)
							if (@:privateAccess backend.cpp.CppTargetCore.isLocalCallableInit(init))
								prefixCallableSample++;
						if (@:privateAccess backend.cpp.CppTargetCore.inferredLocalCallableType(init, prefixTypeFixture.scope)
							.length > 0) prefixCallableSample++;
					case _:
				}
		});
		var prefixDynamicSample = 0;
		final prefixDynamicSeconds = elapsedNamed("prefix_dynamic_checks", calls, () -> {
			prefixDynamicSample = 0;
			for (stmt in prefixVarStmts)
				switch (stmt) {
					case SVar(_, typeHint, init, _):
						if (@:privateAccess backend.cpp.CppTargetCore.isUnhintedNoInitLocal(typeHint, init)
							|| @:privateAccess backend.cpp.CppTargetCore.isUnhintedEmptyArray(typeHint, init)
							|| @:privateAccess backend.cpp.CppTargetCore.isUnhintedNullLocal(typeHint, init)
							|| @:privateAccess backend.cpp.CppTargetCore.isDynamicLikeTypeHint(typeHint)) prefixDynamicSample++;
					case _:
				}
		});

		final prefixEqFixture = fixture();
		final prefixEqCandidates = new StringMap<Bool>();
		var prefixEqSample = 0;
		final prefixEqSeconds = elapsedNamed("prefix_eq_walk", calls, () -> {
			for (stmt in prefixEqStmts)
				@:privateAccess backend.cpp.CppTargetCore.collectDynamicLocalTypeOverridesFromStmt(stmt, prefixEqFixture.scope, prefixEqCandidates);
			prefixEqSample = countKeys(prefixEqCandidates) + countKeys(prefixEqFixture.scope.localTypes);
		});

		final prefixFixture = fixture();
		final prefixCount = indexedMapCount("prefix_collect", calls);
		final prefixLocalTypes = [for (_ in 0...prefixCount) new StringMap<String>()];
		final prefixLocalNames = [for (_ in 0...prefixCount) new StringMap<String>()];
		final prefixLocalNameCounts = [for (_ in 0...prefixCount) new StringMap<Int>()];
		final prefixCandidates = [for (_ in 0...prefixCount) new StringMap<Bool>()];
		var prefixSample = "";
		final prefixSeconds = elapsedIndexedNamed("prefix_collect", calls, i -> {
			prefixFixture.scope.localTypes = prefixLocalTypes[i];
			prefixFixture.scope.localNames = prefixLocalNames[i];
			prefixFixture.scope.localNameCounts = prefixLocalNameCounts[i];
			for (stmt in prefixStmts)
				@:privateAccess backend.cpp.CppTargetCore.collectDynamicLocalTypeOverridesFromStmt(stmt, prefixFixture.scope, prefixCandidates[i]);
			prefixSample = countKeys(prefixFixture.scope.localTypes) + "/" + countKeys(prefixCandidates[i]);
		});
		final prefixOldFixture = fixture();
		final prefixOldCount = indexedMapCount("prefix_collect_old", calls);
		final prefixOldLocalTypes = [for (_ in 0...prefixOldCount) new StringMap<String>()];
		final prefixOldLocalNames = [for (_ in 0...prefixOldCount) new StringMap<String>()];
		final prefixOldLocalNameCounts = [for (_ in 0...prefixOldCount) new StringMap<Int>()];
		final prefixOldCandidates = [for (_ in 0...prefixOldCount) new StringMap<Bool>()];
		var prefixOldSample = "";
		final prefixOldSeconds = elapsedIndexedNamed("prefix_collect_old", calls, i -> {
			prefixOldFixture.scope.localTypes = prefixOldLocalTypes[i];
			prefixOldFixture.scope.localNames = prefixOldLocalNames[i];
			prefixOldFixture.scope.localNameCounts = prefixOldLocalNameCounts[i];
			for (stmt in prefixVarStmts)
				replayOldFreshERegPrefix(stmt, prefixOldFixture.scope, prefixOldCandidates[i]);
			for (stmt in prefixEqStmts)
				@:privateAccess backend.cpp.CppTargetCore.collectDynamicLocalTypeOverridesFromStmt(stmt, prefixOldFixture.scope, prefixOldCandidates[i]);
			prefixOldSample = countKeys(prefixOldFixture.scope.localTypes) + "/" + countKeys(prefixOldCandidates[i]);
		});

		final candidateSeed = fixture();
		final candidateSeedCandidates = new StringMap<Bool>();
		for (stmt in prefixStmts)
			@:privateAccess backend.cpp.CppTargetCore.collectDynamicLocalTypeOverridesFromStmt(stmt, candidateSeed.scope, candidateSeedCandidates);
		final candidateCount = indexedMapCount("candidate_decl", calls);
		final candidateLocalTypes = [
			for (_ in 0...candidateCount)
				@:privateAccess backend.cpp.CppTargetCore.copyStringMap(candidateSeed.scope.localTypes)
		];
		final candidateLocalNames = [
			for (_ in 0...candidateCount)
				@:privateAccess backend.cpp.CppTargetCore.copyStringMap(candidateSeed.scope.localNames)
		];
		final candidateLocalNameCounts = [
			for (_ in 0...candidateCount)
				@:privateAccess backend.cpp.CppTargetCore.copyIntMap(candidateSeed.scope.localNameCounts)
		];
		final candidateMaps = [for (_ in 0...candidateCount) new StringMap<Bool>()];
		var candidateSample = "";
		final candidateSeconds = elapsedIndexedNamed("candidate_decl", calls, i -> {
			candidateSeed.scope.localTypes = candidateLocalTypes[i];
			candidateSeed.scope.localNames = candidateLocalNames[i];
			candidateSeed.scope.localNameCounts = candidateLocalNameCounts[i];
			@:privateAccess backend.cpp.CppTargetCore.collectDynamicLocalTypeOverridesFromStmt(callbackStmt, candidateSeed.scope, candidateMaps[i]);
			candidateSample = candidateSeed.scope.localTypes.get("callback") + "/" + candidateMaps[i].exists("callback");
		});

		final postSeed = fixture();
		final postSeedCandidates = new StringMap<Bool>();
		for (stmt in shapedBody.slice(0, 69))
			@:privateAccess backend.cpp.CppTargetCore.collectDynamicLocalTypeOverridesFromStmt(stmt, postSeed.scope, postSeedCandidates);
		final postCount = indexedMapCount("post_candidate_collect", calls);
		final postLocalTypes = [
			for (_ in 0...postCount)
				@:privateAccess backend.cpp.CppTargetCore.copyStringMap(postSeed.scope.localTypes)
		];
		final postOverrideMaps = [for (_ in 0...postCount) new StringMap<String>()];
		var postSample = "";
		final postSeconds = elapsedIndexedNamed("post_candidate_collect", calls, i -> {
			postSeed.scope.localTypes = postLocalTypes[i];
			postSeed.scope.localTypeOverrides = postOverrideMaps[i];
			for (stmt in postCandidateStmts)
				@:privateAccess backend.cpp.CppTargetCore.collectDynamicLocalTypeOverridesFromStmt(stmt, postSeed.scope, postSeedCandidates);
			postSample = postSeed.scope.localTypeOverrides.get("callback");
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
		var mapOuterGateSample = false;
		final mapOuterGateSeconds = elapsedNamed("map_outer_gate", calls, () -> {
			mapOuterGateSample = @:privateAccess backend.cpp.CppTargetCore.callArgsHaveDirectDynamicLocalCandidate([mapCall, EString("mapped")], mapCandidates);
		});
		final mapLeafExprs = [
			EIdent("eq"),
			EField(EIdent("regex0"), "map"),
			EString("value"),
			EIdent("callback"),
			EString("mapped")
		];
		var mapLeafSample = "";
		final mapLeafSeconds = elapsedNamed("map_leaf_walk", calls, () -> {
			for (expr in mapLeafExprs)
				@:privateAccess backend.cpp.CppTargetCore.collectDynamicLocalTypeOverridesFromExpr(expr, mapFixture.scope, mapCandidates);
			mapLeafSample = mapFixture.scope.localTypes.get("callback");
		});
		var mapNonemptyCheckSample = 0;
		final mapNonemptyCheckSeconds = elapsedNamed("map_nonempty_checks", calls, () -> {
			mapNonemptyCheckSample = 0;
			for (_ in 0...8)
				if (@:privateAccess backend.cpp.CppTargetCore.boolMapHasEntries(mapCandidates))
					mapNonemptyCheckSample++;
		});
		var mapExprOldWalkSample = "";
		final mapExprOldWalkSeconds = elapsedNamed("map_expr_old_walk", calls, () -> {
			for (_ in 0...7)
				@:privateAccess backend.cpp.CppTargetCore.boolMapHasEntries(mapCandidates);
			@:privateAccess backend.cpp.CppTargetCore.collectDynamicLocalTypeOverridesFromExpr(mapExpr, mapFixture.scope, mapCandidates);
			mapExprOldWalkSample = mapFixture.scope.localTypeOverrides.get("callback");
		});
		var mapExprResolvedOldSample = "";
		final mapExprResolvedOldSeconds = elapsedNamed("map_expr_resolved_old", calls, () -> {
			@:privateAccess backend.cpp.CppTargetCore.collectDynamicLocalTypeOverridesFromExpr(mapExpr, mapFixture.scope, mapCandidates);
			replayResolvedERegMapInferenceWork(EField(EIdent("regex0"), "map"), [EString("value"), EIdent("callback")], mapFixture.scope, mapCandidates);
			mapExprResolvedOldSample = mapFixture.scope.localTypeOverrides.get("callback");
		});
		var resolvedMapCallSample = "";
		final resolvedMapCallSeconds = elapsedNamed("resolved_map_call", calls, () -> {
			@:privateAccess backend.cpp.CppTargetCore.collectDynamicLocalTypeOverridesFromExpr(mapCall, mapFixture.scope, mapCandidates);
			resolvedMapCallSample = mapFixture.scope.localTypeOverrides.get("callback");
		});
		var resolvedMapCallOldSample = "";
		final resolvedMapCallOldSeconds = elapsedNamed("resolved_map_call_old", calls, () -> {
			replayResolvedERegMapInferenceWork(EField(EIdent("regex0"), "map"), [EString("value"), EIdent("callback")], mapFixture.scope, mapCandidates);
			resolvedMapCallOldSample = mapFixture.scope.localTypeOverrides.get("callback");
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
		final resolvedMapFixture = fixture();
		resolvedMapFixture.scope.localNames.set("regex0", "regex0");
		resolvedMapFixture.scope.localNames.set("callback", "callback");
		resolvedMapFixture.scope.localTypes.set("regex0", "std::shared_ptr<EReg>");
		resolvedMapFixture.scope.localTypes.set("callback", EXPECTED_CALLBACK_TYPE);
		resolvedMapFixture.scope.localTypeOverrides.set("callback", EXPECTED_CALLBACK_TYPE);
		resolvedMapFixture.scope.argTypeOverrides.set("callback", EXPECTED_CALLBACK_TYPE);
		var resolvedMapSample = "";
		final resolvedMapSeconds = elapsedNamed("resolved_forwarded_map", calls, () -> {
			@:privateAccess backend.cpp.CppTargetCore.collectForwardedCallArgTypeOverrides(EField(EIdent("regex0"), "map"),
				[EString("value"), EIdent("callback")], resolvedMapFixture.scope, mapCandidates);
			resolvedMapSample = resolvedMapFixture.scope.localTypeOverrides.get("callback") + "/" + resolvedMapFixture.scope.argTypeOverrides.get("callback");
		});
		var resolvedMapOldSample = false;
		final resolvedMapOldSeconds = elapsedNamed("resolved_forwarded_map_old", calls, () -> {
			resolvedMapOldSample = @:privateAccess backend.cpp.CppTargetCore.applyTargetOwnedForwardedERegMapCallbackOverride(EField(EIdent("regex0"), "map"),
				[EString("value"), EIdent("callback")], resolvedMapFixture.scope, mapCandidates);
		});
		final resolvedInertLeafSample = @:privateAccess backend.cpp.CppTargetCore.targetOwnedResolvedERegMapInferenceLeavesAreInert(EField(EIdent("regex0"),
			"map"), [EString("value"), EIdent("callback")], resolvedMapFixture.scope, mapCandidates);
		final nestedCandidateLeafSample = @:privateAccess backend.cpp.CppTargetCore.targetOwnedResolvedERegMapInferenceLeavesAreInert(EField(EIdent("regex0"),
			"map"), [ECall(EIdent("identity"), [EIdent("callback")]), EIdent("callback")], resolvedMapFixture.scope, mapCandidates);
		final unrelatedReceiverLeafSample = @:privateAccess backend.cpp.CppTargetCore.targetOwnedResolvedERegMapInferenceLeavesAreInert(EField(EIdent("other"),
			"map"), [EString("value"), EIdent("callback")], resolvedMapFixture.scope, mapCandidates);

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
		assertTrue(freshERegLocalGateSample && qualifiedFreshERegLocalGateSample && !unrelatedFreshLocalGateSample,
			"fresh EReg local registration should stay limited to exact target-owned EReg constructors");
		assertTrue(declaredTypeSample == EXPECTED_CALLBACK_TYPE, "explicit EReg callbacks should retain their exact declared callable type");
		assertTrue(snapshotSample == 0
			&& prefixInitSample == 0
			&& prefixNameSample == "11/11"
			&& prefixTypeSample == 11
			&& prefixPredicateSample == 0
			&& prefixCallableSample == 0
			&& prefixDynamicSample == 0
			&& prefixEqSample == 0
			&& prefixSample == "11/0"
			&& prefixOldSample == "11/0"
			&& candidateSample == EXPECTED_CALLBACK_TYPE + "/true"
			&& postSample == EXPECTED_CALLBACK_TYPE,
			"snapshot, prefix, candidate, and post-candidate phase outputs should retain exact local state");
		assertTrue(overrideSample == EXPECTED_CALLBACK_TYPE && completeSample == EXPECTED_CALLBACK_TYPE,
			"isolated and complete override writes should retain the exact EReg callback type");
		assertTrue(completeOldSample == EXPECTED_CALLBACK_TYPE
			&& noForwardSample == null
			&& mapExprSample == EXPECTED_CALLBACK_TYPE
			&& mapExprOldSample == EXPECTED_CALLBACK_TYPE
			&& forwardedMapSample == EXPECTED_CALLBACK_TYPE,
			"no-forward, complete map-expression, and direct forwarded-map phases should retain their exact override contracts");
		assertTrue(!mapOuterGateSample
			&& mapLeafSample == EXPECTED_CALLBACK_TYPE
			&& mapNonemptyCheckSample == 8
			&& mapExprOldWalkSample == EXPECTED_CALLBACK_TYPE
			&& mapExprResolvedOldSample == EXPECTED_CALLBACK_TYPE
			&& resolvedMapCallSample == EXPECTED_CALLBACK_TYPE
			&& resolvedMapCallOldSample == EXPECTED_CALLBACK_TYPE,
			"outer-gate, recursive-leaf, and nonempty-candidate attribution should retain exact map-expression state");
		assertTrue(resolvedMapSample == EXPECTED_CALLBACK_TYPE + "/" + EXPECTED_CALLBACK_TYPE && resolvedMapOldSample,
			"already-resolved EReg.map callback evidence should retain both exact override maps");
		assertTrue(resolvedInertLeafSample && !nestedCandidateLeafSample && !unrelatedReceiverLeafSample,
			"resolved EReg.map leaf skipping should preserve nested-candidate and unrelated-receiver traversal");
		assertTrue(staleSample == "std::function<std::string(bool)>" && openSample == "int" && !plainEvidence,
			"stale callable, open Dynamic, and ordinary local controls should retain their inference contracts");

		Sys.println("CPP_DYNAMIC_LOCAL_PREP_BENCH:PASS calls=" + calls + " guard_seconds=" + guardSeconds + " callable_predicate_seconds=" + callableSeconds
			+ " declared_type_seconds=" + declaredTypeSeconds + " scope_snapshot_seconds=" + snapshotSeconds + " prefix_init_walk_seconds="
			+ prefixInitSeconds + " prefix_names_seconds=" + prefixNameSeconds + " prefix_types_seconds=" + prefixTypeSeconds + " prefix_predicates_seconds="
			+ prefixPredicateSeconds + " prefix_callable_checks_seconds=" + prefixCallableSeconds + " prefix_dynamic_checks_seconds=" + prefixDynamicSeconds
			+ " prefix_eq_walk_seconds=" + prefixEqSeconds + " prefix_collect_seconds=" + prefixSeconds + " prefix_collect_old_seconds=" + prefixOldSeconds
			+ " candidate_decl_seconds=" + candidateSeconds + " post_candidate_collect_seconds=" + postSeconds + " override_write_seconds="
			+ overrideWriteSeconds + " complete_seconds=" + completeSeconds + " complete_old_seconds=" + completeOldSeconds + " complete_no_forward_seconds="
			+ noForwardSeconds + " map_expr_seconds=" + mapExprSeconds + " map_outer_gate_seconds=" + mapOuterGateSeconds + " map_leaf_walk_seconds="
			+ mapLeafSeconds + " map_nonempty_checks_seconds=" + mapNonemptyCheckSeconds + " map_expr_old_seconds=" + mapExprOldSeconds
			+ " map_expr_old_walk_seconds=" + mapExprOldWalkSeconds + " map_expr_resolved_old_seconds=" + mapExprResolvedOldSeconds
			+ " resolved_map_call_seconds=" + resolvedMapCallSeconds + " resolved_map_call_old_seconds=" + resolvedMapCallOldSeconds
			+ " forwarded_map_seconds=" + forwardedMapSeconds + " resolved_forwarded_map_seconds=" + resolvedMapSeconds
			+ " resolved_forwarded_map_old_seconds=" + resolvedMapOldSeconds + " override=" + completeSample);
	}
}
