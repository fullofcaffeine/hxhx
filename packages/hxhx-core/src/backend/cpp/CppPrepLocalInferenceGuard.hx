package backend.cpp;

/**
	Lightweight syntax checks for C++ prep local-inference phases.

	The real local-inference passes still live in `CppTargetCore` and
	`CppLocalTypeInference`. This module only owns cheap preconditions that avoid
	known no-op body walks before or inside those passes. Keep checks here
	syntax-only and conservative; semantic refinement remains in the pass that
	consumes the evidence.
**/
class CppPrepLocalInferenceGuard {
	public static function functionHasStringMapLocalInferenceEvidence(fn:HxFunctionDecl):Bool {
		return functionHasLocalDeclEvidence(fn, localDeclHasStringMapLocalInferenceEvidence);
	}

	public static function functionHasGenericFactoryLocalInferenceEvidence(fn:HxFunctionDecl):Bool {
		return functionHasLocalDeclEvidence(fn, localDeclHasGenericFactoryLocalInferenceEvidence);
	}

	public static function functionHasOptionalLambdaLocalInferenceEvidence(fn:HxFunctionDecl):Bool {
		return functionHasLocalDeclEvidence(fn, localDeclHasOptionalLambdaLocalInferenceEvidence);
	}

	public static function functionHasBindCallableEvidence(fn:HxFunctionDecl):Bool {
		if (fn == null)
			return false;
		return stmtListHasBindCallableEvidence(HxFunctionDecl.getBody(fn));
	}

	public static function functionHasDynamicLocalInferenceEvidence(fn:HxFunctionDecl, dynamicTypeHint:String->Bool):Bool {
		if (dynamicTypeHint == null)
			return false;
		return functionHasLocalDeclEvidence(fn, function(_, typeHint, init) {
			return localDeclHasDynamicLocalInferenceEvidence(typeHint, init, dynamicTypeHint);
		});
	}

	public static function functionHasHelperTypedAsLocalInferenceEvidence(fn:HxFunctionDecl):Bool {
		if (fn == null)
			return false;
		return stmtListHasHelperTypedAsEvidence(HxFunctionDecl.getBody(fn));
	}

	static function functionHasLocalDeclEvidence(fn:HxFunctionDecl, evidence:String->String->Null<HxExpr>->Bool):Bool {
		if (fn == null)
			return false;
		return stmtListHasLocalDeclEvidence(HxFunctionDecl.getBody(fn), evidence);
	}

	static function stmtListHasLocalDeclEvidence(stmts:Array<HxStmt>, evidence:String->String->Null<HxExpr>->Bool):Bool {
		if (stmts == null)
			return false;
		for (stmt in stmts)
			if (stmtHasLocalDeclEvidence(stmt, evidence))
				return true;
		return false;
	}

	static function stmtHasLocalDeclEvidence(stmt:HxStmt, evidence:String->String->Null<HxExpr>->Bool):Bool {
		if (stmt == null)
			return false;
		return switch (stmt) {
			case SBlock(stmts, _):
				stmtListHasLocalDeclEvidence(stmts, evidence);
			case SIf(_, thenBranch, elseBranch, _): stmtHasLocalDeclEvidence(thenBranch,
					evidence) || (elseBranch != null && stmtHasLocalDeclEvidence(elseBranch, evidence));
			case SForIn(_, _, body, _) | SForKeyValue(_, _, _, body, _) | SWhile(_, body, _) | SDoWhile(body, _, _):
				stmtHasLocalDeclEvidence(body, evidence);
			case SSwitch(_, _, bodies, _):
				stmtListHasLocalDeclEvidence(bodies, evidence);
			case STry(tryBody, catches, _):
				if (stmtHasLocalDeclEvidence(tryBody, evidence)) {
					true;
				} else {
					var found = false;
					for (c in catches)
						if (stmtHasLocalDeclEvidence(c.body, evidence))
							found = true;
					found;
				}
			case SVar(name, typeHint, init, _):
				evidence(name, typeHint, init);
			case SExpr(_, _) | SReturn(_, _) | SThrow(_, _) | SReturnVoid(_) | SBreak(_) | SContinue(_):
				false;
		};
	}

