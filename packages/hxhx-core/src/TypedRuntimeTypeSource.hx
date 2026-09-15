/**
	Recognizes compiler-owned type-operation markers in source-shaped projections.

	A NUL cannot occur in a parsed Haxe identifier. The marker therefore cannot be
	confused with an authored call. It carries only the evaluated child; the exact
	type target belongs to the executable projection's occurrence catalog.
**/
class TypedRuntimeTypeSource {
	public static inline final VALUE = "\x00hxhx.runtime.type.value";
	public static inline final TEST = "\x00hxhx.runtime.type.test";

	public static function isMarker(expression:HxExpr):Bool {
		return switch (expression) {
			case ECall(EIdent(VALUE), _) | ECall(EIdent(TEST), _): true;
			case _: false;
		};
	}

	/** Collect marker objects without interpreting names, targets, or opaque source text. */
	public static function inExpression(expression:Null<HxExpr>):Array<HxExpr> {
		final out = new Array<HxExpr>();
		visitExpression(expression, out);
		return out;
	}

	public static function inStatements(statements:Array<HxStmt>):Array<HxExpr> {
		final out = new Array<HxExpr>();
		for (statement in statements)
			visitStatement(statement, out);
		return out;
	}

	static function visitExpression(expression:Null<HxExpr>, out:Array<HxExpr>):Void {
		if (expression == null)
			return;
		if (isMarker(expression))
			out.push(expression);
		switch (expression) {
			case EField(value, _) | ENullSafeField(value, _) | EMacroExpr(value, _) | ELambda(_, value) | EUnop(_, _, value) | ECast(value, _) |
				EUntyped(value) | EReturn(value):
				visitExpression(value, out);
			case ECall(callee, arguments):
				visitExpression(callee, out);
				for (argument in arguments)
					visitExpression(argument, out);
			case ESwitch(value, _, branches):
				visitExpression(value, out);
				for (branch in branches)
					visitExpression(branch, out);
			case ENew(_, values) | EAnon(_, values) | EArrayDecl(values) | EVars(values):
				for (value in values)
					visitExpression(value, out);
			case EBinop(_, left, right) | EArrayAccess(left, right) | ERange(left, right):
				visitExpression(left, out);
				visitExpression(right, out);
			case ETernary(condition, yes, no):
				visitExpression(condition, out);
				visitExpression(yes, out);
				visitExpression(no, out);
			case EArrayComprehension(_, iterable, guard, value):
				visitExpression(iterable, out);
				visitExpression(guard, out);
				visitExpression(value, out);
			case EVariableDeclaration(_, _, value, _, _, _):
				visitExpression(value, out);
			case EWhile(condition, body, _, _):
				visitExpression(condition, out);
				for (value in body)
					visitExpression(value, out);
			case ENull | EBool(_) | EString(_) | EInt(_) | EFloat(_) | EEnumValue(_) | EThis | ESuper | EIdent(_) | EMacroType(_) | ETryCatchRaw(_) |
				ESwitchRaw(_) | EUnsupported(_) | EBreak(_) | EContinue(_):
		}
	}

	static function visitStatement(statement:HxStmt, out:Array<HxExpr>):Void {
		switch (statement) {
			case SBlock(body, _):
				for (child in body)
					visitStatement(child, out);
			case SVar(_, _, value, _, _) | SThrow(value, _) | SReturn(value, _) | SExpr(value, _):
				visitExpression(value, out);
			case SIf(condition, yes, no, _):
				visitExpression(condition, out);
				visitStatement(yes, out);
				if (no != null)
					visitStatement(no, out);
			case SForIn(_, value, body, _) | SForKeyValue(_, _, value, body, _) | SWhile(value, body, _) | SDoWhile(body, value, _):
				visitExpression(value, out);
				visitStatement(body, out);
			case SSwitch(value, _, bodies, _):
				visitExpression(value, out);
				for (body in bodies)
					visitStatement(body, out);
			case STry(body, catches, _):
				visitStatement(body, out);
				for (clause in catches)
					visitStatement(clause.body, out);
			case SBreak(_) | SContinue(_) | SReturnVoid(_):
		}
	}
}
