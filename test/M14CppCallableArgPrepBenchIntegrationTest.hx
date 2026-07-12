import HxDefaultValue.NoDefault;
import HxExpr;
import HxStmt;
import haxe.ds.StringMap;

typedef CppCallableArgPrepFixture = {
	var fn:HxFunctionDecl;
	var scope:backend.cpp.CppRenderScope;
}

/** Focused attribution probe for C++ callable-argument preparation. **/
class M14CppCallableArgPrepBenchIntegrationTest {
	static inline final DEFAULT_CALLS = 5000;
	static inline final EXPECTED_CALLABLE_TYPE = "std::function<int(int)>";

	static function assertTrue(cond:Bool, message:String):Void {
		if (!cond)
			throw message;
	}

	static function envInt(name:String, fallback:Int):Int {
		final raw = Sys.getEnv(name);
		final parsed = raw == null ? null : Std.parseInt(raw);
		return parsed == null || parsed <= 0 ? fallback : parsed;
	}

	static function selected(name:String):Bool {
		final only = Sys.getEnv("HXHX_CPP_CALLABLE_ARG_PREP_BENCH_ONLY");
		return only == null || StringTools.trim(only).length == 0 || only == name;
	}

	static function elapsed(name:String, calls:Int, action:Void->Void):Float {
		action();
		if (!selected(name))
			return -1.;
		final start = Sys.time();
		for (_ in 0...calls)
			action();
		return Sys.time() - start;
	}

	static function fixture(ownerName:String, fnName:String, args:Array<HxFunctionArg>, returnHint:String, returnCppType:String, body:Array<HxStmt>,
			?extraFunctions:Array<HxFunctionDecl>):CppCallableArgPrepFixture {
		final fn = new HxFunctionDecl(fnName, Public, false, args, returnHint, body, "");
		final functions = [fn];
		if (extraFunctions != null)
			for (extra in extraFunctions)
				functions.push(extra);
		final owner = new HxClassDecl(ownerName, false, functions, []);
		final names = new StringMap<Bool>();
		final classes = new StringMap<HxClassDecl>();
		names.set(ownerName, true);
		classes.set(ownerName, owner);
		return {
			fn: fn,
			scope: @:privateAccess backend.cpp.CppTargetCore.renderScope(owner, {names: names, byName: classes, all: [owner]}, returnCppType)
		};
	}

	static function arg(name:String, typeHint:String):HxFunctionArg {
		return new HxFunctionArg(name, typeHint, NoDefault, false, false);
	}

	static function strictFixture():CppCallableArgPrepFixture {
		final body = new Array<HxStmt>();
		for (i in 0...11)
			body.push(SVar("regex" + i, "EReg", ENew("EReg", [EString("p" + i), EString("")]), HxPos.unknown()));
		for (i in 0...57)
			body.push(SExpr(ECall(EIdent("eq"), [EInt(i), EInt(i)]), HxPos.unknown()));
		body.push(SVar("callback", "EReg->String", ELambda(["value"], EIdent("value")), HxPos.unknown()));
		for (i in 0...19)
			body.push(SExpr(ECall(EField(EIdent("regex" + (i % 11)), "map"), [EString("value" + i), EIdent("callback")]), HxPos.unknown()));
		assertTrue(body.length == 88, "callable-argument fixture should retain 88 statements");
		return fixture("TestEReg", "test", [], "Void", "void", body);
	}

	static function usesDeclaredArgs(sample:CppCallableArgPrepFixture):Bool {
		return @:privateAccess backend.cpp.CppTargetCore.knownStdlibMethodUsesDeclaredCallableArgs(sample.scope, sample.fn);
	}

	static function mayNeedInference(sample:CppCallableArgPrepFixture):Bool {
		return @:privateAccess backend.cpp.CppTargetCore.functionMayNeedCallableArgTypeOverrides(sample.fn);
	}

	static function runComplete(sample:CppCallableArgPrepFixture):Void {
		if (!usesDeclaredArgs(sample) && mayNeedInference(sample))
			@:privateAccess backend.cpp.CppTargetCore.inferCallableArgTypeOverrides(sample.scope, sample.fn);
	}

	static function directCallable(owner:String, name:String, typeHint:String):CppCallableArgPrepFixture {
		return fixture(owner, name, [arg("callback", typeHint)], "Int", "int", [SReturn(ECall(EIdent("callback"), [EInt(1)]), HxPos.unknown())]);
	}

