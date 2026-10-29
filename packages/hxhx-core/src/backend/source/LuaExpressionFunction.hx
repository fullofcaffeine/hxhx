package backend.source;

/**
	Render a Lua closure using the return destination selected by shared lowering.
	The enclosing frame retains exact enum facts and a shared temporary-name supply.
	The statement adapter validates the closure's own return and loop destinations
	before emission; it does not assign those transfers to the enclosing method.
**/
@:access(backend.source.SourceTargetCommon)
function render(frame:SourceFunctionRenderFrame, arguments:Array<String>, body:HxExpr):String {
	final names = [for (argument in arguments) SourceTargetCommon.valueName(Lua, argument)].join(", ");
	if (!body.match(ELoweredControl(FunctionBody, _, _, _)))
		return SourceTargetCommon.luaLambdaExpr(names, body);
	final closureFrame = SourceFunctionRenderFrame.SourceFunctionRenderFrameTools.withLuaControl(frame,
		new LuaControlScope(SourceFunctionRenderFrame.SourceFunctionRenderFrameTools.requireLuaControl(frame).classPlan));
	final lines = ["function(" + names + ")"];
	for (line in SourceTargetCommon.renderStmtsWithFrame(closureFrame, TypedControlStatements.functionBody(body), "  "))
		lines.push(line);
	lines.push("end");
	return lines.join("\n");
}

/** Immediate invocation preserves the same frame for the closure and each argument. */
@:access(backend.source.SourceTargetCommon)
function call(frame:SourceFunctionRenderFrame, arguments:Array<String>, body:HxExpr, values:Array<HxExpr>):String {
	return "("
		+ render(frame, arguments, body)
		+ ")("
		+ [for (value in values) SourceTargetCommon.renderExprWithFrame(frame, value)].join(", ") + ")";
}
