package backend.source;

/**
	Derive the class-wide PHP representation required for abstract backing values.

	Some Haxe abstract-style methods use `this` as the wrapped value: a
	constructor assigns it, an operator updates it, and an ordinary method reads
	it. PHP cannot assign to `$this`, so every method emitted into that class
	must consistently use `$this->__hx_value` once any method requires the
	carrier. This helper derives that one immutable class fact from exact sealed
	function bodies before per-function syntax rendering begins.
**/
class PhpThisValueSlotFacts {
	/** Report whether any exact function body requires the shared value carrier. **/
	public static function classNeedsValueSlot(functions:Array<TypedBackendFunctionProjection>):Bool {
		if (functions == null)
			return false;
		for (fn in functions)
			if (statementListNeedsValueSlot(fn.getBody()))
				return true;
		return false;
	}

	static function statementListNeedsValueSlot(statements:Array<HxStmt>):Bool {
		if (statements == null)
			return false;
		for (statement in statements)
			if (statementNeedsValueSlot(statement))
				return true;
		return false;
	}

	static function statementNeedsValueSlot(statement:HxStmt):Bool {
		return switch (statement) {
			case SBlock(statements, _):
				statementListNeedsValueSlot(statements);
			case SVar(_, _, initializer, _): initializer != null && expressionNeedsValueSlot(initializer);
			case SIf(condition, thenBranch, elseBranch, _): expressionNeedsValueSlot(condition) || statementNeedsValueSlot(thenBranch) || (elseBranch != null
					&& statementNeedsValueSlot(elseBranch));
			case SForIn(_, iterable, body, _): expressionNeedsValueSlot(iterable) || statementNeedsValueSlot(body);
			case SForKeyValue(_, _, iterable, body, _): expressionNeedsValueSlot(iterable) || statementNeedsValueSlot(body);
			case SWhile(condition, body, _): expressionNeedsValueSlot(condition) || statementNeedsValueSlot(body);
			case SDoWhile(body, condition, _): statementNeedsValueSlot(body) || expressionNeedsValueSlot(condition);
			case SSwitch(scrutinee, _, bodies, _): expressionNeedsValueSlot(scrutinee) || statementListNeedsValueSlot(bodies);
			case STry(tryBody, catches, _):
				if (statementNeedsValueSlot(tryBody)) {
					true;
				} else {
					var found = false;
					if (catches != null)
						for (catchClause in catches)
							if (statementNeedsValueSlot(catchClause.body))
								found = true;
					found;
				}
			case SThrow(expression, _) | SReturn(expression, _) | SExpr(expression, _):
				expressionNeedsValueSlot(expression);
			case SBreak(_) | SContinue(_) | SReturnVoid(_):
				false;
		};
	}

	static function expressionNeedsValueSlot(expression:HxExpr):Bool {
		return switch (expression) {
			case EUnop(op, _, EThis) if (op == HxUnaryOperator.Increment || op == HxUnaryOperator.Decrement):
				true;
			case EBinop(op, EThis, _) if (isAssignmentOperator(op) || op == "??=" || op == ">>>="):
				true;
			case ECall(EThis, _):
				true;
			case EThis:
				false;
			case EField(receiver, _):
				expressionNeedsValueSlot(receiver);
			case ECall(callee, arguments): expressionNeedsValueSlot(callee) || expressionListNeedsValueSlot(arguments);
			case EMacroExpr(inner, _):
				expressionNeedsValueSlot(inner);
			case ELambda(_, body):
				expressionNeedsValueSlot(body);
			case ESwitch(scrutinee, _, expressions): expressionNeedsValueSlot(scrutinee) || expressionListNeedsValueSlot(expressions);
			case ENew(_, arguments):
				expressionListNeedsValueSlot(arguments);
			case EUnop(_, _, inner):
				expressionNeedsValueSlot(inner);
			case EBinop(_, left, right): expressionNeedsValueSlot(left) || expressionNeedsValueSlot(right);
			case ETernary(condition, thenExpression, elseExpression): expressionNeedsValueSlot(condition) || expressionNeedsValueSlot(thenExpression) || expressionNeedsValueSlot(elseExpression);
			case EAnon(_, fieldValues):
				expressionListNeedsValueSlot(fieldValues);
			case EArrayComprehension(_, iterable, guardExpression, yieldExpression): expressionNeedsValueSlot(iterable) || (guardExpression != null
					&& expressionNeedsValueSlot(guardExpression)) || expressionNeedsValueSlot(yieldExpression);
			case EArrayDecl(values):
				expressionListNeedsValueSlot(values);
			case EArrayAccess(receiver, index): expressionNeedsValueSlot(receiver) || expressionNeedsValueSlot(index);
			case ECast(inner, _) | EUntyped(inner):
				expressionNeedsValueSlot(inner);
			case _:
				false;
		};
	}

	static function expressionListNeedsValueSlot(expressions:Array<HxExpr>):Bool {
		if (expressions == null)
			return false;
		for (expression in expressions)
			if (expressionNeedsValueSlot(expression))
				return true;
		return false;
	}

	static function isAssignmentOperator(op:String):Bool {
		return switch (op) {
			case "=", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "<<=", ">>=":
				true;
			case _:
				false;
		};
	}
}
