/**
	Check applied class arguments before typed code relies on their declared bounds.
	Substitute the complete application together so a bound such as K:U refers to
	the supplied U. Nested annotations use the same check as constructed values.
	Incomplete inference arguments remain pending until the caller replays them.
 */
function validate(type:TyType, index:TyperIndex, filePath:String, position:HxPos, accepts:(TyType, TyType) -> Bool):Void {
	if (type == null || index == null)
		return;
	if (type.isNullable()) {
		validate(type.getNullableInner(), index, filePath, position, accepts);
		return;
	}
	if (type.isFunction()) {
		for (argument in type.getFunctionArguments())
			validate(argument, index, filePath, position, accepts);
		validate(type.getFunctionReturn(), index, filePath, position, accepts);
	}
	if (type.isAnonymous())
		for (field in type.getAnonymousFieldTypes())
			validate(field, index, filePath, position, accepts);
	final arguments = type.getTypeArguments();
	for (argument in arguments)
		validate(argument, index, filePath, position, accepts);
	final identity = type.getNominalIdentity();
	final owner = identity == null ? null : index.getByFullName(identity.getCanonicalName());
	if (owner == null)
		return;
	final parameters = TyNominalApplication.parameterIds(owner);
	if (parameters.length != arguments.length)
		return;
	final substitutions = TyTypeSubstitution.bind(parameters, arguments, identity.getCanonicalName());
	for (ordinal in 0...parameters.length) {
		final supplied = arguments[ordinal];
		if (supplied.hasUnknownComponent())
			continue;
		for (declared in index.getParameterBounds(parameters[ordinal])) {
			final expected = TyTypeSubstitution.apply(declared, substitutions);
			if (!expected.hasUnknownComponent() && !accepts(expected, supplied))
				throw new TyperError(filePath, position,
					'Constraint check failure for '
					+ identity.getCanonicalName()
					+ '.'
					+ parameters[ordinal].getName()
						+ ': '
						+ supplied.getDisplay()
						+ ' should satisfy '
						+ expected.getDisplay());
		}
	}
}

/** Unused aliases and bounds are still source contracts; validate them after signatures are available. */
function validateDeclarations(parsed:ParsedModule, modulePath:String, index:TyperIndex, accepts:(TyType, TyType) -> Bool):Void {
	if (index == null)
		return;
	final source = parsed.getDecl();
	for (alias in HxModuleDecl.getTypedefs(source)) {
		final context:TyTypeDeclaration.TyTypeResolutionContext = {
			packagePath: HxModuleDecl.getPackagePath(source),
			modulePath: modulePath,
			directives: HxModuleDecl.getDirectives(source),
			filePath: parsed.getFilePath(),
			position: alias.getPos(),
			parameters: []
		};
		final declaration = index.resolveTypeDeclaration(alias.getName(), context);
		if (declaration == null)
			throw 'registered typedef declaration is missing';
		final applied = TyType.unresolved(declaration.getCanonicalName(), declaration.getParameterIds().map(TyType.typeParameter));
		validate(index.resolveTypeUse(applied, context).getType(), index, parsed.getFilePath(), alias.getPos(), accepts);
	}
	for (classSource in HxModuleDecl.getClasses(source)) {
		final owner = index.getForSourceClass(classSource);
		if (owner == null)
			continue;
		final parameters = TyNominalApplication.parameterIds(owner);
		for (method in owner.getDeclarations())
			for (parameter in method.getTypeParameterIds())
				parameters.push(parameter);
		for (parameter in parameters)
			for (bound in index.getParameterBounds(parameter))
				validate(bound, index, parsed.getFilePath(), HxPos.unknown(), accepts);
	}
}
