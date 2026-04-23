package hxhx;

/**
	Stage3 unsupported-expression analysis and diagnostic formatting helpers.

	Why
	- `Stage3Compiler` still mixes orchestration with unsupported-expression counting,
	  raw-snippet collection, and error-string formatting.
	- Those helpers are diagnostic support logic, not driver control flow.

	What
	- Counts unsupported expressions across expressions, statements, functions, and modules.
	- Collects raw unsupported snippets for trace logging.
	- Formats Stage3 typer and runtime diagnostics consistently.

	How
	- Preserve the existing walk shapes and message formatting exactly.
	- Expose only the helper surface already used by `Stage3Compiler`.
**/
class Stage3DiagnosticsSupport {
	public static function escapeOneLine(source:String):String {
		if (source == null)
			return "";
		return StringTools.replace(StringTools.replace(StringTools.replace(StringTools.replace(source, "\\", "\\\\"), "\r", "\\r"), "\n", "\\n"), "\t", "\\t");
	}

	public static function countUnsupportedExprsInExpr(expr:Null<HxExpr>):Int {
		if (expr == null)
			return 0;
		return switch (expr) {
			case EUnsupported(_): 1;
			case EField(obj, _): countUnsupportedExprsInExpr(obj);
			case ECall(callee, args):
				var count = countUnsupportedExprsInExpr(callee);
				for (arg in args)
					count += countUnsupportedExprsInExpr(arg);
				count;
			case ELambda(_args, body):
				countUnsupportedExprsInExpr(body);
			case ETryCatchRaw(_raw):
				0;
			case ENew(_typePath, args):
				var count = 0;
				for (arg in args)
					count += countUnsupportedExprsInExpr(arg);
				count;
			case EUnop(_op, inner): countUnsupportedExprsInExpr(inner);
			case EBinop(_op, left, right): countUnsupportedExprsInExpr(left) + countUnsupportedExprsInExpr(right);
			case ETernary(cond, thenExpr, elseExpr):
				countUnsupportedExprsInExpr(cond) + countUnsupportedExprsInExpr(thenExpr) + countUnsupportedExprsInExpr(elseExpr);
			case EAnon(_names, values):
				var count = 0;
				for (value in values)
					count += countUnsupportedExprsInExpr(value);
				count;
			case EArrayDecl(values):
				var count = 0;
				for (value in values)
					count += countUnsupportedExprsInExpr(value);
				count;
			case EArrayComprehension(_name, iterable, guardExpr, yieldExpr):
				countUnsupportedExprsInExpr(iterable) + (guardExpr == null ? 0 : countUnsupportedExprsInExpr(guardExpr)) +
				countUnsupportedExprsInExpr(yieldExpr);
			case EArrayAccess(arrayExpr, indexExpr):
				countUnsupportedExprsInExpr(arrayExpr) + countUnsupportedExprsInExpr(indexExpr);
			case ECast(inner, _hint):
				countUnsupportedExprsInExpr(inner);
			case EUntyped(inner):
				countUnsupportedExprsInExpr(inner);
			case _:
				0;
		}
	}

