import haxe.ds.StringMap;

/**
	A selected abstract conversion is an executable method call.
	Declared header conversions precede methods; source output methods precede
	destination input methods. Output calls retain the source as their receiver.
	Selection follows declaration order, as upstream does. Each attempted method
	gets an inference fork; rejected input, result, or bounds cannot change the
	caller's variables. The retained plan contains only complete semantic types.
 */
class TyAbstractMethodConversion {
	final declaration:TyDeclarationInfo;
	final actual:TyType;
	final callable:TyType;

	function new(declaration:TyDeclarationInfo, actual:TyType, callable:TyType) {
		this.declaration = declaration;
		this.actual = actual;
		this.callable = callable;
	}

	public function getDeclaration():TyDeclarationInfo
		return declaration;

	public function getInputType():TyType
		return declaration.getIsStatic() ? callable.getFunctionArguments()[0] : actual;

	public function getResultType():TyType
		return callable.getFunctionReturn();

	/** Preserve the exact source operand once, and make the selected method visible to every backend. */
	public function apply(expression:TypedExpr):TypedExpr {
		if (expression.getType().getSemanticKey() != actual.getSemanticKey())
			throw "abstract method conversion received a different source type";
		final position = expression.getPosition();
		if (!declaration.getIsStatic()) {
			final receiver = TypedExpr.instanceMethodRead(expression, declaration.getSignature().getName(), declaration, callable, position);
			return TypedExpr.call(receiver, [], declaration, getResultType(), position);
		}
		final callee = TypedExpr.staticMethodRead(declaration.getSignature().getName(), declaration, callable, position, true);
		return TypedExpr.call(callee, [expression], declaration, getResultType(), position, true);
	}

	/** Select an already concrete conversion without borrowing any caller inference variables. */
	public static function select(index:TyperIndex, expected:TyType, actual:TyType):Null<TyAbstractMethodConversion> {
		// A nullable destination admits the converted value or literal null.
		// Null already satisfies that destination and must not invoke a Dynamic-input method.
		if (expected != null && expected.isNullable())
			return actual == null || actual.isNullLiteral() ? null : select(index, expected.unwrapNull(), actual);
		if (!complete(expected) || !complete(actual) || expected.getSemanticKey() == actual.getSemanticKey())
			return null;
		// A declared header conversion precedes executable conversion methods.
		if (TyImplicitConversionPlan.select(index, expected, actual) != null)
			return null;
		return constrain(index, new TyInferenceSolver("abstract-input-method"), TyInferenceSolver.fromType(actual), expected);
	}

	/** Resolve output methods or infer missing input arguments, committing only the first proven candidate in conversion priority order. */
	public static function constrain(index:TyperIndex, solver:TyInferenceSolver, actual:TyInferenceTerm, expected:TyType):Null<TyAbstractMethodConversion> {
		if (!complete(expected))
			return null;
		final source = solver.preview(actual);
		if (complete(source) && TyImplicitConversionPlan.select(index, expected, source) != null)
			return null;
		final output = choose(index, solver, actual, expected, true);
		return output == null ? choose(index, solver, actual, expected, false) : output;
	}

