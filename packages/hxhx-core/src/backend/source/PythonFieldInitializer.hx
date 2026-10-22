package backend.source;

/**
	Run a field's typed statements before publishing its final value.
	Python has neither statement expressions nor block-local variables. A private
	helper therefore supplies the initializer's lexical scope. Shared control
	adaptation forbids an authored return from escaping through this helper;
	only its final value becomes the generated return. A throw skips publication.
 */
function render(input:{
	projection:TypedBackendFieldInitializerProjection,
	destination:String,
	helperName:Void->String,
	statements:(Array<HxStmt>, String) -> Array<String>,
	expression:HxExpr->String
}):Array<String> {
	final projection = input.projection;
	projection.assertCurrent();
	final body = TypedControlStatements.initializerBody(projection.getExpression(), projection.getStableIdentity());
	if (body.statements.length == 0 && body.value != null)
		return [input.destination + " = " + input.expression(body.value)];
	final helper = input.helperName();
	final lines = ["def " + helper + "():"];
	final statements = input.statements(body.statements, "    ");
	for (line in statements)
		lines.push(line);
	if (body.value != null)
		lines.push("    return " + input.expression(body.value));
	else if (statements.length == 0)
		lines.push("    pass");
	lines.push(input.destination + " = " + helper + "()");
	lines.push("del " + helper);
	projection.assertCurrent();
	return lines;
}
