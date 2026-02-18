package backend.js;

/**
	Statement-to-JS lowering for `js-native` MVP.

	Scope
	- Covers the MVP subset required by initial non-delegating JS smoke fixtures.
	- Unsupported statement forms fail fast through expression-level checks.
**/
class JsStmtEmitter {
	public static function emitFunctionBody(writer:JsWriter, body:Array<HxStmt>, scope:JsFunctionScope):Void {
		for (s in body) emitStmt(writer, s, scope);
	}

	static function emitStmtBlockContent(writer:JsWriter, stmt:HxStmt, scope:JsFunctionScope):Void {
		switch (stmt) {
			case SBlock(stmts, _):
				for (s in stmts) emitStmt(writer, s, scope);
			case _:
				emitStmt(writer, stmt, scope);
		}
	}

	public static function emitStmt(writer:JsWriter, stmt:HxStmt, scope:JsFunctionScope):Void {
		switch (stmt) {
			case SBlock(stmts, _):
				writer.writeln("{");
				writer.pushIndent();
				for (s in stmts) emitStmt(writer, s, scope);
				writer.popIndent();
				writer.writeln("}");
			case SVar(name, _typeHint, init, _):
				final local = scope.declareLocal(name);
				if (init != null) {
					writer.writeln("var " + local + " = " + JsExprEmitter.emit(init, scope.exprScope()) + ";");
				} else {
					writer.writeln("var " + local + ";");
				}
			case SIf(cond, thenBranch, elseBranch, _):
				writer.writeln("if (" + JsExprEmitter.emit(cond, scope.exprScope()) + ") {");
				writer.pushIndent();
				emitStmtBlockContent(writer, thenBranch, scope);
				writer.popIndent();
				if (elseBranch == null) {
					writer.writeln("}");
				} else {
					writer.writeln("} else {");
					writer.pushIndent();
					emitStmtBlockContent(writer, elseBranch, scope);
					writer.popIndent();
					writer.writeln("}");
				}
			case SForIn(name, iterable, body, _):
				emitForIn(writer, name, iterable, body, scope);
			case SSwitch(scrutinee, cases, _):
				emitSwitch(writer, scrutinee, cases, scope);
			case SReturnVoid(_):
				writer.writeln("return;");
			case SReturn(expr, _):
				writer.writeln("return " + JsExprEmitter.emit(expr, scope.exprScope()) + ";");
			case SExpr(expr, _):
				writer.writeln(JsExprEmitter.emit(expr, scope.exprScope()) + ";");
		}
	}

	static function emitForIn(writer:JsWriter, name:String, iterable:HxExpr, body:HxStmt, scope:JsFunctionScope):Void {
		switch (iterable) {
			case ERange(start, end):
				final local = scope.declareLocal(name);
				writer.writeln(
					"for (var " + local + " = " + JsExprEmitter.emit(start, scope.exprScope())
					+ "; " + local + " < " + JsExprEmitter.emit(end, scope.exprScope())
					+ "; " + local + "++) {"
				);
				writer.pushIndent();
				emitStmtBlockContent(writer, body, scope);
				writer.popIndent();
				writer.writeln("}");
			case _:
				final sourceVar = scope.freshTemp("__iter");
				final indexVar = scope.freshTemp("__i");
				final local = scope.declareLocal(name);
				writer.writeln("var " + sourceVar + " = " + JsExprEmitter.emit(iterable, scope.exprScope()) + ";");
				writer.writeln("for (var " + indexVar + " = 0; " + indexVar + " < " + sourceVar + ".length; " + indexVar + "++) {");
				writer.pushIndent();
				writer.writeln("var " + local + " = " + sourceVar + "[" + indexVar + "];");
				emitStmtBlockContent(writer, body, scope);
				writer.popIndent();
				writer.writeln("}");
		}
	}

	static function emitSwitch(
		writer:JsWriter,
		scrutinee:HxExpr,
		cases:Array<{ pattern:HxSwitchPattern, body:HxStmt }>,
		scope:JsFunctionScope
	):Void {
		final scrutineeVar = scope.freshTemp("__sw");
		writer.writeln("var " + scrutineeVar + " = " + JsExprEmitter.emit(scrutinee, scope.exprScope()) + ";");

		var isFirst = true;
		for (c in cases) {
			final lowered = JsSwitchPatternLowering.lower(c.pattern, scrutineeVar);
			final head = isFirst ? "if" : "else if";
			writer.writeln(head + " (" + lowered.cond + ") {");
			writer.pushIndent();
			if (lowered.bindName != null) {
				final bind = scope.declareLocal(lowered.bindName);
				writer.writeln("var " + bind + " = " + scrutineeVar + ";");
			}
			emitStmtBlockContent(writer, c.body, scope);
			writer.popIndent();
			writer.writeln("}");
			isFirst = false;
		}
	}
}
