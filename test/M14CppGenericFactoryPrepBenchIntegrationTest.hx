import HxExpr;
import HxStmt;
import haxe.ds.StringMap;

typedef CppGenericFactoryPrepFixture = {
	var fn:HxFunctionDecl;
	var scope:backend.cpp.CppRenderScope;
}

/**
	Focused attribution probe for C++ generic-factory local preparation.

	The strict-shaped negative fixture contains no unhinted zero-argument
	constructor local. Positive controls preserve generic field inference, exact
	local override output, target-known skips, and lexical-scope isolation.
**/
class M14CppGenericFactoryPrepBenchIntegrationTest {
	static inline final DEFAULT_CALLS = 5000;
	static inline final EXPECTED_FACTORY_TYPE = "std::shared_ptr<GenericRoot<std::string>>";

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
		final only = Sys.getEnv("HXHX_CPP_GENERIC_FACTORY_PREP_BENCH_ONLY");
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

	static function genericRoot():HxClassDecl {
		return new HxClassDecl("GenericRoot", false, [new HxFunctionDecl("new", Public, false, [], "Void", [], "")],
			[new HxFieldDecl("root", Public, false, "T", null)], "", ["__hxhx_type_params=T"]);
	}

	static function fixture(ownerName:String, fnName:String, body:Array<HxStmt>):CppGenericFactoryPrepFixture {
		final fn = new HxFunctionDecl(fnName, Public, false, [], "Void", body, "");
		final owner = new HxClassDecl(ownerName, false, [fn], []);
		final root = genericRoot();
		final plain = new HxClassDecl("Plain", false, [new HxFunctionDecl("new", Public, false, [], "Void", [], "")], []);
		final names = new StringMap<Bool>();
		final classes = new StringMap<HxClassDecl>();
		final all = [owner, root, plain];
		for (cls in all) {
			final name = HxClassDecl.getName(cls);
			names.set(name, true);
			classes.set(name, cls);
		}
		return {
			fn: fn,
			scope: @:privateAccess backend.cpp.CppTargetCore.renderScope(owner, {names: names, byName: classes, all: all}, "void")
		};
	}

	static function strictFixture():CppGenericFactoryPrepFixture {
		final body = new Array<HxStmt>();
		for (i in 0...11)
			body.push(SVar("regex" + i, "EReg", ENew("EReg", [EString("p" + i), EString("")]), HxPos.unknown()));
		for (i in 0...57)
			body.push(SExpr(ECall(EIdent("eq"), [EInt(i), EInt(i)]), HxPos.unknown()));
		body.push(SVar("callback", "EReg->String", ELambda(["value"], EIdent("value")), HxPos.unknown()));
		for (i in 0...19)
			body.push(SExpr(ECall(EField(EIdent("regex" + (i % 11)), "map"), [EString("value" + i), EIdent("callback")]), HxPos.unknown()));
		assertTrue(body.length == 88, "generic-factory fixture should retain 88 statements");
		return fixture("TestEReg", "test", body);
	}

	static function isKnownSkip(sample:CppGenericFactoryPrepFixture):Bool {
		return @:privateAccess backend.cpp.CppTargetCore.knownMethodSkipsPrepLocalInference(sample.scope, sample.fn, "infer_generic_factory_locals");
	}

	static function runComplete(sample:CppGenericFactoryPrepFixture):Void {
		if (!isKnownSkip(sample) && backend.cpp.CppPrepLocalInferenceGuard.functionHasGenericFactoryLocalInferenceEvidence(sample.fn))
			@:privateAccess backend.cpp.CppTargetCore.inferGenericFactoryLocalTypeOverrides(sample.scope, sample.fn);
	}

	static function factoryBody(local:String, typeHint:String = "", args:Null<Array<HxExpr>> = null):Array<HxStmt> {
		final ctorArgs = args == null ? [] : args;
		return [
			SVar(local, typeHint, ENew("GenericRoot", ctorArgs), HxPos.unknown()),
			SExpr(EBinop("=", EField(EIdent(local), "root"), EString("value")), HxPos.unknown())
		];
	}

