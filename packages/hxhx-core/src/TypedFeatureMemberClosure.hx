/**
	Follow exact function and field references before feature branch selection.
	The policy owner supplies entry declarations, including initialization and metadata
	roots. This pass follows retained declaration facts in both selection branches,
	but never macro quotations. It does not choose DCE roots. Referenced instance
	members retain implementations in retained descendant classes. Static method values
	retain shared declaration facts; callable member
	reads without those facts fail explicitly rather than silently losing features.
	Class-object references retain their resolved ancestors and interfaces, including
	class initialization, without making every instance method reachable.
	Only declarations owned by this exact typed program can enter the work queue.
**/
function discover(input:TypedFeatureRoots.TypedFeatureRootSet):TypedFeatureDiscovery {
	return new TypedFeatureDiscovery(retain(input));
}

/** Return exact reachable declarations before feature selection, for discovery and emission policy. */
function retain(input:TypedFeatureRoots.TypedFeatureRootSet):TypedFeatureRoots.TypedFeatureRootSet {
	final program = input.program;
	program.assertTypedBodyRevisionsCurrent();
	final declarations = new haxe.ds.ObjectMap<TyDeclarationInfo, TypedFunction>();
	final functionOwners = new haxe.ds.ObjectMap<TypedFunction, TypedClass>();
	final fieldOwners = new haxe.ds.ObjectMap<TyFieldInfo, TypedClass>();
	final initializers = new haxe.ds.ObjectMap<TyFieldInfo, TypedFieldInitializer>();
	final ownedClasses = new haxe.ds.ObjectMap<TypedClass, Bool>();
	final nominalClasses = new haxe.ds.StringMap<TypedClass>();
	for (module in program.getTypedModules()) {
		for (owner in module.getTypedClasses()) {
			ownedClasses.set(owner, true);
			final info = owner.getSemanticInfo();
			if (info == null || nominalClasses.exists(info.getIdentity().getCanonicalName()))
				throw "feature member closure requires unique semantic class providers";
			nominalClasses.set(info.getIdentity().getCanonicalName(), owner);
			for (fn in owner.getFunctions()) {
				final declaration = fn.getDeclaration();
				if (declaration == null || declarations.exists(declaration))
					throw "feature member closure requires unique semantic function declarations";
				declarations.set(declaration, fn);
				functionOwners.set(fn, owner);
			}
			if (owner.getSemanticInfo() != null)
				for (field in owner.getSemanticInfo().getFieldInfos())
					fieldOwners.set(field, owner);
			for (initializer in owner.getFieldInitializers())
				initializers.set(initializer.getField(), initializer);
		}
	}
	final classes = new Array<TypedClass>();
	final functions = new Array<TypedFunction>();
	final fields = new Array<TyFieldInfo>();
	final seenClasses = new haxe.ds.ObjectMap<TypedClass, Bool>();
	final seenFunctions = new haxe.ds.ObjectMap<TypedFunction, Bool>();
	final seenFields = new haxe.ds.ObjectMap<TyFieldInfo, Bool>();
	function retainClass(owner:TypedClass):Void {
		if (!ownedClasses.exists(owner))
			throw "feature member closure requires an owned class";
		if (!seenClasses.exists(owner)) {
			seenClasses.set(owner, true);
			classes.push(owner);
		}
	}
	function retainFunction(fn:TypedFunction):Void {
		final owner = functionOwners.get(fn);
		if (owner == null)
			throw "feature member closure requires an owned function";
		if (!seenFunctions.exists(fn)) {
			seenFunctions.set(fn, true);
			functions.push(fn);
			retainClass(owner);
		}
	}
	function retainNominal(identity:TyNominalTypeId):Void {
		final owner = nominalClasses.get(identity.getCanonicalName());
		if (owner == null)
			throw "feature class reference has no exact program provider: " + identity.getCanonicalName();
		retainClass(owner);
	}
	function retainField(field:TyFieldInfo):Void {
		final owner = fieldOwners.get(field);
		if (owner == null)
			throw "feature member closure requires an owned field";
		if (!seenFields.exists(field)) {
			seenFields.set(field, true);
			fields.push(field);
			retainClass(owner);
		}
	}
	function expression(node:TypedExpr, selectedCallee:Bool = false):Void {
		if (node.getTag() == MacroExpr || node.getTag() == MacroType)
			return;
		final target = node.getRuntimeTypeTarget();
		final identity = target == null ? null : target.getDeclarationIdentity();
		if (identity != null)
			retainNominal(identity);
		final declaration = node.getDeclaration();
		if (declaration != null) {
			final fn = declarations.get(declaration);
			if (fn == null)
				throw "feature member reference has no owned function declaration";
			retainFunction(fn);
		}
		final field = node.getFieldInfo();
		if (!selectedCallee && declaration == null && field == null && node.getType().isFunction())
			switch (node.getTag()) {
				case NameRead | FieldRead | NullSafeFieldRead:
					throw "feature member closure requires an exact method-value declaration";
				case _:
			}
		if (field != null)
			retainField(field);
		final children = node.getExpressions();
		for (index in 0...children.length) {
			// A direct call already owns its selected declaration. Parentheses may
			// wrap that callee without turning it into a separate method-value read.
			final bound = index == 0
				&& ((node.getTag() == Call && declaration != null) || (node.getTag() == Parenthesized && selectedCallee));
			expression(children[index], bound);
		}
	}
	function statement(node:TypedStmt):Void {
		for (child in node.getExpressions())
			expression(child);
		for (child in node.getStatements())
			statement(child);
	}
	for (owner in input.classes)
		retainClass(owner);
	for (fn in input.functions)
		retainFunction(fn);
	for (field in input.fields)
		retainField(field);
	var functionCursor = 0;
	var fieldCursor = 0;
	var classCursor = 0;
	while (functionCursor < functions.length || fieldCursor < fields.length || classCursor < classes.length) {
		while (classCursor < classes.length) {
			final owner = classes[classCursor++];
			final inherited = owner.getResolvedImplements().concat(owner.getResolvedInterfaceExtends());
			if (owner.getResolvedExtends() != null)
				inherited.push(owner.getResolvedExtends());
			for (type in inherited) {
				final identity = type.getNominalIdentity();
				if (identity == null)
					throw "feature inheritance requires an exact nominal provider";
				retainNominal(identity);
			}
			for (fn in owner.getFunctions())
				if (fn.getDeclaration().getIsStatic() && fn.getDeclaration().getSignature().getName() == "__init__")
					retainFunction(fn);
		}
		while (functionCursor < functions.length)
			for (body in functions[functionCursor++].getBody().getStatements())
				statement(body);
		while (fieldCursor < fields.length) {
			final initializer = initializers.get(fields[fieldCursor++]);
			if (initializer != null)
				expression(initializer.getExpression());
		}
		// New methods can expose further classes and calls. Revisit dispatch after
		// draining ordinary references, until all declaration queues stop growing.
		final references = new haxe.ds.StringMap<Array<TypedFunction>>();
		for (fn in functions) {
			final declaration = fn.getDeclaration();
			final name = declaration.getSignature().getName();
			if (declaration.getIsStatic() || name == "new")
				continue;
			var group = references.get(name);
			if (group == null) {
				group = [];
				references.set(name, group);
			}
			group.push(fn);
		}
		for (owner in classes.copy())
			for (candidate in owner.getFunctions()) {
				if (seenFunctions.exists(candidate) || candidate.getDeclaration().getIsStatic())
					continue;
				final group = references.get(candidate.getDeclaration().getSignature().getName());
				if (group == null)
					continue;
				for (reference in group)
					if (TypedFeatureDispatch.implementsReference(candidate, reference, nominalClasses)) {
						retainFunction(candidate);
						break;
					}
			}
	}
	return {
		program: program,
		classes: classes,
		functions: functions,
		fields: fields
	};
}