	static function localDeclHasStringMapLocalInferenceEvidence(_:String, typeHint:String, init:Null<HxExpr>):Bool {
		if (hasTypeHint(typeHint))
			return false;
		return switch (init) {
			case ENew(typePath, _):
				switch (typePathBaseName(typePath)) {
					case "Map" | "StringMap" | "IntMap":
						true;
					case _:
						false;
				}
			case _:
				false;
		};
	}

	static function localDeclHasGenericFactoryLocalInferenceEvidence(_:String, typeHint:String, init:Null<HxExpr>):Bool {
		if (hasTypeHint(typeHint))
			return false;
		return switch (init) {
			case ENew(_, args): args != null && args.length == 0;
			case _:
				false;
		};
	}

	static function localDeclHasOptionalLambdaLocalInferenceEvidence(_:String, typeHint:String, init:Null<HxExpr>):Bool {
		return !hasTypeHint(typeHint) && isOptionalLambdaLocalInit(init);
	}

	static function localDeclHasDynamicLocalInferenceEvidence(typeHint:String, init:Null<HxExpr>, dynamicTypeHint:String->Bool):Bool {
		if (isLocalCallableInit(init))
			return true;
		if (dynamicTypeHint(typeHint))
			return true;
		if (hasTypeHint(typeHint))
			return false;
		return init == null || isEmptyArrayExpr(init) || isNullExpr(init);
	}

	static function hasTypeHint(typeHint:String):Bool {
		return StringTools.trim(typeHint == null ? "" : typeHint).length > 0;
	}

	static function typePathBaseName(typePath:String):String {
		final clean = StringTools.trim(typePath == null ? "" : typePath);
		final dot = clean.lastIndexOf(".");
		final slash = clean.lastIndexOf("/");
		final sep = dot > slash ? dot : slash;
		return sep < 0 ? clean : clean.substr(sep + 1);
	}

	static function isEmptyArrayExpr(expr:Null<HxExpr>):Bool {
		return switch (expr) {
			case EArrayDecl(values):
				values.length == 0;
			case _:
				false;
		};
	}

	static function isNullExpr(expr:Null<HxExpr>):Bool {
		return switch (expr) {
			case ENull:
				true;
			case _:
				false;
		};
	}

	static function isLocalCallableInit(expr:Null<HxExpr>):Bool {
		return switch (expr) {
			case ELambda(_, _):
				true;
			case ECall(EIdent("__hxhx_optional_lambda"), _):
				true;
			case ECall(EField(receiver, "makeVarArgs"), args) if (args.length == 1 && isReflectStaticReceiver(receiver)):
				true;
			case _:
				false;
		};
	}

	static function isOptionalLambdaLocalInit(expr:Null<HxExpr>):Bool {
		return switch (expr) {
			case ECall(EIdent("__hxhx_optional_lambda"), [ELambda(_, _), EArrayDecl(_)]):
				true;
			case _:
				false;
		};
	}

