package backend.cpp;

/**
	Lightweight syntax checks for C++ prep local-inference phases.

	The real local-inference passes still live in `CppTargetCore` and
	`CppLocalTypeInference`. This module only owns cheap preconditions that avoid
	a known no-op body walk after a pass has already found candidates. Keep checks
	here syntax-only and conservative; semantic refinement remains in the pass
	that consumes the evidence.
**/
class CppPrepLocalInferenceGuard {
	public static function functionHasBindCallableEvidence(fn:HxFunctionDecl):Bool {
		if (fn == null)
			return false;
		return stmtListHasBindCallableEvidence(HxFunctionDecl.getBody(fn));
	}

	static function stmtListHasBindCallableEvidence(stmts:Array<HxStmt>):Bool {
		if (stmts == null)
			return false;
		for (stmt in stmts)
			if (stmtHasBindCallableEvidence(stmt))
				return true;
		return false;
	}

	static function stmtHasBindCallableEvidence(stmt:HxStmt):Bool {
		if (stmt == null)
			return false;
		return switch (stmt) {
			case SBlock(stmts, _):
				stmtListHasBindCallableEvidence(stmts);
			case SIf(cond, thenBranch, elseBranch, _): exprHasBindCallableEvidence(cond) || stmtHasBindCallableEvidence(thenBranch) || (elseBranch != null
					&& stmtHasBindCallableEvidence(elseBranch));
			case SForIn(_, iterable, body, _) | SForKeyValue(_, _, iterable, body, _): exprHasBindCallableEvidence(iterable) || stmtHasBindCallableEvidence(body);
			case SWhile(cond, body, _): exprHasBindCallableEvidence(cond) || stmtHasBindCallableEvidence(body);
			case SDoWhile(body, cond, _): stmtHasBindCallableEvidence(body) || exprHasBindCallableEvidence(cond);
			case SSwitch(scrutinee, _, bodies, _): exprHasBindCallableEvidence(scrutinee) || stmtListHasBindCallableEvidence(bodies);
			case STry(tryBody, catches, _):
				if (stmtHasBindCallableEvidence(tryBody)) {
					true;
				} else {
					var found = false;
					for (c in catches)
						if (stmtHasBindCallableEvidence(c.body))
							found = true;
					found;
				}
			case SVar(_, _, init, _):
				exprHasBindCallableEvidence(init);
			case SExpr(expr, _) | SReturn(expr, _) | SThrow(expr, _):
				exprHasBindCallableEvidence(expr);
			case SReturnVoid(_) | SBreak(_) | SContinue(_):
				false;
		};
	}

	static function exprHasBindCallableEvidence(expr:Null<HxExpr>):Bool {
		if (expr == null)
			return false;
		return switch (expr) {
			case ECall(EField(_, "bind"), _):
				true;
			case ECall(callee, args): exprHasBindCallableEvidence(callee) || exprListHasBindCallableEvidence(args);
			case EBinop(_, left, right) | EArrayAccess(left, right): exprHasBindCallableEvidence(left) || exprHasBindCallableEvidence(right);
			case EField(receiver, _) | EUnop(_, receiver) | ECast(receiver, _) | EUntyped(receiver) | EMacroExpr(receiver, _):
				exprHasBindCallableEvidence(receiver);
			case ETernary(cond, thenExpr, elseExpr): exprHasBindCallableEvidence(cond) || exprHasBindCallableEvidence(thenExpr) || exprHasBindCallableEvidence(elseExpr);
			case EAnon(_, fieldValues) | EArrayDecl(fieldValues):
				exprListHasBindCallableEvidence(fieldValues);
			case EArrayComprehension(_, iterable, guardExpr, yieldExpr): exprHasBindCallableEvidence(iterable) || exprHasBindCallableEvidence(guardExpr) || exprHasBindCallableEvidence(yieldExpr);
			case ESwitch(scrutinee, _, exprs): exprHasBindCallableEvidence(scrutinee) || exprListHasBindCallableEvidence(exprs);
			case ENew(_, args):
				exprListHasBindCallableEvidence(args);
			case ERange(start, end): exprHasBindCallableEvidence(start) || exprHasBindCallableEvidence(end);
			case ELambda(_, body):
				exprHasBindCallableEvidence(body);
			case _:
				false;
		};
	}

	static function exprListHasBindCallableEvidence(exprs:Array<HxExpr>):Bool {
		if (exprs == null)
			return false;
		for (expr in exprs)
			if (exprHasBindCallableEvidence(expr))
				return true;
		return false;
	}
}