	static function collectUnsupportedExprRawInExpr(expr:Null<HxExpr>, out:Array<String>, max:Int):Void {
		if (expr == null || out.length >= max)
			return;
		switch (expr) {
			case EUnsupported(raw):
				if (out.length < max)
					out.push(raw);
			case EField(obj, _):
				collectUnsupportedExprRawInExpr(obj, out, max);
			case ECall(callee, args):
				collectUnsupportedExprRawInExpr(callee, out, max);
				for (arg in args)
					collectUnsupportedExprRawInExpr(arg, out, max);
			case ELambda(_args, body):
				collectUnsupportedExprRawInExpr(body, out, max);
			case ETryCatchRaw(_raw):
			case ENew(_typePath, args):
				for (arg in args)
					collectUnsupportedExprRawInExpr(arg, out, max);
			case EUnop(_op, inner):
				collectUnsupportedExprRawInExpr(inner, out, max);
			case EBinop(_op, left, right):
				collectUnsupportedExprRawInExpr(left, out, max);
				collectUnsupportedExprRawInExpr(right, out, max);
			case ETernary(cond, thenExpr, elseExpr):
				collectUnsupportedExprRawInExpr(cond, out, max);
				collectUnsupportedExprRawInExpr(thenExpr, out, max);
				collectUnsupportedExprRawInExpr(elseExpr, out, max);
			case EAnon(_names, values):
				for (value in values)
					collectUnsupportedExprRawInExpr(value, out, max);
			case EArrayDecl(values):
				for (value in values)
					collectUnsupportedExprRawInExpr(value, out, max);
			case EArrayComprehension(_name, iterable, guardExpr, yieldExpr):
				collectUnsupportedExprRawInExpr(iterable, out, max);
				if (guardExpr != null)
					collectUnsupportedExprRawInExpr(guardExpr, out, max);
				collectUnsupportedExprRawInExpr(yieldExpr, out, max);
			case EArrayAccess(arrayExpr, indexExpr):
				collectUnsupportedExprRawInExpr(arrayExpr, out, max);
				collectUnsupportedExprRawInExpr(indexExpr, out, max);
			case ECast(inner, _hint):
				collectUnsupportedExprRawInExpr(inner, out, max);
			case EUntyped(inner):
				collectUnsupportedExprRawInExpr(inner, out, max);
			case _:
		}
	}

	static function collectUnsupportedExprRawInStmt(stmt:HxStmt, out:Array<String>, max:Int):Void {
		if (out.length >= max)
			return;
		switch (stmt) {
			case SBlock(stmts, _pos):
				for (child in stmts)
					collectUnsupportedExprRawInStmt(child, out, max);
			case SVar(_name, _hint, init, _pos):
				collectUnsupportedExprRawInExpr(init, out, max);
			case SIf(cond, thenBranch, elseBranch, _pos):
				collectUnsupportedExprRawInExpr(cond, out, max);
				collectUnsupportedExprRawInStmt(thenBranch, out, max);
				if (elseBranch != null)
					collectUnsupportedExprRawInStmt(elseBranch, out, max);
			case SWhile(cond, body, _pos):
				collectUnsupportedExprRawInExpr(cond, out, max);
				collectUnsupportedExprRawInStmt(body, out, max);
			case SDoWhile(body, cond, _pos):
				collectUnsupportedExprRawInStmt(body, out, max);
				collectUnsupportedExprRawInExpr(cond, out, max);
			case SForIn(_name, iterable, body, _pos):
				collectUnsupportedExprRawInExpr(iterable, out, max);
				collectUnsupportedExprRawInStmt(body, out, max);
			case SForKeyValue(_keyName, _valueName, iterable, body, _pos):
				collectUnsupportedExprRawInExpr(iterable, out, max);
				collectUnsupportedExprRawInStmt(body, out, max);
			case STry(tryBody, catches, _pos):
				collectUnsupportedExprRawInStmt(tryBody, out, max);
				for (catchBranch in catches)
					collectUnsupportedExprRawInStmt(catchBranch.body, out, max);
			case SBreak(_pos):
			case SContinue(_pos):
			case SThrow(expr, _pos):
				collectUnsupportedExprRawInExpr(expr, out, max);
			case SSwitch(scrutinee, _patterns, bodies, _pos):
				collectUnsupportedExprRawInExpr(scrutinee, out, max);
				for (body in bodies)
					collectUnsupportedExprRawInStmt(body, out, max);
			case SReturnVoid(_pos):
			case SReturn(expr, _pos):
				collectUnsupportedExprRawInExpr(expr, out, max);
			case SExpr(expr, _pos):
				collectUnsupportedExprRawInExpr(expr, out, max);
		}
	}