	static function assertControls():Void {
		final positive = fixture("PositiveOwner", "positive", factoryBody("box"));
		assertTrue(backend.cpp.CppPrepLocalInferenceGuard.functionHasGenericFactoryLocalInferenceEvidence(positive.fn),
			"unhinted zero-argument constructors should retain generic-factory evidence");
		runComplete(positive);
		assertTrue(positive.scope.localTypeOverrides.get("box") == EXPECTED_FACTORY_TYPE,
			"generic field inference should retain the exact String factory type");

		final typed = fixture("TypedOwner", "typed", factoryBody("box", "GenericRoot<String>"));
		assertTrue(!backend.cpp.CppPrepLocalInferenceGuard.functionHasGenericFactoryLocalInferenceEvidence(typed.fn),
			"explicitly typed constructors should not need generic-factory inference");
		final withArg = fixture("WithArgOwner", "withArg", factoryBody("box", "", [EString("value")]));
		assertTrue(!backend.cpp.CppPrepLocalInferenceGuard.functionHasGenericFactoryLocalInferenceEvidence(withArg.fn),
			"constructors with arguments should remain outside zero-argument factory inference");

		final nested = fixture("NestedOwner", "nested", [SBlock(factoryBody("box"), HxPos.unknown())]);
		assertTrue(backend.cpp.CppPrepLocalInferenceGuard.functionHasGenericFactoryLocalInferenceEvidence(nested.fn),
			"nested unhinted zero-argument constructors should retain evidence");
		runComplete(nested);
		assertTrue(!nested.scope.localTypeOverrides.exists("box"), "nested factory overrides should not escape their lexical block");

		final shadowed = fixture("ShadowedOwner", "shadowed", [
			SVar("box", "GenericRoot<String>", ENew("GenericRoot", []), HxPos.unknown()),
			SBlock(factoryBody("box"), HxPos.unknown())
		]);
		runComplete(shadowed);
		assertTrue(!shadowed.scope.localTypeOverrides.exists("box"), "nested inference should not overwrite a typed outer shadow");

		final plain = fixture("PlainOwner", "plain", [SVar("value", "", ENew("Plain", []), HxPos.unknown())]);
		assertTrue(backend.cpp.CppPrepLocalInferenceGuard.functionHasGenericFactoryLocalInferenceEvidence(plain.fn),
			"the syntax guard should conservatively retain non-generic zero-argument constructors");
		runComplete(plain);
		assertTrue(!plain.scope.localTypeOverrides.exists("value"), "non-generic constructors should not receive a factory override");

		final noConstructor = fixture("NoConstructorOwner", "noConstructor", [SVar("value", "", EString("value"), HxPos.unknown())]);
		assertTrue(!backend.cpp.CppPrepLocalInferenceGuard.functionHasGenericFactoryLocalInferenceEvidence(noConstructor.fn),
			"locals without constructors should remain outside generic-factory inference");

		final knownSkip = fixture("Unserializer", "unserialize", factoryBody("box"));
		assertTrue(isKnownSkip(knownSkip), "Unserializer.unserialize should retain its target-known generic-factory skip");
		runComplete(knownSkip);
		assertTrue(!knownSkip.scope.localTypeOverrides.exists("box"), "target-known skips should bypass generic-factory writes");
	}

	static function main():Void {
		assertControls();
		final calls = envInt("HXHX_CPP_GENERIC_FACTORY_PREP_BENCH_CALLS", DEFAULT_CALLS);
		final strict = strictFixture();
		var knownSkipSample = true;
		final knownSkipSeconds = elapsed("known_skip", calls, () -> knownSkipSample = isKnownSkip(strict));
		var guardSample = true;
		final guardSeconds = elapsed("guard", calls, () -> {
			guardSample = backend.cpp.CppPrepLocalInferenceGuard.functionHasGenericFactoryLocalInferenceEvidence(strict.fn);
		});
		final completeNegativeSeconds = elapsed("complete_negative", calls, () -> runComplete(strict));
		final positive = fixture("TimedPositiveOwner", "timedPositive", factoryBody("box"));
		final completePositiveSeconds = elapsed("complete_positive", calls, () -> {
			positive.scope.localTypeOverrides.remove("box");
			runComplete(positive);
		});

		assertTrue(!knownSkipSample, "TestEReg.test should not use a target-known generic-factory skip");
		assertTrue(!guardSample, "strict-shaped TestEReg should have no generic-factory evidence");
		assertTrue(!strict.scope.localTypeOverrides.keys().hasNext(), "negative generic-factory preparation should not write overrides");
		assertTrue(positive.scope.localTypeOverrides.get("box") == EXPECTED_FACTORY_TYPE,
			"timed positive generic-factory inference should retain exact typing");
		Sys.println("cpp_generic_factory_prep_bench_calls=" + calls);
		Sys.println("known_skip_seconds=" + knownSkipSeconds);
		Sys.println("guard_seconds=" + guardSeconds);
		Sys.println("complete_negative_seconds=" + completeNegativeSeconds);
		Sys.println("complete_positive_seconds=" + completePositiveSeconds);
	}
}
