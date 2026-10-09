import TyTypeDeclaration.TyTypeResolutionContext;

/** Duplicate structural members are compared after their referenced graph is sealed. */
private typedef DeferredAliasFieldComparison = {
	final previous:TyAnonymousField;
	final current:TyAnonymousField;
	final filePath:String;
};

/**
	Build one finite alias graph, then publish a transparent type view.
	Named uses allocate references. Bodies and defaults resolve once in their
	defining scopes, without recursively expanding arguments. Structural bases
	demand a body during construction; ordinary recursive fields do not.
	Each public resolver call owns a fresh instance, so a failed or incomplete
	graph cannot contaminate a later type use or compiler request.
 */
class TyTypeUseResolution {
	final catalog:TyTypeDeclarationCatalog;
	final declarations = new Array<TyTypeDeclaration>();
	final definitions = new haxe.ds.StringMap<TyAliasDefinition>();
	final pending = new Array<TyAliasDefinition>();
	final constructing = new Array<TyAliasDefinition>();
	final comparisons = new Array<DeferredAliasFieldComparison>();

	public function new(catalog:TyTypeDeclarationCatalog) {
		this.catalog = catalog;
	}

	public function resolve(type:TyType, context:TyTypeResolutionContext):TyResolvedTypeUse {
		final normalized = normalize(type, context);
		return new TyResolvedTypeUse(finish(normalized), declarations, context.position);
	}

