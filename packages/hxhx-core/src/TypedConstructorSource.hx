/** Collect executable construction objects, including closure bodies, without interpreting quoted macro syntax. */
function inExpression(expression:Null<HxExpr>):Array<HxExpr> {
	final out = new Array<HxExpr>();
	collect(expression, out);
	return out;
}

/** Preserve deterministic source order across statements and nested control flow. */
function inStatements(statements:Array<HxStmt>):Array<HxExpr> {
	final out = new Array<HxExpr>();
	function visit(statement:HxStmt):Void {
		TypedBackendSourceWalk.statementChildren(statement, expression -> collect(expression, out), visit);
	}
	for (statement in statements)
		visit(statement);
	return out;
}

private function collect(expression:Null<HxExpr>, out:Array<HxExpr>):Void {
	if (expression == null)
		return;
	switch expression {
		case EMacroExpr(_, _):
			return;
		case ENew(_, _) | ECall(ESuper, _):
			out.push(expression);
		case _:
	}
	TypedBackendSourceWalk.expressionChildren(expression, child -> collect(child, out));
}

/** Retain executable construction in declaration defaults as well as body statements. */
function inFunction(declaration:HxFunctionDecl):Array<HxExpr> {
	final out = new Array<HxExpr>();
	for (argument in HxFunctionDecl.getArgs(declaration))
		switch HxFunctionArg.getDefaultValue(argument) {
			case NoDefault:
			case Default(expression):
				collect(expression, out);
		}
	return out.concat(inStatements(HxFunctionDecl.getBody(declaration)));
}
