import HxDefaultValue.NoDefault;
import HxExpr;
import HxStmt;
import haxe.ds.StringMap;

typedef CppBindCallablePrepFixture = {
	var fn:HxFunctionDecl;
	var scope:backend.cpp.CppRenderScope;
}

/**
	Focused attribution probe for C++ bind-callable local preparation.

	The strict-shaped fixture is repo-owned and reproduces TestEReg's method
	scale without copying upstream source. Selectable phases compare the current
	deep bind-call syntax guard with the necessary unhinted callable-candidate
	check and the complete preparation branch. Positive controls retain actual
	bind inference and exact local override output.
**/
class M14CppBindCallablePrepBenchIntegrationTest {
	static inline final DEFAULT_CALLS = 5000;
	static inline final EXPECTED_CALLBACK_TYPE = "std::function<int(int)>";

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
		final only = Sys.getEnv("HXHX_CPP_BIND_CALLABLE_PREP_BENCH_ONLY");
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

	static function scopeFor(owner:HxClassDecl):backend.cpp.CppRenderScope {
		final names = new StringMap<Bool>();
		final classes = new StringMap<HxClassDecl>();
		names.set(HxClassDecl.getName(owner), true);
		classes.set(HxClassDecl.getName(owner), owner);
		return @:privateAccess backend.cpp.CppTargetCore.renderScope(owner, {names: names, byName: classes, all: [owner]}, "void");
	}

	/** Build an 88-statement no-bind method with a late explicitly typed callback. **/
	static function strictFixture():CppBindCallablePrepFixture {
		final body = new Array<HxStmt>();
		for (i in 0...11)
			body.push(SVar("regex" + i, "EReg", ENew("EReg", [EString("p" + i), EString("")]), HxPos.unknown()));
		for (i in 0...57)
			body.push(SExpr(ECall(EIdent("eq"), [EInt(i), EInt(i)]), HxPos.unknown()));
		body.push(SVar("callback", "EReg->String", ELambda(["value"], EIdent("value")), HxPos.unknown()));
		for (i in 0...19)
			body.push(SExpr(ECall(EField(EIdent("regex" + (i % 11)), "map"), [EString("value" + i), EIdent("callback")]), HxPos.unknown()));
		assertTrue(body.length == 88, "bind-callable strict fixture should retain 88 statements");
		final fn = new HxFunctionDecl("test", Public, false, [], "Void", body, "");
		final owner = new HxClassDecl("TestEReg", false, [fn], []);
		return {fn: fn, scope: scopeFor(owner)};
	}

	/** Return whether the function has an unhinted local callable candidate with at least one argument. **/
	static function functionHasBindCallableCandidate(fn:HxFunctionDecl):Bool {
		return @:privateAccess backend.cpp.CppPrepLocalInferenceGuard.functionHasLocalDeclEvidence(fn, (_, typeHint, init) -> {
			if (StringTools.trim(typeHint == null ? "" : typeHint).length > 0)
				return false;
			final lambda = @:privateAccess backend.cpp.CppTargetCore.localCallableLambdaShape(init);
			return lambda != null && lambda.args.length > 0;
		});
	}

	static function runCurrentPrepBranch(fixture:CppBindCallablePrepFixture):Void {
		if (backend.cpp.CppPrepLocalInferenceGuard.functionHasBindCallableEvidence(fixture.fn))
			@:privateAccess backend.cpp.CppTargetCore.inferBindCallableLocalTypeOverrides(fixture.scope, fixture.fn);
	}

	static function runCandidateGatedPrepBranch(fixture:CppBindCallablePrepFixture):Void {
		if (functionHasBindCallableCandidate(fixture.fn)
			&& backend.cpp.CppPrepLocalInferenceGuard.functionHasBindCallableEvidence(fixture.fn))
			@:privateAccess backend.cpp.CppTargetCore.inferBindCallableLocalTypeOverrides(fixture.scope, fixture.fn);
	}

