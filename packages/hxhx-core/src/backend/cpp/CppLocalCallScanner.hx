package backend.cpp;

/**
	Small AST scanner for finding direct calls through a local name.

	CppTargetCore uses this as a cheap preflight before running the much more
	expensive forwarded-argument inference pass. The scanner is intentionally
	syntactic: it answers "does this body call `local(...)` anywhere?" without
	trying to infer types or interpret the call target. Names come from the
	exact function projection and are compared before C++ spelling changes;
	`int` and `int_` must remain different candidates.
**/
class CppLocalCallScanner {
	public static function stmtListCallsLocal(stmts:Array<HxStmt>, local:String):Bool {
		if (stmts == null || local == null || local.length == 0)
			return false;
		for (stmt in stmts)
			if (stmtCallsLocal(stmt, local))
				return true;
		return false;
	}

	static function stmtCallsLocal(stmt:HxStmt, local:String):Bool {
		return switch (stmt) {
			case STargetScope(_, _, _): throw "native target scope is not valid in this source or target phase";
			case SBlock(stmts, _):
				stmtListCallsLocal(stmts, local);
			case SVar(_, _, init, _):
				exprCallsLocal(init, local);
			case SIf(cond, thenBranch, elseBranch, _): exprCallsLocal(cond,
					local) || stmtCallsLocal(thenBranch, local) || (elseBranch != null && stmtCallsLocal(elseBranch, local));
			case SForIn(_, iterable, body, _) | SForKeyValue(_, _, iterable, body, _): exprCallsLocal(iterable, local) || stmtCallsLocal(body, local);
			case SWhile(cond, body, _): exprCallsLocal(cond, local) || stmtCallsLocal(body, local);
			case SDoWhile(body, cond, _): stmtCallsLocal(body, local) || exprCallsLocal(cond, local);
			case SSwitch(scrutinee, _, bodies, _):
				var found = exprCallsLocal(scrutinee, local);
				for (body in bodies)
					if (stmtCallsLocal(body, local))
						found = true;
				found;
			case STry(tryBody, catches, _):
				var found = stmtCallsLocal(tryBody, local);
				for (c in catches)
					if (stmtCallsLocal(c.body, local))
						found = true;
				found;
			case SExpr(expr, _) | SReturn(expr, _) | SThrow(expr, _):
				exprCallsLocal(expr, local);
			case SReturnVoid(_) | SBreak(_) | SContinue(_):
				false;
		}
	}

	static function exprCallsLocal(expr:Null<HxExpr>, local:String):Bool {
		if (expr == null)
			return false;
		return switch (expr) {
			case ECall(EIdent(name), args): name == local || exprListCallsLocal(args, local);
			case ECall(callee, args): exprCallsLocal(callee, local) || exprListCallsLocal(args, local);
			case EField(receiver, _):
				exprCallsLocal(receiver, local);
			case EArrayAccess(array, index): exprCallsLocal(array, local) || exprCallsLocal(index, local);
			case EArrayDecl(values):
				exprListCallsLocal(values, local);
			case EArrayComprehension(_, iterable, guardExpr, yieldExpr): exprCallsLocal(iterable,
					local) || exprCallsLocal(guardExpr, local) || exprCallsLocal(yieldExpr, local);
			case ERange(start, end): exprCallsLocal(start, local) || exprCallsLocal(end, local);
			case EBinop(_, left, right) | EDiscardThen(left, right): exprCallsLocal(left, local) || exprCallsLocal(right, local);
			case EParenthesized(inner, _) | EUnop(_, _, inner) | ECast(inner, _) | EUntyped(inner) | EMacroExpr(inner, _):
				exprCallsLocal(inner, local);
			case ETernary(cond, thenExpr, elseExpr): exprCallsLocal(cond, local) || exprCallsLocal(thenExpr, local) || exprCallsLocal(elseExpr, local);
			case EAnon(_, fieldValues):
				exprListCallsLocal(fieldValues, local);
			case ESwitch(scrutinee, _, exprs): exprCallsLocal(scrutinee, local) || exprListCallsLocal(exprs, local);
			case ELambda(_, body):
				exprCallsLocal(body, local);
			case _:
				false;
		}
	}

	static function exprListCallsLocal(exprs:Array<HxExpr>, local:String):Bool {
		if (exprs == null)
			return false;
		for (expr in exprs)
			if (exprCallsLocal(expr, local))
				return true;
		return false;
	}
}