	/** Resolve an already parsed bound without reconstructing type-hint text. */
	public function resolveParsed(syntax:HxTypeSyntax, context:TyTypeResolutionContext, scopeIdentity:String):TyResolvedTypeUse {
		return new TyResolvedTypeUse(finish(resolveSyntax(syntax, context, scopeIdentity)), declarations, syntax.getPos());
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
		}
	}

	/** Allocate default slots too, so unused defaults still receive name and scope checks. */
	function definitionFor(declaration:TyTypeDeclaration, ?defaultIndex:Int = -1):TyAliasDefinition {
		final key = declaration.getCanonicalName() + (defaultIndex < 0 ? "" : "/default:" + defaultIndex);
		final existing = definitions.get(key);
		if (existing != null)
			return existing;
		final definition = new TyAliasDefinition(declaration, defaultIndex);
		definitions.set(key, definition);
		pending.push(definition);
		if (defaultIndex < 0)
			switch (declaration.getKind()) {
				case Alias(source):
					final parameters = source.getParameters();
					for (index in 0...parameters.length)
						if (parameters[index].defaultType != null)
							definitionFor(declaration, index);
				case Nominal(_):
			}
		return definition;
	}

	/** Structural base lookup can demand a body before the remaining queue is drained. */
	function buildDefinition(definition:TyAliasDefinition):TyType {
		final existing = definition.getBoundBody();
		if (existing != null)
			return existing;
		final declaration = definition.getDeclaration();
		final context = declaration.getContext();
		final source = definition.getSourceSyntax();
		if (constructing.indexOf(definition) >= 0)
			throw new TyperError(context.filePath, source.getPos(),
				"Recursive typedef is not allowed in a structural extension: " + definition.getCanonicalName());
		constructing.push(definition);
		final bound:TyTypeResolutionContext = {
			packagePath: context.packagePath,
			modulePath: context.modulePath,
			directives: context.directives,
			filePath: context.filePath,
			position: source.getPos(),
			parameters: definition.getParameterIds()
		};
		final body = resolveSyntax(source, bound, definition.getCanonicalName());
		definition.bind(body);
		constructing.pop();
		return body;
	}

	/** Seal before comparison or publication; validate every demanded definition's result path. */
	function finish(type:TyType):TyType {
		var index = 0;
		while (index < pending.length)
			buildDefinition(pending[index++]);
		TyAliasDefinition.seal(pending);
		for (definition in pending)
			TyAliasExpansion.reveal(TyType.aliasApplication(definition, definition.getParameterIds().map(TyType.typeParameter)));
		for (comparison in comparisons) {
			final previous = TyAnonymousField.withType(comparison.previous, materialize(comparison.previous.type, []));
			final current = TyAnonymousField.withType(comparison.current, materialize(comparison.current.type, []));
			if (TyAnonymousField.semanticKey(previous) != TyAnonymousField.semanticKey(current))
				throw new TyperError(comparison.filePath, current.position, "Cannot redefine field " + current.name + " with different type");
		}
		return materialize(type, []);
	}

	/** Expand ordinary aliases transparently, retaining exact references only at recursive edges. */
	function materialize(type:TyType, path:Array<TyAliasDefinition>):TyType {
		final definition = type.getAliasDefinition();
		if (definition != null) {
			if (path.indexOf(definition) >= 0)
				return TyType.aliasApplication(definition, [for (argument in type.getTypeArguments()) materialize(argument, path)]);
			return materialize(TyAliasExpansion.reveal(type), path.concat([definition]));
		}
		if (type.isNullable())
			return TyType.nullable(materialize(type.unwrapNull(), path));
		if (type.isFunction())
			return type.withFunctionTypes([for (argument in type.getFunctionArguments()) materialize(argument, path)],
				materialize(type.getFunctionReturn(), path));
		if (type.isAnonymous())
			return type.withAnonymousTypes([for (field in type.getAnonymousFieldTypes()) materialize(field, path)]);
		final arguments = type.getTypeArguments();
		if (arguments.length == 0)
			return type;
		final actual = [for (argument in arguments) materialize(argument, path)];
		if (type.isAbstractMeta())
			return TyType.abstractMeta(actual[0]);
		if (type.getNominalIdentity() != null)
			return TyType.nominal(type.getNominalIdentity(), actual);
		if (type.isUnresolved())
			return TyType.unresolved(type.getUnresolvedPath(), actual);
		throw "alias resolution cannot rebuild " + type.getSemanticKey();
	}

	function remember(declaration:TyTypeDeclaration):Void {
		for (existing in declarations)
			if (existing.getCanonicalName() == declaration.getCanonicalName())
				return;
		declarations.push(declaration);
	}

	function normalize(type:TyType, context:TyTypeResolutionContext):TyType {
		if (type.isNullable())
			return TyType.nullable(normalize(type.getNullableInner(), context));
		if (type.isFunction())
			return type.withFunctionTypes([
				for (arg in type.getFunctionArguments())
					normalize(arg, context)
			], normalize(type.getFunctionReturn(), context));
		if (type.isAnonymous())
			return type.withAnonymousTypes([
				for (field in type.getAnonymousFieldTypes())
					normalize(field, context)
			]);
		if (!type.isUnresolved())
			return type;
		final args = [
			for (arg in type.getTypeArguments())
				normalize(arg, context)
		];
		return resolvePath(type.getUnresolvedPath(), args, context, false, type.getDisplay());
	}

	function resolvePath(path:String, args:Array<TyType>, context:TyTypeResolutionContext, required:Bool, ?display:String):TyType {
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
		remember(declaration);
		return switch (declaration.getKind()) {
			case Nominal(identity): TyType.nominal(identity, args, display);
			case Alias(source):
				final defining = declaration.getContext();
				final key = declaration.getCanonicalName();
				final parameters = source.getParameters();
				if (args.length > parameters.length)
					throw new TyperError(context.filePath, context.position, "Too many type parameters for " + declaration.getShortName());
				final applied = args.copy();
				for (index in args.length...parameters.length) {
					final defaultType = parameters[index].defaultType;
					if (defaultType == null)
						throw new TyperError(context.filePath, context.position, "Not enough type parameters for " + declaration.getShortName());
					applied.push(TyType.aliasApplication(definitionFor(declaration, index), []));
				}
				for (parameter in parameters)
					if (parameter.constraints.length != 0)
						throw new TyperError(defining.filePath, parameter.pos, "Constrained typedef resolution is not implemented: " + key);
				TyType.aliasApplication(definitionFor(declaration), applied);
		};
	}

	/** Interpret parsed target nodes directly; type-hint strings are never reconstructed. */
	function resolveSyntax(syntax:HxTypeSyntax, context:TyTypeResolutionContext, scope:String):TyType {
		final positioned:TyTypeResolutionContext = {
			packagePath: context.packagePath,
			modulePath: context.modulePath,
			directives: context.directives,
			filePath: context.filePath,
			position: syntax.getPos(),
			parameters: context.parameters
		};
		return switch (syntax.getKind()) {
			case GroupedType(inner): resolveSyntax(inner, positioned, scope);
			case IntersectionType(members):
				// Structural intersections share extension rules: preserve every field
				// contract and reject conflicting or non-structural bases.
				resolveStructure([], members, positioned, scope);
			case TypePath(segments, arguments):
				final path = segments.join(".");
				final args = [
					for (index in 0...arguments.length)
						resolveSyntax(arguments[index], positioned, scope + "/type-arg:" + index)
				];
				if (path == "Null" && args.length == 1) {
					TyType.nullable(args[0]);
				} else if (args.length == 0
					&& (path == "Int" || path == "Float" || path == "Bool" || path == "String" || path == "Void" || path == "Dynamic")) {
					TyType.fromHintText(path);
				} else {
					resolvePath(path, args, positioned, true);
				}
			case FunctionType(arguments, result):
				TyType.functionSignature([
					for (index in 0...arguments.length)
						{
							name: arguments[index].name,
							type: resolveSyntax(arguments[index].type, positioned, scope + "/arg:" + index),
							isOptional: arguments[index].isOptional,
							isRest: arguments[index].isRest,
							metadata: arguments[index].metadata
						}
				], resolveSyntax(result, positioned, scope + "/result"));
			case ArrowType(_, _):
				resolveArrow(syntax, positioned, scope);
			case AnonymousType(fields, extensions):
				resolveStructure(fields, extensions, positioned, scope);
		};
	}

	/** Flatten only ungrouped legacy arrows; parentheses preserve a returned function. */
	function resolveArrow(syntax:HxTypeSyntax, context:TyTypeResolutionContext, scope:String):TyType {
		final arguments = new Array<TyType>();
		var current = syntax;
		while (true) {
			switch (current.getKind()) {
				case ArrowType(argument, result):
					arguments.push(resolveSyntax(argument, context, scope + "/arg:" + arguments.length));
					current = result;
				case _:
					if (arguments.length == 1 && TyAliasExpansion.revealForResolution(arguments[0], buildDefinition).isVoid())
						arguments.resize(0);
					return TyType.functionType(arguments, resolveSyntax(current, context, scope + "/result"));
			}
		}
	}

	/**
		Merge structural bases and authored fields without object-literal overwrite rules.
		A repeated inherited field must have the same resolved contract. Method binders
		use a declaration-relative syntax path, not a source offset or allocation identity.
	 */
	function resolveStructure(fields:Array<HxTypeSyntax.HxTypeSyntaxField>, extensions:Array<HxTypeSyntax>, context:TyTypeResolutionContext,
			scope:String):TyType {
		final merged = new haxe.ds.StringMap<TyAnonymousField>();
		function add(field:TyAnonymousField):Void {
			final previous = merged.get(field.name);
			if (previous != null)
				comparisons.push({previous: previous, current: field, filePath: context.filePath});
			merged.set(field.name, field);
		}
		for (index in 0...extensions.length) {
			final base = TyAliasExpansion.revealForResolution(resolveSyntax(extensions[index], context, scope + "/base:" + index), buildDefinition);
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
						type: resolveSyntax(type, context, fieldScope),
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
						type: resolveSyntax(signature, methodContext, fieldScope),
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
