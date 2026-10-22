package backend.source;

import backend.source.SourceFunctionRenderFrame.SourceFunctionRenderFrameTools;

/**
	Render Haxe control across Lua protected calls without turning transfers into errors.
	A protected function returns a private completion tag and its optional value.
	Only actual Lua errors enter the catch chain. Each nested closure starts a new
	function scope; each loop records the protected-call depth of its destination.
**/
@:access(backend.source.SourceTargetCommon)
private function scope(frame:SourceFunctionRenderFrame):LuaControlScope
	return SourceFunctionRenderFrameTools.requireLuaControl(frame);

@:access(backend.source.SourceTargetCommon)
private function plan(frame:SourceFunctionRenderFrame):LuaClassPlan
	return scope(frame).classPlan;

@:access(backend.source.SourceTargetCommon)
function returned(frame:SourceFunctionRenderFrame, value:Null<HxExpr>):String {
	final rendered = value == null ? "nil" : SourceTargetCommon.renderExprWithFrame(frame, value);
	return returnValue(frame, rendered);
}

@:access(backend.source.SourceTargetCommon)
private function returnValue(frame:SourceFunctionRenderFrame, value:String):String
	return "do return " + (scope(frame).depth > 0 ? "1, " : "") + value + " end";

@:access(backend.source.SourceTargetCommon)
function thrown(frame:SourceFunctionRenderFrame, value:HxExpr):String
	return plan(frame).runtimeName + ".raise(" + SourceTargetCommon.renderExprWithFrame(frame, value) + ", 0)";

@:access(backend.source.SourceTargetCommon)
function loopTransfer(frame:SourceFunctionRenderFrame, isBreak:Bool):String {
	final current = scope(frame);
	if (current.loop == null)
		throw "Lua loop transfer has no enclosing loop";
	if (current.depth > current.loop.depth)
		return "do return " + (isBreak ? "2" : "3") + " end";
	return "do " + (isBreak ? current.loop.breakFlag + " = true; " : "") + "break end";
}

/** A one-shot repeat block implements continue without requiring a Lua goto extension. */
@:access(backend.source.SourceTargetCommon)
function loop(frame:SourceFunctionRenderFrame, header:String, body:HxStmt, indent:String, ?until:String):Array<String> {
	final flag = SourceFunctionRenderFrameTools.freshPatternName(frame);
	final child = SourceFunctionRenderFrameTools.withLuaControl(frame, scope(frame).withinLoop(flag));
	final out = [indent + header, indent + "  local " + flag + " = false", indent + "  repeat"];
	for (line in SourceTargetCommon.renderStmtWithFrame(child, body, indent + "    "))
		out.push(line);
	out.push(indent + "  until true");
	out.push(indent + "  if " + flag + " then break end");
	out.push(indent + (until == null ? "end" : "until " + until));
	return out;
}

/** Catch names only locate typed bindings; written type strings never decide runtime matching. */
@:access(backend.source.SourceTargetCommon)
private function matches(frame:SourceFunctionRenderFrame, name:String, value:String, classPlan:LuaClassPlan):String {
	final local = switch frame {
		case TypedFunction(Lua, projection, _, _, _): projection.getLocalCatalog().findByProjectedName(name);
		case _: throw "Lua catch requires its exact typed function";
	};
	if (local == null || !local.getBinding().getKind().match(CatchVariable))
		throw "Lua catch has no exact binding: " + name;
	final type = TyAliasExpansion.revealNonNullable(local.getBinding().getType());
	if (type.isDynamic())
		return "true";
	final nativeType = switch type.getSemanticKey() {
		case "primitive:String" | "nominal:String": "string";
		case "primitive:Bool" | "nominal:StdTypes.Bool": "boolean";
		case _: null;
	};
	if (nativeType != null)
		return classPlan.runtimeName + ".valueType(" + value + ") == " + SourceTargetCommon.quoteString(nativeType);
	final identity = type.getNominalIdentity();
	final owner = identity == null ? null : classPlan.findOwner(identity.getCanonicalName());
	if (owner != null && !owner.isInterface)
		return classPlan.runtimeName + ".isInstance(" + value + ", " + owner.reference + ")";
	throw "Lua catch requires an admitted runtime type: " + type.getSemanticKey();
}

@:access(backend.source.SourceTargetCommon)
function tryStatement(frame:SourceFunctionRenderFrame, body:HxStmt, catches:Array<{name:String, typeHint:String, body:HxStmt}>, indent:String):Array<String> {
	final classPlan = plan(frame);
	final ok = SourceFunctionRenderFrameTools.freshPatternName(frame);
	final kind = SourceFunctionRenderFrameTools.freshPatternName(frame);
	final value = SourceFunctionRenderFrameTools.freshPatternName(frame);
	final protectedFrame = SourceFunctionRenderFrameTools.withLuaControl(frame, scope(frame).protectedCall());
	final out = [indent + "do",
		indent
		+ "  local "
		+ ok
		+ ", "
		+ kind
		+ ", "
		+ value
		+ " = "
		+ classPlan.runtimeName
		+ ".protect(function()"];
	for (line in SourceTargetCommon.renderStmtWithFrame(protectedFrame, body, indent + "    "))
		out.push(line);
	out.push(indent + "  end)");
	out.push(indent + "  if " + ok + " then");
	out.push(indent + "    if " + kind + " == 1 then " + returnValue(frame, value));
	if (scope(frame).loop != null) {
		out.push(indent + "    elseif " + kind + " == 2 then " + loopTransfer(frame, true));
		out.push(indent + "    elseif " + kind + " == 3 then " + loopTransfer(frame, false));
	}
	out.push(indent + "    end");
	out.push(indent + "  else");
	for (index in 0...catches.length) {
		final clause = catches[index];
		out.push(indent + "    " + (index == 0 ? "if " : "elseif ") + matches(frame, clause.name, kind, classPlan) + " then");
		out.push(indent + "      local " + SourceTargetCommon.valueName(Lua, clause.name) + " = " + kind);
		for (line in SourceTargetCommon.renderStmtWithFrame(frame, clause.body, indent + "      "))
			out.push(line);
	}
	if (catches.length > 0)
		out.push(indent + "    else");
	out.push(indent + "      " + classPlan.runtimeName + ".raise(" + kind + ", 0)");
	if (catches.length > 0)
		out.push(indent + "    end");
	out.push(indent + "  end");
	out.push(indent + "end");
	return out;
}
