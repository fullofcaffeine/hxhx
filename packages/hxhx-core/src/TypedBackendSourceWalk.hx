/** Visits projected source nodes in deterministic preorder without interpreting transport names or raw source. */
class TypedBackendSourceWalk {
	public static function expression(node:Null<HxExpr>, onExpression:HxExpr->Void):Void {
		if (node == null)
			return;
		onExpression(node);
		switch (node) {
			case EField(value, _) | ENullSafeField(value, _) | EMacroExpr(value, _) | ELambda(_, value) | EUnop(_, _, value) | ECast(value, _) |
				EUntyped(value) | EReturn(value):
				expression(value, onExpression);
			case ECall(callee, arguments):
				expression(callee, onExpression);
				for (argument in arguments)
					expression(argument, onExpression);
			case ESwitch(value, _, branches):
				expression(value, onExpression);
				for (branch in branches)
					expression(branch, onExpression);
			case ENew(_, values) | EAnon(_, values) | EArrayDecl(values) | EVars(values):
				for (value in values)
					expression(value, onExpression);
			case EBinop(_, left, right) | EArrayAccess(left, right) | ERange(left, right):
				expression(left, onExpression);
				expression(right, onExpression);
			case ETernary(condition, yes, no):
				expression(condition, onExpression);
				expression(yes, onExpression);
				expression(no, onExpression);
			case EArrayComprehension(_, iterable, guard, value):
				expression(iterable, onExpression);
				expression(guard, onExpression);
				expression(value, onExpression);
			case EVariableDeclaration(_, _, value, _, _, _):
				expression(value, onExpression);
			case EWhile(condition, body, _, _):
				expression(condition, onExpression);
				for (value in body)
					expression(value, onExpression);
			case ENull | EBool(_) | EString(_) | EInt(_) | EFloat(_) | EEnumValue(_) | EThis | ESuper | EIdent(_) | EMacroType(_) | ETryCatchRaw(_) |
				ESwitchRaw(_) | EUnsupported(_) | EBreak(_) | EContinue(_):
		}
	}

	public static function statement(node:HxStmt, onExpression:HxExpr->Void, onStatement:HxStmt->Void):Void {
		onStatement(node);
		switch (node) {
			case SBlock(body, _):
				for (child in body)
					statement(child, onExpression, onStatement);
			case SVar(_, _, value, _, _) | SThrow(value, _) | SReturn(value, _) | SExpr(value, _):
				expression(value, onExpression);
			case SIf(condition, yes, no, _):
				expression(condition, onExpression);
				statement(yes, onExpression, onStatement);
				if (no != null)
					statement(no, onExpression, onStatement);
			case SForIn(_, value, body, _) | SForKeyValue(_, _, value, body, _) | SWhile(value, body, _) | SDoWhile(body, value, _):
				expression(value, onExpression);
				statement(body, onExpression, onStatement);
			case SSwitch(value, _, bodies, _):
				expression(value, onExpression);
				for (body in bodies)
					statement(body, onExpression, onStatement);
			case STry(body, catches, _):
				statement(body, onExpression, onStatement);
				for (clause in catches)
					statement(clause.body, onExpression, onStatement);
			case SBreak(_) | SContinue(_) | SReturnVoid(_):
		}
	}
}
