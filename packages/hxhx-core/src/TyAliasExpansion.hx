import haxe.ds.StringMap;

/**
	An argument retains the caller environment and expansion path.
	Following a parameter resumes that caller, rather than treating the argument
	as another occurrence inside the callee's definition. This distinction lets
	Id<Id<Int>> reduce to Int while Branch=Id<Branch> remains a cycle.
 */
private typedef AliasExpansionArgument = {
	final type:TyType;
	final bindings:StringMap<AliasExpansionArgument>;
	final path:Array<TyAliasDefinition>;
};

/**
	Reveal a type constructor without expanding its recursive children.
	Field, call, and index consumers can request this view explicitly. The shared
	TyType getters remain finite and never unfold a referenced definition.
	Arguments are demanded only when a body uses them, so Drop<Branch> can
	reduce to Int even when Branch itself names Drop<Branch>.
 */
function reveal(type:TyType):TyType {
	return follow(type, new StringMap<AliasExpansionArgument>(), [], false, definition -> definition.getBody());
}

/**
	Resolve a structural base while its enclosing alias graph is under construction.
	The resolver supplies bound bodies on demand and owns construction-cycle checks.
	This entry never publishes a type use. Other consumers require sealed bodies.
 */
function revealForResolution(type:TyType, body:TyAliasDefinition->TyType):TyType {
	return follow(type, new StringMap<AliasExpansionArgument>(), [], false, body);
}

/**
	Reveal a receiver through nullable wrappers in the same guarded expansion.
	Keeping one path prevents a nullable alias cycle from restarting expansion
	forever at each wrapper. This is a termination guard, not a parity claim for
	upstream declarations that fail to terminate during type resolution.
 */
function revealNonNullable(type:TyType):TyType {
	return follow(type, new StringMap<AliasExpansionArgument>(), [], true, definition -> definition.getBody());
}

/** Follow only the result path; a real constructor ends this expansion step. */
private function follow(type:TyType, bindings:StringMap<AliasExpansionArgument>, path:Array<TyAliasDefinition>, unwrapNullable:Bool,
		body:TyAliasDefinition->TyType):TyType {
	if (unwrapNullable && type.isNullable())
		return follow(type.unwrapNull(), bindings, path, unwrapNullable, body);
	final parameter = type.getTypeParameterIdentity();
	if (parameter != null) {
		final argument = bindings.get(parameter.getCanonicalKey());
		return argument == null ? type : follow(argument.type, argument.bindings, argument.path, unwrapNullable, body);
	}
	final definition = type.getAliasDefinition();
	if (definition == null)
		return substitute(type, bindings);
	if (path.indexOf(definition) >= 0) {
		final declaration = definition.getDeclaration();
		final context = declaration.getContext();
		throw new TyperError(context.filePath, definition.getSourceSyntax().getPos(), "Recursive typedef is not allowed: " + [
			for (entry in path.concat([definition]))
				entry.getCanonicalName()
		].join(" -> "));
	}
	final local = new StringMap<AliasExpansionArgument>();
	final parameters = definition.getParameterIds();
	final arguments = type.getTypeArguments();
	for (index in 0...parameters.length)
		local.set(parameters[index].getCanonicalKey(), {type: arguments[index], bindings: bindings, path: path});
	return follow(body(definition), local, path.concat([definition]), unwrapNullable, body);
}

/**
	Copy the visible constructor with its actual arguments. Do not unfold aliases
	in those arguments: future field accesses choose their own finite expansion.
	Captured environments are acyclic because each call refers only to its caller.
 */
private function substitute(type:TyType, bindings:StringMap<AliasExpansionArgument>):TyType {
	if (!bindings.iterator().hasNext())
		return type;
	final replacements = new StringMap<TyType>();
	for (parameter in TyTypeSubstitution.freeParameterIdentities(type)) {
		final key = parameter.getCanonicalKey();
		final argument = bindings.get(key);
		if (argument != null)
			replacements.set(key, substitute(argument.type, argument.bindings));
	}
	return replacements.iterator().hasNext() ? TyTypeSubstitution.apply(type, replacements) : type;
}
