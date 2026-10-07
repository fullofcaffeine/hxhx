import TyTypeDeclaration.TyTypeResolutionContext;

/**
	Normalize named type uses while retaining the declarations traversed.

	Expansion runs in the alias's defining module. Each call owns its expansion
	path and evidence; no result survives into another compiler request. Generic
	targets resolve with declaration-owned parameters before exact substitution.
	Structural members retain access rules and method-local binders. Recursive
	and constrained forms remain explicit failures until their model exists.
 */
class TyTypeUseResolver {
	final catalog:TyTypeDeclarationCatalog;

	public function new(catalog:TyTypeDeclarationCatalog) {
		this.catalog = catalog;
	}

	public function resolve(type:TyType, context:TyTypeResolutionContext):TyResolvedTypeUse {
		final declarations = new Array<TyTypeDeclaration>();
		final normalized = normalize(type, context, [], declarations);
		return new TyResolvedTypeUse(normalized, declarations, context.position);
	}

	/** Resolve an already parsed bound without reconstructing type-hint text. */
	public function resolveParsed(syntax:HxTypeSyntax, context:TyTypeResolutionContext, scopeIdentity:String):TyResolvedTypeUse {
		final declarations = new Array<TyTypeDeclaration>();
		return new TyResolvedTypeUse(resolveSyntax(syntax, context, [], declarations, scopeIdentity), declarations, syntax.getPos());
	}

	/**
		Check an unused alias with its parameters still open, rather than applying
		it with zero arguments. Defaults resolve outside that parameter scope, as
		Haxe 4.3.7 requires, and are checked even when no use omits an argument.
	 */
	public function validateDeclaration(declaration:TyTypeDeclaration):Void {
		switch (declaration.getKind()) {
			case Nominal(_):
			case Alias(source):
				final context = declaration.getContext();
				resolve(TyType.unresolved(declaration.getCanonicalName(), [for (parameter in declaration.getParameterIds()) TyType.typeParameter(parameter)]),
					context);
				for (parameter in source.getParameters())
					if (parameter.defaultType != null)
						resolveSyntax(parameter.defaultType, context, [declaration.getCanonicalName()], [],
							declaration.getCanonicalName() + "/default:" + parameter.name);
		}
	}

	function remember(declaration:TyTypeDeclaration, declarations:Array<TyTypeDeclaration>):Void {
		for (existing in declarations)
			if (existing.getCanonicalName() == declaration.getCanonicalName())
				return;
		declarations.push(declaration);
	}

	function normalize(type:TyType, context:TyTypeResolutionContext, expansion:Array<String>, declarations:Array<TyTypeDeclaration>):TyType {
		if (type.isNullable())
			return TyType.nullable(normalize(type.getNullableInner(), context, expansion, declarations));
		if (type.isFunction())
			return type.withFunctionTypes([
				for (arg in type.getFunctionArguments())
					normalize(arg, context, expansion, declarations)
			], normalize(type.getFunctionReturn(), context, expansion, declarations));
		if (type.isAnonymous())
			return type.withAnonymousTypes([
				for (field in type.getAnonymousFieldTypes())
					normalize(field, context, expansion, declarations)
			]);
		if (!type.isUnresolved())
			return type;
		final args = [
			for (arg in type.getTypeArguments())
				normalize(arg, context, expansion, declarations)
		];
		return resolvePath(type.getUnresolvedPath(), args, context, expansion, declarations, false, type.getDisplay());
	}

