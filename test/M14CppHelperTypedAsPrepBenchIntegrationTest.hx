import HxExpr;
import HxStmt;
import haxe.ds.StringMap;

/** Focused attribution probe for C++ helper typed-as preparation. **/
class M14CppHelperTypedAsPrepBenchIntegrationTest {
	static inline final DEFAULT_CALLS = 5000;

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
		final only = Sys.getEnv("HXHX_CPP_HELPER_TYPED_AS_PREP_BENCH_ONLY");
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

	static function strictFunction():HxFunctionDecl {
		final body = new Array<HxStmt>();
		for (i in 0...11)
			body.push(SVar("regex" + i, "EReg", ENew("EReg", [EString("p" + i), EString("")]), HxPos.unknown()));
		for (i in 0...57)
			body.push(SExpr(ECall(EIdent("eq"), [EInt(i), EInt(i)]), HxPos.unknown()));
		body.push(SVar("callback", "EReg->String", ELambda(["value"], EIdent("value")), HxPos.unknown()));
		for (i in 0...19)
			body.push(SExpr(ECall(EField(EIdent("regex" + (i % 11)), "map"), [EString("value" + i), EIdent("callback")]), HxPos.unknown()));
		assertTrue(body.length == 88, "helper typed-as fixture should retain 88 statements");
		return new HxFunctionDecl("test", Public, false, [], "Void", body, "");
	}

	static function exprListHasFastEvidence(exprs:Array<HxExpr>):Bool {
		if (exprs == null)
			return false;
		for (expr in exprs)
			if (exprHasFastEvidence(expr))
				return true;
		return false;
	}

	/** Replay the current grammar while treating direct identifier callees as terminal. **/
	static function exprHasFastEvidence(expr:Null<HxExpr>):Bool {
		if (expr == null)
			return false;
		return switch (expr) {
			case ECall(EIdent(name), args): name == "typedAs" || exprListHasFastEvidence(args);
			case ECall(callee, args): @:privateAccess backend.cpp.CppPrepLocalInferenceGuard.isHelperTypedAsCallee(callee) || exprHasFastEvidence(callee) || exprListHasFastEvidence(args);
			case EBinop(_, left, right) | EArrayAccess(left, right): exprHasFastEvidence(left) || exprHasFastEvidence(right);
			case EField(receiver, _) | EUnop(_, receiver) | ECast(receiver, _) | EUntyped(receiver) | EMacroExpr(receiver, _):
				exprHasFastEvidence(receiver);
			case ETernary(cond, thenExpr, elseExpr): exprHasFastEvidence(cond) || exprHasFastEvidence(thenExpr) || exprHasFastEvidence(elseExpr);
			case EAnon(_, values) | EArrayDecl(values): exprListHasFastEvidence(values);
			case EArrayComprehension(_, iterable, guardExpr, yieldExpr): exprHasFastEvidence(iterable) || exprHasFastEvidence(guardExpr) || exprHasFastEvidence(yieldExpr);
			case ESwitch(scrutinee, _, exprs): exprHasFastEvidence(scrutinee) || exprListHasFastEvidence(exprs);
			case ENew(_, args): exprListHasFastEvidence(args);
			case ERange(start, end): exprHasFastEvidence(start) || exprHasFastEvidence(end);
			case ELambda(_, body): exprHasFastEvidence(body);
			case _:
				false;
		};
	}

	static function stmtListHasFastEvidence(stmts:Array<HxStmt>):Bool {
		for (stmt in stmts)
			if (stmtHasFastEvidence(stmt))
				return true;
		return false;
	}

