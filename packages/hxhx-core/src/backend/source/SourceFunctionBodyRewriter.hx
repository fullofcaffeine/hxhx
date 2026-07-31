package backend.source;

/**
	Rebuild one source-shaped function body and apply a post-order expression
	transform.

	Target-specific lowerings use this shared structural walk while their own
	callback decides which already-typed expression needs a target marker. The
	rewriter preserves statement positions, declaration metadata, and expression
	evaluation order; it owns no semantic lookup or mutable request state.
**/
class SourceFunctionBodyRewriter {
	public static function body(statements:Array<HxStmt>, transform:HxExpr->HxExpr):Array<HxStmt> {
		if (transform == null)
			throw "source function body rewriter requires an expression transform";
		return statements == null ? [] : [for (statement in statements) statementNode(statement, transform)];
	}

	static function nullableExpression(value:Null<HxExpr>, transform:HxExpr->HxExpr):Null<HxExpr>
		return value == null ? null : expressionNode(value, transform);

	static function statementNode(statement:HxStmt, transform:HxExpr->HxExpr):HxStmt {
		return switch (statement) {
			case SBlock(statements, position):
				SBlock([for (child in statements) statementNode(child, transform)], position);
			case SVar(name, typeHint, initializer, position, metadata):
				SVar(name, typeHint, nullableExpression(initializer, transform), position, metadata == null ? [] : metadata.copy());
			case SIf(condition, thenBranch, elseBranch, position):
				SIf(expressionNode(condition, transform), statementNode(thenBranch, transform),
					elseBranch == null ? null : statementNode(elseBranch, transform), position);
			case SForIn(name, iterable, loopBody, position):
				SForIn(name, expressionNode(iterable, transform), statementNode(loopBody, transform), position);
			case SForKeyValue(keyName, valueName, iterable, loopBody, position):
				SForKeyValue(keyName, valueName, expressionNode(iterable, transform), statementNode(loopBody, transform), position);
			case SWhile(condition, loopBody, position):
				SWhile(expressionNode(condition, transform), statementNode(loopBody, transform), position);
			case SDoWhile(loopBody, condition, position):
				SDoWhile(statementNode(loopBody, transform), expressionNode(condition, transform), position);
			case SSwitch(scrutinee, patterns, bodies, position):
				SSwitch(expressionNode(scrutinee, transform), patterns == null ? [] : patterns.copy(),
					bodies == null ? [] : [for (body in bodies) statementNode(body, transform)], position);
			case STry(tryBody, catches, position):
				STry(statementNode(tryBody, transform), [
					for (item in catches)
						{
							name: item.name,
							typeHint: item.typeHint,
							body: statementNode(item.body, transform)
						}
				], position);
			case SThrow(value, position):
				SThrow(expressionNode(value, transform), position);
			case SReturn(value, position):
				SReturn(expressionNode(value, transform), position);
			case SExpr(value, position):
				SExpr(expressionNode(value, transform), position);
			case SBreak(_) | SContinue(_) | SReturnVoid(_):
				statement;
		};
	}

	static function expressionNode(value:HxExpr, transform:HxExpr->HxExpr):HxExpr {
		final rebuilt:HxExpr = switch (value) {
			case EField(receiver, field):
				EField(expressionNode(receiver, transform), field);
			case ENullSafeField(receiver, field):
				ENullSafeField(expressionNode(receiver, transform), field);
			case ECall(callee, arguments):
				ECall(expressionNode(callee, transform), [for (argument in arguments) expressionNode(argument, transform)]);
			case EMacroExpr(inner, wrappers):
				EMacroExpr(expressionNode(inner, transform), wrappers == null ? [] : wrappers.copy());
			case ELambda(arguments, lambdaBody):
				ELambda(arguments == null ? [] : arguments.copy(), expressionNode(lambdaBody, transform));
			case ESwitch(scrutinee, patterns, expressions):
				ESwitch(expressionNode(scrutinee, transform), patterns == null ? [] : patterns.copy(),
					expressions == null ? [] : [for (item in expressions) expressionNode(item, transform)]);
			case ENew(typePath, arguments):
				ENew(typePath, [for (argument in arguments) expressionNode(argument, transform)]);
			case EUnop(op, fixity, inner):
				EUnop(op, fixity, expressionNode(inner, transform));
			case EBinop(op, left, right):
				EBinop(op, expressionNode(left, transform), expressionNode(right, transform));
			case ETernary(condition, thenExpression, elseExpression):
				ETernary(expressionNode(condition, transform), expressionNode(thenExpression, transform), expressionNode(elseExpression, transform));
			case EAnon(fieldNames, fieldValues):
				EAnon(fieldNames == null ? [] : fieldNames.copy(),
					fieldValues == null ? [] : [for (fieldValue in fieldValues) expressionNode(fieldValue, transform)]);
			case EArrayComprehension(name, iterable, guardExpression, yieldExpression):
				EArrayComprehension(name, expressionNode(iterable, transform), nullableExpression(guardExpression, transform),
					expressionNode(yieldExpression, transform));
			case EArrayDecl(values):
				EArrayDecl([for (item in values) expressionNode(item, transform)]);
			case EArrayAccess(array, index):
				EArrayAccess(expressionNode(array, transform), expressionNode(index, transform));
			case ERange(start, end):
				ERange(expressionNode(start, transform), expressionNode(end, transform));
			case ECast(inner, typeHint):
				ECast(expressionNode(inner, transform), typeHint);
			case EUntyped(inner):
				EUntyped(expressionNode(inner, transform));
			case EReturn(inner):
				EReturn(nullableExpression(inner, transform));
			case EVars(declarations):
				EVars([for (declaration in declarations) expressionNode(declaration, transform)]);
			case EVariableDeclaration(name, typeHint, initializer, position, isFinal, isStatic):
				EVariableDeclaration(name, typeHint, nullableExpression(initializer, transform), position, isFinal, isStatic);
			case EWhile(condition, body, bodyIsBlock, position):
				EWhile(expressionNode(condition, transform), [for (item in body) expressionNode(item, transform)], bodyIsBlock, position);
			case _:
				value;
		};
		return transform(rebuilt);
	}
}