	public static function collectUnsupportedExprRawInModule(pm:ParsedModule, max:Int):Array<String> {
		final out = new Array<String>();
		final decl = pm.getDecl();
		for (cls in HxModuleDecl.getClasses(decl)) {
			for (field in HxClassDecl.getFields(cls))
				collectUnsupportedExprRawInExpr(HxFieldDecl.getInit(field), out, max);
			for (fn in HxClassDecl.getFunctions(cls)) {
				for (stmt in HxFunctionDecl.getBody(fn))
					collectUnsupportedExprRawInStmt(stmt, out, max);
			}
		}
		return out;
	}

	static function countUnsupportedExprsInStmt(stmt:HxStmt):Int {
		return switch (stmt) {
			case SBlock(stmts, _pos):
				var count = 0;
				for (child in stmts)
					count += countUnsupportedExprsInStmt(child);
				count;
			case SVar(_name, _hint, init, _pos):
				countUnsupportedExprsInExpr(init);
			case SIf(cond, thenBranch, elseBranch, _pos):
				countUnsupportedExprsInExpr(cond) + countUnsupportedExprsInStmt(thenBranch) +
				(elseBranch == null ? 0 : countUnsupportedExprsInStmt(elseBranch));
			case SWhile(cond, body, _pos):
				countUnsupportedExprsInExpr(cond) + countUnsupportedExprsInStmt(body);
			case SDoWhile(body, cond, _pos):
				countUnsupportedExprsInStmt(body) + countUnsupportedExprsInExpr(cond);
			case SForIn(_name, iterable, body, _pos):
				countUnsupportedExprsInExpr(iterable) + countUnsupportedExprsInStmt(body);
			case SForKeyValue(_keyName, _valueName, iterable, body, _pos):
				countUnsupportedExprsInExpr(iterable) + countUnsupportedExprsInStmt(body);
			case STry(tryBody, catches, _pos):
				var count = countUnsupportedExprsInStmt(tryBody);
				for (catchBranch in catches)
					count += countUnsupportedExprsInStmt(catchBranch.body);
				count;
			case SBreak(_pos):
				0;
			case SContinue(_pos):
				0;
			case SThrow(expr, _pos):
				countUnsupportedExprsInExpr(expr);
			case SSwitch(scrutinee, _patterns, bodies, _pos):
				var count = countUnsupportedExprsInExpr(scrutinee);
				for (body in bodies)
					count += countUnsupportedExprsInStmt(body);
				count;
			case SReturnVoid(_pos):
				0;
			case SReturn(expr, _pos):
				countUnsupportedExprsInExpr(expr);
			case SExpr(expr, _pos):
				countUnsupportedExprsInExpr(expr);
		}
	}

	public static function countUnsupportedExprsInModule(pm:ParsedModule):Int {
		var count = 0;
		final decl = pm.getDecl();
		for (cls in HxModuleDecl.getClasses(decl)) {
			for (field in HxClassDecl.getFields(cls))
				count += countUnsupportedExprsInExpr(HxFieldDecl.getInit(field));
			for (fn in HxClassDecl.getFunctions(cls)) {
				for (stmt in HxFunctionDecl.getBody(fn))
					count += countUnsupportedExprsInStmt(stmt);
			}
		}
		return count;
	}

	public static function countUnsupportedExprsInFunction(fn:HxFunctionDecl):Int {
		var count = 0;
		for (stmt in HxFunctionDecl.getBody(fn))
			count += countUnsupportedExprsInStmt(stmt);
		return count;
	}

	public static function formatException(e:TyperError):String {
		final pos = e.getPos();
		final line = pos == null ? 0 : pos.getLine();
		final col = pos == null ? 0 : pos.getColumn();
		return e.getFilePath() + ":" + line + ":" + col + ": " + e.getMessage();
	}

	public static function rawTyperDiagnostic(e:TyperError):Null<String> {
		return TyperStage.extractRawDiagnostic(e.getMessage());
	}

	public static function formatDynamicException(error:Dynamic):String {
		if (Std.isOfType(error, haxe.Exception)) {
			final ex:haxe.Exception = cast error;
			if (ex.message != null && ex.message.length > 0)
				return ex.message;
		}
		return Std.string(error);
	}
}
