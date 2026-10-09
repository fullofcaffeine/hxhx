/** Visits projected source nodes in deterministic preorder without interpreting transport names or raw source. */
class TypedBackendSourceWalk {
	/** Visit conditional defaults and then the body without making defaults body statements. */
	public static function functionDeclaration(declaration:HxFunctionDecl, onExpression:HxExpr->Void, onStatement:HxStmt->Void):Void {
		for (argument in HxFunctionDecl.getArgs(declaration))
			switch HxFunctionArg.getDefaultValue(argument) {
				case NoDefault:
				case Default(value):
					expression(value, onExpression);
			}
		for (value in HxFunctionDecl.getBody(declaration))
			statement(value, onExpression, onStatement);
	}

	public static function expression(node:Null<HxExpr>, onExpression:HxExpr->Void):Void {
		if (node == null)
			return;
		onExpression(node);
		expressionChildren(node, child -> expression(child, onExpression));
	}

	/** Visit direct children so execution-aware consumers can own quotation and closure boundaries. */
	public static function expressionChildren(node:HxExpr, onChild:HxExpr->Void):Void {
		function visit(child:Null<HxExpr>):Void {
			if (child != null)
				onChild(child);
		}
		switch (node) {
			case ESourceFunction(facts, body, defaults, _):
				facts.assertDefaultCount(defaults.length);
				visit(body);
				for (value in defaults)
					visit(value);
			case EPrivateAccess(value, _) | EParenthesized(value, _) | EField(value, _) | ENullSafeField(value, _) | EMacroExpr(value, _) |
				ELambda(_, value) | EUnop(_, _, value) | ECast(value, _) | EUntyped(value) | EReturn(value) | EThrow(value, _):
				visit(value);
			case ECall(callee, arguments):
				visit(callee);
				for (argument in arguments)
					visit(argument);
			case ESwitch(value, _, branches):
				visit(value);
				for (branch in branches)
					visit(branch);
			case ESourceTry(_, values, _) | ENew(_, values) | EAnon(_, values) | EArrayDecl(values) | EVars(values) | ESourceGroup(values, _) |
				ELoweredControl(_, _, values, _):
				for (value in values)
					visit(value);
			case EBinop(_, left, right) | EArrayAccess(left, right) | ERange(left, right) | EDiscardThen(left, right) | ESourceFor(_, left, right, _):
				visit(left);
				visit(right);
			case ETernary(condition, yes, no) | ESourceIf(condition, yes, no, _):
				visit(condition);
				visit(yes);
				visit(no);
			case EArrayComprehension(_, iterable, guard, value):
				visit(iterable);
				visit(guard);
				visit(value);
			case EVariableDeclaration(_, _, value, _, _, _):
				visit(value);
			case EWhile(condition, body, _, _, loopKind):
				visit(condition);
				for (value in body)
					visit(value);
			case ENull | EBool(_) | EString(_) | EInt(_) | EFloat(_) | EEnumValue(_) | EThis | ESuper | EIdent(_) | EMacroType(_) | ETryCatchRaw(_) |
				ESwitchRaw(_) | EUnsupported(_) | EBreak(_) | EContinue(_):
		}
	}

	public static function statement(node:HxStmt, onExpression:HxExpr->Void, onStatement:HxStmt->Void):Void {
		onStatement(node);
		statementChildren(node, value -> expression(value, onExpression), child -> statement(child, onExpression, onStatement));
	}

	/** Preserve direct-child order without choosing whether a consumer descends into each child. */
	public static function statementChildren(node:HxStmt, onExpression:HxExpr->Void, onStatement:HxStmt->Void):Void {
		function visit(value:Null<HxExpr>):Void {
			if (value != null)
				onExpression(value);
		}
		switch (node) {
			case STargetScope(_, body, _):
				onStatement(body);
			case SBlock(body, _):
				for (child in body)
					onStatement(child);
			case SVar(_, _, value, _, _) | SThrow(value, _) | SReturn(value, _) | SExpr(value, _):
				visit(value);
			case SIf(condition, yes, no, _):
				visit(condition);
				onStatement(yes);
				if (no != null)
					onStatement(no);
			case SForIn(_, value, body, _) | SForKeyValue(_, _, value, body, _) | SWhile(value, body, _) | SDoWhile(body, value, _):
				visit(value);
				onStatement(body);
			case SSwitch(value, _, bodies, _):
				visit(value);
				for (body in bodies)
					onStatement(body);
			case STry(body, catches, _):
				onStatement(body);
				for (clause in catches)
					onStatement(clause.body);
			case SBreak(_) | SContinue(_) | SReturnVoid(_):
		}
	}
}
