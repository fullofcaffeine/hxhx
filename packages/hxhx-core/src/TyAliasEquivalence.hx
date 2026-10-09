/** A repeated definition pair is useful only after its applied argument obligations pass. */
private typedef AliasDefinitionPair = {
	final left:TyAliasDefinition;
	final right:TyAliasDefinition;
};

/**
	Prove an exact recursive template equivalence as a sufficient assignment fact.
	A false result means this shortcut proved nothing; the caller must still use
	its ordinary directional relation. No variance or conversion is inferred here.
 */
function equivalentApplications(left:TyType, right:TyType):Bool {
	if (left.getAliasDefinition() == null || right.getAliasDefinition() == null)
		return false;
	return equivalentTypes(left, right);
}

/**
	Compare complete storage types when nested aliases have different expansion depths.
	The same finite template proof preserves nominal owners, field rules, and
	argument identity. It grants no structural width, variance, or conversions.
 */
function equivalentTypes(left:TyType, right:TyType):Bool {
	if (left.hasUnknownComponent() || right.hasUnknownComponent())
		return false;
	if (left.getSemanticKey() == right.getSemanticKey())
		return true;
	return new AliasEquivalenceProof(left, right).compare(left, right, [], [], []);
}

/**
	Own the finite definition graph and its observable-parameter fixed point.
	Only declaration-owned parameters can enter a row, so each iteration adds
	from a finite set. Passing an argument only around an alias cycle does not
	make it observable; a real field, function, or nominal constructor must use it.
 */
private class AliasEquivalenceProof {
	final definitions = new Array<TyAliasDefinition>();
	final used = new Array<Array<Bool>>();

	public function new(left:TyType, right:TyType) {
		collect(left);
		collect(right);
		for (definition in definitions)
			used.push([for (_ in definition.getParameterIds()) false]);
		var changed = true;
		while (changed) {
			changed = false;
			for (index in 0...definitions.length) {
				final definition = definitions[index];
				final parameters = definition.getParameterIds();
				function visit(type:TyType):Void {
					final parameter = type.getTypeParameterIdentity();
					if (parameter != null)
						for (slot in 0...parameters.length)
							if (parameter.equals(parameters[slot]) && !used[index][slot]) {
								used[index][slot] = true;
								changed = true;
							}
					final alias = type.getAliasDefinition();
					if (alias != null) {
						final row = used[definitions.indexOf(alias)];
						final arguments = type.getTypeArguments();
						for (slot in 0...arguments.length)
							if (row[slot])
								visit(arguments[slot]);
					} else
						for (child in children(type))
							visit(child);
				}
				visit(definition.getBody());
			}
		}
	}

	function collect(type:TyType):Void {
		final alias = type.getAliasDefinition();
		if (alias != null && definitions.indexOf(alias) < 0) {
			definitions.push(alias);
			collect(alias.getBody());
		}
		for (child in children(type))
			collect(child);
	}

	static function children(type:TyType):Array<TyType> {
		final result = type.getTypeArguments().concat(type.getFunctionArguments()).concat(type.getAnonymousFieldTypes());
		if (type.isNullable())
			result.push(type.unwrapNull());
		if (type.isFunction())
			result.push(type.getFunctionReturn());
		return result;
	}