	function resolvePath(path:String, args:Array<TyType>, context:TyTypeResolutionContext, expansion:Array<String>, declarations:Array<TyTypeDeclaration>,
			required:Bool, ?display:String):TyType {
		if (args.length == 0)
			for (offset in 0...context.parameters.length) {
				final parameter = context.parameters[context.parameters.length - 1 - offset];
				if (parameter.getName() == path)
					return TyType.typeParameter(parameter);
			}
		final declaration = catalog.resolve(path, context);
		if (declaration == null) {
			if (required)
				throw new TyperError(context.filePath, context.position, "Type not found : " + path);
			return TyType.unresolved(path, args, display);
		}
		remember(declaration, declarations);
		return switch (declaration.getKind()) {
			case Nominal(identity): TyType.nominal(identity, args, display);
			case Alias(source):
				final defining = declaration.getContext();
				final key = declaration.getCanonicalName();
				if (expansion.indexOf(key) >= 0)
					throw new TyperError(defining.filePath, source.getPos(), "Recursive typedef is not allowed: " + expansion.concat([key]).join(" -> "));
				final parameters = source.getParameters();
				final ids = declaration.getParameterIds();
				final path = expansion.concat([key]);
				if (args.length > parameters.length)
					throw new TyperError(context.filePath, context.position, "Too many type parameters for " + declaration.getShortName());
				final applied = args.copy();
				for (index in args.length...parameters.length) {
					final defaultType = parameters[index].defaultType;
					if (defaultType == null)
						throw new TyperError(context.filePath, context.position, "Not enough type parameters for " + declaration.getShortName());
					applied.push(resolveSyntax(defaultType, defining, path, declarations, key + "/default:" + parameters[index].name));
				}
				for (parameter in parameters)
					if (parameter.constraints.length != 0)
						throw new TyperError(defining.filePath, parameter.pos, "Constrained typedef resolution is not implemented: " + key);
				final bound:TyTypeResolutionContext = {
					packagePath: defining.packagePath,
					modulePath: defining.modulePath,
					directives: defining.directives,
					filePath: defining.filePath,
					position: source.getPos(),
					parameters: ids
				};
				final template = resolveSyntax(source.getTarget(), bound, path, declarations, key);
				TyTypeSubstitution.apply(template, TyTypeSubstitution.bind(ids, applied, key));
		};
	}

	/** Interpret parsed target nodes directly; type-hint strings are never reconstructed. */
	function resolveSyntax(syntax:HxTypeSyntax, context:TyTypeResolutionContext, expansion:Array<String>, declarations:Array<TyTypeDeclaration>,
			scope:String):TyType {
		final positioned:TyTypeResolutionContext = {
			packagePath: context.packagePath,
			modulePath: context.modulePath,
			directives: context.directives,
			filePath: context.filePath,
			position: syntax.getPos(),
			parameters: context.parameters
		};
		return switch (syntax.getKind()) {
			case GroupedType(inner): resolveSyntax(inner, positioned, expansion, declarations, scope);
			case IntersectionType(members):
				// Structural intersections share extension rules: preserve every field
				// contract and reject conflicting or non-structural bases.
				resolveStructure([], members, positioned, expansion, declarations, scope);
			case TypePath(segments, arguments):
				final path = segments.join(".");
				final args = [
					for (index in 0...arguments.length)
						resolveSyntax(arguments[index], positioned, expansion, declarations, scope + "/type-arg:" + index)
				];
				if (path == "Null" && args.length == 1) {
					TyType.nullable(args[0]);
				} else if (args.length == 0
					&& (path == "Int" || path == "Float" || path == "Bool" || path == "String" || path == "Void" || path == "Dynamic")) {
					TyType.fromHintText(path);
				} else {
					resolvePath(path, args, positioned, expansion, declarations, true);
				}
			case FunctionType(arguments, result):
				TyType.functionSignature([
					for (index in 0...arguments.length)
						{
							name: arguments[index].name,
							type: resolveSyntax(arguments[index].type, positioned, expansion, declarations, scope + "/arg:" + index),
							isOptional: arguments[index].isOptional,
							isRest: arguments[index].isRest,
							metadata: arguments[index].metadata
						}
				], resolveSyntax(result, positioned, expansion, declarations, scope + "/result"));
			case ArrowType(_, _):
				resolveArrow(syntax, positioned, expansion, declarations, scope);
			case AnonymousType(fields, extensions):
				resolveStructure(fields, extensions, positioned, expansion, declarations, scope);
		};
	}

