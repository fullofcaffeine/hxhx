package backend.js;

import StringTools;

/**
	Statement-to-JS lowering for `js-native` MVP.

	Scope
	- Covers the MVP subset required by initial non-delegating JS smoke fixtures.
	- Unsupported statement forms fail fast through expression-level checks.
**/
class JsStmtEmitter {
	public static function emitFunctionBody(writer:JsWriter, body:Array<HxStmt>, scope:JsFunctionScope):Void {
		for (s in body)
			emitStmt(writer, s, scope);
	}

	static function emitStmtBlockContent(writer:JsWriter, stmt:HxStmt, scope:JsFunctionScope):Void {
		switch (stmt) {
			case SBlock(stmts, _):
				for (s in stmts)
					emitStmt(writer, s, scope);
			case _:
				emitStmt(writer, stmt, scope);
		}
	}

	public static function emitStmt(writer:JsWriter, stmt:HxStmt, scope:JsFunctionScope):Void {
		switch (stmt) {
			case SBlock(stmts, _):
				writer.writeln("{");
				writer.pushIndent();
				for (s in stmts)
					emitStmt(writer, s, scope);
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
			case SWhile(cond, body, _):
				writer.writeln("while (" + JsExprEmitter.emit(cond, scope.exprScope()) + ") {");
				writer.pushIndent();
				emitStmtBlockContent(writer, body, scope);
				writer.popIndent();
				writer.writeln("}");
			case SDoWhile(body, cond, _):
				writer.writeln("do {");
				writer.pushIndent();
				emitStmtBlockContent(writer, body, scope);
				writer.popIndent();
				writer.writeln("} while (" + JsExprEmitter.emit(cond, scope.exprScope()) + ");");
			case STry(tryBody, catches, _):
				emitTry(writer, tryBody, catches, scope);
			case SForIn(name, iterable, body, _):
				emitForIn(writer, name, iterable, body, scope);
			case SSwitch(scrutinee, cases, _):
				emitSwitch(writer, scrutinee, cases, scope);
			case SReturnVoid(_):
				writer.writeln("return;");
			case SReturn(expr, _):
				writer.writeln("return " + JsExprEmitter.emit(expr, scope.exprScope()) + ";");
			case SThrow(expr, _):
				writer.writeln("throw " + JsExprEmitter.emit(expr, scope.exprScope()) + ";");
			case SBreak(_):
				writer.writeln("break;");
			case SContinue(_):
				writer.writeln("continue;");
			case SExpr(expr, _):
				writer.writeln(JsExprEmitter.emit(expr, scope.exprScope()) + ";");
		}
	}

	static function normalizeCatchType(typeHint:String):String {
		if (typeHint == null)
			return "";
		var hint = StringTools.trim(typeHint);
		if (hint.length == 0)
			return "";
		hint = StringTools.replace(hint, " ", "");
		hint = StringTools.replace(hint, "\t", "");
		hint = StringTools.replace(hint, "\n", "");
		hint = StringTools.replace(hint, "\r", "");
		while (StringTools.startsWith(hint, "Null<") && StringTools.endsWith(hint, ">")) {
			hint = hint.substr(5, hint.length - 6);
		}
		final genericAt = hint.indexOf("<");
		if (genericAt >= 0)
			hint = hint.substr(0, genericAt);
		return hint;
	}

	static function simpleTypeName(fullName:String):String {
		if (fullName == null || fullName.length == 0)
			return "";
		final parts = fullName.split(".");
		return parts[parts.length - 1];
	}

	static function emitCatchCondition(typeHint:String, errRef:String):String {
		final normalized = normalizeCatchType(typeHint);
		if (normalized.length == 0 || normalized == "Dynamic" || normalized == "Any")
			return "true";

		return switch (normalized) {
			case "String" | "StdTypes.String":
				"(typeof " + errRef + " === \"string\" || " + errRef + " instanceof String)";
			case "Bool" | "StdTypes.Bool":
				"(typeof " + errRef + " === \"boolean\")";
			case "Int" | "StdTypes.Int":
				"(typeof " + errRef + " === \"number\" && ((" + errRef + " | 0) === " + errRef + "))";
			case "Float" | "StdTypes.Float":
				"(typeof " + errRef + " === \"number\")";
			case "Array" | "StdTypes.Array":
				"Array.isArray(" + errRef + ")";
			default:
				final simple = simpleTypeName(normalized);
				final normalizedQuoted = JsNameMangler.quoteString(normalized);
				final simpleQuoted = JsNameMangler.quoteString(simple);
				"("
				+ errRef
				+ " != null && typeof "
				+ errRef
				+ " === \"object\" && ("
				+ errRef
				+ ".__hx_name === "
				+ normalizedQuoted
				+ " || "
				+ errRef
				+ ".__hx_name === "
				+ simpleQuoted
				+ " || ("
				+ errRef
				+ ".constructor != null && ("
				+ errRef
				+ ".constructor.__hx_name === "
				+ normalizedQuoted
				+ " || "
				+ errRef
				+ ".constructor.__hx_name === "
				+ simpleQuoted
				+ "))))";
		}
	}

	static function emitTry(writer:JsWriter, tryBody:HxStmt, catches:Array<{name:String, typeHint:String, body:HxStmt}>, scope:JsFunctionScope):Void {
		writer.writeln("try {");
		writer.pushIndent();
		emitStmtBlockContent(writer, tryBody, scope);
		writer.popIndent();
		writer.writeln("} catch (__hx_err) {");
		writer.pushIndent();

		if (catches == null || catches.length == 0) {
			writer.writeln("throw __hx_err;");
		} else {
			for (i in 0...catches.length) {
				final c = catches[i];
				final head = i == 0 ? "if" : "else if";
				final condition = emitCatchCondition(c.typeHint, "__hx_err");
				writer.writeln(head + " (" + condition + ") {");
				writer.pushIndent();
				final bind = scope.declareLocal(c.name);
				writer.writeln("var " + bind + " = __hx_err;");
				emitStmtBlockContent(writer, c.body, scope);
				writer.popIndent();
				writer.writeln("}");
			}
			writer.writeln("else {");
			writer.pushIndent();
			writer.writeln("throw __hx_err;");
			writer.popIndent();
			writer.writeln("}");
		}

		writer.popIndent();
		writer.writeln("}");
	}

	static function emitForIn(writer:JsWriter, name:String, iterable:HxExpr, body:HxStmt, scope:JsFunctionScope):Void {
		switch (iterable) {
			case ERange(start, end):
				final local = scope.declareLocal(name);
				writer.writeln("for (var " + local + " = " + JsExprEmitter.emit(start, scope.exprScope()) + "; " + local + " < "
					+ JsExprEmitter.emit(end, scope.exprScope()) + "; " + local + "++) {");
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

	static function emitSwitch(writer:JsWriter, scrutinee:HxExpr, cases:Array<{pattern:HxSwitchPattern, body:HxStmt}>, scope:JsFunctionScope):Void {
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