	static function validBindFixture():CppBindCallablePrepFixture {
		final fn = new HxFunctionDecl("bindCallable", Public, false, [], "Void", [
			SVar("callback", "", ELambda(["value"], EIdent("value")), HxPos.unknown()),
			SExpr(ECall(ECall(EField(EIdent("callback"), "bind"), [EInt(1)]), []), HxPos.unknown())
		], "");
		final owner = new HxClassDecl("BindCallableOwner", false, [fn], []);
		return {fn: fn, scope: scopeFor(owner)};
	}

	static function assertExactControls():Void {
		final candidateOnly = new HxFunctionDecl("candidateOnly", Public, false, [], "Void",
			[SVar("callback", "", ELambda(["value"], EIdent("value")), HxPos.unknown())], "");
		assertTrue(functionHasBindCallableCandidate(candidateOnly), "unhinted local lambdas should remain bind-callable candidates");
		assertTrue(!backend.cpp.CppPrepLocalInferenceGuard.functionHasBindCallableEvidence(candidateOnly),
			"candidate-only functions should have no bind-call evidence");

		final bindOnly = new HxFunctionDecl("bindOnly", Public, false, [], "Void", [
			SExpr(ECall(EField(EIdent("externalCallback"), "bind"), [EInt(1)]), HxPos.unknown())
		], "");
		assertTrue(!functionHasBindCallableCandidate(bindOnly), "external bind calls should not invent a local candidate");
		assertTrue(backend.cpp.CppPrepLocalInferenceGuard.functionHasBindCallableEvidence(bindOnly),
			"external bind calls should remain visible to the conservative bind syntax guard");

		final typedCandidate = new HxFunctionDecl("typedCandidate", Public, false, [], "Void", [
			SVar("callback", "Int->Int", ELambda(["value"], EIdent("value")), HxPos.unknown()),
			SExpr(ECall(EField(EIdent("callback"), "bind"), [EInt(1)]), HxPos.unknown())
		], "");
		assertTrue(!functionHasBindCallableCandidate(typedCandidate), "explicitly typed lambdas should not need bind-callable inference");
		final optionalCandidate = new HxFunctionDecl("optionalCandidate", Public, false, [], "Void", [
			SVar("callback", "", ECall(EIdent("__hxhx_optional_lambda"), [ELambda(["value"], EIdent("value")), EArrayDecl([EString("value")])]),
				HxPos.unknown())
		], "");
		assertTrue(functionHasBindCallableCandidate(optionalCandidate), "parser-normalized optional lambdas should remain bind-callable candidates");
		final restCandidate = new HxFunctionDecl("restCandidate", Public, false, [], "Void", [
			SVar("callback", "", ECall(EIdent("__hxhx_rest_lambda"), [ELambda(["values"], EIdent("values")), EInt(0)]), HxPos.unknown())
		], "");
		assertTrue(functionHasBindCallableCandidate(restCandidate), "parser-normalized rest lambdas should remain bind-callable candidates");
		final optionalRestCandidate = new HxFunctionDecl("optionalRestCandidate", Public, false, [], "Void", [
			SVar("callback", "", ECall(EIdent("__hxhx_optional_lambda"), [
				ECall(EIdent("__hxhx_rest_lambda"), [ELambda(["values"], EIdent("values")), EInt(0)]),
				EArrayDecl([EString("values")])
			]), HxPos.unknown())
		], "");
		assertTrue(functionHasBindCallableCandidate(optionalRestCandidate), "parser-normalized optional rest lambdas should remain bind-callable candidates");

		final valid = validBindFixture();
		assertTrue(functionHasBindCallableCandidate(valid.fn), "valid unhinted bind callables should retain candidate evidence");
		assertTrue(backend.cpp.CppPrepLocalInferenceGuard.functionHasBindCallableEvidence(valid.fn),
			"valid unhinted bind callables should retain bind evidence");
		runCandidateGatedPrepBranch(valid);
		assertTrue(valid.scope.localTypeOverrides.get("callback") == EXPECTED_CALLBACK_TYPE,
			"candidate-gated bind inference should retain the exact callable override");

		final nested = new HxFunctionDecl("nested", Public, false, [], "Void", [
			SBlock([
				SVar("callback", "", ELambda(["value"], EIdent("value")), HxPos.unknown()),
				SExpr(ECall(ECall(EField(EIdent("callback"), "bind"), [EInt(2)]), []), HxPos.unknown())
			], HxPos.unknown())
		], "");
		assertTrue(functionHasBindCallableCandidate(nested)
			&& backend.cpp.CppPrepLocalInferenceGuard.functionHasBindCallableEvidence(nested),
			"nested local candidates and bind calls should remain visible");

		final shadowed = new HxFunctionDecl("shadowed", Public, false, [], "Void", [
			SVar("callback", "", ELambda(["value"], EIdent("value")), HxPos.unknown()),
			SBlock([
				SVar("callback", "Int->Int", ELambda(["value"], EIdent("value")), HxPos.unknown()),
				SExpr(ECall(ECall(EField(EIdent("callback"), "bind"), [EInt(2)]), []), HxPos.unknown())
			], HxPos.unknown())
		], "");
		final shadowedOwner = new HxClassDecl("ShadowedBindCallableOwner", false, [shadowed], []);
		final shadowedFixture = {fn: shadowed, scope: scopeFor(shadowedOwner)};
		runCandidateGatedPrepBranch(shadowedFixture);
		assertTrue(!shadowedFixture.scope.localTypeOverrides.exists("callback"),
			"bind calls on a typed shadow should not provide evidence for an outer unhinted candidate");
	}

