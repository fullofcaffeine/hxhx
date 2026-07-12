import HxDefaultValue.NoDefault;
import HxExpr;
import HxStmt;
import haxe.ds.StringMap;

typedef CppKnownArgTypesPrepFixture = {
	var owner:HxClassDecl;
	var fn:HxFunctionDecl;
	var scope:backend.cpp.CppRenderScope;
}

/**
	Focused attribution probe for C++ known-argument-type preparation.

	The zero-argument fixture matches the strict TestEReg frontier's owner,
	inheritance, and statement count without copying upstream test source.
	Selectable phases separate the zero-argument evidence check, inherited
	utest recognition, known-signature lookup, override writes, and the complete
	preparation pass. Exact controls cover inherited optional positions, extra
	arguments, unrelated lookalikes, and target-owned constructor signatures.
**/
class M14CppKnownArgTypesPrepBenchIntegrationTest {
	static inline final DEFAULT_CALLS = 5000;

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
		final only = Sys.getEnv("HXHX_CPP_KNOWN_ARG_TYPES_BENCH_ONLY");
		return only == null || StringTools.trim(only).length == 0 || only == name;
	}

	static function elapsedNamed(name:String, calls:Int, action:Void->Void):Float {
		action();
		if (!selectedBench(name))
			return -1.;
		final start = Sys.time();
		for (_ in 0...calls)
			action();
		return Sys.time() - start;
	}

	static function addClass(cls:HxClassDecl, names:StringMap<Bool>, classes:StringMap<HxClassDecl>, all:Array<HxClassDecl>):Void {
		final name = HxClassDecl.getName(cls);
		names.set(name, true);
		classes.set(name, cls);
		all.push(cls);
	}

	/** Build a repo-owned TestEReg-shaped zero-argument method and class graph. **/
	static function strictFixture():CppKnownArgTypesPrepFixture {
		final names = new StringMap<Bool>();
		final classes = new StringMap<HxClassDecl>();
		final all = new Array<HxClassDecl>();
		final test = new HxClassDecl("Test", false, [], []);
		final body = [for (i in 0...88) SExpr(EInt(i), HxPos.unknown())];
		final fn = new HxFunctionDecl("test", Public, false, [], "Void", body, "");
		final owner = new HxClassDecl("TestEReg", false, [fn], [], "Test");
		addClass(test, names, classes, all);
		addClass(owner, names, classes, all);
		for (i in 0...280)
			addClass(new HxClassDecl("KnownArgTypesDummy" + i, false, [], []), names, classes, all);
		return {
			owner: owner,
			fn: fn,
			scope: @:privateAccess backend.cpp.CppTargetCore.renderScope(owner, {names: names, byName: classes, all: all}, "void")
		};
	}

	static function scopeFor(owner:HxClassDecl, classes:Array<HxClassDecl>):backend.cpp.CppRenderScope {
		final names = new StringMap<Bool>();
		final byName = new StringMap<HxClassDecl>();
		for (cls in classes) {
			final name = HxClassDecl.getName(cls);
			names.set(name, true);
			byName.set(name, cls);
		}
		return @:privateAccess backend.cpp.CppTargetCore.renderScope(owner, {names: names, byName: byName, all: classes}, "void");
	}

	/** Replay the complete pre-zero-argument-gate preparation for same-source comparison. **/
	static function replayUngatedKnownArgTypes(scope:backend.cpp.CppRenderScope, fn:HxFunctionDecl):Void {
		@:privateAccess backend.cpp.CppTargetCore.applyKnownUtestForwardedPositionArgOverride(scope, fn);
		final ownerName = HxClassDecl.getName(scope.owner);
		final methodName = HxFunctionDecl.getName(fn);
		final knownTypes = methodName == "new" ? @:privateAccess
			backend.cpp.CppTargetCore.knownStdlibConstructorParamCppTypes(ownerName, scope, scope.classLookup, fn) : @:privateAccess
			backend.cpp.CppTargetCore.knownStdlibMethodParamCppTypes(ownerName, methodName, scope, scope.classLookup);
		if (knownTypes.length == 0)
			return;
		final args = HxFunctionDecl.getArgs(fn);
		for (i in 0...args.length) {
			if (i >= knownTypes.length)
				break;
			final typeName = knownTypes[i];
			if (typeName != null && typeName.length > 0)
				scope.argTypeOverrides.set(@:privateAccess backend.cpp.CppTargetCore.sanitizeIdentifier(HxFunctionArg.getName(args[i])), typeName);
		}
	}

	static function assertExactControls():Void {
		final test = new HxClassDecl("Test", false, [], []);
		final forwarded = new HxFunctionDecl("checkExc", Public, false, [new HxFunctionArg("pos", "", NoDefault, true, false)], "Void", [
			SExpr(ECall(EIdent("exc"), [ELambda([], EInt(1)), EIdent("pos")]), HxPos.unknown())
		], "");
		final inheritedOwner = new HxClassDecl("TestInheritedKnownArgs", false, [forwarded], [], "Test");
		final inheritedScope = scopeFor(inheritedOwner, [test, inheritedOwner]);
		@:privateAccess backend.cpp.CppTargetCore.applyKnownStdlibFunctionArgOverrides(inheritedScope, forwarded);
		assertTrue(inheritedScope.argTypeOverrides.get("pos") == "PosInfos", "inherited wrappers should type forwarded optional utest positions");

		final nonForwarded = new HxFunctionDecl("plain", Public, false, [new HxFunctionArg("pos", "", NoDefault, true, false)], "Void", [], "");
		final nonForwardedScope = scopeFor(inheritedOwner, [test, inheritedOwner]);
		@:privateAccess backend.cpp.CppTargetCore.applyKnownStdlibFunctionArgOverrides(nonForwardedScope, nonForwarded);
		assertTrue(!nonForwardedScope.argTypeOverrides.exists("pos"), "optional positions should remain untouched when they are not forwarded");

		final exc = new HxFunctionDecl("exc", Public, false, [
			new HxFunctionArg("callback", "Dynamic", NoDefault),
			new HxFunctionArg("pos", "Dynamic", NoDefault, true),
			new HxFunctionArg("extra", "Dynamic", NoDefault)
		], "Void", [], "");
		final testScope = scopeFor(test, [test]);
		@:privateAccess backend.cpp.CppTargetCore.applyKnownStdlibFunctionArgOverrides(testScope, exc);
		assertTrue(testScope.argTypeOverrides.get("callback") == "std::function<void()>", "target-owned Test.exc should type its callback argument");
		assertTrue(testScope.argTypeOverrides.get("pos") == "std::optional<PosInfos>", "target-owned Test.exc should type its optional position argument");
		assertTrue(!testScope.argTypeOverrides.exists("extra"), "extra arguments beyond a known signature should remain untouched");

		final lookalike = new HxClassDecl("TestForwardKnownStdlibLike", false, [exc], []);
		final lookalikeScope = scopeFor(lookalike, [test, lookalike]);
		@:privateAccess backend.cpp.CppTargetCore.applyKnownStdlibFunctionArgOverrides(lookalikeScope, exc);
		assertTrue(!lookalikeScope.argTypeOverrides.exists("callback") && !lookalikeScope.argTypeOverrides.exists("pos"),
			"unrelated methods named exc should not inherit Test's target-owned signature");

		final jsonCtor = new HxFunctionDecl("new", Public, false, [
			new HxFunctionArg("replacer", "Dynamic", NoDefault),
			new HxFunctionArg("space", "Dynamic", NoDefault)
		], "Void", [], "");
		final jsonOwner = new HxClassDecl("JsonPrinter", false, [jsonCtor], []);
		final jsonScope = scopeFor(jsonOwner, [jsonOwner]);
		@:privateAccess backend.cpp.CppTargetCore.applyKnownStdlibFunctionArgOverrides(jsonScope, jsonCtor);
		assertTrue(jsonScope.argTypeOverrides.get("replacer") == "std::function<std::string(std::string, std::string)>",
			"target-owned JsonPrinter constructor should type its callback argument");
		assertTrue(jsonScope.argTypeOverrides.get("space") == "std::string", "target-owned JsonPrinter constructor should type its string argument");
	}

	static function main():Void {
		assertExactControls();
		final calls = envInt("HXHX_CPP_KNOWN_ARG_TYPES_BENCH_CALLS", DEFAULT_CALLS);
		final strict = strictFixture();
		var zeroArgSample = false;
		final zeroArgSeconds = elapsedNamed("zero_arg_gate", calls, () -> {
			zeroArgSample = HxFunctionDecl.getArgs(strict.fn).length == 0;
		});
		var inheritedSample = false;
		final inheritedSeconds = elapsedNamed("inherited_utest", calls, () -> {
			@:privateAccess backend.cpp.CppTargetCore.applyKnownUtestForwardedPositionArgOverride(strict.scope, strict.fn);
			inheritedSample = strict.scope.classInheritanceCache.get("TestEReg\x1fTest");
		});
		var knownTypesSample = -1;
		final knownTypesSeconds = elapsedNamed("known_types", calls, () -> {
			knownTypesSample = @:privateAccess
				backend.cpp.CppTargetCore.knownStdlibMethodParamCppTypes("TestEReg", "test", strict.scope, strict.scope.classLookup).length;
		});
		final oldCompleteSeconds = elapsedNamed("old_complete", calls, () -> replayUngatedKnownArgTypes(strict.scope, strict.fn));
		final completeSeconds = elapsedNamed("complete", calls, () -> {
			@:privateAccess backend.cpp.CppTargetCore.applyKnownStdlibFunctionArgOverrides(strict.scope, strict.fn);
		});

		final test = new HxClassDecl("Test", false, [], []);
		final exc = new HxFunctionDecl("exc", Public, false, [
			new HxFunctionArg("callback", "Dynamic", NoDefault),
			new HxFunctionArg("pos", "Dynamic", NoDefault, true)
		], "Void", [], "");
		final writeScope = scopeFor(test, [test]);
		final overrideWriteSeconds = elapsedNamed("override_writes", calls, () -> {
			writeScope.argTypeOverrides.remove("callback");
			writeScope.argTypeOverrides.remove("pos");
			@:privateAccess backend.cpp.CppTargetCore.applyKnownStdlibFunctionArgOverrides(writeScope, exc);
		});

		assertTrue(zeroArgSample, "strict-shaped TestEReg.test should have no declared arguments");
		assertTrue(inheritedSample, "strict-shaped TestEReg should retain inherited Test recognition");
		assertTrue(knownTypesSample == 0, "TestEReg.test should have no target-owned known signature");
		assertTrue(strict.scope.argTypeOverrides.keys().hasNext() == false, "zero-argument known-type preparation should not write overrides");
		assertTrue(writeScope.argTypeOverrides.get("callback") == "std::function<void()>",
			"timed target-owned override writes should retain the callback type");
		assertTrue(writeScope.argTypeOverrides.get("pos") == "std::optional<PosInfos>",
			"timed target-owned override writes should retain the optional position type");

		Sys.println("cpp_known_arg_types_prep_bench_calls=" + calls);
		Sys.println("zero_arg_gate_seconds=" + zeroArgSeconds);
		Sys.println("inherited_utest_seconds=" + inheritedSeconds);
		Sys.println("known_types_seconds=" + knownTypesSeconds);
		Sys.println("old_complete_seconds=" + oldCompleteSeconds);
		Sys.println("complete_seconds=" + completeSeconds);
		Sys.println("override_writes_seconds=" + overrideWriteSeconds);
	}
}
