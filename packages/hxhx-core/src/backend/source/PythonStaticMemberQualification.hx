package backend.source;

/**
	Keep Haxe static members attached to their declaring class in Python.

	Python methods do not implicitly search the surrounding class for bare names.
	Use the exact field and call declarations selected by typing to request owner
	qualification before source projection. Local reads and macro quotations keep
	their original meaning; no name-based scope reconstruction is needed.
**/
private function expression(value:TypedExpr):TypedExpr {
	if (value.getTag() == MacroExpr || value.getTag() == MacroType)
		return value;
	final children = [for (child in value.getExpressions()) expression(child)];
	final rebuilt = value.withExpressions(children);
	final field = rebuilt.getFieldInfo();
	if (rebuilt.getTag() == NameRead && field != null && field.getIsStatic())
		return TypedExpr.nameRead(rebuilt.getTexts()[0], rebuilt.getType(), rebuilt.getPosition(), field, true);
	final declaration = rebuilt.getDeclaration();
	if (rebuilt.getTag() == Call
		&& declaration != null
		&& declaration.getIsStatic()
		&& !declaration.getIsEnumConstructor()
		&& rebuilt.getExtensionProvider() == null
		&& children.length > 0
		&& children[0].getTag() == NameRead)
		return TypedExpr.call(children[0], children.slice(1), declaration, rebuilt.getType(), rebuilt.getPosition(), true);
	return rebuilt;
}

private function statement(value:TypedStmt):TypedStmt {
	return value.withChildren([for (child in value.getExpressions()) expression(child)], [for (child in value.getStatements()) statement(child)]);
}

/** Produce a Python-only typed view while preserving the caller's program and declarations. */
function qualify(program:MacroExpandedProgram):MacroExpandedProgram {
	final modules = [
		for (module in program.getTypedModules()) {
			final classes = [
				for (cls in module.getTypedClasses()) {
					final functions = [
						for (fn in cls.getFunctions()) {
							final body = fn.getBody();
							fn.withBody(new TypedFunctionBody([for (child in body.getStatements()) statement(child)], body.getSourceFingerprint()));
						}
					];
					final initializers = [
						for (initializer in cls.getFieldInitializers())
							new TypedFieldInitializer(initializer.getField(), expression(initializer.getExpression()))
					];
					new TypedClass(cls.getSourceDeclaration(), cls.getSemanticInfo(), functions, initializers, cls.getResolvedExtends(),
						cls.getResolvedImplements());
				}
			];
			module.withTypedClasses(classes);
		}
	];
	return new MacroExpandedProgram(modules, program.macroMode, program.getGeneratedOcamlModules());
}