	/** Flatten only ungrouped legacy arrows; parentheses preserve a returned function. */
	function resolveArrow(syntax:HxTypeSyntax, context:TyTypeResolutionContext, expansion:Array<String>, declarations:Array<TyTypeDeclaration>,
			scope:String):TyType {
		final arguments = new Array<TyType>();
		var current = syntax;
		while (true) {
			switch (current.getKind()) {
				case ArrowType(argument, result):
					arguments.push(resolveSyntax(argument, context, expansion, declarations, scope + "/arg:" + arguments.length));
					current = result;
				case _:
					if (arguments.length == 1 && arguments[0].isVoid())
						arguments.resize(0);
					return TyType.functionType(arguments, resolveSyntax(current, context, expansion, declarations, scope + "/result"));
			}
		}
	}

	/**
		Merge structural bases and authored fields without object-literal overwrite rules.
		A repeated inherited field must have the same resolved contract. Method binders
		use a declaration-relative syntax path, not a source offset or allocation identity.
	 */
	function resolveStructure(fields:Array<HxTypeSyntax.HxTypeSyntaxField>, extensions:Array<HxTypeSyntax>, context:TyTypeResolutionContext,
			expansion:Array<String>, declarations:Array<TyTypeDeclaration>, scope:String):TyType {
		final merged = new haxe.ds.StringMap<TyAnonymousField>();
		function add(field:TyAnonymousField):Void {
			final previous = merged.get(field.name);
			if (previous != null && TyAnonymousField.semanticKey(previous) != TyAnonymousField.semanticKey(field))
				throw new TyperError(context.filePath, field.position, "Cannot redefine field " + field.name + " with different type");
			merged.set(field.name, field);
		}
		for (index in 0...extensions.length) {
			final base = resolveSyntax(extensions[index], context, expansion, declarations, scope + "/base:" + index);
			if (!base.isAnonymous())
				throw new TyperError(context.filePath, extensions[index].getPos(), "Structural extension requires an anonymous type");
			for (field in base.getAnonymousFields())
				add(field);
		}
		final authored = new haxe.ds.StringMap<Bool>();
		for (field in fields) {
			if (authored.exists(field.name))
				throw new TyperError(context.filePath, field.pos, "Duplicate field declaration : " + field.name);
			authored.set(field.name, true);
			final fieldScope = scope + "/field:" + field.name;
			final resolved = switch (field.kind) {
				case Variable(type, finalField, get, set):
					{
						type: resolveSyntax(type, context, expansion, declarations, fieldScope),
						kind: TyAnonymousField.TyAnonymousFieldKind.Variable(finalField, get, set)
					};
				case Method(parameters, arguments, result):
					final ids = new Array<TyTypeParameterId>();
					final names = new haxe.ds.StringMap<Bool>();
					for (parameter in parameters) {
						if (names.exists(parameter.name))
							throw new TyperError(context.filePath, parameter.pos, "Duplicate type parameter name: " + parameter.name);
						names.set(parameter.name, true);
						if (parameter.constraints.length != 0 || parameter.defaultType != null)
							throw new TyperError(context.filePath, parameter.pos, "Constrained or defaulted structural method parameters are not implemented");
						ids.push(new TyTypeParameterId("structural-method:" + fieldScope, ids.length, parameter.name));
					}
					final methodContext:TyTypeResolutionContext = {
						packagePath: context.packagePath,
						modulePath: context.modulePath,
						directives: context.directives,
						filePath: context.filePath,
						position: field.pos,
						parameters: context.parameters.concat(ids)
					};
					final signature = new HxTypeSyntax(FunctionType(arguments, result), field.pos, field.endPos);
					{
						type: resolveSyntax(signature, methodContext, expansion, declarations, fieldScope),
						kind: TyAnonymousField.TyAnonymousFieldKind.Method(ids)
					};
			};
			add({
				name: field.name,
				type: resolved.type,
				kind: resolved.kind,
				isOptional: field.isOptional,
				visibility: field.visibility,
				metadata: field.metadata,
				position: field.pos
			});
		}
		return TyType.declaredAnonymous([for (field in merged) field]);
	}
}
