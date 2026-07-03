package backend.cpp;

/**
	Small AST scanner for finding direct calls through a local name.

	CppTargetCore uses this as a cheap preflight before running the much more
	expensive forwarded-argument inference pass. The scanner is intentionally
	syntactic: it answers "does this body call `local(...)` anywhere?" without
	trying to infer types or interpret the call target.
**/
class CppLocalCallScanner {
	public static function stmtListCallsLocal(stmts:Array<HxStmt>, local:String, sanitizeIdentifier:String->String):Bool {
		if (stmts == null || local == null || local.length == 0)
			return false;
		for (stmt in stmts)
			if (stmtCallsLocal(stmt, local, sanitizeIdentifier))
				return true;
		return false;
	}

	static function stmtCallsLocal(stmt:HxStmt, local:String, sanitizeIdentifier:String->String):Bool {
		return switch (stmt) {
			case SBlock(stmts, _):
				stmtListCallsLocal(stmts, local, sanitizeIdentifier);
			case SVar(_, _, init, _):
				exprCallsLocal(init, local, sanitizeIdentifier);
			case SIf(cond, thenBranch, elseBranch, _): exprCallsLocal(cond, local,
					sanitizeIdentifier) || stmtCallsLocal(thenBranch, local,
					sanitizeIdentifier) || (elseBranch != null && stmtCallsLocal(elseBranch, local, sanitizeIdentifier));
			case SForIn(_, iterable, body, _) | SForKeyValue(_, _, iterable, body, _): exprCallsLocal(iterable, local,
					sanitizeIdentifier) || stmtCallsLocal(body, local, sanitizeIdentifier);
			case SWhile(cond, body, _): exprCallsLocal(cond, local, sanitizeIdentifier) || stmtCallsLocal(body, local, sanitizeIdentifier);
			case SDoWhile(body, cond, _): stmtCallsLocal(body, local, sanitizeIdentifier) || exprCallsLocal(cond, local, sanitizeIdentifier);
			case SSwitch(scrutinee, _, bodies, _):
				var found = exprCallsLocal(scrutinee, local, sanitizeIdentifier);
				for (body in bodies)
					if (stmtCallsLocal(body, local, sanitizeIdentifier))
						found = true;
				found;
			case STry(tryBody, catches, _):
				var found = stmtCallsLocal(tryBody, local, sanitizeIdentifier);
				for (c in catches)
					if (stmtCallsLocal(c.body, local, sanitizeIdentifier))
						found = true;
				found;
			case SExpr(expr, _) | SReturn(expr, _) | SThrow(expr, _):
				exprCallsLocal(expr, local, sanitizeIdentifier);
			case SReturnVoid(_) | SBreak(_) | SContinue(_):
				false;
		}
	}

	static function exprCallsLocal(expr:Null<HxExpr>, local:String, sanitizeIdentifier:String->String):Bool {
		if (expr == null)
			return false;
		return switch (expr) {
			case ECall(EIdent(name), args): sanitizeIdentifier(name) == local || exprListCallsLocal(args, local, sanitizeIdentifier);
			case ECall(callee, args): exprCallsLocal(callee, local, sanitizeIdentifier) || exprListCallsLocal(args, local, sanitizeIdentifier);
			case EField(receiver, _):
				exprCallsLocal(receiver, local, sanitizeIdentifier);
			case EArrayAccess(array, index): exprCallsLocal(array, local, sanitizeIdentifier) || exprCallsLocal(index, local, sanitizeIdentifier);
			case EArrayDecl(values):
				exprListCallsLocal(values, local, sanitizeIdentifier);
			case EArrayComprehension(_, iterable, guardExpr, yieldExpr): exprCallsLocal(iterable, local,
					sanitizeIdentifier) || exprCallsLocal(guardExpr, local, sanitizeIdentifier) || exprCallsLocal(yieldExpr, local, sanitizeIdentifier);
			case ERange(start, end): exprCallsLocal(start, local, sanitizeIdentifier) || exprCallsLocal(end, local, sanitizeIdentifier);
			case EBinop(_, left, right): exprCallsLocal(left, local, sanitizeIdentifier) || exprCallsLocal(right, local, sanitizeIdentifier);
			case EUnop(_, inner) | ECast(inner, _) | EUntyped(inner) | EMacroExpr(inner, _):
				exprCallsLocal(inner, local, sanitizeIdentifier);
			case ETernary(cond, thenExpr, elseExpr): exprCallsLocal(cond, local,
					sanitizeIdentifier) || exprCallsLocal(thenExpr, local, sanitizeIdentifier) || exprCallsLocal(elseExpr, local, sanitizeIdentifier);
			case EAnon(_, fieldValues):
				exprListCallsLocal(fieldValues, local, sanitizeIdentifier);
			case ESwitch(scrutinee, _, exprs): exprCallsLocal(scrutinee, local, sanitizeIdentifier) || exprListCallsLocal(exprs, local, sanitizeIdentifier);
			case ELambda(_, body):
				exprCallsLocal(body, local, sanitizeIdentifier);
			case _:
				false;
		}
	}

	static function exprListCallsLocal(exprs:Array<HxExpr>, local:String, sanitizeIdentifier:String->String):Bool {
		if (exprs == null)
			return false;
		for (expr in exprs)
			if (exprCallsLocal(expr, local, sanitizeIdentifier))
				return true;
		return false;
	}
}
