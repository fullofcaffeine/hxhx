package backend.js;

/** Emit callback bodies with their checked parameter contract and the enclosing Haxe receiver. */
function emit(expression:HxExpr, arguments:Array<String>, body:HxExpr, scope:JsEmitScope):String {
	final nested = JsFunctionScope.nested(scope);
	final cells = new Array<String>();
	final cellParameters = new Array<String>();
	if (scope != null && scope.iterationStorage != null)
		for (name in scope.iterationStorage.captures(expression)) {
			final cell = scope.resolveIterationCell == null ? null : scope.resolveIterationCell(name);
			if (cell == null)
				throw "JavaScript closure lost its exact iteration cell";
			cells.push(cell);
			cellParameters.push(nested.bindIterationCell(name));
		}
	final parameters = [for (argument in arguments) nested.declareLocal(argument)];
	final writer = new JsWriter();
	if (scope != null && scope.lambdaUses != null) {
		final occurrence = scope.lambdaUses(expression);
		if (occurrence == null)
			throw "JavaScript lambda requires its exact callable occurrence";
		final contract = occurrence.callableType.getFunctionParameters();
		if (contract.length != parameters.length)
			throw "JavaScript lambda parameter count changed after projection";
		for (index in 0...contract.length)
			if (contract[index].isRest)
				// The array literal also works when a source local shadows the global Array constructor.
				writer.writeln(parameters[index] + " = [].slice.call(arguments, " + index + ");");
	}
	// Direct expression-emitter fixtures can lack a typed owner; production scopes supply one.
	switch body {
		case ELoweredControl(FunctionBody, _, _, _):
			JsStmtEmitter.emitFunctionBody(writer, TypedControlStatements.functionBody(body, null, nested.exprScope().requireExpression), nested);
		case _:
			writer.writeln("return " + JsExprEmitter.emit(body, nested.exprScope()) + ";");
	}
	final callback = "(function(" + parameters.join(", ") + ") {\n" + writer.toString() + "\n}).bind(this)";
	// ES5 has function-scoped vars. Capture the current cell object in a new
	// function scope without changing the callback's parameters or Haxe receiver.
	return cells.length == 0 ? callback : "(function("
		+ cellParameters.join(", ")
		+ ") { return "
		+ callback
		+ "; }).call(this, "
		+ cells.join(", ")
		+ ")";
}

/** An initializer keeps its own lambda facts even when its code runs inside a constructor. */
function initializerLookup(owner:TypedBackendClassProjection, field:HxFieldDecl):HxExpr->Null<TypedBackendLambdaOccurrence> {
	for (initializer in owner.getFieldInitializers())
		if (initializer.getDeclaration() == field)
			return initializer.findLambda;
	throw "JavaScript field initializer requires its exact lambda catalog";
}