	static function stmtHasFastEvidence(stmt:HxStmt):Bool {
		return switch (stmt) {
			case SBlock(stmts, _): stmtListHasFastEvidence(stmts);
			case SIf(cond, thenBranch, elseBranch, _): exprHasFastEvidence(cond) || stmtHasFastEvidence(thenBranch) || (elseBranch != null
					&& stmtHasFastEvidence(elseBranch));
			case SForIn(_, iterable, body, _) | SForKeyValue(_, _, iterable, body, _): exprHasFastEvidence(iterable) || stmtHasFastEvidence(body);
			case SWhile(cond, body, _): exprHasFastEvidence(cond) || stmtHasFastEvidence(body);
			case SDoWhile(body, cond, _): stmtHasFastEvidence(body) || exprHasFastEvidence(cond);
			case SSwitch(scrutinee, _, bodies, _): exprHasFastEvidence(scrutinee) || stmtListHasFastEvidence(bodies);
			case STry(tryBody, catches, _):
				if (stmtHasFastEvidence(tryBody)) true; else {
					var found = false;
					for (c in catches)
						if (stmtHasFastEvidence(c.body))
							found = true;
					found;
				}
			case SVar(_, _, init, _): exprHasFastEvidence(init);
			case SExpr(expr, _) | SReturn(expr, _) | SThrow(expr, _): exprHasFastEvidence(expr);
			case SReturnVoid(_) | SBreak(_) | SContinue(_): false;
		};
	}

	static function assertControls():Void {
		final direct = ECall(EIdent("typedAs"), [EIdent("value"), EString("String")]);
		final qualified = ECall(EField(EIdent("HelperMacros"), "typedAs"), [EIdent("value"), EString("String")]);
		final unitQualified = ECall(EField(EField(EIdent("unit"), "HelperMacros"), "typedAs"), [EIdent("value"), EString("String")]);
		final lookalike = ECall(EField(EIdent("Other"), "typedAs"), [EIdent("value"), EString("String")]);
		final nested = ECall(EIdent("eq"), [EInt(1), direct]);
		for (expr in [direct, qualified, unitQualified, nested])
			assertTrue(exprHasFastEvidence(expr), "direct, qualified, and nested typedAs evidence should remain visible");
		assertTrue(!exprHasFastEvidence(lookalike), "unrelated qualified typedAs lookalikes should remain excluded");

		final inferFn = new HxFunctionDecl("infer", Public, false, [], "Void", [
			SVar("expected", "String", EString(""), HxPos.unknown()),
			SVar("actual", "", ENull, HxPos.unknown()),
			SExpr(ECall(EIdent("typedAs"), [EIdent("actual"), EIdent("expected")]), HxPos.unknown())
		], "");
		final owner = new HxClassDecl("HelperTypedAsOwner", false, [inferFn], []);
		final names = new StringMap<Bool>();
		final classes = new StringMap<HxClassDecl>();
		names.set("HelperTypedAsOwner", true);
		classes.set("HelperTypedAsOwner", owner);
		final scope = @:privateAccess backend.cpp.CppTargetCore.renderScope(owner, {names: names, byName: classes, all: [owner]}, "void");
		@:privateAccess backend.cpp.CppTargetCore.inferHelperTypedAsLocalTypeOverrides(scope, inferFn);
		assertTrue(scope.localTypeOverrides.get("actual") == "std::string", "direct helper typedAs inference should retain the exact local override");
	}

	static function main():Void {
		assertControls();
		final calls = envInt("HXHX_CPP_HELPER_TYPED_AS_PREP_BENCH_CALLS", DEFAULT_CALLS);
		final fn = strictFunction();
		var currentSample = true;
		final currentSeconds = elapsed("current_guard", calls, () -> {
			currentSample = backend.cpp.CppPrepLocalInferenceGuard.functionHasHelperTypedAsLocalInferenceEvidence(fn);
		});
		var fastSample = true;
		final fastSeconds = elapsed("direct_ident_fast_guard", calls, () -> {
			fastSample = stmtListHasFastEvidence(HxFunctionDecl.getBody(fn));
		});
		assertTrue(!currentSample && !fastSample, "strict-shaped TestEReg should have no helper typedAs evidence");
		Sys.println("cpp_helper_typed_as_prep_bench_calls=" + calls);
		Sys.println("current_guard_seconds=" + currentSeconds);
		Sys.println("direct_ident_fast_guard_seconds=" + fastSeconds);
	}
}
