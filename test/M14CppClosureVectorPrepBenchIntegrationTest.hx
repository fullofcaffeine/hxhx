import HxExpr;
import HxStmt;
import haxe.ds.StringMap;

typedef CppClosureVectorPrepFixture = {
	var fn:HxFunctionDecl;
	var scope:backend.cpp.CppRenderScope;
}

/**
	Focused attribution probe for C++ closure-vector local preparation.

	The negative fixture reproduces TestEReg's 88-statement scale with no empty
	array candidate. Positive fixtures exercise the existing candidate, capture,
	push-evidence, vector typing, scope restoration, and override-write paths.
**/
class M14CppClosureVectorPrepBenchIntegrationTest {
	static inline final DEFAULT_CALLS = 5000;
	static inline final EXPECTED_VECTOR_TYPE = "std::vector<std::function<int()>>";

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
		final only = Sys.getEnv("HXHX_CPP_CLOSURE_VECTOR_PREP_BENCH_ONLY");
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

	static function scopeFor(owner:HxClassDecl):backend.cpp.CppRenderScope {
		final names = new StringMap<Bool>();
		final classes = new StringMap<HxClassDecl>();
		final name = HxClassDecl.getName(owner);
		names.set(name, true);
		classes.set(name, owner);
		return @:privateAccess backend.cpp.CppTargetCore.renderScope(owner, {names: names, byName: classes, all: [owner]}, "void");
	}

	static function fixture(name:String, body:Array<HxStmt>):CppClosureVectorPrepFixture {
		final fn = new HxFunctionDecl(name, Public, false, [], "Void", body, "");
		final owner = new HxClassDecl("ClosureVectorPrepOwner_" + name, false, [fn], []);
		return {fn: fn, scope: scopeFor(owner)};
	}

	static function strictFixture():CppClosureVectorPrepFixture {
		final body = new Array<HxStmt>();
		for (i in 0...11)
			body.push(SVar("regex" + i, "EReg", ENew("EReg", [EString("p" + i), EString("")]), HxPos.unknown()));
		for (i in 0...57)
			body.push(SExpr(ECall(EIdent("eq"), [EInt(i), EInt(i)]), HxPos.unknown()));
		body.push(SVar("callback", "EReg->String", ELambda(["value"], EIdent("value")), HxPos.unknown()));
		for (i in 0...19)
			body.push(SExpr(ECall(EField(EIdent("regex" + (i % 11)), "map"), [EString("value" + i), EIdent("callback")]), HxPos.unknown()));
		assertTrue(body.length == 88, "closure-vector fixture should retain 88 statements");
		return fixture("test", body);
	}

	static function candidateNames(fn:HxFunctionDecl):StringMap<Bool> {
		final candidates = new StringMap<Bool>();
		final inference = @:privateAccess new backend.cpp.CppLocalTypeInference(@:privateAccess backend.cpp.CppTargetCore.localTypeInferenceApi());
		for (stmt in HxFunctionDecl.getBody(fn))
			@:privateAccess inference.collectClosureVectorLocalCandidatesFromStmt(stmt, candidates);
		return candidates;
	}

	static function runComplete(fixture:CppClosureVectorPrepFixture):Void {
		backend.cpp.CppLocalTypeInference.inferClosureVectorLocalTypeOverrides(fixture.scope, fixture.fn,
			@:privateAccess backend.cpp.CppTargetCore.localTypeInferenceApi());
	}

	static function closureBody(local:String, captured:Bool):Array<HxStmt> {
		final lambdaBody = captured ? EIdent("i") : EInt(7);
		return [
			SVar(local, "", EArrayDecl([]), HxPos.unknown()),
			SForIn("i", ERange(EInt(0), EInt(2)), SBlock([
				SExpr(ECall(EField(EIdent(local), "push"), [ELambda([], lambdaBody)]), HxPos.unknown())
			], HxPos.unknown()), HxPos.unknown())
		];
	}

	static function assertControls():Void {
		final captured = fixture("captured", closureBody("funs", true));
		final nonCaptured = fixture("nonCaptured", closureBody("funs", false));
		for (sample in [captured, nonCaptured]) {
			assertTrue(candidateNames(sample.fn).exists("funs"), "unhinted empty arrays should remain closure-vector candidates");
			runComplete(sample);
			assertTrue(sample.scope.localTypeOverrides.get("funs") == EXPECTED_VECTOR_TYPE,
				"captured and non-captured closures should retain exact callable-vector typing");
		}

		final typed = fixture("typed", [SVar("funs", "Array<Void->Int>", EArrayDecl([]), HxPos.unknown())]);
		assertTrue(!candidateNames(typed.fn).exists("funs"), "explicitly typed empty arrays should not need closure-vector inference");
		final candidateOnly = fixture("candidateOnly", [SVar("funs", "", EArrayDecl([]), HxPos.unknown())]);
		runComplete(candidateOnly);
		assertTrue(!candidateOnly.scope.localTypeOverrides.exists("funs"), "empty arrays without pushed closures should not gain an override");

		final nestedBody = closureBody("funs", true);
		final nested = fixture("nested", [SBlock(nestedBody, HxPos.unknown())]);
		runComplete(nested);
		assertTrue(nested.scope.localTypeOverrides.get("funs") == EXPECTED_VECTOR_TYPE, "nested closure-vector declarations should remain visible");

		final shadowedBody = closureBody("funs", false);
		shadowedBody.insert(1, SBlock([SVar("funs", "Array<Int>", EArrayDecl([]), HxPos.unknown())], HxPos.unknown()));
		final shadowed = fixture("shadowed", shadowedBody);
		runComplete(shadowed);
		assertTrue(shadowed.scope.localTypeOverrides.get("funs") == EXPECTED_VECTOR_TYPE,
			"a typed nested shadow should not erase outer closure-vector evidence");

		final unrelated = fixture("unrelated", [SVar("value", "", EInt(1), HxPos.unknown())]);
		assertTrue(!candidateNames(unrelated.fn).keys().hasNext(), "unrelated locals should not become closure-vector candidates");
	}

	static function main():Void {
		assertControls();
		final calls = envInt("HXHX_CPP_CLOSURE_VECTOR_PREP_BENCH_CALLS", DEFAULT_CALLS);
		final strict = strictFixture();
		var candidateCount = -1;
		final candidateSeconds = elapsed("candidate_scan", calls, () -> {
			candidateCount = 0;
			for (_ in candidateNames(strict.fn).keys())
				candidateCount++;
		});
		final completeSeconds = elapsed("complete_negative", calls, () -> runComplete(strict));
		final positive = fixture("positive", closureBody("funs", true));
		final positiveSeconds = elapsed("complete_positive", calls, () -> {
			positive.scope.localTypeOverrides.remove("funs");
			runComplete(positive);
		});
		assertTrue(candidateCount == 0, "strict-shaped TestEReg should have no closure-vector candidate");
		assertTrue(!strict.scope.localTypeOverrides.keys().hasNext(), "negative closure-vector preparation should not write overrides");
		assertTrue(positive.scope.localTypeOverrides.get("funs") == EXPECTED_VECTOR_TYPE,
			"timed positive inference should retain exact callable-vector typing");
		Sys.println("cpp_closure_vector_prep_bench_calls=" + calls);
		Sys.println("candidate_scan_seconds=" + candidateSeconds);
		Sys.println("complete_negative_seconds=" + completeSeconds);
		Sys.println("complete_positive_seconds=" + positiveSeconds);
	}
}
