package backend.ocaml;

/** A native function region owns its return exception and exact result carrier. */
typedef FunctionStatements = {
	final statements:Array<HxStmt>;
	final carrier:String;
	final isVoid:Bool;
}

/** Rendering callbacks keep native syntax here and the caller's lexical environment in its owner. */
typedef FunctionRenderInput = {
	final facts:TypedBackendLambdaOccurrence;
	final body:HxExpr;
	final names:Stage3OcamlLocalNames;
	final renderType:TyType->String;
	final renderStatements:Array<HxStmt>->String;
}

/** Each closure owns a return exception; the nearest invocation catches its own exit. */
function render(input:FunctionRenderInput):String {
	final selected = plan(input.facts, input.body);
	if (input.names == null)
		throw "OCaml block function requires its local naming owner";
	final arguments = switch input.facts.expression {
		case ELambda(names, _): names;
		case _: throw "OCaml block function lost its lambda occurrence";
	};
	final parameters = input.facts.callableType.getFunctionParameters();
	if (arguments.length != parameters.length)
		throw "OCaml block function lost its parameter mapping";
	final renderedArguments = new Array<String>();
	for (index in 0...arguments.length) {
		final parameter = parameters[index];
		if (parameter.type.hasUnknownComponent() || parameter.isOptional || parameter.isRest)
			throw "OCaml block function requires complete fixed required parameters";
		renderedArguments.push("(" + input.names.targetName(arguments[index]) + " : " + input.renderType(parameter.type) + ")");
	}
	final rendered = input.renderStatements(selected.statements);
	final payload = input.names.internalName("__hx_block_result");
	final fallthrough = selected.isVoid ? "()" : "failwith \"native function reached its end without returning\"";
	// Every caught payload comes from this exact region and has the checked scalar
	// return type. Obj.obj only removes the representation used by the local exception.
	return "(let exception HxBlockReturn of Obj.t in fun "
		+ (renderedArguments.length == 0 ? "()" : renderedArguments.join(" "))
		+ " -> try (let _ = ("
		+ rendered
		+ ") in "
		+ fallthrough
		+ ") with HxBlockReturn "
		+ payload
		+ " -> (Obj.obj "
		+ payload
		+ " : "
		+ selected.carrier
		+ "))";
}

/**
	Admit shared block-function control only where native statements preserve it.
	Return payloads currently require the same concrete scalar type as the callable;
	broader conversion needs exact per-return adaptation before this boundary expands.
 */
function plan(facts:TypedBackendLambdaOccurrence, body:HxExpr):FunctionStatements {
	if (facts == null)
		throw "OCaml block function requires its exact lambda facts";
	switch facts.expression {
		case ELambda(_, selected) if (selected == body):
		case _:
			throw "OCaml block function body is not its exact projected occurrence";
	}
	final result = facts.callableType.getFunctionReturn();
	final carrier = switch result.getSemanticKey() {
		case "primitive:Int": "int";
		case "primitive:Bool": "bool";
		case "primitive:String": "string";
		case "primitive:Void": "unit";
		case _: throw "OCaml block function requires a supported concrete return carrier";
	};
	for (type in facts.getReturnTypes())
		if (type.getSemanticKey() != result.getSemanticKey())
			throw "OCaml block function requires per-return representation conversion";
	final statements = TypedControlStatements.functionBody(body);
	var returns = 0;
	for (statement in statements)
		returns += validate(statement);
	if (returns != facts.getReturnTypes().length)
		throw "OCaml block function lost its typed return operands";
	return {statements: statements, carrier: carrier, isVoid: result.isVoid()};
}

/** Keep unsupported native statement paths from becoming silent placeholder success. */
private function validate(statement:HxStmt):Int {
	return switch statement {
		case SBlock(entries, _):
			var count = 0;
			for (entry in entries)
				count += validate(entry);
			count;
		case SIf(_, yes, no, _): validate(yes) + (no == null ? 0 : validate(no));
		case SWhile(_, body, _) | SDoWhile(body, _, _): validate(body);
		case SForIn(_, ERange(_, _), body, _): validate(body);
		case SSwitch(_, _, branches, _):
			var count = 0;
			for (branch in branches)
				count += validate(branch);
			count;
		case STry(body, catches, _):
			var count = validate(body);
			for (handler in catches)
				count += validate(handler.body);
			count;
		case SThrow(_, _): 0;
		// The shared projection already checked that these target the nearest loop
		// in this function. Native loop handlers catch only their own control signal.
		case SBreak(_) | SContinue(_): 0;
		case SReturn(_, _) | SReturnVoid(_): 1;
		case SVar(_, _, _, _, _) | SExpr(_, _): 0;
		case _: throw "OCaml block function requires a validated adapter for this control form";
	};
}