	/** Compare bodies under their own binders; compare application arguments in the caller's scopes. */
	public function compare(left:TyType, right:TyType, leftScopes:Array<Array<TyTypeParameterId>>, rightScopes:Array<Array<TyTypeParameterId>>,
			active:Array<AliasDefinitionPair>):Bool {
		final first = left.getAliasDefinition();
		final second = right.getAliasDefinition();
		if (first != null && second != null) {
			final leftArguments = left.getTypeArguments();
			final rightArguments = right.getTypeArguments();
			final firstUsed = used[definitions.indexOf(first)];
			final secondUsed = used[definitions.indexOf(second)];
			final firstSlots = [for (index in 0...firstUsed.length) if (firstUsed[index]) index];
			final secondSlots = [for (index in 0...secondUsed.length) if (secondUsed[index]) index];
			if (firstSlots.length != secondSlots.length)
				return false;
			for (index in 0...firstSlots.length)
				if (!compare(leftArguments[firstSlots[index]], rightArguments[secondSlots[index]], leftScopes, rightScopes, active))
					return false;
			for (pair in active)
				if (pair.left == first && pair.right == second)
					return true;
			final firstParameters = first.getParameterIds();
			final secondParameters = second.getParameterIds();
			return compare(first.getBody(), second.getBody(), [[for (slot in firstSlots) firstParameters[slot]]],
				[[for (slot in secondSlots) secondParameters[slot]]], active.concat([
					{
						left: first,
						right: second
					}
				]));
		}
		if (first != null || second != null)
			return compare(TyAliasExpansion.reveal(left), TyAliasExpansion.reveal(right), leftScopes, rightScopes, active);
		if (left.isNullable() || right.isNullable())
			return left.isNullable()
				&& right.isNullable()
				&& compare(left.unwrapNull(), right.unwrapNull(), leftScopes, rightScopes, active);
		if (left.isFunction() || right.isFunction()) {
			if (!left.isFunction() || !right.isFunction())
				return false;
			final firstParameters = left.getFunctionParameters();
			final secondParameters = right.getFunctionParameters();
			if (firstParameters.length != secondParameters.length)
				return false;
			for (index in 0...firstParameters.length) {
				final a = firstParameters[index];
				final b = secondParameters[index];
				if (a.isOptional != b.isOptional || a.isRest != b.isRest || !compare(a.type, b.type, leftScopes, rightScopes, active))
					return false;
			}
			return compare(left.getFunctionReturn(), right.getFunctionReturn(), leftScopes, rightScopes, active);
		}
		if (left.isAnonymous() || right.isAnonymous()) {
			if (!left.isAnonymous() || !right.isAnonymous())
				return false;
			final firstFields = left.getAnonymousFields();
			final secondFields = right.getAnonymousFields();
			if (firstFields.length != secondFields.length)
				return false;
			for (index in 0...firstFields.length) {
				final a = firstFields[index];
				final b = secondFields[index];
				if (TyAnonymousField.semanticKey(TyAnonymousField.withType(a,
					TyType.unknown())) != TyAnonymousField.semanticKey(TyAnonymousField.withType(b, TyType.unknown())))
					return false;
				final localLeft = switch a.kind {
					case Method(parameters): leftScopes.concat([parameters]);
					case _: leftScopes;
				};
				final localRight = switch b.kind {
					case Method(parameters): rightScopes.concat([parameters]);
					case _: rightScopes;
				};
				if (!compare(a.type, b.type, localLeft, localRight, active))
					return false;
			}
			return true;
		}
		if (left.getNominalIdentity() != null
			|| right.getNominalIdentity() != null
			|| left.isAbstractMeta()
			|| right.isAbstractMeta()) {
			if (left.isAbstractMeta() != right.isAbstractMeta())
				return false;
			if (!left.isAbstractMeta()
				&& (left.getNominalIdentity() == null
					|| right.getNominalIdentity() == null
					|| !left.getNominalIdentity().equals(right.getNominalIdentity())))
				return false;
			final a = left.getTypeArguments();
			final b = right.getTypeArguments();
			if (a.length != b.length)
				return false;
			for (index in 0...a.length)
				if (!compare(a[index], b[index], leftScopes, rightScopes, active))
					return false;
			return true;
		}
		return !left.isUnknown()
			&& !right.isUnknown()
			&& !left.isUnresolved()
			&& !right.isUnresolved()
			&& left.semanticKeyInScopes(leftScopes) == right.semanticKeyInScopes(rightScopes);
	}
}