	static function assertControls():Void {
		for (sample in [
			directCallable("StringCallableOwner", "run", "String"),
			directCallable("DynamicCallableOwner", "run", "Dynamic")
		]) {
			assertTrue(mayNeedInference(sample), "legacy String-shaped and Dynamic called arguments should retain inference evidence");
			runComplete(sample);
			assertTrue(sample.scope.argTypeOverrides.get("callback") == EXPECTED_CALLABLE_TYPE,
				"called erased arguments should retain the exact Int callable override");
		}

		final concrete = directCallable("ConcreteOwner", "run", "Int->Int");
		assertTrue(!mayNeedInference(concrete), "concrete callable arguments should retain their declared function type");
		final unusedString = fixture("UnusedStringOwner", "run", [arg("callback", "String")], "Void", "void", [SReturnVoid(HxPos.unknown())]);
		assertTrue(!mayNeedInference(unusedString), "unused String arguments should not be treated as erased callables");
		final openUnused = fixture("OpenUnusedOwner", "run", [arg("value", "")], "Void", "void", [SReturnVoid(HxPos.unknown())]);
		assertTrue(mayNeedInference(openUnused), "untyped arguments should conservatively retain inference evidence");
		runComplete(openUnused);
		assertTrue(!openUnused.scope.argTypeOverrides.exists("value"), "unused open arguments should not gain an override");

		final target = new HxFunctionDecl("target", Public, false, [arg("callback", "Int->Int")], "Int",
			[SReturn(ECall(EIdent("callback"), [EInt(1)]), HxPos.unknown())], "");
		final forwarded = fixture("ForwardingOwner", "run", [arg("callback", "Dynamic")], "Int", "int",
			[SReturn(ECall(EIdent("target"), [EIdent("callback")]), HxPos.unknown())], [target]);
		assertTrue(!usesDeclaredArgs(forwarded) && mayNeedInference(forwarded), "ordinary owner methods should preserve forwarded callable inference");
		runComplete(forwarded);
		assertTrue(forwarded.scope.argTypeOverrides.get("callback") == EXPECTED_CALLABLE_TYPE,
			"same-owner forwarding should retain the declared target callable shape");

		final resolver = fixture("DefaultResolver", "resolveClass", [arg("name", "String")], "Class<Dynamic>", "std::shared_ptr<Class>", []);
		assertTrue(usesDeclaredArgs(resolver), "DefaultResolver.resolveClass should retain its exact declared-argument skip");
		assertTrue(!mayNeedInference(resolver), "the resolver's unused String argument should not need callable inference");
	}

	static function main():Void {
		assertControls();
		final calls = envInt("HXHX_CPP_CALLABLE_ARG_PREP_BENCH_CALLS", DEFAULT_CALLS);
		final strict = strictFixture();
		var declaredSkipSample = true;
		final declaredSkipSeconds = elapsed("declared_skip", calls, () -> declaredSkipSample = usesDeclaredArgs(strict));
		var preflightSample = true;
		final preflightSeconds = elapsed("preflight", calls, () -> preflightSample = mayNeedInference(strict));
		final completeNegativeSeconds = elapsed("complete_negative", calls, () -> runComplete(strict));
		final positive = directCallable("TimedPositiveOwner", "timedPositive", "String");
		final completePositiveSeconds = elapsed("complete_positive", calls, () -> {
			positive.scope.argTypeOverrides.remove("callback");
			runComplete(positive);
		});

		assertTrue(!declaredSkipSample, "TestEReg.test should not use a target-known declared-argument skip");
		assertTrue(!preflightSample, "zero-argument TestEReg.test should not need callable-argument inference");
		assertTrue(!strict.scope.argTypeOverrides.keys().hasNext(), "negative callable-argument preparation should not write overrides");
		assertTrue(positive.scope.argTypeOverrides.get("callback") == EXPECTED_CALLABLE_TYPE,
			"timed positive callable-argument inference should retain exact typing");
		Sys.println("cpp_callable_arg_prep_bench_calls=" + calls);
		Sys.println("declared_skip_seconds=" + declaredSkipSeconds);
		Sys.println("preflight_seconds=" + preflightSeconds);
		Sys.println("complete_negative_seconds=" + completeNegativeSeconds);
		Sys.println("complete_positive_seconds=" + completePositiveSeconds);
	}
}
