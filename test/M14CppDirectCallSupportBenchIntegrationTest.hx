import HxExpr;
import HxStmt;
import haxe.ds.StringMap;

typedef DirectCallSupportFixture = {
	var scope:backend.cpp.CppRenderScope;
	var owner:HxClassDecl;
}

/**
	Focused attribution probe for C++ direct-call owner and support-signature lookup.

	The upstream unit fixture calls inherited `Test.unspec` helpers without a
	parsed owner declaration. This probe keeps that path cheap to measure while
	locking down ordinary owner calls, local shadowing, free calls, and imported
	Int64 helpers that share the same direct-call dispatcher.
**/
class M14CppDirectCallSupportBenchIntegrationTest {
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

	static function fixture():DirectCallSupportFixture {
		final names = new StringMap<Bool>();
		final classes = new StringMap<HxClassDecl>();
		final all = new Array<HxClassDecl>();
		final testBase = new HxClassDecl("Test", false, [], []);
		var parent = testBase;
		for (i in 0...24) {
			final functions = switch (i) {
				case 5: [
						new HxFunctionDecl("overridden", Public, false, [new HxFunctionArg("value", "Int", NoDefault, false, false)], "Void", [], "")
					];
				case 8: [
						new HxFunctionDecl("staticInt", Public, true, [new HxFunctionArg("value", "Int", NoDefault, false, false)], "Void", [], "")
					];
				case 10: [new HxFunctionDecl("and", Public, false, [], "Void", [], "")];
				case 12: [
						new HxFunctionDecl("inheritedInt", Public, false, [new HxFunctionArg("value", "Int", NoDefault, false, false)], "Void", [], "")
					];
				case _: [];
			};
			final layer = new HxClassDecl("DirectSupportLayer" + i, false, functions, [], HxClassDecl.getName(parent));
			for (cls in [parent, layer]) {
				final name = HxClassDecl.getName(cls);
				if (!classes.exists(name)) {
					names.set(name, true);
					classes.set(name, cls);
					all.push(cls);
				}
			}
			parent = layer;
		}
		final ownInt = new HxFunctionDecl("ownInt", Public, false, [new HxFunctionArg("value", "Int", NoDefault, false, false)], "Void", [], "");
		final ownCallback = new HxFunctionDecl("ownCallback", Public, false, [new HxFunctionArg("callback", "EReg->String", NoDefault, false, false)], "Void",
			[], "");
		final overrideFn = new HxFunctionDecl("overridden", Public, false, [new HxFunctionArg("value", "String", NoDefault, false, false)], "Void", [], "");
		final owner = new HxClassDecl("DirectSupportOwner", false, [ownInt, ownCallback, overrideFn], [], HxClassDecl.getName(parent));
		final eReg = new HxClassDecl("EReg", false, [
			new HxFunctionDecl("map", Public, false, [
				new HxFunctionArg("value", "String", NoDefault, false, false),
				new HxFunctionArg("callback", "EReg->String", NoDefault, false, false)
			], "String", [], "")
		], []);
		names.set("EReg", true);
		classes.set("EReg", eReg);
		all.push(eReg);
		names.set(HxClassDecl.getName(owner), true);
		classes.set(HxClassDecl.getName(owner), owner);
		all.push(owner);
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

	static function cppDynamicTypeHint(typeHint:String):Bool {
		return @:privateAccess backend.cpp.CppTargetCore.isDynamicLikeTypeHint(typeHint);
	}

	static function walkOwnerChain(entry:DirectCallSupportFixture, visit:HxClassDecl->Void, inheritanceLookup:Bool = false):Void {
		final scope = entry.scope;
		final lookup = @:privateAccess backend.cpp.CppTargetCore.lookupForScope(scope);
		var current:HxClassDecl = entry.owner;
		final seen = new StringMap<Bool>();
		while (current != null) {
			final key = @:privateAccess backend.cpp.CppTargetCore.renderedClassName(current, lookup);
			if (key.length == 0 || seen.exists(key))
				break;
			seen.set(key, true);
			visit(current);
			final next = HxClassDecl.getExtendsPath(current);
			if (next == null || next.length == 0)
				break;
			current = if (inheritanceLookup) @:privateAccess backend.cpp.CppTargetCore.lookupClassForInheritancePath(next, scope, lookup);
			else
				@:privateAccess backend.cpp.CppTargetCore.lookupClassForTypeHint(next, scope, lookup);
		}
	}

	static function assertInheritanceLookupParity(entry:DirectCallSupportFixture):Void {
		final scope = entry.scope;
		final lookup = @:privateAccess backend.cpp.CppTargetCore.lookupForScope(scope);
		var current:HxClassDecl = entry.owner;
		while (current != null) {
			final next = HxClassDecl.getExtendsPath(current);
			if (next == null || next.length == 0)
				break;
			final general = @:privateAccess backend.cpp.CppTargetCore.lookupClassForTypeHint(next, scope, lookup);
			final inheritance = @:privateAccess backend.cpp.CppTargetCore.lookupClassForInheritancePath(next, scope, lookup);
			assertTrue(inheritance == general, "inheritance lookup should match general class lookup for " + next);
			current = inheritance;
		}
	}

	static function assertInheritanceLookupPathControls():Void {
		final names = new StringMap<Bool>();
		final classes = new StringMap<HxClassDecl>();
		final localBase = new HxClassDecl("Module.Base", false, [], []);
		final otherBase = new HxClassDecl("Other.Base", false, [], []);
		final owner = new HxClassDecl("Module.Child", false, [], [], "Base");
		for (entry in [
			{name: "Module_Base", cls: localBase},
			{name: "Other_Base", cls: otherBase},
			{name: "Base", cls: otherBase},
			{name: "Module_Child", cls: owner}
		]) {
			names.set(entry.name, true);
			classes.set(entry.name, entry.cls);
		}
		final scope = @:privateAccess backend.cpp.CppTargetCore.renderScope(owner, {names: names, byName: classes, all: [localBase, otherBase, owner]}, "void");
		final lookup = @:privateAccess backend.cpp.CppTargetCore.lookupForScope(scope);
		final resolve = path -> @:privateAccess backend.cpp.CppTargetCore.lookupClassForInheritancePath(path, scope, lookup);
		assertTrue(resolve("Base") == localBase, "unqualified inheritance should prefer the owner's module-local class");
		assertTrue(resolve("Other.Base") == otherBase, "qualified inheritance should retain its exact class owner");
		assertTrue(resolve("Module.Base<T>") == localBase, "generic inheritance should resolve its class path without probing value carriers");
	}

	static function main():Void {
		final calls = envInt("HXHX_CPP_DIRECT_SUPPORT_BENCH_CALLS", DEFAULT_CALLS);
		assertInheritanceLookupParity(fixture());
		assertInheritanceLookupPathControls();
		var sampleOwner:HxClassDecl = null;
		final currentFixture = fixture();
		final currentOwnerSeconds = elapsed(calls, () -> {
			sampleOwner = @:privateAccess backend.cpp.CppTargetCore.currentOrInheritedOwnerMethodOwner("ownInt", currentFixture.scope);
		});
		assertTrue(sampleOwner == currentFixture.owner, "current direct-call methods should resolve to the current owner");

		final inheritedFixture = fixture();
		final inheritedOwnerSeconds = elapsed(calls, () -> {
			sampleOwner = @:privateAccess backend.cpp.CppTargetCore.currentOrInheritedOwnerMethodOwner("inheritedInt", inheritedFixture.scope);
		});
		assertTrue(sampleOwner != null && HxClassDecl.getName(sampleOwner) == "DirectSupportLayer12",
			"inherited direct-call methods should resolve to their declaring owner");
		final inheritedFunction = @:privateAccess backend.cpp.CppTargetCore.ownerMethodDeclIn(sampleOwner, "inheritedInt");
		var inferredTypes:Array<String> = null;
		final inferredArgTypesSeconds = elapsed(calls, () -> {
			inferredTypes = @:privateAccess backend.cpp.CppTargetCore.inferredFunctionArgCppTypes(inheritedFunction, sampleOwner,
				inheritedFixture.scope.classByName, inheritedFixture.scope.allClasses);
		});
		assertTrue(inferredTypes.join(",") == "int", "inherited ordinary calls should retain inferred Int parameters");

		final missingFixture = fixture();
		final missingOwnerSeconds = elapsed(calls, () -> {
			sampleOwner = @:privateAccess backend.cpp.CppTargetCore.currentOrInheritedOwnerMethodOwner("ordinaryFree", missingFixture.scope);
		});
		assertTrue(sampleOwner == null, "ordinary free calls should not gain an owner");
		final coldMissingFixtures = [for (_ in 0...calls) fixture()];
		final coldMissingSeconds = elapsedIndexed(calls, i -> {
			sampleOwner = @:privateAccess
				backend.cpp.CppTargetCore.currentOrInheritedOwnerMethodOwner("ordinaryFree", coldMissingFixtures[i].scope);
		});
		assertTrue(sampleOwner == null, "fresh ordinary free calls should retain a complete owner miss");
		final hierarchyFixtures = [for (_ in 0...calls) fixture()];
		final hierarchySeconds = elapsedIndexed(calls, i -> walkOwnerChain(hierarchyFixtures[i], _ -> {}));
		final inheritanceLookupFixtures = [for (_ in 0...calls) fixture()];
		final inheritanceLookupSeconds = elapsedIndexed(calls, i -> walkOwnerChain(inheritanceLookupFixtures[i], _ -> {}, true));
		final inheritanceFixtures = [for (_ in 0...calls) fixture()];
		final inheritanceSeconds = elapsedIndexed(calls, i -> {
			final entry = inheritanceFixtures[i];
			final lookup = @:privateAccess backend.cpp.CppTargetCore.lookupForScope(entry.scope);
			final root = @:privateAccess backend.cpp.CppTargetCore.renderedClassName(entry.owner, lookup);
			walkOwnerChain(entry,
				cls -> @:privateAccess backend.cpp.CppTargetCore.cacheKnownClassInheritance(root,
					@:privateAccess backend.cpp.CppTargetCore.renderedClassName(cls, lookup),
					entry.scope));
		});
		final methodIndexFixtures = [for (_ in 0...calls) fixture()];
		final methodIndexSeconds = elapsedIndexed(calls,
			i -> walkOwnerChain(methodIndexFixtures[i],
				cls -> @:privateAccess backend.cpp.CppTargetCore.cacheNearestMethodOwners(cls, methodIndexFixtures[i].scope)));
		final combinedWalkFixtures = [for (_ in 0...calls) fixture()];
		final combinedWalkSeconds = elapsedIndexed(calls, i -> {
			final entry = combinedWalkFixtures[i];
			final lookup = @:privateAccess backend.cpp.CppTargetCore.lookupForScope(entry.scope);
			final root = @:privateAccess backend.cpp.CppTargetCore.renderedClassName(entry.owner, lookup);
			walkOwnerChain(entry, cls -> {
				@:privateAccess backend.cpp.CppTargetCore.cacheKnownClassInheritance(root, @:privateAccess backend.cpp.CppTargetCore.renderedClassName(cls,
					lookup),
					entry.scope);
				@:privateAccess backend.cpp.CppTargetCore.cacheNearestMethodOwners(cls, entry.scope);
			});
		});
		final postMissFixtures = [for (_ in 0...calls) fixture()];
		for (entry in postMissFixtures)
			@:privateAccess backend.cpp.CppTargetCore.currentOrInheritedOwnerMethodOwner("firstMissing", entry.scope);
		final postMissMissingSeconds = elapsedIndexed(calls, i -> {
			sampleOwner = @:privateAccess backend.cpp.CppTargetCore.currentOrInheritedOwnerMethodOwner("secondMissing", postMissFixtures[i].scope);
		});
		assertTrue(sampleOwner == null, "a distinct name after a full owner miss should remain ownerless");
		final postMissInheritedSeconds = elapsedIndexed(calls, i -> {
			sampleOwner = @:privateAccess backend.cpp.CppTargetCore.currentOrInheritedOwnerMethodOwner("inheritedInt", postMissFixtures[i].scope);
		});
		assertTrue(sampleOwner != null && HxClassDecl.getName(sampleOwner) == "DirectSupportLayer12",
			"a full owner miss should not change later inherited-owner resolution");
		final indexedControl = postMissFixtures[0];
		final overriddenOwner = @:privateAccess backend.cpp.CppTargetCore.currentOrInheritedOwnerMethodOwner("overridden", indexedControl.scope);
		final staticOwner = @:privateAccess backend.cpp.CppTargetCore.currentOrInheritedOwnerMethodOwner("staticInt", indexedControl.scope);
		final sanitizedOwner = @:privateAccess backend.cpp.CppTargetCore.currentOrInheritedOwnerMethodOwner("and_", indexedControl.scope);
		assertTrue(overriddenOwner == indexedControl.owner, "nearest overrides should win after a full-chain miss");
		assertTrue(staticOwner != null && HxClassDecl.getName(staticOwner) == "DirectSupportLayer8",
			"static owner methods should retain direct owner discovery");
		assertTrue(sanitizedOwner != null && HxClassDecl.getName(sanitizedOwner) == "DirectSupportLayer10",
			"sanitized direct-call names should retain owner discovery");

		final supportFixture = fixture();
		var supportTypes:Array<String> = null;
		final supportSignatureSeconds = elapsed(calls, () -> {
			supportTypes = @:privateAccess backend.cpp.CppTargetCore.knownDirectCallSupportParamCppTypes(null, "unspec", supportFixture.scope);
		});
		assertTrue(supportTypes.join(",") == "std::function<void()>,std::optional<PosInfos>",
			"inherited Test.unspec should keep its target-owned support signature");

		final forwardedFixture = fixture();
		final forwardedCandidates = new StringMap<Bool>();
		forwardedCandidates.set("callback", true);
		forwardedFixture.scope.localNames.set("callback", "callback");
		forwardedFixture.scope.localTypes.set("callback", "std::function<std::string(std::shared_ptr<EReg>)>");
		final forwardedCandidateMissSeconds = elapsed(calls, () -> {
			@:privateAccess backend.cpp.CppTargetCore.collectForwardedCallArgTypeOverrides(EIdent("ownInt"), [EInt(1)], forwardedFixture.scope,
				forwardedCandidates);
		});
		final forwardedCandidateHitSeconds = elapsed(calls, () -> {
			@:privateAccess backend.cpp.CppTargetCore.collectForwardedCallArgTypeOverrides(EIdent("ownCallback"), [EIdent("callback")],
				forwardedFixture.scope, forwardedCandidates);
		});
		assertTrue(forwardedFixture.scope.localTypeOverrides.get("callback") == "std::function<std::string(std::shared_ptr<EReg>)>",
			"forwarded candidate identifiers should retain their exact callback parameter override");
		forwardedFixture.scope.localNames.set("regex", "regex");
		forwardedFixture.scope.localTypes.set("regex", "std::shared_ptr<EReg>");
		final forwardedERegMapSeconds = elapsed(calls, () -> {
			@:privateAccess backend.cpp.CppTargetCore.collectForwardedCallArgTypeOverrides(EField(EIdent("regex"), "map"),
				[EString("value"), EIdent("callback")], forwardedFixture.scope, forwardedCandidates);
		});
		assertTrue(forwardedFixture.scope.localTypeOverrides.get("callback") == "std::function<std::string(std::shared_ptr<EReg>)>",
			"typed EReg.map forwarding should retain its exact named callback override");

		final exactCallbackBody = new Array<HxStmt>();
		exactCallbackBody.push(SVar("regex", "EReg", ENew("EReg", [EString("a"), EString("")]), HxPos.unknown()));
		exactCallbackBody.push(SVar("callback", "EReg->String", ELambda(["value"], EString("ok")), HxPos.unknown()));
		for (i in 0...40)
			exactCallbackBody.push(SExpr(ECall(EField(EIdent("regex"), "map"), [EString("value" + i), EIdent("callback")]), HxPos.unknown()));
		final exactCallbackFn = new HxFunctionDecl("exactCallback", Public, false, [], "Void", exactCallbackBody, "");
		final exactCallbackFixture = fixture();
		var exactCallbackOverride = "";
		final dynamicExactCallbackSeconds = elapsed(calls, () -> {
			exactCallbackFixture.scope.localTypeOverrides = new StringMap<String>();
			@:privateAccess backend.cpp.CppTargetCore.inferDynamicLocalTypeOverrides(exactCallbackFixture.scope, exactCallbackFn);
			exactCallbackOverride = exactCallbackFixture.scope.localTypeOverrides.get("callback");
		});
		assertTrue(exactCallbackOverride == "std::function<std::string(std::shared_ptr<EReg>)>",
			"full dynamic-local inference should retain an exact forwarded EReg callback type");

		final staleCallbackFn = new HxFunctionDecl("staleCallback", Public, false, [], "Void", [
			SVar("callback", "(String)->String", ELambda(["value"], EIdent("value")), HxPos.unknown()),
			SExpr(ECall(EIdent("callback"), [EBool(true)]), HxPos.unknown())
		], "");
		final staleCallbackFixture = fixture();
		var staleCallbackOverride = "";
		final dynamicStaleCallbackSeconds = elapsed(calls, () -> {
			staleCallbackFixture.scope.localTypeOverrides = new StringMap<String>();
			@:privateAccess backend.cpp.CppTargetCore.inferDynamicLocalTypeOverrides(staleCallbackFixture.scope, staleCallbackFn);
			staleCallbackOverride = staleCallbackFixture.scope.localTypeOverrides.get("callback");
		});
		assertTrue(staleCallbackOverride == "std::function<std::string(bool)>",
			"full dynamic-local inference should still refine stale callable argument types from direct calls");
		final dynamicControlFn = new HxFunctionDecl("dynamicControls", Public, false, [], "Void", [
			SVar("capturedText", "String", EString("captured"), HxPos.unknown()),
			SVar("capturedCallback", "EReg->String", ELambda(["value"], EIdent("capturedText")), HxPos.unknown()),
			SExpr(ECall(EIdent("ownCallback"), [EIdent("capturedCallback")]), HxPos.unknown()),
			SVar("inferredCallback", "", ELambda([], EString("inferred")), HxPos.unknown()),
			SVar("dynamicValue", "Dynamic", ENull, HxPos.unknown()),
			SExpr(EBinop("=", EIdent("dynamicValue"), EInt(3)), HxPos.unknown()),
			SVar("ordinary", "Int", EInt(1), HxPos.unknown())
		], "");
		final dynamicControlFixture = fixture();
		@:privateAccess backend.cpp.CppTargetCore.inferDynamicLocalTypeOverrides(dynamicControlFixture.scope, dynamicControlFn);
		assertTrue(dynamicControlFixture.scope.localTypeOverrides.get("capturedCallback") == "std::function<std::string(std::shared_ptr<EReg>)>"
			&& dynamicControlFixture.scope.localTypeOverrides.get("inferredCallback") == "std::function<std::string()>"
			&& dynamicControlFixture.scope.localTypeOverrides.get("dynamicValue") == "int"
			&& !dynamicControlFixture.scope.localTypeOverrides.exists("ordinary"),
			"dynamic-local inference should preserve captured, inferred, open, and non-callable controls");
		final dynamicEvidenceSeconds = elapsed(calls,
			() -> backend.cpp.CppPrepLocalInferenceGuard.functionHasDynamicLocalInferenceEvidence(exactCallbackFn, cppDynamicTypeHint));

		final callback = ELambda([], EBool(true));
		final coldLookupFixtures = [for (_ in 0...calls) fixture()];
		var coldLookupTypes:Array<String> = null;
		final coldLookupSeconds = elapsedIndexed(calls, i -> {
			final cold = coldLookupFixtures[i];
			final owner = @:privateAccess backend.cpp.CppTargetCore.currentOrInheritedOwnerMethodOwner("unspec", cold.scope);
			coldLookupTypes = @:privateAccess backend.cpp.CppTargetCore.knownDirectCallSupportParamCppTypes(owner, "unspec", cold.scope);
		});
		assertTrue(coldLookupTypes.join(",") == supportTypes.join(","), "cold owner and support discovery should retain the inherited support signature");
		final coldCallFixtures = [for (_ in 0...calls) fixture()];
		var coldCallSample = "";
		final coldSupportCallSeconds = elapsedIndexed(calls, i -> {
			coldCallSample = @:privateAccess backend.cpp.CppTargetCore.directCallExpr("unspec", [callback], coldCallFixtures[i].scope);
		});
		assertTrue(StringTools.startsWith(coldCallSample, "unspec("), "cold support calls should retain exact direct-call dispatch");
		var argRenderSample:Array<String> = null;
		final argRenderSeconds = elapsed(calls, () -> {
			argRenderSample = @:privateAccess backend.cpp.CppTargetCore.renderKnownCppParamCallArgs(supportTypes, [callback], supportFixture.scope);
		});
		assertTrue(argRenderSample.length == 1 && StringTools.startsWith(argRenderSample[0], "[&]() -> void"),
			"support argument rendering should retain its expected callback type");
		var omittedSample = "";
		final omittedSupportSeconds = elapsed(calls, () -> {
			omittedSample = @:privateAccess backend.cpp.CppTargetCore.directCallExpr("unspec", [callback], supportFixture.scope);
		});
		supportFixture.scope.localNames.set("position", "position");
		supportFixture.scope.localTypes.set("position", "std::optional<PosInfos>");
		var explicitSample = "";
		final explicitSupportSeconds = elapsed(calls, () -> {
			explicitSample = @:privateAccess
				backend.cpp.CppTargetCore.directCallExpr("unspec", [callback, EIdent("position")], supportFixture.scope);
		});
		final excSample = @:privateAccess backend.cpp.CppTargetCore.directCallExpr("exc", [callback], supportFixture.scope);
		final positiveSample = @:privateAccess backend.cpp.CppTargetCore.directCallExpr("ownInt", [EInt(1)], supportFixture.scope);
		final negativeSample = @:privateAccess backend.cpp.CppTargetCore.directCallExpr("inheritedInt", [EUnop("-", EInt(1))], supportFixture.scope);
		final freeSample = @:privateAccess backend.cpp.CppTargetCore.directCallExpr("ordinaryFree", [EInt(1)], supportFixture.scope);
		final int64Sample = @:privateAccess backend.cpp.CppTargetCore.directCallExpr("ofInt", [EInt(3)], supportFixture.scope);
		supportFixture.scope.localNames.set("unspec", "local_unspec");
		supportFixture.scope.localTypes.set("unspec", "std::function<void(std::function<void()>)>");
		final shadowSample = @:privateAccess backend.cpp.CppTargetCore.directCallExpr("unspec", [callback], supportFixture.scope);

		assertTrue(StringTools.startsWith(omittedSample, "unspec(") && omittedSample.indexOf("PosInfos") < 0,
			"omitted PosInfos should continue relying on the support helper's C++ default");
		assertTrue(StringTools.startsWith(explicitSample, "unspec(") && explicitSample.indexOf("position") >= 0,
			"explicit PosInfos should retain target-owned optional-position forwarding, got " + explicitSample);
		assertTrue(StringTools.startsWith(excSample, "exc(") && excSample.indexOf("PosInfos") < 0,
			"inherited Test.exc should share the omitted-position support contract");
		assertTrue(positiveSample == "ownInt(1)" && negativeSample == "inheritedInt((-1))",
			"current and inherited Int methods should retain positive and negative literal rendering");
		assertTrue(freeSample == "ordinaryFree(1)", "unrelated free calls should retain ordinary direct rendering");
		assertTrue(int64Sample == "static_cast<long long>(3)", "imported Int64 controls should retain intrinsic lowering");
		assertTrue(StringTools.startsWith(shadowSample, "local_unspec("), "local callables should continue shadowing inherited support helpers");

		final nullCheckScope = fixture().scope;
		for (name in ["regex", "optionalText", "unknown"])
			nullCheckScope.localNames.set(name, name);
		nullCheckScope.localTypes.set("regex", "std::shared_ptr<EReg>");
		nullCheckScope.localTypes.set("optionalText", "std::optional<std::string>");
		final matched = ECall(EField(EIdent("regex"), "matched"), [EInt(1)]);
		final matchedNull = EBinop("==", matched, ENull);
		final matchedNotNull = EBinop("!=", matched, ENull);
		final nullMatched = EBinop("==", ENull, matched);
		final nullMatchedNot = EBinop("!=", ENull, matched);
		final matchedLeftNull = EBinop("==", ECall(EField(EIdent("regex"), "matchedLeft"), []), ENull);
		final nullMatchedRightNot = EBinop("!=", ENull, ECall(EField(EIdent("regex"), "matchedRight"), []));
		final optionalNull = EBinop("==", EIdent("optionalText"), ENull);
		final unrelatedNull = EBinop("==", ECall(EField(EIdent("regex"), "match"), [EString("value")]), ENull);
		final unknownMatchedNull = EBinop("==", ECall(EField(EIdent("unknown"), "matched"), [EInt(1)]), ENull);
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.renderExpr(matchedNull, nullCheckScope) == "(!regex->matched(1).has_value())"
			&& @:privateAccess backend.cpp.CppTargetCore.renderExpr(matchedNotNull, nullCheckScope) == "(regex->matched(1).has_value())"
			&& @:privateAccess backend.cpp.CppTargetCore.renderExpr(nullMatched, nullCheckScope) == "(!regex->matched(1).has_value())"
			&& @:privateAccess backend.cpp.CppTargetCore.renderExpr(nullMatchedNot, nullCheckScope) == "(regex->matched(1).has_value())"
			&& @:privateAccess backend.cpp.CppTargetCore.renderExpr(matchedLeftNull, nullCheckScope) == "false"
			&& @:privateAccess backend.cpp.CppTargetCore.renderExpr(nullMatchedRightNot, nullCheckScope) == "true",
			"typed EReg indexed captures should use nullable presence while side captures remain non-nullable");
		assertTrue(@:privateAccess backend.cpp.CppTargetCore.renderExpr(optionalNull, nullCheckScope) == "(!optionalText.has_value())",
			"optional locals should retain storage-aware null comparison");
		final unrelatedNullSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(unrelatedNull, nullCheckScope);
		final unknownMatchedNullSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(unknownMatchedNull, nullCheckScope);
		final nullCheckArgs = [matchedNull];
		var nullCheckSample = "";
		final nullCheckRenderSeconds = elapsed(calls,
			() -> nullCheckSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(matchedNull, nullCheckScope));
		var nullCheckArgSample = "";
		final nullCheckArgSeconds = elapsed(calls,
			() -> nullCheckArgSample = @:privateAccess backend.cpp.CppTargetCore.renderFunctionTypeCallArgs("", nullCheckArgs, nullCheckScope).join(", "));
		var matchedRenderSample = "";
		final matchedRenderSeconds = elapsed(calls, () -> matchedRenderSample = @:privateAccess backend.cpp.CppTargetCore.renderExpr(matched, nullCheckScope));
		var optionalSample = false;
		final matchedOptionalSeconds = elapsed(calls,
			() -> optionalSample = @:privateAccess backend.cpp.CppTargetCore.exprHasOptionalType(matched, nullCheckScope));
		var nonNullableSample = false;
		final matchedNonNullableSeconds = elapsed(calls,
			() -> nonNullableSample = @:privateAccess backend.cpp.CppTargetCore.exprHasNonNullableValueType(matched, nullCheckScope));
		var exactShapeSample = false;
		final matchedExactShapeSeconds = elapsed(calls,
			() -> exactShapeSample = @:privateAccess backend.cpp.CppTargetCore.isTypedLocalERegCaptureCall(EIdent("regex"), "matched", 1, nullCheckScope));
		var nullCheckCallSample = "";
		final nullCheckCallSeconds = elapsed(calls,
			() -> nullCheckCallSample = @:privateAccess backend.cpp.CppTargetCore.directCallExpr("t", nullCheckArgs, nullCheckScope));
		assertTrue(nullCheckSample == "(!regex->matched(1).has_value())"
			&& nullCheckArgSample == nullCheckSample
			&& matchedRenderSample == "regex->matched(1)"
			&& optionalSample
			&& !nonNullableSample
			&& exactShapeSample
			&& nullCheckCallSample == "t((!regex->matched(1).has_value()))",
			"focused typed EReg null checks should reproduce the repeated free-call argument leaf");

		Sys.println("CPP_DIRECT_CALL_SUPPORT_BENCH:PASS calls=" + calls + " current_owner_seconds=" + currentOwnerSeconds + " inherited_owner_seconds="
			+ inheritedOwnerSeconds + " inferred_arg_types_seconds=" + inferredArgTypesSeconds + " missing_owner_seconds=" + missingOwnerSeconds
			+ " cold_missing_seconds=" + coldMissingSeconds + " hierarchy_seconds=" + hierarchySeconds + " inheritance_lookup_seconds="
			+ inheritanceLookupSeconds + " inheritance_seconds=" + inheritanceSeconds + " method_index_seconds=" + methodIndexSeconds
			+ " combined_walk_seconds=" + combinedWalkSeconds + " post_miss_missing_seconds=" + postMissMissingSeconds + " post_miss_inherited_seconds="
			+ postMissInheritedSeconds + " support_signature_seconds=" + supportSignatureSeconds + " cold_lookup_seconds=" + coldLookupSeconds
			+ " forwarded_candidate_miss_seconds=" + forwardedCandidateMissSeconds + " forwarded_candidate_hit_seconds=" + forwardedCandidateHitSeconds
			+ " forwarded_ereg_map_seconds=" + forwardedERegMapSeconds + " dynamic_evidence_seconds=" + dynamicEvidenceSeconds
			+ " dynamic_exact_callback_seconds=" + dynamicExactCallbackSeconds + " dynamic_stale_callback_seconds=" + dynamicStaleCallbackSeconds
			+ " cold_support_call_seconds=" + coldSupportCallSeconds + " support_arg_render_seconds=" + argRenderSeconds + " omitted_support_seconds="
			+ omittedSupportSeconds + " explicit_support_seconds=" + explicitSupportSeconds + " null_check_render_seconds=" + nullCheckRenderSeconds
			+ " null_check_arg_seconds=" + nullCheckArgSeconds + " matched_render_seconds=" + matchedRenderSeconds + " matched_optional_seconds="
			+ matchedOptionalSeconds + " matched_non_nullable_seconds=" + matchedNonNullableSeconds + " matched_exact_shape_seconds="
			+ matchedExactShapeSeconds + " null_check_call_seconds=" + nullCheckCallSeconds + " unrelated_null_sample=" + unrelatedNullSample
			+ " unknown_matched_null_sample=" + unknownMatchedNullSample);
	}
}
