import HxExpr;
import HxStmt;
import haxe.ds.StringMap;

typedef CppStringMapPrepFixture = {
	var fn:HxFunctionDecl;
	var scope:backend.cpp.CppRenderScope;
}

/** Focused attribution probe for C++ StringMap local preparation. **/
class M14CppStringMapPrepBenchIntegrationTest {
	static inline final DEFAULT_CALLS = 5000;
	static inline final EXPECTED_MAP_TYPE = "std::shared_ptr<StringMap<int>>";

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
		final only = Sys.getEnv("HXHX_CPP_STRING_MAP_PREP_BENCH_ONLY");
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

	static function fixture(name:String, body:Array<HxStmt>):CppStringMapPrepFixture {
		final fn = new HxFunctionDecl(name, Public, false, [], "Void", body, "");
		final owner = new HxClassDecl("StringMapPrepOwner_" + name, false, [fn], []);
		final names = new StringMap<Bool>();
		final classes = new StringMap<HxClassDecl>();
		final ownerName = HxClassDecl.getName(owner);
		names.set(ownerName, true);
		classes.set(ownerName, owner);
		return {
			fn: fn,
			scope: @:privateAccess backend.cpp.CppTargetCore.renderScope(owner, {names: names, byName: classes, all: [owner]}, "void")
		};
	}

	static function strictFixture():CppStringMapPrepFixture {
		final body = new Array<HxStmt>();
		for (i in 0...11)
			body.push(SVar("regex" + i, "EReg", ENew("EReg", [EString("p" + i), EString("")]), HxPos.unknown()));
		for (i in 0...57)
			body.push(SExpr(ECall(EIdent("eq"), [EInt(i), EInt(i)]), HxPos.unknown()));
		body.push(SVar("callback", "EReg->String", ELambda(["value"], EIdent("value")), HxPos.unknown()));
		for (i in 0...19)
			body.push(SExpr(ECall(EField(EIdent("regex" + (i % 11)), "map"), [EString("value" + i), EIdent("callback")]), HxPos.unknown()));
		assertTrue(body.length == 88, "StringMap fixture should retain 88 statements");
		return fixture("test", body);
	}

	static function runComplete(sample:CppStringMapPrepFixture):Void {
		if (backend.cpp.CppPrepLocalInferenceGuard.functionHasStringMapLocalInferenceEvidence(sample.fn))
			backend.cpp.CppLocalTypeInference.inferStringMapLocalTypeOverrides(sample.scope, sample.fn,
				@:privateAccess backend.cpp.CppTargetCore.localTypeInferenceApi());
	}

	static function mapBody(local:String, typeHint:String = ""):Array<HxStmt> {
		return [
			SVar(local, typeHint, ENew("haxe.ds.StringMap", []), HxPos.unknown()),
			SExpr(ECall(EField(EIdent(local), "set"), [EString("key"), EInt(7)]), HxPos.unknown())
		];
	}

	static function assertControls():Void {
		final positive = fixture("positive", mapBody("map"));
		assertTrue(backend.cpp.CppPrepLocalInferenceGuard.functionHasStringMapLocalInferenceEvidence(positive.fn),
			"unhinted StringMap constructors should retain evidence");
		runComplete(positive);
		assertTrue(positive.scope.localTypeOverrides.get("map") == EXPECTED_MAP_TYPE, "StringMap set evidence should retain the exact Int value type");

		final typed = fixture("typed", mapBody("map", "StringMap<Int>"));
		assertTrue(!backend.cpp.CppPrepLocalInferenceGuard.functionHasStringMapLocalInferenceEvidence(typed.fn),
			"typed StringMap locals should not need inference");
		final nested = fixture("nested", [SBlock(mapBody("map"), HxPos.unknown())]);
		assertTrue(backend.cpp.CppPrepLocalInferenceGuard.functionHasStringMapLocalInferenceEvidence(nested.fn),
			"nested unhinted StringMap locals should retain evidence");
		final shadowed = fixture("shadowed", [
			SVar("map", "StringMap<Int>", ENew("StringMap", []), HxPos.unknown()),
			SBlock(mapBody("map"), HxPos.unknown())
		]);
		runComplete(shadowed);
		assertTrue(!shadowed.scope.localTypeOverrides.exists("map"), "block-local inferred map overrides should not escape onto a typed outer shadow");
		final unrelated = fixture("unrelated", [SVar("value", "", ENew("OtherMap", []), HxPos.unknown())]);
		assertTrue(!backend.cpp.CppPrepLocalInferenceGuard.functionHasStringMapLocalInferenceEvidence(unrelated.fn),
			"unrelated map-like constructors should remain excluded");
	}

	static function main():Void {
		assertControls();
		final calls = envInt("HXHX_CPP_STRING_MAP_PREP_BENCH_CALLS", DEFAULT_CALLS);
		final strict = strictFixture();
		var guardSample = true;
		final guardSeconds = elapsed("guard", calls, () -> {
			guardSample = backend.cpp.CppPrepLocalInferenceGuard.functionHasStringMapLocalInferenceEvidence(strict.fn);
		});
		final completeNegativeSeconds = elapsed("complete_negative", calls, () -> runComplete(strict));
		final positive = fixture("timedPositive", mapBody("map"));
		final completePositiveSeconds = elapsed("complete_positive", calls, () -> {
			positive.scope.localTypeOverrides.remove("map");
			runComplete(positive);
		});
		assertTrue(!guardSample, "strict-shaped TestEReg should have no StringMap evidence");
		assertTrue(!strict.scope.localTypeOverrides.keys().hasNext(), "negative StringMap preparation should not write overrides");
		assertTrue(positive.scope.localTypeOverrides.get("map") == EXPECTED_MAP_TYPE, "timed positive StringMap inference should retain exact typing");
		Sys.println("cpp_string_map_prep_bench_calls=" + calls);
		Sys.println("guard_seconds=" + guardSeconds);
		Sys.println("complete_negative_seconds=" + completeNegativeSeconds);
		Sys.println("complete_positive_seconds=" + completePositiveSeconds);
	}
}
