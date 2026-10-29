/** A guard's lowered effects stay inside its matching case and before its Boolean result. */
typedef LoweredSwitchGuard = {
	final steps:Array<TypedExpr>;
	final value:Null<TypedExpr>;
	final completes:Bool;
}

/** Exact case bindings and nominal selections survive the decomposition into individual matches. */
typedef GuardedSwitchInput = {
	final source:TypedExpr;
	final input:TyLocalBinding;
	final selected:TyLocalBinding;
	final bodies:Array<TypedExpr>;
	final guards:Array<LoweredSwitchGuard>;
	final completionType:TyType;
	final exhaustive:Bool;
}

/**
	Retain one body per case while the whole switch shares its structural decisions.
	The caller snapshots the input once. A case binds its observed values, then
	evaluates its guard. Marking a selected case before executing its body keeps
	later cases ineligible even when the body changes the input or guard variables.
	No function or loop is introduced, so authored returns and loop exits retain
	their original destinations.
 */
function lower(request:GuardedSwitchInput):Array<TypedExpr> {
	final source = request.source;
	final patterns = source.getPatterns();
	if (request.bodies.length != patterns.length || request.guards.length != patterns.length)
		throw "guarded switch requires one body and guard per case";
	final position = source.getPosition();
	final voidType = TyType.fromHintText("Void");
	final boolType = TyType.fromHintText("Bool");
	final input = TypedExpr.localRead(request.input.getSourceName(), request.input.getType(), position, request.input);
	final selected = TypedExpr.localRead(request.selected.getSourceName(), boolType, position, request.selected);
	final bindings = source.getLocalBindings();
	final facts = source.getSwitchPatterns();
	final selections = facts == null ? [] : facts.getSelections();
	final derivedPatterns = [for (pattern in patterns) TypedSwitchGuards.pattern(pattern)];
	final bodies = new Array<TypedExpr>();
	for (index in 0...patterns.length) {
		final selectedBody = TypedExpr.controlRegion([
			TypedExpr.assign(selected, TypedExpr.boolLiteral(true, boolType, position), boolType, position),
			request.bodies[index]
		], request.bodies[index].getType(), position);
		final guard = request.guards[index];
		final steps = guard.steps.copy();
		if (guard.completes) {
			if (guard.value == null)
				throw "a completing switch guard must provide its Boolean value";
			steps.push(TypedExpr.controlBranch(guard.value, selectedBody, null, voidType, position));
		}
		bodies.push(TypedExpr.controlRegion(steps, voidType, position));
	}
	var result = TypedExpr.controlPatternAttempts(input, TypedExpr.unary(LogicalNot, Prefix, selected, boolType, position), bodies, derivedPatterns, bindings,
		position, request.exhaustive)
		.withType(request.completionType);
	if (facts != null)
		result = result.withSwitchPatterns(new TypedSwitchPatterns(input.getType(), derivedPatterns, selections));
	return [result];
}

/**
	Read completion from the canonical typed attempt before statement projection.
	Only a completing accepted body needs a target exit after it. A guard that
	exits the function or loop never reaches either its accepted body or a retry.
	Checking this layout here avoids rediscovering completion from generated text.
 */
function acceptedCanComplete(body:TypedExpr):Bool {
	if (body.getTag() != ControlRegion)
		throw "guarded completion requires a canonical typed attempt";
	final entries = body.getExpressions();
	for (index in 0...entries.length) {
		final entry = entries[index];
		if (entry.getType().isNoNormalCompletion())
			return false;
		if (index == entries.length - 1 && entry.getTag() == ControlBranch) {
			final children = entry.getExpressions();
			if (children.length != 2)
				throw "guarded attempt must end with its one-armed acceptance branch";
			return !children[1].getType().isNoNormalCompletion();
		}
	}
	throw "guarded attempt lost its acceptance branch or abrupt guard";
}