	/** Each direction binds the abstract that owns the method, using isolated candidate variables. */
	static function choose(index:TyperIndex, solver:TyInferenceSolver, actual:TyInferenceTerm, expected:TyType, output:Bool):Null<TyAbstractMethodConversion> {
		final sourceType = solver.preview(actual);
		final ownerType = output ? sourceType : expected;
		if (output && !complete(sourceType))
			return null;
		final identity = ownerType.getNominalIdentity();
		final owner = identity == null || index == null ? null : index.getAbstractByFullName(identity.getCanonicalName());
		if (owner == null || owner.getTypeParameterIds().length != ownerType.getTypeArguments().length)
			return null;
		if (complete(sourceType)) {
			if (TyImplicitConversionPlan.select(index, expected, sourceType) != null)
				return null;
		} else if (owner.getImplicitFromTypes().length > 0) {
			// Header-result inference owns this unresolved choice. A method cannot
			// solve the source first and thereby displace a higher-priority header.
			return null;
		}
		final ownerBindings = TyTypeSubstitution.bind(owner.getTypeParameterIds(), ownerType.getTypeArguments(), identity.getCanonicalName());
		for (declaration in owner.getDeclarations()) {
			final signature = TyCallableSignature.fromDeclaration(declaration).getFunctionType();
			final parameters = signature.getFunctionParameters();
			if (output ? declaration.getIsStatic()
				|| !hasConversion(declaration.getMetadata(), "to")
				|| parameters.length != 0 : !declaration.getIsStatic()
				|| !hasConversion(declaration.getMetadata(), "from")
				|| parameters.length != 1
				|| parameters[0].isOptional
				|| parameters[0].isRest)
				continue;
			final candidate = solver.fork();
			final variables = new StringMap<TyInferenceTerm>();
			final bounds = declaration.getResolvedTypeParameterConstraints();
			final needed = TyTypeSubstitution.parameterIdentities(signature).map(parameter -> parameter.getCanonicalKey());
			for (key => constraints in bounds)
				for (bound in constraints) {
					needed.push(key);
					for (parameter in TyTypeSubstitution.parameterIdentities(bound))
						needed.push(parameter.getCanonicalKey());
				}
			// Unused, unconstrained method parameters supply no value contract and
			// must not leave phantom unsolved variables in the caller's solver.
			for (parameter in declaration.getTypeParameterIds())
				if (needed.indexOf(parameter.getCanonicalKey()) >= 0)
					variables.set(parameter.getCanonicalKey(), candidate.fresh());
			function applied(type:TyType):TyInferenceTerm
				return term(TyTypeSubstitution.apply(type, ownerBindings), variables);
			if (!candidate.constrain(applied(signature.getFunctionReturn()), TyInferenceSolver.fromType(expected)))
				continue;
			final input = output ? TyInferenceSolver.fromType(sourceType) : applied(parameters[0].type);
			final projected = TyInferenceNominalContext.view(index, actual, candidate.preview(input));
			if (projected == null || !candidate.constrain(input, projected)) {
				// An explicitly declared Dynamic input accepts a known source value;
				// this provides no evidence for an unknown source type argument.
				if (!candidate.preview(input).isDynamic() || !complete(candidate.preview(actual)))
					continue;
			}
			if (!complete(candidate.preview(actual)) || !complete(candidate.preview(input)))
				continue;
			var valid = true;
			for (parameter in declaration.getTypeParameterIds()) {
				final key = parameter.getCanonicalKey();
				if (!variables.exists(key))
					continue;
				final supplied = candidate.preview(variables.get(key));
				if (!complete(supplied)) {
					valid = false;
					break;
				}
				if (bounds.exists(key))
					for (bound in bounds.get(key)) {
						if (!acceptsBound(index, candidate.preview(applied(bound)), supplied)) {
							valid = false;
							break;
						}
					}
				if (!valid)
					break;
			}
			if (!valid)
				continue;
			final callable = candidate.requireSolved(applied(signature));
			final plan = new TyAbstractMethodConversion(declaration, candidate.requireSolved(actual), callable);
			solver.commit(candidate);
			return plan;
		}
		return null;
	}

	/** Bounds require semantic proof; equal display names and an abstract's backing storage are insufficient. */
	@:allow(TyMultiTypeSelection)
	static function acceptsBound(index:TyperIndex, expected:TyType, actual:TyType):Bool {
		if (!complete(expected) || !complete(actual))
			return false;
		if (expected.isAnonymous() && expected.getAnonymousFields().length == 0)
			return TyEmptyObjectConstraint.accepts(actual, index);
		if (TyAssignmentCompatibility.classify(expected, actual, Unchecked) == Compatible)
			return true;
		final identity = expected.getNominalIdentity();
		final ancestor = identity == null ? null : TyNominalAncestor.view(index, actual, identity);
		return ancestor != null && ancestor.getSemanticKey() == expected.getSemanticKey();
	}

	@:allow(TyMultiTypeSelection)
	static function hasConversion(metadata:Array<String>, direction:String):Bool {
		for (entry in metadata) {
			var name = StringTools.trim(entry);
			while (StringTools.startsWith(name, "@") || StringTools.startsWith(name, ":"))
				name = name.substr(1);
			if (name == direction)
				return true;
		}
		return false;
	}

	/** Substitute exact method variables through all type constructors without parsing rendered types. */
	@:allow(TyMultiTypeSelection)
	static function term(type:TyType, variables:StringMap<TyInferenceTerm>):TyInferenceTerm {
		final parameter = type.getTypeParameterIdentity();
		if (parameter != null && variables.exists(parameter.getCanonicalKey()))
			return variables.get(parameter.getCanonicalKey());
		if (type.isNullable())
			return Nullable(term(type.unwrapNull(), variables));
		if (type.isFunction())
			return Function(type.getFunctionArguments().map(child -> term(child, variables)), term(type.getFunctionReturn(), variables), type);
		if (type.isAnonymous())
			return Structure(type.getAnonymousFieldTypes().map(child -> term(child, variables)), type);
		final identity = type.getNominalIdentity();
		return identity == null ? Known(type) : Nominal(identity, type.getTypeArguments().map(child -> term(child, variables)));
	}

	@:allow(TyMultiTypeSelection)
	static function complete(type:TyType):Bool {
		if (type == null || type.isUnknown() || type.isUnresolved())
			return false;
		if (type.isNullable() && !complete(type.unwrapNull()))
			return false;
		for (child in type.getTypeArguments().concat(type.getFunctionArguments()).concat(type.getAnonymousFieldTypes()))
			if (!complete(child))
				return false;
		return !type.isFunction() || complete(type.getFunctionReturn());
	}
}