	static function main():Void {
		assertExactControls();
		final calls = envInt("HXHX_CPP_BIND_CALLABLE_PREP_BENCH_CALLS", DEFAULT_CALLS);
		final strict = strictFixture();
		var candidateSample = true;
		final candidateSeconds = elapsedNamed("candidate_gate", calls, () -> {
			candidateSample = functionHasBindCallableCandidate(strict.fn);
		});
		var bindSample = true;
		final bindSeconds = elapsedNamed("bind_gate", calls, () -> {
			bindSample = backend.cpp.CppPrepLocalInferenceGuard.functionHasBindCallableEvidence(strict.fn);
		});
		final currentCompleteSeconds = elapsedNamed("current_complete", calls, () -> runCurrentPrepBranch(strict));
		final candidateGatedCompleteSeconds = elapsedNamed("candidate_gated_complete", calls, () -> runCandidateGatedPrepBranch(strict));

		final positiveCurrent = validBindFixture();
		final positiveCurrentSeconds = elapsedNamed("positive_current", calls, () -> {
			positiveCurrent.scope.localTypes.remove("callback");
			positiveCurrent.scope.localTypeOverrides.remove("callback");
			runCurrentPrepBranch(positiveCurrent);
		});
		final positiveCandidate = validBindFixture();
		final positiveCandidateSeconds = elapsedNamed("positive_candidate", calls, () -> {
			positiveCandidate.scope.localTypes.remove("callback");
			positiveCandidate.scope.localTypeOverrides.remove("callback");
			runCandidateGatedPrepBranch(positiveCandidate);
		});

		assertTrue(!candidateSample, "strict-shaped TestEReg should have no unhinted bind-callable candidate");
		assertTrue(!bindSample, "strict-shaped TestEReg should have no bind call");
		assertTrue(!strict.scope.localTypeOverrides.keys().hasNext(), "negative strict-shaped preparation should not write overrides");
		assertTrue(positiveCurrent.scope.localTypeOverrides.get("callback") == EXPECTED_CALLBACK_TYPE,
			"timed current positive preparation should retain the exact callable override");
		assertTrue(positiveCandidate.scope.localTypeOverrides.get("callback") == EXPECTED_CALLBACK_TYPE,
			"timed positive preparation should retain the exact callable override");

		Sys.println("cpp_bind_callable_prep_bench_calls=" + calls);
		Sys.println("candidate_gate_seconds=" + candidateSeconds);
		Sys.println("bind_gate_seconds=" + bindSeconds);
		Sys.println("current_complete_seconds=" + currentCompleteSeconds);
		Sys.println("candidate_gated_complete_seconds=" + candidateGatedCompleteSeconds);
		Sys.println("positive_current_seconds=" + positiveCurrentSeconds);
		Sys.println("positive_candidate_seconds=" + positiveCandidateSeconds);
	}
}
