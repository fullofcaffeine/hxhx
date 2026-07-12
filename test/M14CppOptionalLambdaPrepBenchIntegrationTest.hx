import HxExpr;
import HxStmt;
import haxe.ds.StringMap;

typedef CppOptionalLambdaPrepFixture = {
	var fn:HxFunctionDecl;
	var scope:backend.cpp.CppRenderScope;
}

/**
	Focused attribution probe for C++ optional-lambda local preparation.

	The strict-shaped negative fixture contains no parser-normalized optional
	lambda local. Positive controls preserve call-shape inference, exact optional
	argument typing, and local-shadow isolation.
**/
class M14CppOptionalLambdaPrepBenchIntegrationTest {
	static inline final DEFAULT_CALLS = 5000;
	static inline final EXPECTED_LAMBDA_TYPE = "std::function<int(int, std::optional<int>)>";

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
		final only = Sys.getEnv("HXHX_CPP_OPTIONAL_LAMBDA_PREP_BENCH_ONLY");
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

	static function fixture(ownerName:String, fnName:String, body:Array<HxStmt>):CppOptionalLambdaPrepFixture {
		final fn = new HxFunctionDecl(fnName, Public, false, [], "Void", body, "");
		final owner = new HxClassDecl(ownerName, false, [fn], []);
		final names = new StringMap<Bool>();
		final classes = new StringMap<HxClassDecl>();
		names.set(ownerName, true);
		classes.set(ownerName, owner);
		return {
			fn: fn,
			scope: @:privateAccess backend.cpp.CppTargetCore.renderScope(owner, {names: names, byName: classes, all: [owner]}, "void")
		};
	}

	static function strictFixture():CppOptionalLambdaPrepFixture {
		final body = new Array<HxStmt>();
		for (i in 0...11)
			body.push(SVar("regex" + i, "EReg", ENew("EReg", [EString("p" + i), EString("")]), HxPos.unknown()));
		for (i in 0...57)
			body.push(SExpr(ECall(EIdent("eq"), [EInt(i), EInt(i)]), HxPos.unknown()));
		body.push(SVar("callback", "EReg->String", ELambda(["value"], EIdent("value")), HxPos.unknown()));
		for (i in 0...19)
			body.push(SExpr(ECall(EField(EIdent("regex" + (i % 11)), "map"), [EString("value" + i), EIdent("callback")]), HxPos.unknown()));
		assertTrue(body.length == 88, "optional-lambda fixture should retain 88 statements");
		return fixture("TestEReg", "test", body);
	}

	static function isKnownSkip(sample:CppOptionalLambdaPrepFixture):Bool {
		return @:privateAccess backend.cpp.CppTargetCore.knownMethodSkipsPrepLocalInference(sample.scope, sample.fn, "infer_optional_lambda_locals");
	}

	static function runComplete(sample:CppOptionalLambdaPrepFixture):Void {
		if (!isKnownSkip(sample) && backend.cpp.CppPrepLocalInferenceGuard.functionHasOptionalLambdaLocalInferenceEvidence(sample.fn))
			@:privateAccess backend.cpp.CppTargetCore.inferOptionalLambdaLocalTypeOverrides(sample.scope, sample.fn);
	}

	static function normalizedOptionalLambda():HxExpr {
		return ECall(EIdent("__hxhx_optional_lambda"), [ELambda(["a", "b"], EIdent("a")), EArrayDecl([EString("b")])]);
	}

	static function optionalBody(local:String, typeHint:String = ""):Array<HxStmt> {
		return [
			SVar(local, typeHint, normalizedOptionalLambda(), HxPos.unknown()),
			SExpr(ECall(EIdent(local), [EInt(1)]), HxPos.unknown()),
			SExpr(ECall(EIdent(local), [EInt(1), EInt(2)]), HxPos.unknown())
		];
	}