	static function isReflectStaticReceiver(expr:HxExpr):Bool {
		return switch (expr) {
			case EIdent(name):
				typePathBaseName(name) == "Reflect";
			case EField(receiver, name): typePathBaseName(name) == "Reflect" || isReflectStaticReceiver(receiver);
			case _:
				false;
		};
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

	static function stmtListHasHelperTypedAsEvidence(stmts:Array<HxStmt>):Bool {
		if (stmts == null)
			return false;
		for (stmt in stmts)
			if (stmtHasHelperTypedAsEvidence(stmt))
				return true;
		return false;
	}

	static function stmtHasHelperTypedAsEvidence(stmt:HxStmt):Bool {
		if (stmt == null)
			return false;
		return switch (stmt) {
			case SBlock(stmts, _):
				stmtListHasHelperTypedAsEvidence(stmts);
			case SIf(cond, thenBranch, elseBranch, _): exprHasHelperTypedAsEvidence(cond) || stmtHasHelperTypedAsEvidence(thenBranch) || (elseBranch != null
					&& stmtHasHelperTypedAsEvidence(elseBranch));
			case SForIn(_, iterable, body, _) | SForKeyValue(_, _, iterable, body, _): exprHasHelperTypedAsEvidence(iterable) || stmtHasHelperTypedAsEvidence(body);
			case SWhile(cond, body, _): exprHasHelperTypedAsEvidence(cond) || stmtHasHelperTypedAsEvidence(body);
			case SDoWhile(body, cond, _): stmtHasHelperTypedAsEvidence(body) || exprHasHelperTypedAsEvidence(cond);
			case SSwitch(scrutinee, _, bodies, _): exprHasHelperTypedAsEvidence(scrutinee) || stmtListHasHelperTypedAsEvidence(bodies);
			case STry(tryBody, catches, _):
				if (stmtHasHelperTypedAsEvidence(tryBody)) {
					true;
				} else {
					var found = false;
					for (c in catches)
						if (stmtHasHelperTypedAsEvidence(c.body))
							found = true;
					found;
				}
			case SVar(_, _, init, _):
				exprHasHelperTypedAsEvidence(init);
			case SExpr(expr, _) | SReturn(expr, _) | SThrow(expr, _):
				exprHasHelperTypedAsEvidence(expr);
			case SReturnVoid(_) | SBreak(_) | SContinue(_):
				false;
		};
	}

	static function exprHasHelperTypedAsEvidence(expr:Null<HxExpr>):Bool {
		if (expr == null)
			return false;
		return switch (expr) {
			case ECall(callee, args): isHelperTypedAsCallee(callee) || exprHasHelperTypedAsEvidence(callee) || exprListHasHelperTypedAsEvidence(args);
			case EBinop(_, left, right) | EArrayAccess(left, right): exprHasHelperTypedAsEvidence(left) || exprHasHelperTypedAsEvidence(right);
			case EField(receiver, _) | EUnop(_, receiver) | ECast(receiver, _) | EUntyped(receiver) | EMacroExpr(receiver, _):
				exprHasHelperTypedAsEvidence(receiver);
			case ETernary(cond, thenExpr, elseExpr): exprHasHelperTypedAsEvidence(cond) || exprHasHelperTypedAsEvidence(thenExpr) || exprHasHelperTypedAsEvidence(elseExpr);
			case EAnon(_, fieldValues) | EArrayDecl(fieldValues):
				exprListHasHelperTypedAsEvidence(fieldValues);
			case EArrayComprehension(_, iterable, guardExpr, yieldExpr): exprHasHelperTypedAsEvidence(iterable) || exprHasHelperTypedAsEvidence(guardExpr) || exprHasHelperTypedAsEvidence(yieldExpr);
			case ESwitch(scrutinee, _, exprs): exprHasHelperTypedAsEvidence(scrutinee) || exprListHasHelperTypedAsEvidence(exprs);
			case ENew(_, args):
				exprListHasHelperTypedAsEvidence(args);
			case ERange(start, end): exprHasHelperTypedAsEvidence(start) || exprHasHelperTypedAsEvidence(end);
			case ELambda(_, body):
				exprHasHelperTypedAsEvidence(body);
			case _:
				false;
		};
	}

	static function exprListHasHelperTypedAsEvidence(exprs:Array<HxExpr>):Bool {
		if (exprs == null)
			return false;
		for (expr in exprs)
			if (exprHasHelperTypedAsEvidence(expr))
				return true;
		return false;
	}

	static function isHelperTypedAsCallee(callee:HxExpr):Bool {
		return switch (callee) {
			case EIdent("typedAs"):
				true;
			case EField(EIdent("HelperMacros"), "typedAs"):
				true;
			case EField(EField(EIdent("unit"), "HelperMacros"), "typedAs"):
				true;
			case _:
				false;
		};
	}
}