	static function assertControls():Void {
		final positive = fixture("PositiveOwner", "positive", optionalBody("callback"));
		assertTrue(backend.cpp.CppPrepLocalInferenceGuard.functionHasOptionalLambdaLocalInferenceEvidence(positive.fn),
			"unhinted normalized optional lambdas should retain evidence");
		runComplete(positive);
		assertTrue(positive.scope.localTypeOverrides.get("callback") == EXPECTED_LAMBDA_TYPE,
			"optional-lambda inference should retain the exact optional Int function type");

		final typed = fixture("TypedOwner", "typed", optionalBody("callback", "Int->?Int->Int"));
		assertTrue(!backend.cpp.CppPrepLocalInferenceGuard.functionHasOptionalLambdaLocalInferenceEvidence(typed.fn),
			"explicitly typed normalized lambdas should not need optional-lambda inference");
		final plainLambda = fixture("PlainLambdaOwner", "plainLambda", [SVar("callback", "", ELambda(["value"], EIdent("value")), HxPos.unknown())]);
		assertTrue(!backend.cpp.CppPrepLocalInferenceGuard.functionHasOptionalLambdaLocalInferenceEvidence(plainLambda.fn),
			"ordinary lambdas should remain outside the normalized optional-lambda pass");

		final nested = fixture("NestedOwner", "nested", [SBlock(optionalBody("callback"), HxPos.unknown())]);
		assertTrue(backend.cpp.CppPrepLocalInferenceGuard.functionHasOptionalLambdaLocalInferenceEvidence(nested.fn),
			"nested normalized optional lambdas should retain evidence");
		runComplete(nested);
		assertTrue(nested.scope.localTypeOverrides.get("callback") == EXPECTED_LAMBDA_TYPE, "nested optional-lambda inference should retain exact typing");

		final shadowed = fixture("ShadowedOwner", "shadowed", [
			SVar("callback", "Int->Int", ELambda(["value"], EIdent("value")), HxPos.unknown()),
			SBlock(optionalBody("callback"), HxPos.unknown())
		]);
		runComplete(shadowed);
		assertTrue(!shadowed.scope.localTypeOverrides.exists("callback"), "nested inference should not overwrite a typed outer shadow");
		assertTrue(shadowed.scope.localTypeOverrides.get("callback_2") == EXPECTED_LAMBDA_TYPE,
			"nested shadow inference should retain its distinct local name and exact type");

		final malformed = fixture("MalformedOwner", "malformed", [
			SVar("callback", "", ECall(EIdent("__hxhx_optional_lambda"), [ELambda(["value"], EIdent("value")), EString("value")]), HxPos.unknown())
		]);
		assertTrue(!backend.cpp.CppPrepLocalInferenceGuard.functionHasOptionalLambdaLocalInferenceEvidence(malformed.fn),
			"malformed optional-lambda helpers should remain excluded");
		final unrelated = fixture("UnrelatedOwner", "unrelated", [SVar("value", "", EString("value"), HxPos.unknown())]);
		assertTrue(!backend.cpp.CppPrepLocalInferenceGuard.functionHasOptionalLambdaLocalInferenceEvidence(unrelated.fn),
			"unrelated locals should remain outside optional-lambda inference");

		final unserializer = fixture("Unserializer", "unserialize", optionalBody("callback"));
		final testType = fixture("TestType", "testInlineCast", optionalBody("callback"));
		assertTrue(!isKnownSkip(unserializer) && !isKnownSkip(testType), "existing target-known skips should not bypass optional-lambda inference");
	}

	static function main():Void {
		assertControls();
		final calls = envInt("HXHX_CPP_OPTIONAL_LAMBDA_PREP_BENCH_CALLS", DEFAULT_CALLS);
		final strict = strictFixture();
		var knownSkipSample = true;
		final knownSkipSeconds = elapsed("known_skip", calls, () -> knownSkipSample = isKnownSkip(strict));
		var guardSample = true;
		final guardSeconds = elapsed("guard", calls, () -> {
			guardSample = backend.cpp.CppPrepLocalInferenceGuard.functionHasOptionalLambdaLocalInferenceEvidence(strict.fn);
		});
		final completeNegativeSeconds = elapsed("complete_negative", calls, () -> runComplete(strict));
		final positive = fixture("TimedPositiveOwner", "timedPositive", optionalBody("callback"));
		final completePositiveSeconds = elapsed("complete_positive", calls, () -> {
			positive.scope.localTypeOverrides.remove("callback");
			runComplete(positive);
		});

		assertTrue(!knownSkipSample, "TestEReg.test should not use a target-known optional-lambda skip");
		assertTrue(!guardSample, "strict-shaped TestEReg should have no optional-lambda evidence");
		assertTrue(!strict.scope.localTypeOverrides.keys().hasNext(), "negative optional-lambda preparation should not write overrides");
		assertTrue(positive.scope.localTypeOverrides.get("callback") == EXPECTED_LAMBDA_TYPE,
			"timed positive optional-lambda inference should retain exact typing");
		Sys.println("cpp_optional_lambda_prep_bench_calls=" + calls);
		Sys.println("known_skip_seconds=" + knownSkipSeconds);
		Sys.println("guard_seconds=" + guardSeconds);
		Sys.println("complete_negative_seconds=" + completeNegativeSeconds);
		Sys.println("complete_positive_seconds=" + completePositiveSeconds);
	}
}
