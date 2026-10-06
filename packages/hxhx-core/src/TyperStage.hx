private typedef TyMethodCallResolution = {
	final type:TyType;
	final declaration:Null<TyDeclarationInfo>;
	final ?order:TyMethodArgumentOrder;
	final ?actual:Array<TyType>;
};

/** One source-call traversal hands its selected declaration and operand types to generic inference. */
private typedef TyMethodCallCapture = {
	var selection:Null<TyMethodCallResolution>;
};

/** The already-typed receiver supplies owner arguments without repeating its traversal. */
private typedef TyCallReceiverContext = {
	final expression:HxExpr;
	final type:TyType;
};

private typedef TyExtensionCallResolution = {
	final type:TyType;
	final declaration:TyDeclarationInfo;
	final usingProvider:TyNominalTypeId;
	final ?order:TyMethodArgumentOrder;
};

private typedef TypedClassBuildResult = {
	final classes:Array<TypedClass>;
	final mainFunctions:Array<TyFunctionEnv>;
	final resolvedDirectives:Array<TyModuleDirective>;
};

private typedef TypedClassHeaderTypes = {
	final extendsType:Null<TyType>;
	final implementsTypes:Array<TyType>;
	final interfaceExtendsTypes:Array<TyType>;
};

/**
	Stage 2 typer skeleton.

	Why:
	- The “typer” is the heart of the compiler and the largest bootstrapping
	  milestone.
	- Even as a stub, we keep the API shaped like the real thing: consume a parsed
	  module and return a typed module.
**/
class TyperStage {
	static inline function isStrict():Bool {
		final v = Sys.getEnv("HXHX_TYPER_STRICT");
		return v == "1" || v == "true" || v == "yes";
	}

	/**
		Combine an assignment with the local's already-selected type.

		A complete local type is its storage contract. Assignment compatibility
		must not widen Int storage to Null<Int> merely because the incoming value
		needs conversion. Incomplete locals may still acquire missing facts;
		compatibility and mismatch decisions remain owned by `TyType.unify`.
	**/
	static function assignedLocalType(existing:TyType, incoming:TyType):Null<TyType> {
		if (existing != null && !existing.isUnknown() && !existing.isDynamic() && incoming != null && incoming.isDynamic())
			return existing;
		final compatible = TyType.unify(existing, incoming);
		return compatible != null && !existing.hasUnknownComponent() ? existing : compatible;
	}

	static function arrayElementType(t:TyType):Null<TyType> {
		if (t == null)
			return null;
		final arguments = t.getTypeArguments();
		if (arguments.length == 1) {
			final identity = t.getNominalIdentity();
			final containerName = identity == null ? t.getUnresolvedPath() : identity.getCanonicalName();
			if (containerName == "Array" || containerName == "haxe.Array")
				return arguments[0];
		}
		final d = t.getDisplay();
		if (d == null)
			return null;
		if (!StringTools.startsWith(d, "Array<"))
			return null;
		if (!StringTools.endsWith(d, ">"))
			return null;
		final inner = StringTools.trim(d.substr("Array<".length, d.length - "Array<".length - 1));
		return inner.length == 0 ? TyType.unknown() : TyType.fromHintText(inner);
	}

	static function typeFromHintInContext(hint:String, ctx:TyperContext, ?scope:TyFunctionEnv):TyType {
		final raw = hint == null ? "" : StringTools.trim(hint);
		if (raw.length == 0)
			return TyType.unknown();
		// Keep primitive-like names stable.
		switch (raw) {
			case "Int", "Float", "Bool", "String", "Void", "Dynamic", "Null":
				return TyType.fromHintText(raw);
			case _:
		}

		// Resolve binders from outermost to innermost through the shared type-use owner.
		final owner = ctx == null ? null : ctx.currentClass();
		// Nominal providers have a closed class/abstract boundary. Preserve their
		// indexed binders instead of creating parameters from local hint spelling.
		var parameters = if (Std.isOfType(owner, TyClassInfo)) {
			(cast owner : TyClassInfo).getTypeParameterIds();
		} else if (Std.isOfType(owner, TyAbstractInfo)) {
			(cast owner : TyAbstractInfo).getTypeParameterIds();
		} else {
			[];
		};
		if (owner != null && scope != null)
			for (declaration in owner.getDeclarations())
				if (declaration.getIdentity().getCanonicalKey() == scope.getOwnerIdentity())
					parameters = parameters.concat(declaration.getTypeParameterIds());
		if (scope != null)
			parameters = parameters.concat(scope.getTypeParameters());
		return resolveTypeInContext(TyType.fromHintText(raw), ctx, parameters);
	}

	static function resolveTypeInContext(type:TyType, ctx:TyperContext, ?typeParameters:Array<TyTypeParameterId>):TyType {
		if (type == null)
			return TyType.unknown();
		if (type.isNullable())
			return TyType.nullable(resolveTypeInContext(type.getNullableInner(), ctx, typeParameters), type.getDisplay());
		if (type.isFunction()) {
			final result = type.getFunctionReturn();
			return type.withFunctionTypes([
				for (argument in type.getFunctionArguments())
					resolveTypeInContext(argument, ctx, typeParameters)
			],
				result == null ? TyType.unknown() : resolveTypeInContext(result, ctx, typeParameters));
		}
		if (type.isAnonymous())
			return TyType.anonymous(type.getAnonymousFieldNames(), [
				for (fieldType in type.getAnonymousFieldTypes())
					resolveTypeInContext(fieldType, ctx, typeParameters)
			]);
		if (!type.isUnresolved())
			return type;
		final arguments = [
			for (argument in type.getTypeArguments())
				resolveTypeInContext(argument, ctx, typeParameters)
		];
		// The shared resolver searches innermost binders first, including method
		// parameters that shadow an enclosing class parameter with the same name.
		final unresolved = TyType.unresolved(type.getUnresolvedPath(), arguments, type.getDisplay());
		final resolved = ctx == null ? unresolved : ctx.resolveTypeUse(unresolved, typeParameters).getType();
		validateClassArguments(resolved, ctx, HxPos.unknown());
		return resolved;
	}

	/** Validate annotations and finalized constructor applications with the same bound relation. */
	static function validateClassArguments(type:TyType, ctx:TyperContext, position:HxPos):Void {
		if (ctx != null)
			TyClassArgumentBounds.validate(type, ctx.getIndex(), ctx.getFilePath(), position,
				(expected, supplied) -> constraintAccepts(expected, supplied, ctx.getIndex()));
	}

	/** Bound checks preserve exact nominal ancestry and the object-only meaning of an empty record. */
	static function constraintAccepts(expected:TyType, supplied:TyType, index:TyperIndex):Bool {
		if (supplied.isDynamic())
			return true;
		return TyCallerConstraintProof.accepts(expected, supplied, index.getParameterBounds, (target, actual) -> {
			if (target.isAnonymous() && target.getAnonymousFieldNames().length == 0)
				return TyEmptyObjectConstraint.accepts(actual, index);
			final owner = target.getNominalIdentity();
			if (owner != null && actual.getNominalIdentity() != null) {
				final ancestor = TyNominalAncestor.view(index, actual, owner);
				return ancestor != null && ancestor.getSemanticKey() == target.getSemanticKey();
			}
			return overloadArgScore(target, actual, [], index) >= 0;
		});
	}

	static function nominalInfoForType(index:TyperIndex, type:TyType):Null<TyNominalInfo> {
		if (index == null || type == null)
			return null;
		final nominal = type.unwrapNull();
		final identity = nominal.getNominalIdentity();
		return identity == null ? index.getByFullName(nominal.getDisplay()) : index.getByFullName(identity.getCanonicalName());
	}

	/**
		Load and return one exact nominal path without accepting a same-short-name fallback.

		A directive path is already fully qualified source input. Accepting the ordinary
		short-name fallback here could misclassify `model.Api.PI` as an unrelated type
		named `PI`, which would recreate the backend spelling guess this layer removes.
	**/
	static function exactDirectiveProvider(path:String, packagePath:String, sourceDirectives:Array<HxModuleDirective>, index:TyperIndex,
			loader:ModuleLoader):Null<TyNominalInfo> {
		if (index == null || path == null || path.length == 0)
			return null;
		var provider = index.getByFullName(path);
		if (provider == null && loader != null) {
			loader.ensureTypeAvailable(path, packagePath, sourceDirectives);
			provider = index.getByFullName(path);
		}
		return provider != null && provider.getVisibility() == HxVisibility.Public ? provider : null;
	}

	/**
		Resolve the type named by one `using` directive in its source module.

		A one-segment directive can name a secondary type declared in the same
		module. Its canonical identity includes that module (`Main.Helper`), so a
		direct full-name lookup alone is insufficient. Ordinary type-path
		resolution preserves that source meaning while still enforcing visibility.
	**/
	static function usingDirectiveProvider(path:String, packagePath:String, modulePath:String, sourceDirectives:Array<HxModuleDirective>, index:TyperIndex,
			loader:ModuleLoader):Null<TyNominalInfo> {
		if (index == null || path == null || path.length == 0)
			return null;
		var provider = index.resolveTypePath(path, packagePath, sourceDirectives, null, modulePath);
		if (provider == null && loader != null) {
			loader.ensureTypeAvailable(path, packagePath, sourceDirectives);
			provider = index.resolveTypePath(path, packagePath, sourceDirectives, null, modulePath);
		}
		return provider;
	}

	static function providerDefinesStaticMember(provider:TyNominalInfo, memberName:String):Bool {
		if (provider == null || memberName == null || memberName.length == 0)
			return false;
		final field = provider.fieldInfo(memberName);
		if (field != null && field.getIsStatic() && field.getIsPublic())
			return true;
		for (candidate in provider.staticMethodCandidates(memberName)) {
			final declaration = provider.declarationForSignature(candidate);
			if (declaration != null && declaration.getIsPublic())
				return true;
		}
		return false;
	}

	/** Load one module path and return every type that its current source declares. **/
	static function moduleDirectiveProviders(path:String, packagePath:String, sourceDirectives:Array<HxModuleDirective>, index:TyperIndex,
			loader:ModuleLoader):Array<TyNominalInfo> {
		if (path == null || path.length == 0 || index == null)
			return [];
		if (loader != null)
			loader.ensureTypeAvailable(path, packagePath, sourceDirectives);
		return index.getByModulePath(path);
	}

	static function providerIdentities(providers:Array<TyNominalInfo>):Array<TyNominalTypeId> {
		return providers == null ? [] : [for (provider in providers) provider.getIdentity()];
	}

	/** Resolve parsed directives once so every target consumes the same Haxe meaning. **/
	static function resolveModuleDirectives(sourceDirectives:Array<HxModuleDirective>, packagePath:String, modulePath:String, index:TyperIndex,
			loader:ModuleLoader):Array<TyModuleDirective> {
		final out = new Array<TyModuleDirective>();
		for (source in sourceDirectives) {
			final path = HxModuleDirective.getPath(source);
			switch (HxModuleDirective.getKind(source)) {
				case Using:
					final moduleProviders = moduleDirectiveProviders(path, packagePath, sourceDirectives, index, loader);
					if (moduleProviders.length > 0) {
						out.push(new TyModuleDirective(source, UsingType, providerIdentities(moduleProviders)));
					} else {
						final provider = usingDirectiveProvider(path, packagePath, modulePath, sourceDirectives, index, loader);
						out.push(provider == null ? new TyModuleDirective(source,
							Unresolved) : new TyModuleDirective(source, UsingType, [provider.getIdentity()]));
					}
				case ImportAll:
					final provider = exactDirectiveProvider(path, packagePath, sourceDirectives, index, loader);
					out.push(provider == null ? new TyModuleDirective(source,
						PackageWildcardImport) : new TyModuleDirective(source, StaticWildcardImport, [provider.getIdentity()]));
				case ImportNormal:
					final moduleProviders = moduleDirectiveProviders(path, packagePath, sourceDirectives, index, loader);
					if (moduleProviders.length > 0) {
						out.push(new TyModuleDirective(source, TypeImport, providerIdentities(moduleProviders)));
						continue;
					}
					final exactType = exactDirectiveProvider(path, packagePath, sourceDirectives, index, loader);
					if (exactType != null) {
						out.push(new TyModuleDirective(source, TypeImport, [exactType.getIdentity()]));
						continue;
					}
					var separator = path.lastIndexOf(".");
					var resolved:Null<TyModuleDirective> = null;
					while (separator > 0 && resolved == null) {
						final ownerPath = path.substr(0, separator);
						final memberName = path.substr(separator + 1);
						final provider = exactDirectiveProvider(ownerPath, packagePath, sourceDirectives, index, loader);
						if (provider != null && memberName.indexOf(".") < 0 && providerDefinesStaticMember(provider, memberName))
							resolved = new TyModuleDirective(source, StaticMemberImport(memberName), [provider.getIdentity()]);
						separator = ownerPath.lastIndexOf(".");
					}
					out.push(resolved == null ? new TyModuleDirective(source, Unresolved) : resolved);
				case ImportAlias(_):
					final exactType = exactDirectiveProvider(path, packagePath, sourceDirectives, index, loader);
					if (exactType != null) {
						out.push(new TyModuleDirective(source, TypeImport, [exactType.getIdentity()]));
						continue;
					}
					var separator = path.lastIndexOf(".");
					var resolved:Null<TyModuleDirective> = null;
					while (separator > 0 && resolved == null) {
						final ownerPath = path.substr(0, separator);
						final memberName = path.substr(separator + 1);
						final provider = exactDirectiveProvider(ownerPath, packagePath, sourceDirectives, index, loader);
						if (provider != null && memberName.indexOf(".") < 0 && providerDefinesStaticMember(provider, memberName))
							resolved = new TyModuleDirective(source, StaticMemberImport(memberName), [provider.getIdentity()]);
						separator = ownerPath.lastIndexOf(".");
					}
					out.push(resolved == null ? new TyModuleDirective(source, Unresolved) : resolved);
			}
		}
		return out;
	}

	/**
		Resolve fields and unambiguous method values with their exact receiver type.
		Inherited storage substitutes through its declaring parent's application;
		static storage retains its shared declaration type. Method values use the
		same receiver substitution, while overloaded values still need selection.
	**/
	static function declaredMemberReadType(owner:TyNominalInfo, name:String, isStatic:Bool, ctx:TyperContext, ?receiver:TyType):Null<TyType> {
		if (owner == null)
			return null;
		final inheritedField = isStatic ? null : ctx.instanceField(name, owner);
		final selectedField = inheritedField == null ? owner.fieldInfo(name) : inheritedField;
		final fieldType = selectedField == null ? null : TyNominalApplication.fieldType(ctx.getIndex(), selectedField, receiver);
		if (fieldType != null)
			return fieldType;
		if (!isStatic) {
			owner = ctx.instanceMethodOwner(name, owner);
			if (owner == null)
				return null;
		}
		final candidates = isStatic ? owner.staticMethodCandidates(name) : owner.instanceMethodCandidates(name);
		if (candidates.length == 1)
			return functionReferenceType(TyNominalApplication.signature(ctx.getIndex(), owner, receiver, candidates[0]));
		final method = isStatic ? owner.staticMethod(name) : owner.instanceMethod(name);
		if (isStatic && owner.staticMethodCandidates(name).length == 1) {
			final declaration = owner.declarationForSignature(method);
			if (declaration != null)
				return TyCallableSignature.fromDeclaration(declaration).getFunctionType();
		}
		return method == null ? null : TyType.unknown();
	}

	/**
		Select the property declaration before choosing an abstract update operator.
		A class value has type Class<T>; its resolved runtime target owns static
		properties, while an instance type owns instance properties.
	**/
	static function accessorPropertyForAccess(expression:HxExpr, scope:TyFunctionEnv, ctx:TyperContext, position:HxPos):Null<TyPropertyInfo> {
		var receiver:Null<HxExpr> = null;
		var field = "";
		switch (expression) {
			case EField(exactReceiver, exactField):
				receiver = exactReceiver;
				field = exactField;
			case _:
		}
		if (receiver == null)
			return null;
		final runtimeTarget = TypedRuntimeTypeResolver.resolve(receiver, scope, ctx, ValueExpression);
		final runtimeOwner = runtimeTarget == null ? null : runtimeTarget.getDeclarationIdentity();
		final owner = runtimeTarget != null ? (runtimeOwner == null ? null : ctx.getIndex()
			.getByFullName(runtimeOwner.getCanonicalName())) : switch (receiver) {
				case EThis: nominalInfoForType(ctx.getIndex(), currentThisType(ctx));
				case _: nominalInfoForType(ctx.getIndex(), inferExprType(receiver, scope, ctx, position));
			};
		final property = owner == null ? null : owner.propertyInfo(field);
		return property != null && property.usesExplicitAccessors() ? property : null;
	}

	/**
		Explicit this denotes an abstract's storage type inside its body, and the
		applied class type otherwise. Member lookup must use this type rather than
		the enclosing declaration, which can expose different methods with the same name.
	 */
	static function currentThisType(ctx:TyperContext):TyType {
		if (ctx == null)
			return TyType.unknown();
		final current = ctx.currentClass();
		if (current == null)
			return TyType.unknown();
		if (Std.isOfType(current, TyAbstractInfo))
			return (cast current : TyAbstractInfo).getUnderlyingType();
		return TyType.nominal(current.getIdentity(), [
			for (parameter in TyNominalApplication.parameterIds(current))
				TyType.typeParameter(parameter)
		], current.getFullName());
	}

	static function declarePatternBindings(scope:TyFunctionEnv, pattern:HxSwitchPattern, baseTy:TyType, ctx:TyperContext, pos:HxPos):Void {
		TySwitchPatternBindings.declare(scope, pattern, baseTy, (input, name, arity) -> TyEnumPatternArguments.resolve(input, name, arity, ctx, pos));
	}

	/** Patterns constrain omitted inputs before either switch form declares payload locals. */
	static function inferSwitchInput(scrutinee:HxExpr, patterns:Array<HxSwitchPattern>, scope:TyFunctionEnv, ctx:TyperContext, pos:HxPos):TyType {
		final actual = inferExprType(scrutinee, scope, ctx, pos);
		if (!actual.isUnknown() || !scope.getInference().canReceiveContext(scrutinee, scope))
			return actual;
		final expected = TyEnumPatternInput.resolve(patterns, ctx, pos);
		return expected == null ? actual : inferExprType(scrutinee, scope, ctx, pos, expected);
	}

	static function buildTypedClasses(parsed:ParsedModule, index:TyperIndex, loader:ModuleLoader, modulePath:String,
			deferProgramLowering:Bool = false):TypedClassBuildResult {
		if (index != null) {
			index.getMethodBodyResults().configure(declaration -> inferDeclaredMethodResult(declaration, index, loader));
			index.getFieldInitializerTypes().configure((field, source) -> inferDeclaredFieldType(field, source, index, loader));
		}
		final declaration = parsed.getDecl();
		final packagePath = HxModuleDecl.getPackagePath(declaration);
		final directives = HxModuleDecl.getDirectives(declaration);
		final resolvedDirectives = resolveModuleDirectives(directives, packagePath, modulePath, index, loader);
		TyClassArgumentBounds.validateDeclarations(parsed, modulePath, index, (expected, supplied) -> constraintAccepts(expected, supplied, index));
		final mainClass = HxModuleDecl.getMainClass(declaration);
		final typedClasses = new Array<TypedClass>();
		var mainFunctions = new Array<TyFunctionEnv>();

		for (classDeclaration in HxModuleDecl.getClasses(declaration)) {
			final className = HxClassDecl.getName(classDeclaration);
			final semanticInfo = index == null ? null : index.getForSourceClass(classDeclaration);
			final classFullName = semanticInfo == null ? ((packagePath == null || packagePath.length == 0) ? className : packagePath
				+ "."
				+ className) : semanticInfo.getFullName();
			final context = new TyperContext(index, parsed.getFilePath(), modulePath, packagePath, directives, classFullName, loader, resolvedDirectives);
			final headerTypes = resolveClassHeaderTypes(classDeclaration, context);
			final typedFunctions = new Array<TypedFunction>();
			final typedFieldInitializers = new Array<TypedFieldInitializer>();
			final functionEnvironments = new Array<TyFunctionEnv>();
			final typeResolver:TypedExprTypeResolver = {
				lambdaType: function(names, body, argumentTypes, signature, position, lexicalEnvironment) {
					return inferLambdaType(names, body, argumentTypes, lexicalEnvironment.copyForInference(), context, position, signature);
				},
				expressionType: function(expression, position, lexicalEnvironment, expected) {
					return inferExprType(expression, lexicalEnvironment.copyForInference(), context, position, expected);
				},
				callTargetType: function(expression, position, lexicalEnvironment) {
					final scope = lexicalEnvironment.copyForInference();
					final method = resolveStaticMethodValue(expression, scope, context);
					return method != null
						|| resolveInstanceMethodValue(expression, scope, context,
							position) != null ? inferExprValueType(expression, scope, context, position,
							null) : inferExprType(expression, scope, context, position);
				},
				declaredType: function(hint, lexicalEnvironment) {
					return typeFromHintInContext(hint, context, lexicalEnvironment);
				},
				runtimeTypeTarget: function(expression, lexicalEnvironment, namespace) {
					return TypedRuntimeTypeResolver.resolve(expression, lexicalEnvironment, context, namespace);
				},
				catchUse: function(binding) {
					return context.hasDefine("neko") || context.hasDefine("cpp") ? TypedCatchUse.resolve(binding, context) : null;
				},
				enumPatternArguments: function(input, name, arity, position) {
					return TyEnumPatternArguments.resolve(input, name, arity, context, position);
				},
				enumSwitchCoverage: function(input, patterns, position, isCapture) {
					return TyEnumSwitchCoverage.proves(input, patterns, context, position, isCapture);
				},
				convertValue: function(value, expected) {
					final conversion = TyAbstractMethodConversion.select(context.getIndex(), expected, value.getType());
					if (conversion != null)
						return conversion.apply(value);
					// Initializers and returns must materialize declared header conversions
					// too; accepting their type does not unwrap the target's stored value.
					// Nullable storage admits the converted non-null value; literal
					// null must retain its value and skip conversion effects.
					final storageType = expected.isNullable() && !value.getType().isNullLiteral() ? expected.unwrapNull() : expected;
					final storage = TyImplicitConversionPlan.select(context.getIndex(), storageType, value.getType());
					return storage != null && storage.isRepresentationPreservingAbstractConversion() ? storage.apply(value) : value;
				},
				constructorApplication: function(constructed, arguments, sources) {
					return TypedConstructorSelection.select(context.getIndex(), constructed, arguments, sources,
						(signature, actual, parameters) -> overloadCandidateScore(signature, actual, actual.length, parameters, context.getIndex()));
				}
			};
			final callResolver:TypedCallDeclarationResolver = function(callee, arguments, position, lexicalEnvironment, callExpression) {
				final inferenceEnvironment = lexicalEnvironment.copyForInference();
				var selection = resolveCallSelection(callee, arguments, inferenceEnvironment, context, position);
				var declaration = selection == null ? null : selection.declaration;
				var extensionProvider:Null<TyNominalTypeId> = null;
				if (declaration == null) {
					switch (callee) {
						case EField(receiver, field):
							final extension = resolveExtensionCall(receiver, field, arguments, inferenceEnvironment, context, position);
							if (extension != null) {
								declaration = extension.declaration;
								extensionProvider = extension.usingProvider;
								selection = {type: extension.type, declaration: extension.declaration, order: extension.order};
							}
						case _:
					}
				}
				final current = context.currentClass();
				final inheritedInstanceCall = declaration != null
					&& !declaration.getIsStatic()
					&& current != null
					&& declaration.getOwner().getCanonicalName() != current.getIdentity().getCanonicalName();
				final requiresOwnerQualification = inheritedInstanceCall
					|| (declaration != null && declaration.getIsEnumConstructor())
					|| switch (callee) {
						case EIdent(name) if (declaration != null
							&& declaration.getIsStatic()
							&& lexicalEnvironment.resolveSymbol(name) == null): (current == null
								|| current.staticMethodCandidates(name).length == 0) && context.importedStaticMethod(name) != null;
						case _: false;
					};
				final inferredCall = declaration == null ? null : lexicalEnvironment.getInference().directCallType(callExpression, declaration);
				var named:Null<TypedNamedCallPlan> = null;
				if (selection != null && selection.order != null && declaration != null) {
					final supplied = arguments.copy();
					if (extensionProvider != null)
						switch callee {
							case EField(receiver, _):
								supplied.unshift(receiver);
							case _:
								throw "selected extension lost its receiver";
						}
					final actual = [
						for (argument in supplied)
							inferExprType(argument, inferenceEnvironment, context, position)
					];
					final signature = appliedCallSignature(declaration, callee, inferenceEnvironment, context, position);
					final parameters = TyMethodGenericBinding.specializeParameters(declaration, signature, selection.order.rankedTypes(actual),
						context.getIndex());
					if (inferredCall != null) {
						// A later result or alias context may solve a method variable after
						// selection. Recheck its declared bound before publishing that solution.
						if (declaration.getResolvedTypeParameterConstraints().keys().hasNext()) {
							final boundOwner = context.getIndex().getByFullName(declaration.getOwner().getCanonicalName());
							final boundReceiver = callReceiverType(declaration, callee, inferenceEnvironment, context, position);
							final failure = TyMethodGenericBinding.constraintFailure(declaration, signature, inferredCall.getFunctionArguments(),
								bound -> TyNominalApplication.applyType(context.getIndex(), boundOwner, boundReceiver, bound),
								(expected, actual) -> constraintAccepts(expected, actual, context.getIndex()), context.getIndex());
							if (failure != null)
								throw new TyperError(context.getFilePath(), position, failure);
						}
						final solved = inferredCall.getFunctionArguments();
						if (solved.length != parameters.length)
							throw "named call inference changed its parameter count";
						for (slot in 0...parameters.length)
							if (slot >= signature.getArgRest().length || !signature.getArgRest()[slot])
								parameters[slot] = solved[slot];
							else {
								final container = signature.getArgs()[slot];
								if (container.getTypeArguments().length != 1
									|| (container.getNominalIdentity() == null && !container.isUnresolved()))
									throw "named rest inference lost its declared container";
								parameters[slot] = container.isUnresolved() ? TyType.unresolved(container.getUnresolvedPath(),
									[solved[slot]]) : TyType.nominal(container.getNominalIdentity(), [solved[slot]]);
							}
					}
					named = new TypedNamedCallPlan({
						declaration: declaration,
						signature: signature,
						order: selection.order,
						parameters: parameters,
						sources: arguments,
						index: context.getIndex(),
						extensionProvider: extensionProvider
					});
				}
				final expectedArguments = named != null ? named.getExpectedArguments() : inferredCall == null ? callArgumentExpectedTypes(declaration,
					extensionProvider, callee, arguments, lexicalEnvironment.copyForInference(), context, position) : inferredCall.getFunctionArguments();
				final argumentConversions = callArgumentConversions(declaration, extensionProvider, arguments, lexicalEnvironment.copyForInference(), context,
					position, named == null ? null : expectedArguments);
				return new TypedCallResolution(declaration, requiresOwnerQualification, extensionProvider, argumentConversions, expectedArguments, named);
			};
			final memberResolver:TypedMemberDeclarationResolver = function(expression, position, lexicalEnvironment) {
				final field = resolveFieldDeclaration(expression, lexicalEnvironment.copyForInference(), context, position);
				if (field == null) {
					final method = resolveStaticMethodValue(expression, lexicalEnvironment, context);
					if (method == null) {
						final instance = resolveInstanceMethodValue(expression, lexicalEnvironment, context, position);
						if (instance != null)
							return TypedMemberResolution.instanceMethod(instance, lexicalEnvironment.isStaticContext() ? null : currentThisType(context));
						// Only the typing index can distinguish an abstract from a class
						// with an equally unresolved member. Lowering must not guess.
						return switch (expression) {
							case EField(receiver, _): final identity = inferExprType(receiver, lexicalEnvironment.copyForInference(), context,
									position).getNominalIdentity(); identity != null && context.getIndex()
									.getAbstractByFullName(identity.getCanonicalName()) != null ? TypedMemberResolution.unresolvedAbstractField() : null;
							case _: null;
						};
					}
					if (method.getIsEnumConstructor())
						return null;
					// Instance bodies have no implicit static-method binding. Preserve
					// the selected class when a bare static method is used as a value.
					final qualifyBareMethod = switch (expression) {
						case EIdent(name) | EEnumValue(name): final current = context.currentClass(); !lexicalEnvironment.isStaticContext() || current == null || current.declarationForSignature(current.staticMethod(name)) != method;
						case _: false;
					};
					return TypedMemberResolution.method(method, qualifyBareMethod);
				}
				final importedBareField = switch (expression) {
					case EIdent(name) | EEnumValue(name) if (lexicalEnvironment.resolveSymbol(name) == null): final current = context.currentClass(); (current == null
							|| current.fieldInfo(name) == null) && (context.importedStaticField(name) == field
							|| context.moduleEnumConstructorField(name) == field);
					case _: false;
				};
				return TypedMemberResolution.field(field, importedBareField);
			};
			for (field in HxClassDecl.getFields(classDeclaration)) {
				final initializer = HxFieldDecl.getInit(field);
				final fieldInfo = semanticInfo == null ? null : semanticInfo.fieldInfo(HxFieldDecl.getName(field));
				if (fieldInfo != null)
					validateClassArguments(fieldInfo.getType(), context, HxFieldDecl.getPos(field));
				if (initializer == null || fieldInfo == null)
					continue;
				final fieldType = fieldInfo.getType();
				final initializerType = TypedFieldInitialization.expectedType(fieldInfo);
				final fieldControls = new TyControlScope(fieldInfo.getCanonicalKey(), TypedBodyFingerprint.forExpression(initializer), Initializer);
				final fieldEnvironment = new TyFunctionEnv("<field-initializer:" + fieldInfo.getName() + ">", [], [], fieldType, fieldType,
					fieldInfo.getCanonicalKey(), null, false, 0, fieldInfo.getIsStatic(), fieldControls);
				// Record declarations and control destinations before building immutable nodes.
				// The initializer owns this traversal; only nested source functions accept returns.
				inferExprType(initializer, fieldEnvironment, context, HxFieldDecl.getPos(field), initializerType);
				fieldEnvironment.sealInference();
				final fieldReplay = fieldEnvironment.createBodyReplay();
				final typedInitializer = TypedBodyBuilder.buildExpression(initializer, HxFieldDecl.getPos(field), fieldReplay, typeResolver, callResolver,
					memberResolver, initializerType);
				typedFieldInitializers.push(new TypedFieldInitializer(fieldInfo,
					TypedFieldInitialization.adapt(context.getIndex(), fieldInfo, typedInitializer, context.getFilePath())));
				fieldReplay.assertReplayComplete();
			}
			final sourceFunctions = HxClassDecl.getFunctions(classDeclaration);
			final semanticDeclarations = new Array<Null<TyDeclarationInfo>>();
			final functionIdentities = new Array<String>();
			for (functionIndex in 0...sourceFunctions.length) {
				final sourceFunction = sourceFunctions[functionIndex];
				final semanticDeclaration = semanticInfo == null ? null : semanticInfo.declarationForSource(sourceFunction);
				final functionIdentity = TypedFunction.stableIdentityFor(className, functionIndex, sourceFunction, semanticDeclaration);
				final functionEnvironment = typeFunction(sourceFunction, context, functionIdentity, semanticDeclaration);
				semanticDeclarations.push(semanticDeclaration);
				functionIdentities.push(functionIdentity);
				functionEnvironments.push(functionEnvironment);
				// A function with no value-returning statement still has its finalized
				// Void result; expression-only evidence would leave callers unresolved.
				if (semanticDeclaration != null && semanticDeclaration.getSignature().getReturnType().isUnknown())
					context.recordInferredReturnType(semanticDeclaration, functionEnvironment.getReturnType());
			}

			// The declaration index is built before bodies are typed, so an unannotated
			// method initially has an Unknown result. Retry only unresolved callers after
			// every concrete body result in this class is available. This keeps method
			// order from changing inference without retyping already settled functions.
			var pendingReturnInference = [
				for (functionIndex in 0...sourceFunctions.length)
					if (semanticDeclarations[functionIndex] != null
						&& semanticDeclarations[functionIndex].getSignature().getReturnType().isUnknown()
						&& (functionEnvironments[functionIndex].getReturnExprType().isUnknown()
							|| functionEnvironments[functionIndex].getReturnExprType().isDynamic())) functionIndex
			];
			while (pendingReturnInference.length > 0) {
				var progress = false;
				final stillPending = new Array<Int>();
				for (functionIndex in pendingReturnInference) {
					final functionEnvironment = typeFunction(sourceFunctions[functionIndex], context, functionIdentities[functionIndex],
						semanticDeclarations[functionIndex]);
					functionEnvironments[functionIndex] = functionEnvironment;
					if (context.recordInferredReturnType(semanticDeclarations[functionIndex], functionEnvironment.getReturnType())) {
						progress = true;
					} else if (functionEnvironment.getReturnExprType().isUnknown()
						|| functionEnvironment.getReturnExprType().isDynamic()) {
						stillPending.push(functionIndex);
					}
				}
				if (!progress)
					break;
				pendingReturnInference = stillPending;
			}

			for (functionIndex in 0...sourceFunctions.length) {
				typedFunctions.push(TypedBodyBuilder.buildFunction(className, functionIndex, sourceFunctions[functionIndex],
					semanticDeclarations[functionIndex], functionEnvironments[functionIndex], typeResolver, callResolver, memberResolver));
			}
			if (classDeclaration == mainClass)
				mainFunctions = functionEnvironments;
			typedClasses.push(new TypedClass(classDeclaration, semanticInfo, typedFunctions, typedFieldInitializers, headerTypes.extendsType,
				headerTypes.implementsTypes, headerTypes.interfaceExtendsTypes,
				null, semanticInfo == null || index == null ? null : index.getFieldInitializerTypes()
				.publish(semanticInfo)));
		}

		final loweredClasses = index == null
			|| deferProgramLowering ? typedClasses : TypedAbstractOperatorLowering.lowerClasses(typedClasses, index, parsed.getFilePath());
		return {classes: loweredClasses, mainFunctions: mainFunctions, resolvedDirectives: resolvedDirectives};
	}

	/**
		Make every type named by `extends` or `implements` available before typing the class body.

		Class headers are part of typing even when no method expression mentions the
		parent. Resolving them through the ordinary context lets the existing lazy
		loader find, prepare, and index the owning module without scanning unrelated
		source files. Parsing the header as a type also discovers generic arguments.
	**/
	static function resolveClassHeaderTypes(classDeclaration:HxClassDecl, context:TyperContext):TypedClassHeaderTypes {
		// Header loading can resolve a provider after the declaration index was
		// built. Keep the index's exact generic binders while selecting that provider.
		final owner = context.currentClass();
		final typeParameters = owner != null && Std.isOfType(owner, TyClassInfo) ? (cast owner : TyClassInfo).getTypeParameterIds() : [];
		final extendsPath = HxClassDecl.getExtendsPath(classDeclaration);
		final extendsType = extendsPath != null
			&& StringTools.trim(extendsPath).length > 0 ? resolveTypeInContext(TyType.fromHintText(extendsPath), context, typeParameters) : null;
		final implementsTypes = new Array<TyType>();
		for (implementedPath in HxClassDecl.getImplementsPaths(classDeclaration))
			if (implementedPath != null && StringTools.trim(implementedPath).length > 0)
				implementsTypes.push(resolveTypeInContext(TyType.fromHintText(implementedPath), context, typeParameters));
		final interfaceExtendsTypes = [
			for (path in HxClassDecl.getInterfaceExtendsPaths(classDeclaration))
				resolveTypeInContext(TyType.fromHintText(path), context, typeParameters)
		];
		return {extendsType: extendsType, implementsTypes: implementsTypes, interfaceExtendsTypes: interfaceExtendsTypes};
	}

	/**
		Type a parsed module into a minimal `TypedModule`.

		Why:
		- Later stages (macro expansion + backend codegen) need a stable typed
		  surface, even before we implement the full Haxe type system.
		- For `hih-compiler` acceptance, we care about determinism and basic type
		  inference for literals and simple `return` expressions.

		What:
		- Builds a `TyModuleEnv` containing:
		  - package/import summary
		  - a `TyClassEnv` with per-function environments

		How:
		- Stage 3: we build a real local scope per function (params + locals) and
		  infer return types when no explicit return hint exists.
	**/
	public static function typeModule(m:ParsedModule):TypedModule {
		final decl = m.getDecl();
		final pkg = HxModuleDecl.getPackagePath(decl);
		final directives = HxModuleDecl.getDirectives(decl);
		final cls = HxModuleDecl.getMainClass(decl);
		final built = buildTypedClasses(m, null, null, "");
		final classEnv = new TyClassEnv(HxClassDecl.getName(cls), built.mainFunctions);
		final env = new TyModuleEnv(pkg, directives, classEnv, built.resolvedDirectives);
		return new TypedModule(m, env, built.classes);
	}

	/**
		Type a resolved module using a shared program index.

		Why
		- Stage 3.3 needs cross-module knowledge (imports, class fields, statics)
		  to type `Util.ping()` and `this.x` in upstream-shaped code.
	**/
	public static function typeResolvedModule(m:ResolvedModule, index:TyperIndex, ?loader:ModuleLoader, deferProgramLowering:Bool = false):TypedModule {
		final pm = ResolvedModule.getParsed(m);
		final decl = pm.getDecl();
		final pkg = HxModuleDecl.getPackagePath(decl);
		final directives = HxModuleDecl.getDirectives(decl);
		final cls = HxModuleDecl.getMainClass(decl);
		final built = buildTypedClasses(pm, index, loader, ResolvedModule.getModulePath(m), deferProgramLowering);
		final classEnv = new TyClassEnv(HxClassDecl.getName(cls), built.mainFunctions);
		final env = new TyModuleEnv(pkg, directives, classEnv, built.resolvedDirectives);
		return new TypedModule(pm, env, built.classes, 1, ResolvedModule.getSourceOrigin(m), ResolvedModule.getConditionalCompilation(m),
			ResolvedModule.getGeneratedDeclarations(m));
	}

	/** Infer storage from its own initializer under the declaring module's names and binders. */
	static function inferDeclaredFieldType(field:TyFieldInfo, source:HxFieldDecl, index:TyperIndex, loader:ModuleLoader):TyType {
		final module = index.getRegisteredModule(field.getModulePath());
		if (module == null)
			return TyType.unknown();
		final parsed = ResolvedModule.getParsed(module);
		final declaration = parsed.getDecl();
		final packagePath = HxModuleDecl.getPackagePath(declaration);
		final directives = HxModuleDecl.getDirectives(declaration);
		final resolved = resolveModuleDirectives(directives, packagePath, field.getModulePath(), index, loader);
		final context = new TyperContext(index, parsed.getFilePath(), field.getModulePath(), packagePath, directives, field.getOwner().getCanonicalName(),
			loader, resolved);
		final initializer = HxFieldDecl.getInit(source);
		final owner = context.currentClass();
		final parameters = field.getIsStatic() || owner == null ? [] : TyNominalApplication.parameterIds(owner);
		final scope = new TyFunctionEnv('<field-initializer:' + field.getName() + '>', [], [], field.getType(), field.getType(), field.getCanonicalKey(),
			null, false, 0, field.getIsStatic(), new TyControlScope(field.getCanonicalKey(), TypedBodyFingerprint.forExpression(initializer), Initializer),
			null, parameters);
		final result = inferExprType(initializer, scope, context, HxFieldDecl.getPos(source));
		scope.sealInference();
		return result;
	}

	/** Infer in the declaring module, never under the imports or binders of its consumer. */
	static function inferDeclaredMethodResult(declaration:TyDeclarationInfo, index:TyperIndex, loader:ModuleLoader):TyMethodBodyResults.TyMethodBodyResult {
		final module = index.getRegisteredModule(declaration.getModulePath());
		if (module == null)
			return {type: TyType.unknown(), complete: false, parameters: declaration.getSignature().getArgs()};
		final parsed = ResolvedModule.getParsed(module);
		final owner = parsed.getDecl();
		final packagePath = HxModuleDecl.getPackagePath(owner);
		final directives = HxModuleDecl.getDirectives(owner);
		final resolved = resolveModuleDirectives(directives, packagePath, declaration.getModulePath(), index, loader);
		final context = new TyperContext(index, parsed.getFilePath(), declaration.getModulePath(), packagePath, directives,
			declaration.getOwner().getCanonicalName(), loader, resolved);
		var result:TyMethodBodyResults.TyMethodBodyResult = {type: TyType.unknown(), complete: false, parameters: declaration.getSignature().getArgs()};
		typeFunction(declaration.getSourceDeclaration(), context, declaration.getIdentity().getCanonicalKey(), declaration, value -> result = value);
		return result;
	}

	/** Build one body scope; constructor completion is distinct from its allocation result. */
	static function typeFunction(fn:HxFunctionDecl, ctx:TyperContext, functionIdentity:String, ?semanticDeclaration:TyDeclarationInfo,
			?onResult:TyMethodBodyResults.TyMethodBodyResult->Void):TyFunctionEnv {
		// Stage 3 local scope:
		// - parameters (type hints, if any)
		// - locals (not parsed yet; reserved for later)
		final params = new Array<TySymbol>();
		final functionArgs = HxFunctionDecl.getArgs(fn);
		final semanticArguments = semanticDeclaration == null ? [] : semanticDeclaration.getSignature().getArgs();
		for (argumentIndex in 0...functionArgs.length) {
			final arg = functionArgs[argumentIndex];
			final name = HxFunctionArg.getName(arg);
			final ty = argumentIndex < semanticArguments.length ? semanticArguments[argumentIndex] : typeFromHintInContext(HxFunctionArg.getTypeHint(arg), ctx);
			validateClassArguments(ty, ctx, HxFunctionDecl.getPos(fn));
			params.push(new TySymbol(name, TyFunctionParameter.declarationBodyType(ty, arg),
				TyLocalId.forSourceDeclaration(functionIdentity, argumentIndex, Parameter, name), Parameter));
		}

		final semanticBody = TypedBodyBuilder.expandStructuralStatements(HxFunctionDecl.getBody(fn));
		final locals = new Array<TySymbol>();
		final owner = ctx.currentClass();
		final typeParameters = HxFunctionDecl.getIsStatic(fn)
			|| owner == null ? [] : Std.isOfType(owner,
				TyClassInfo) ? (cast owner : TyClassInfo).getTypeParameterIds() : Std.isOfType(owner,
				TyAbstractInfo) ? (cast owner : TyAbstractInfo).getTypeParameterIds() : [];
		if (semanticDeclaration != null)
			for (parameter in semanticDeclaration.getTypeParameterIds())
				typeParameters.push(parameter);
		final retHintText = HxFunctionDecl.getReturnTypeHint(fn);
		final constructorBody = HxFunctionDecl.getName(fn) == "new" && !HxFunctionDecl.getIsStatic(fn);
		final expectedReturn = constructorBody ? TyType.fromHintText("Void") : semanticDeclaration != null ? semanticDeclaration.getSignature()
			.getReturnType() : typeFromHintInContext(retHintText, ctx);
		validateClassArguments(expectedReturn, ctx, HxFunctionDecl.getPos(fn));
		final scope = new TyFunctionEnv(HxFunctionDecl.getName(fn), params, locals, expectedReturn, TyType.unknown(), functionIdentity, null, false, 0,
			HxFunctionDecl.getIsStatic(fn), new TyControlScope(functionIdentity, TypedBodyFingerprint.forStatements(semanticBody)), null, typeParameters);
		for (argumentIndex in 0...functionArgs.length) {
			final hint = HxFunctionArg.getTypeHint(functionArgs[argumentIndex]);
			if ((hint == null || StringTools.trim(hint).length == 0) && params[argumentIndex].getType().unwrapNull().isUnknown())
				scope.getInference().registerOmittedParameter(params[argumentIndex]);
		}

		// Defaults belong to declaration entry. Infer them before the body so an
		// omitted annotation has the same concrete input type at every body use.
		for (argumentIndex in 0...functionArgs.length) {
			switch HxFunctionArg.getDefaultValue(functionArgs[argumentIndex]) {
				case NoDefault:
				case Default(expression):
					final parameter = params[argumentIndex];
					final expected = scope.getInference().localType(parameter);
					final actual = inferExprType(expression, scope, ctx, HxFunctionDecl.getPos(fn), expected);
					if (expected.hasUnknownComponent()) {
						if (!scope.getInference().constrain([EIdent(parameter.getName())], [actual], scope, ctx.getIndex()))
							throw new TyperError(ctx.getFilePath(), HxFunctionDecl.getPos(fn), "function default conflicts with parameter inference");
					} else if (isStrict() && overloadArgScore(expected, actual, [], ctx.getIndex()) < 0) {
						throw new TyperError(ctx.getFilePath(), HxFunctionDecl.getPos(fn), "function default is not compatible with its parameter");
					}
			}
		}

		var completeReturnEvidence = true;
		final returnExprTy = inferReturnType(semanticBody, scope, ctx, complete -> completeReturnEvidence = complete);
		final retTy = if (constructorBody && Std.isOfType(ctx.currentClass(), TyAbstractInfo)) {
			// An abstract constructor initializes its backing value and completes with
			// Void. Haxe permits a written result annotation, but that annotation does
			// not describe body completion. The indexed signature independently owns
			// the constructed abstract type. Retain any actual value-returning body
			// result so constructor validation still rejects it before publication.
			returnExprTy.isUnknown() ? TyType.fromHintText("Void") : returnExprTy;
		} else if (retHintText != null && retHintText.length > 0) {
			final hinted = semanticDeclaration == null
				|| constructorBody ? typeFromHintInContext(retHintText, ctx) : semanticDeclaration.getSignature().getReturnType();
			// If we couldn't infer a concrete return type (e.g. because the parser produced an
			// empty/unsupported body), keep bring-up moving by trusting the explicit hint.
			if (!returnExprTy.isUnknown()) {
				final unified = TyType.unify(hinted, returnExprTy);
				if (unified == null) {
					if (isStrict()) {
						throw new TyperError(ctx.getFilePath(), HxPos.unknown(),
							"return type hint " + hinted + " conflicts with inferred return " + returnExprTy);
					}
					// Bring-up default: trust the explicit hint and continue.
				}
			}
			hinted;
		} else {
			// No explicit hint:
			// - If we inferred a return type from `return` statements, use it.
			// - Otherwise, default to `Void` to match the common `function f() { ... }` / `static function main()` shape.
			//
			// Bring-up heuristic:
			// - The parsed declaration can retain a "first return string literal" even when
			//   best-effort body recovery cannot model a complex body (for example, a
			//   `switch` with returns in cases).
			// - If present, treat the function as returning `String` instead of collapsing to `Void`.
			if (!returnExprTy.isUnknown()) {
				returnExprTy;
			} else {
				final retStr = HxFunctionDecl.getReturnStringLiteral(fn);
				(retStr != null && retStr.length > 0) ? TyType.fromHintText("String") : TyType.fromHintText("Void");
			}
		}

		scope.sealInference();
		if (onResult != null)
			onResult({
				type: retTy,
				complete: completeReturnEvidence && !retTy.hasUnknownComponent(),
				parameters: scope.getParams().map(parameter -> parameter.getType())
			});
		return scope.withReturnTypes(retTy, returnExprTy);
	}

	/**
		Check the body once, then resolve each return through its retained lexical term.
		Later uses can constrain an omitted input after an early return reads it. Joining
		final previews keeps those returns complete without rebinding names after scope
		exit. Missing evidence still prevents publication of a checked method result.
	 */
	static function inferReturnType(statements:Array<HxStmt>, scope:TyFunctionEnv, ctx:TyperContext, ?onEvidence:Bool->Void):TyType {
		var out:Null<TyType> = null;
		var sawUnresolvedValueReturn = false;
		var sawIncompleteReturnType = false;
		// Expression-position returns belong to this same method, including inside value blocks.
		final controls = scope.requireControlScope();
		final rootTarget = controls.getRoot();
		controls.beginReturns(rootTarget, null);

		function unifyInto(t:TyType, pos:HxPos):Void {
			if (t.hasUnknownComponent())
				sawIncompleteReturnType = true;
			if (out == null) {
				out = t;
				return;
			}
			final u = TyType.unify(out, t);
			if (u == null) {
				if (isStrict()) {
					throw new TyperError(ctx.getFilePath(), pos, "incompatible return types: " + out + " vs " + t);
				}
				// Bring-up default: collapse to Dynamic to keep typing moving.
				out = TyType.fromHintText("Dynamic");
				return;
			}
			out = u;
		}

		function typeStmt(s:HxStmt):Void {
			switch (s) {
				case SBlock(stmts, _pos):
					scope.enterLexicalScope();
					for (ss in stmts)
						typeStmt(ss);
					scope.exitLexicalScope();
				case SSwitch(scrutinee, patterns, bodies, pos):
					// Check the finite source domain before accepting any case body.
					final scrutTy = inferSwitchInput(scrutinee, patterns, scope, ctx, pos);
					TySwitchTyping.check(scrutTy, patterns, bodies == null ? -1 : bodies.length, ctx, pos);
					if (patterns != null && bodies != null) {
						final count = patterns.length < bodies.length ? patterns.length : bodies.length;
						for (i in 0...count) {
							final pattern = patterns[i];
							final body = bodies[i];
							scope.enterLexicalScope();
							try {
								declarePatternBindings(scope, pattern, scrutTy, ctx, pos);
								typeStmt(body);
							} catch (error:Dynamic) {
								// Haxe permits any thrown value. This cleanup boundary neither
								// inspects nor converts it; callers receive the same failure.
								scope.exitLexicalScope();
								throw error;
							}
							scope.exitLexicalScope();
						}
					}
				case SIf(cond, thenBranch, elseBranch, pos):
					// Best-effort: ensure the condition is at least type-checked for locals.
					inferExprType(cond, scope, ctx, pos);
					scope.enterLexicalScope();
					typeStmt(thenBranch);
					scope.exitLexicalScope();
					if (elseBranch != null) {
						scope.enterLexicalScope();
						typeStmt(elseBranch);
						scope.exitLexicalScope();
					}
				case SWhile(cond, body, pos):
					inferExprType(cond, scope, ctx, pos);
					final controls = scope.requireControlScope();
					final target = controls.enter(Loop, TypedBodyFingerprint.forStatements([s]));
					scope.enterLexicalScope();
					typeStmt(body);
					scope.exitLexicalScope();
					controls.exit(target);
				case SDoWhile(body, cond, pos):
					final controls = scope.requireControlScope();
					final target = controls.enter(Loop, TypedBodyFingerprint.forStatements([s]));
					scope.enterLexicalScope();
					typeStmt(body);
					scope.exitLexicalScope();
					controls.exit(target);
					inferExprType(cond, scope, ctx, pos);
				case STry(tryBody, catches, _):
					scope.enterLexicalScope();
					typeStmt(tryBody);
					scope.exitLexicalScope();
					for (c in catches) {
						scope.enterLexicalScope();
						final writtenCatchType = StringTools.trim(c.typeHint == null ? "" : c.typeHint);
						final catchType = typeFromHintInContext(writtenCatchType.length == 0 ? "haxe.Exception" : writtenCatchType, ctx, scope);
						scope.declareLocal(c.name, catchType, CatchVariable);
						typeStmt(c.body);
						scope.exitLexicalScope();
					}
				case SBreak(_):
				case SContinue(_):
				case SForIn(name, iterable, body, pos):
					// Bring-up: type-check the iterable expression and bind the loop variable.
					final iterableTy = inferExprType(iterable, scope, ctx, pos);
					final loopTy = switch (iterable) {
						case ERange(_, _):
							TyType.fromHintText("Int");
						case _:
							// Best-effort: if we can see an `Array<T>` element type, propagate it
							// to the loop variable so string/number-heavy harness code can emit.
							final elem = arrayElementType(iterableTy);
							(elem != null && !elem.isUnknown()) ? elem : TyType.fromHintText("Dynamic");
					}
					final controls = scope.requireControlScope();
					final target = controls.enter(Loop, TypedBodyFingerprint.forStatements([s]));
					scope.enterLexicalScope();
					scope.declareLocal(name, loopTy, LoopVariable);
					typeStmt(body);
					scope.exitLexicalScope();
					controls.exit(target);
				case SForKeyValue(keyName, valueName, iterable, body, pos):
					final iterableType = inferExprType(iterable, scope, ctx, pos);
					// Array statements use the same index and element contract as expression loops.
					final bindingTypes = TySourceFor.bindingTypes(KeyValue(keyName, valueName), iterable, iterableType);
					final controls = scope.requireControlScope();
					final target = controls.enter(Loop, TypedBodyFingerprint.forStatements([s]));
					scope.enterLexicalScope();
					scope.declareLocal(keyName, bindingTypes == null ? TyType.fromHintText("String") : bindingTypes[0], LoopVariable);
					scope.declareLocal(valueName, bindingTypes == null ? TyType.fromHintText("Dynamic") : bindingTypes[1], LoopVariable);
					typeStmt(body);
					scope.exitLexicalScope();
					controls.exit(target);
				case SVar(name, typeHint, init, pos):
					final hinted = typeFromHintInContext(typeHint, ctx, scope);
					final hasWrittenType = StringTools.trim(typeHint == null ? "" : typeHint).length > 0;
					var initializerType:Null<TyType> = null;
					if (init != null) {
						// The new declaration is not visible in its own initializer.
						// A same-name read therefore selects the nearest outer local.
						initializerType = inferLocalInitializer(init, hasWrittenType ? hinted : null, scope, ctx, pos);
					}
					final initializerTerm = init == null ? null : scope.getInference().sourceTerm(init, scope);
					final sym = scope.declareLocal(name, hinted, Variable);
					if (initializerType != null) {
						final u = hasWrittenType && scope.isUntypedContext() ? hinted : assignedLocalType(sym.getType(), initializerType);
						if (u == null) {
							if (isStrict()) {
								throw new TyperError(ctx.getFilePath(), pos,
									"initializer type "
									+ initializerType
									+ " is not compatible with local "
									+ name
									+ ":"
									+ sym.getType());
							}
							// A written local type remains the semantic contract in permissive
							// bring-up mode. Conversion typing is incomplete, so replacing that
							// identity with Dynamic would erase the exact abstract needed by
							// later operator binding.
							return;
						}
						// The written local type is the static contract. Unification checks
						// whether the initializer can enter that slot; it must not replace
						// `Int` with `Null<Int>` or otherwise widen the declared identity.
						sym.setType(hasWrittenType ? hinted : u);
					}
					if (initializerTerm != null
						&& !(hasWrittenType
							&& (hinted.isDynamic()
								|| scope.isUntypedContext()
								&& initializerType != null
								&& hinted.getSemanticKey() != initializerType.getSemanticKey())))
						scope.getInference().recordLocal(sym, initializerTerm);
				case SReturnVoid(pos):
					controls.currentReturns().record(Known(TyType.fromHintText("Void")), pos);
				case SReturn(e, pos):
					final expected = scope.getReturnType();
					final t = inferExprType(e, scope, ctx, pos, expected.isUnknown() ? null : expected);
					final term = scope.getInference().sourceTerm(e, scope);
					controls.currentReturns().record(term == null ? Known(t) : term, pos);
				case SExpr(e, pos):
					inferExprType(e, scope, ctx, pos);
				case SThrow(expr, pos):
					inferExprType(expr, scope, ctx, pos);
			}
		}

		for (s in statements)
			typeStmt(s);
		for (returned in controls.finishReturns(rootTarget)) {
			final type = scope.getInference().termType(returned.term);
			if (type.isUnknown())
				sawUnresolvedValueReturn = true;
			else
				unifyInto(type, returned.position);
		}
		if (onEvidence != null)
			onEvidence(!sawUnresolvedValueReturn && !sawIncompleteReturnType);
		// If we saw no explicit returns, the true return type depends on surrounding typing rules.
		// For bootstrap bring-up we return `Unknown` here so `typeFunction` can:
		// - trust an explicit return type hint, or
		// - default to `Void` when no hint is provided.
		if (out == null)
			return sawUnresolvedValueReturn ? TyType.fromHintText("Dynamic") : TyType.unknown();
		// A value-returning path with no known value type cannot safely collapse to
		// Void merely because another branch uses a bare return.
		if (sawUnresolvedValueReturn && out.getDisplay() == "Void")
			return TyType.fromHintText("Dynamic");
		return out;
	}

	/**
		Best-effort: extract a dotted name from a field chain expression.

		Why
		- Stage3 must recognize fully-qualified type paths used directly in expressions, e.g.:
		  `runci.targets.Macro.run(args)` (no import for `runci.targets.Macro`).
		- The lazy ModuleLoader can load such modules on-demand, but only if we call
		  `ctx.resolveType(...)` with the dotted type path.

		What
		- Converts `EIdent("runci")`, `EField(_, "targets")`, `EField(_, "Macro")` into:
		  `"runci.targets.Macro"`.

		How
		- Conservative: only supports `EIdent` + `EField` chains.
		- Returns an empty string for non-chain expressions.
	**/
	static function dottedFieldPath(e:HxExpr):String {
		return switch (e) {
			case EParenthesized(inner, _) | EPrivateAccess(inner, _): dottedFieldPath(inner);
			case EIdent(name):
				name == null ? "" : name;
			case EField(obj, field):
				final base = dottedFieldPath(obj);
				base.length == 0 ? "" : (base + "." + field);
			case _:
				"";
		}
	}

	static function isUpperStartName(name:String):Bool {
		if (name == null || name.length == 0)
			return false;
		final c = name.charCodeAt(0);
		return c >= "A".code && c <= "Z".code;
	}

	static function helperCompileTimeProbeName(callee:HxExpr):Null<String> {
		final path = dottedFieldPath(callee);
		for (name in ["typeError", "typeErrorText", "getErrorMessage"])
			if (path == name || path == "HelperMacros." + name || StringTools.endsWith(path, ".HelperMacros." + name))
				return name;
		for (name in ["followWithAbstracts", "followWithAbstractsOnce"])
			if (path == name || path == "MyMacroHelper." + name || StringTools.endsWith(path, ".MyMacroHelper." + name))
				return name;
		return null;
	}

	/** Type a macro diagnostic probe without making its enclosing `try` value-producing. **/
	static function typeErrorProbe(expression:HxExpr, scope:TyFunctionEnv, ctx:TyperContext, position:HxPos):Void {
		inferExprType(expression, scope.copyForInference(), ctx, position);
	}

	public static inline var RAW_DIAGNOSTIC_PREFIX:String = "__HXHX_RAW_DIAGNOSTIC__:";

	public static function extractRawDiagnostic(message:String):Null<String> {
		if (message == null || !StringTools.startsWith(message, RAW_DIAGNOSTIC_PREFIX))
			return null;
		return message.substr(RAW_DIAGNOSTIC_PREFIX.length);
	}

	static function sourceLine(filePath:String, line:Int):String {
		if (filePath == null || filePath.length == 0 || line <= 0 || !sys.FileSystem.exists(filePath))
			return "";
		final lines = sys.io.File.getContent(filePath).split("\n");
		return line <= lines.length ? lines[line - 1] : "";
	}

	static function diagnosticFileName(filePath:String):String {
		if (filePath == null || filePath.length == 0)
			return "<unknown>";
		return haxe.io.Path.withoutDirectory(filePath);
	}

	static function isRangeIdentCode(code:Int):Bool {
		return (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || (code >= 48 && code <= 57) || code == 95;
	}

	static function callRange(filePath:String, pos:HxPos):{start:Int, end:Int} {
		final start = pos == null || pos.getColumn() <= 0 ? 0 : pos.getColumn() - 1;
		final line = sourceLine(filePath, pos == null ? 0 : pos.getLine());
		if (line.length == 0)
			return {start: start, end: start};
		var startIndex = start > 0 ? start : 0;
		if (startIndex > 0
			&& startIndex < line.length
			&& isRangeIdentCode(line.charCodeAt(startIndex - 1))
			&& isRangeIdentCode(line.charCodeAt(startIndex))) {
			startIndex -= 1;
		}
		final rest = startIndex < line.length ? line.substr(startIndex) : "";
		var end = line.length;
		final semicolon = rest.indexOf(";");
		if (semicolon >= 0)
			end = start + semicolon;
		return {start: start, end: end};
	}

	static function declarationLineRange(filePath:String, pos:HxPos):{start:Int, end:Int} {
		final start = pos == null || pos.getColumn() <= 0 ? 1 : pos.getColumn();
		final line = sourceLine(filePath, pos == null ? 0 : pos.getLine());
		if (line.length == 0)
			return {start: start, end: start};
		final end = line.length < start ? start : line.length;
		return {start: start, end: end};
	}

	static function functionNameRange(filePath:String, name:String, pos:HxPos):{start:Int, end:Int} {
		final line = sourceLine(filePath, pos == null ? 0 : pos.getLine());
		final idx = line.indexOf(name);
		final start = idx >= 0 ? idx + 1 : (pos == null || pos.getColumn() <= 0 ? 1 : pos.getColumn());
		return {start: start, end: start + name.length};
	}

	static function renderArgType(sig:TyFunSig, index:Int):String {
		final args = sig.getArgs();
		final optional = sig.getArgOptional();
		final raw = index < args.length ? args[index].getDisplay() : "Dynamic";
		if (index < optional.length && optional[index] && !StringTools.startsWith(raw, "Null<"))
			return "Null<" + raw + ">";
		return raw;
	}

	static function renderOverloadCandidate(filePath:String, sig:TyFunSig):String {
		final pos = sig.getPos();
		final range = functionNameRange(filePath, sig.getName(), pos);
		final names = sig.getArgNames();
		final optional = sig.getArgOptional();
		final args = sig.getArgs();
		final parts = new Array<String>();
		for (i in 0...args.length) {
			final argName = i < names.length ? names[i] : ("arg" + i);
			final prefix = (i < optional.length && optional[i]) ? "?" : "";
			parts.push(prefix + argName + " : " + renderArgType(sig, i));
		}
		return diagnosticFileName(filePath) + ":" + (pos == null ? 0 : pos.getLine()) + ": characters " + range.start + "-" + range.end + " : ... ("
			+ parts.join(", ") + ") -> " + sig.getReturnType().getDisplay();
	}

	static function normalizeOverloadTypeName(ty:TyType):String {
		if (ty == null)
			return "Unknown";
		var s = StringTools.trim(ty.getDisplay());
		while (StringTools.startsWith(s, "Null<") && StringTools.endsWith(s, ">"))
			s = StringTools.trim(s.substr(5, s.length - 6));
		return s;
	}

	static function normalizeFunctionTypeSegment(s:String):String {
		var out = StringTools.trim(s);
		while (StringTools.startsWith(out, "(") && StringTools.endsWith(out, ")"))
			out = StringTools.trim(out.substr(1, out.length - 2));
		return out;
	}

	static function functionTypeSegments(display:String):Array<String> {
		final trimmed = StringTools.trim(display);
		if (trimmed.indexOf("->") < 0)
			return [];
		final out = new Array<String>();
		for (part in trimmed.split("->")) {
			final segment = normalizeFunctionTypeSegment(part);
			if (segment.length == 0)
				return [];
			out.push(segment);
		}
		return out.length < 2 ? [] : out;
	}

	static function flatOverloadTypeScore(exp:String, act:String):Int {
		if (exp == act)
			return 4;
		if (exp == "Unknown" || act == "Unknown" || exp == "Dynamic" || act == "Dynamic")
			return 0;
		if ((exp == "Float" && act == "Int") || (exp == "Int" && act == "Float"))
			return 1;
		return -1;
	}

	static function functionOverloadTypeScore(exp:String, act:String):Int {
		final expParts = functionTypeSegments(exp);
		final actParts = functionTypeSegments(act);
		if (expParts.length == 0 && actParts.length == 0)
			return flatOverloadTypeScore(exp, act);
		if (expParts.length == 0 || actParts.length == 0 || expParts.length != actParts.length)
			return -1;
		var score = 0;
		for (i in 0...expParts.length) {
			final partScore = flatOverloadTypeScore(expParts[i], actParts[i]);
			if (partScore < 0)
				return -1;
			score += partScore;
		}
		return score;
	}

	/**
		Score method-generic parameters as bounded wildcards while keeping exact
		concrete overloads more specific. Nested nominal and function shapes are
		compared structurally so `Array<T>` can accept `Array<String>` without
		turning the backend carrier into the binding key.
	**/
	static function overloadArgScore(expected:TyType, actual:TyType, methodTypeParameters:Array<TyTypeParameterId>, semanticIndex:TyperIndex):Int {
		if (expected == null || actual == null)
			return -1;
		if (TyMethodGenericBinding.isInferableParameter(expected, methodTypeParameters))
			return actual.isUnknown() || actual.isDynamic() || actual.isNullLiteral() ? 0 : 1;
		if (expected != null && actual != null && expected.getSemanticKey() == actual.getSemanticKey())
			return 4;
		if (TyEnumValueCompatibility.accepts(semanticIndex, expected, actual))
			return 3;
		// Null supplies no preference between reference overloads. Scalar legality
		// still requires the target's rule or an explicit nullable parameter.
		if (actual.isNullLiteral())
			return TyNullArgument.acceptsLiteral(expected, semanticIndex) ? 0 : -1;
		if (expected.isNullable() || actual.isNullable())
			return overloadArgScore(expected.unwrapNull(), actual.unwrapNull(), methodTypeParameters, semanticIndex);
		// A caller's T satisfies Null<T> through the existing nullable relation;
		// only a different underlying destination needs a bound proof.
		// An unknown receiver parameter is still awaiting inference, not a bound
		// the caller must prove before selection can constrain that receiver.
		if (actual.isTypeParameter() && !expected.isDynamic() && !expected.isUnknown() && semanticIndex != null)
			return TyCallerConstraintProof.accepts(expected, actual, semanticIndex.getParameterBounds,
				(target, bound) -> overloadArgScore(target, bound, methodTypeParameters, semanticIndex) >= 0) ? 1 : -1;
		// Executable abstract conversions are weaker than exact or header matches.
		// Selection owns a private solver; ranking must not mutate caller inference.
		if (TyAbstractMethodConversion.select(semanticIndex, expected, actual) != null)
			return 1;
		final structural = TyStructuralArgument.compatibility(semanticIndex, expected, actual);
		if (structural != null)
			return structural == Compatible ? 3 : -1;
		if (expected.isFunction() || actual.isFunction()) {
			// Explicit Dynamic admits callable values in either direction, but must
			// not outrank a concrete signature or erase that signature's argument facts.
			if (expected.isDynamic() || actual.isDynamic())
				return 0;
			if (!expected.isFunction() || !actual.isFunction())
				return -1;
			final expectedArguments = expected.getFunctionArguments();
			final actualArguments = actual.getFunctionArguments();
			if (expectedArguments.length != actualArguments.length)
				return -1;
			var score = 0;
			for (index in 0...expectedArguments.length) {
				final argumentScore = overloadArgScore(expectedArguments[index], actualArguments[index], methodTypeParameters, semanticIndex);
				if (argumentScore < 0)
					return -1;
				score += argumentScore;
			}
			final expectedReturn = expected.getFunctionReturn();
			final actualReturn = actual.getFunctionReturn();
			if (expectedReturn == null || actualReturn == null)
				return -1;
			final returnScore = overloadArgScore(expectedReturn, actualReturn, methodTypeParameters, semanticIndex);
			return returnScore < 0 ? -1 : score + returnScore;
		}
		final expectedArguments = expected.getTypeArguments();
		final actualArguments = actual.getTypeArguments();
		if (expectedArguments.length > 0
			&& expectedArguments.length == actualArguments.length
			&& TyMethodGenericBinding.sameTypeConstructor(expected, actual)) {
			var score = 2;
			for (index in 0...expectedArguments.length) {
				final argumentScore = overloadArgScore(expectedArguments[index], actualArguments[index], methodTypeParameters, semanticIndex);
				if (argumentScore < 0)
					return -1;
				score += argumentScore;
			}
			return score;
		}
		// A concrete ancestor application is less specific than an exact match.
		// Keep generic argument equality here: inheritance must not erase binders.
		final expectedIdentity = expected.getNominalIdentity();
		final ancestor = expectedIdentity == null ? null : TyNominalAncestor.view(semanticIndex, actual, expectedIdentity);
		if (ancestor != null && ancestor.getSemanticKey() == expected.getSemanticKey())
			return 3;
		if (ancestor != null && !TyMethodGenericBinding.sameTypeConstructor(expected, actual)) {
			final ancestorScore = overloadArgScore(expected, ancestor, methodTypeParameters, semanticIndex);
			// An exact generic shape outranks a match reached through inheritance.
			return ancestorScore < 0 ? -1 : ancestorScore > 2 ? 2 : ancestorScore;
		}
		final implicitConversion = TyImplicitConversionPlan.select(semanticIndex, expected, actual);
		if (implicitConversion != null && implicitConversion.isRepresentationPreservingAbstractConversion())
			return implicitConversion.getScore();
		// Declared parameters compare by identity, never by a coincidentally equal
		// class or binder spelling. Preserve the existing incomplete-input policy.
		if (expected.isTypeParameter() || actual.isTypeParameter())
			return expected.isUnknown() || actual.isUnknown() || expected.isDynamic() || actual.isDynamic() ? 0 : -1;
		final exp = normalizeOverloadTypeName(expected);
		final act = normalizeOverloadTypeName(actual);
		return functionOverloadTypeScore(exp, act);
	}

	static function overloadCandidateScore(sig:TyFunSig, argTypes:Array<TyType>, suppliedArity:Int, methodTypeParameters:Array<TyTypeParameterId>,
			semanticIndex:TyperIndex):Int {
		if (!sig.acceptsArity(suppliedArity))
			return -1;
		var score = 0;
		for (i in 0...suppliedArity) {
			final parameter = TyCallableSignature.argumentParameter(sig, i);
			if (parameter == null)
				return -1;
			// Explicit null selects an optional argument's default just like an
			// omitted value. It supplies no type evidence for overload ranking.
			if (parameter.isOptional && i < argTypes.length && argTypes[i].isNullLiteral())
				continue;
			final argScore = overloadArgScore(parameter.type, i < argTypes.length ? argTypes[i] : TyType.unknown(), methodTypeParameters, semanticIndex);
			if (argScore < 0)
				return -1;
			score += argScore;
		}
		return TyMethodGenericBinding.argumentsAreConsistent(sig, argTypes, suppliedArity, methodTypeParameters, semanticIndex) ? score : -1;
	}

	/** Align a candidate with the same structural and conversion rules used for its overload score. */
	static function methodArgumentOrder(signature:TyFunSig, sources:Array<HxExpr>, types:Array<TyType>, parameters:Array<TyTypeParameterId>, index:TyperIndex,
			literalType:(HxExpr, TyType) -> Null<TyType>):Null<TyMethodArgumentOrder> {
		return TyMethodArgumentOrder.select(signature, sources, (source, slot, spread) -> {
			final parameter = TyCallableSignature.argumentParameter(signature, slot);
			if (spread)
				return TyAssignmentCompatibility.classifyRestSpread(parameter.type, types[source]);
			// Authored unchecked casts receive the selected destination later. Empty
			// collections likewise need the candidate's collection kind before ranking.
			if (TypedCastExpectation.isUnchecked(sources[source]))
				return Compatible;
			if (!TyStructuralArgument.literalFits(sources[source], parameter.type))
				return Incompatible;
			if (TypedAnonymousLiteral.isLiteral(sources[source]) && parameter.type.unwrapNull().isAnonymous()) {
				final literal = literalType(sources[source], parameter.type);
				return literal != null && overloadArgScore(parameter.type, literal, parameters, index) >= 0 ? Compatible : Incompatible;
			}
			if (parameter.isOptional && types[source].isNullLiteral())
				return Compatible;
			final contextual = TypedCollectionExpectation.select(sources[source], parameter.type);
			return overloadArgScore(parameter.type, contextual == null ? types[source] : contextual, parameters, index) >= 0 ? Compatible : Incompatible;
		});
	}

	static function selectedMethodCallResolution(owner:TyNominalInfo, signature:TyFunSig, argTypes:Array<TyType>, ctx:TyperContext,
			?applied:TyFunSig):TyMethodCallResolution {
		final declaration = owner.declarationForSignature(signature);
		if (declaration == null)
			return {type: signature.getReturnType(), declaration: null};
		final selected = applied == null ? signature : applied;
		final result = ctx.refinedMethodReturnType(declaration, selected.getReturnType());
		// Body results still contain their declaring method's binders. Refine before
		// specializing the selected call, and preserve an already-applied receiver result.
		final effective = new TyFunSig(selected.getName(), selected.getIsStatic(), selected.getArgNames(), selected.getArgs(), selected.getArgOptional(),
			selected.getArgRest(), result, selected.getPos());
		return {type: TyMethodGenericBinding.specializeResult(declaration, effective, argTypes, ctx.getIndex()), declaration: declaration};
	}

	/**
		Select representation-safe conversions for explicit call arguments.

		A declared input or output conversion proves that the call is legal. This
		helper emits a typed cast only when the selected conversion preserves the
		stored value. Custom conversion methods need a separate typed call model
		and must not be mistaken for storage casts here.
	**/
	static function callArgumentConversions(declaration:Null<TyDeclarationInfo>, extensionProvider:Null<TyNominalTypeId>, arguments:Array<HxExpr>,
			scope:TyFunctionEnv, ctx:TyperContext, pos:HxPos, ?sourceContexts:Array<TyType>):Array<Null<TyImplicitConversionPlan>> {
		if (declaration == null || arguments.length == 0)
			return [];
		final signature = declaration.getSignature();
		final expectedTypes = sourceContexts == null ? signature.getArgs() : sourceContexts;
		final restArguments = signature.getArgRest();
		final parameterOffset = sourceContexts != null || extensionProvider == null ? 0 : 1;
		final conversions = new Array<Null<TyImplicitConversionPlan>>();
		var found = false;
		for (argumentIndex in 0...arguments.length) {
			final parameterIndex = argumentIndex + parameterOffset;
			if (parameterIndex >= expectedTypes.length
				|| (sourceContexts == null && parameterIndex < restArguments.length && restArguments[parameterIndex])
				|| TypedCastExpectation.isUnchecked(arguments[argumentIndex])) {
				conversions.push(null);
				continue;
			}
			final actualType = inferExprType(arguments[argumentIndex], scope, ctx, pos);
			final expectedType = expectedTypes[parameterIndex];
			final conversion = TyImplicitConversionPlan.select(ctx.getIndex(), expectedType, actualType);
			final representationSafe = conversion != null && conversion.isRepresentationPreservingAbstractConversion();
			conversions.push(representationSafe ? conversion : null);
			if (representationSafe)
				found = true;
		}
		return found ? conversions : [];
	}

	/**
		Specialize parameter contexts from the complete call, including an extension
		receiver's generic evidence. Return contexts for explicit arguments only;
		the receiver already has its own expression and must not shift those contexts.
	 */
	static function callArgumentExpectedTypes(declaration:Null<TyDeclarationInfo>, extensionProvider:Null<TyNominalTypeId>, callee:HxExpr,
			arguments:Array<HxExpr>, scope:TyFunctionEnv, ctx:TyperContext, pos:HxPos):Array<TyType> {
		if (declaration == null)
			return [];
		final supplied = arguments.copy();
		if (extensionProvider != null)
			switch (callee) {
				case EField(receiver, _):
					supplied.unshift(receiver);
				case _:
					return [];
			}
		final actual = [for (argument in supplied) inferExprType(argument, scope, ctx, pos)];
		final signature = appliedCallSignature(declaration, callee, scope, ctx, pos);
		final expected = TyMethodGenericBinding.specializeParameters(declaration, signature, actual, ctx.getIndex());
		return extensionProvider == null ? expected : expected.slice(1);
	}

	/** Resolve receiver applications once at the shared call boundary, including inherited and implicit receivers. */
	static function appliedCallSignature(declaration:TyDeclarationInfo, callee:HxExpr, scope:TyFunctionEnv, ctx:TyperContext, pos:HxPos):TyFunSig {
		final signature = declaration.getSignature();
		if (declaration.getIsStatic())
			return ctx.getIndex().getMethodBodyResults().signature(declaration);
		final receiverType = callReceiverType(declaration, callee, scope, ctx, pos);
		final owner = ctx.getIndex().getByFullName(declaration.getOwner().getCanonicalName());
		return owner == null ? signature : TyNominalApplication.signature(ctx.getIndex(), owner, receiverType, signature);
	}

	/** Apply the same declaring-owner receiver to method parameters and their post-inference bounds. */
	static function callReceiverType(declaration:TyDeclarationInfo, callee:HxExpr, scope:TyFunctionEnv, ctx:TyperContext, pos:HxPos):Null<TyType> {
		if (declaration.getIsStatic())
			return null;
		return switch callee {
			case EParenthesized(inner, _) | EPrivateAccess(inner, _): callReceiverType(declaration, inner, scope, ctx, pos);
			case EField(receiver, _) | ENullSafeField(receiver, _): inferExprType(receiver, scope, ctx, pos);
			case _: currentThisType(ctx);
		};
	}

	static function resolveMethodCall(c:TyNominalInfo, field:String, isStatic:Bool, args:Array<HxExpr>, scope:TyFunctionEnv, ctx:TyperContext, pos:HxPos,
			?admittedCandidates:Array<TyFunSig>, ?receiver:TyCallReceiverContext):TyMethodCallResolution {
		if (!isStatic && admittedCandidates == null && field != "new") {
			final declaring = ctx.instanceMethodOwner(field, c);
			if (declaring != null)
				c = declaring;
		}
		function select(signature:TyFunSig, actual:Array<TyType>, order:TyMethodArgumentOrder):TyMethodCallResolution {
			final inference = scope.getInference();
			final ranked = order.rankedTypes(actual);
			if (receiver != null && !inference.constrainMember(receiver.expression, c, signature, ranked, scope, ctx.getIndex()))
				throw new TyperError(ctx.getFilePath(), pos, "selected member conflicts with generic constructor constraints");
			final applied = TyNominalApplication.signature(ctx.getIndex(), c,
				receiver == null ? null : inference.expressionType(receiver.expression, receiver.type, scope), signature);
			final declaration = c.declarationForSignature(signature);
			if (declaration != null) {
				final expected = order.sourceContexts(TyMethodGenericBinding.specializeParameters(declaration, applied, ranked, ctx.getIndex()));
				if (!scope.getInference().constrain(args, expected, scope, ctx.getIndex()))
					throw new TyperError(ctx.getFilePath(), pos, "selected call conflicts with generic constructor constraints");
			}
			final solved = [
				for (index in 0...args.length)
					scope.getInference().expressionType(args[index], actual[index], scope)
			];
			final selected = selectedMethodCallResolution(c, signature, order.rankedTypes(solved), ctx, applied);
			return {
				type: selected.type,
				declaration: selected.declaration,
				order: order,
				actual: solved
			};
		}
		final candidates = admittedCandidates == null ? (isStatic ? c.staticMethodCandidates(field) : c.instanceMethodCandidates(field)) : admittedCandidates;
		// Open method binders need operand evidence before specialization; do not turn them into rigid lambda annotations.
		final contextualCandidates = candidates.filter(signature -> {
			final declaration = c.declarationForSignature(signature);
			return declaration != null && declaration.getTypeParameterIds().length == 0;
		});
		final callbackContexts = TyLambdaArgumentContext.shared(contextualCandidates.length != candidates.length ? [] : contextualCandidates.map(signature ->
			TyNominalApplication.signature(ctx.getIndex(), c, receiver == null ? null : receiver.type, signature)),
			args.length);
		final argTypes = [
			for (index in 0...args.length)
				inferExprType(args[index], scope, ctx, pos, callbackContexts[index])
		];
		// Candidate trials must not commit context to the caller's inference state.
		function literalType(source:HxExpr, expected:TyType):Null<TyType> {
			return try {
				inferExprType(source, scope.copyForInference(), ctx, pos, expected);
			} catch (_:TyperError) {
				null;
			};
		}

		if (candidates.length == 0)
			return {type: TyType.unknown(), declaration: null};
		final arityMatches = new Array<TyFunSig>();
		var bestScore = -1;
		final bestMatches = new Array<TyFunSig>();
		var bestArguments = argTypes;
		var bestOrder:Null<TyMethodArgumentOrder> = null;
		var rejectedReceiverConstraint = false;
		var rejectedArgumentTypes = false;
		var rejectedMethodConstraint:Null<String> = null;
		for (candidate in candidates) {
			final declaration = c.declarationForSignature(candidate);
			final candidateInference = receiver == null ? scope.getInference() : scope.getInference().fork();
			final initial = TyNominalApplication.signature(ctx.getIndex(), c,
				receiver == null ? null : candidateInference.expressionType(receiver.expression, receiver.type, scope), candidate);
			final methodTypeParameters = TyMethodGenericBinding.inferableTypeParameters(declaration);
			final order = methodArgumentOrder(initial, args, argTypes, methodTypeParameters, ctx.getIndex(), literalType);
			if (order == null) {
				if (initial.acceptsArity(args.length))
					rejectedArgumentTypes = true;
				continue;
			}
			final ranked = order.rankedTypes(argTypes);
			if (receiver != null
				&& !candidateInference.constrainMember(receiver.expression, c, candidate, ranked, scope, ctx.getIndex())) {
				rejectedReceiverConstraint = true;
				continue;
			}
			final applied = TyNominalApplication.signature(ctx.getIndex(), c,
				receiver == null ? null : candidateInference.expressionType(receiver.expression, receiver.type, scope), candidate);
			// Each candidate supplies its own collection and unchecked-cast context. Keep normal
			// scoring and ambiguity checks when more than one accepts the literal.
			final contextual = argTypes.copy();
			if (declaration != null
				&& (args.filter(TypedCollectionExpectation.isEmpty).length > 0
					|| args.filter(TypedCastExpectation.isUnchecked).length > 0
					|| args.filter(TypedAnonymousLiteral.isLiteral).length > 0)) {
				final expected = order.sourceContexts(TyMethodGenericBinding.specializeParameters(declaration, applied, ranked, ctx.getIndex()));
				final rest = candidate.getArgRest();
				for (index in 0...args.length)
					if (index < expected.length && !(order.parameterIndex(index) < rest.length && rest[order.parameterIndex(index)])) {
						final selected = TypedCastExpectation.isUnchecked(args[index]) ? expected[index] : TypedAnonymousLiteral.isLiteral(args[index]) ? literalType(args[index],
							expected[index]) : TypedCollectionExpectation.select(args[index], expected[index]);
						if (selected != null)
							contextual[index] = selected;
					}
			}
			final contextualRanked = order.rankedTypes(contextual);
			if (declaration != null && applied.acceptsArity(args.length)) {
				final boundReceiver = receiver == null ? (isStatic ? null : currentThisType(ctx)) : candidateInference.expressionType(receiver.expression,
					receiver.type, scope);
				final failure = TyMethodGenericBinding.constraintFailure(declaration, applied, contextualRanked,
					bound -> TyNominalApplication.applyType(ctx.getIndex(), c, boundReceiver, bound),
					(expected, supplied) -> TyCallerConstraintProof.accepts(expected, supplied, ctx.getIndex().getParameterBounds, (expected, supplied) -> {
						if (expected.isAnonymous() && expected.getAnonymousFieldNames().length == 0)
							return TyEmptyObjectConstraint.accepts(supplied, ctx.getIndex());
						final expectedOwner = expected.getNominalIdentity();
						if (expectedOwner != null && supplied.getNominalIdentity() != null) {
							final ancestor = TyNominalAncestor.view(ctx.getIndex(), supplied, expectedOwner);
							return ancestor != null && ancestor.getSemanticKey() == expected.getSemanticKey();
						}
						return overloadArgScore(expected, supplied, [], ctx.getIndex()) >= 0;
					}), ctx.getIndex());
				if (failure != null) {
					rejectedMethodConstraint = failure;
					continue;
				}
			}
			var literalsFit = true;
			for (argumentIndex in 0...args.length) {
				final parameter = TyCallableSignature.argumentParameter(applied, order.parameterIndex(argumentIndex));
				if (parameter != null && !TyStructuralArgument.literalFits(args[argumentIndex], parameter.type))
					literalsFit = false;
			}
			final score = literalsFit ? overloadCandidateScore(applied, contextualRanked, contextualRanked.length, methodTypeParameters, ctx.getIndex()) : -1;
			if (score < 0 && applied.acceptsArity(args.length))
				rejectedArgumentTypes = true;
			if (score >= 0) {
				arityMatches.push(candidate);
				if (score > bestScore) {
					bestScore = score;
					bestArguments = contextual;
					bestOrder = order;
					bestMatches.resize(0);
					bestMatches.push(candidate);
				} else if (score == bestScore) {
					bestMatches.push(candidate);
				}
			}
		}
		if (bestMatches.length == 1 && bestScore > 0) {
			final selected = bestMatches[0];
			return select(selected, bestArguments, bestOrder);
		}
		if (bestMatches.length == 1 && arityMatches.length == 1) {
			final selected = bestMatches[0];
			return select(selected, bestArguments, bestOrder);
		}
		if (arityMatches.length > 1) {
			final range = callRange(ctx.getFilePath(), pos);
			final lines = [diagnosticFileName(ctx.getFilePath())
				+ ":"
				+ (pos == null ? 0 : pos.getLine())
				+ ": characters "
				+ range.start
				+ "-"
				+ range.end
				+ " : Ambiguous overload, candidates follow"];
			for (candidate in arityMatches)
				lines.push(renderOverloadCandidate(ctx.getFilePath(), candidate));
			throw new TyperError(ctx.getFilePath(), pos, RAW_DIAGNOSTIC_PREFIX + lines.join("\n"));
		}
		if (arityMatches.length == 1) {
			final selected = arityMatches[0];
			return select(selected, bestArguments, bestOrder);
		}

		if (rejectedMethodConstraint != null)
			throw new TyperError(ctx.getFilePath(), pos, rejectedMethodConstraint);
		if (rejectedReceiverConstraint || (receiver != null && scope.getInference().sourceTerm(receiver.expression, scope) != null))
			throw new TyperError(ctx.getFilePath(), pos, "member call conflicts with generic constructor constraints");
		if (rejectedArgumentTypes)
			throw new TyperError(ctx.getFilePath(), pos, "No compatible method signature for " + field);
		return {type: TyType.unknown(), declaration: null};
	}

	/**
		Resolve a receiver-style call through exact module `using` facts.

		The receiver becomes the first argument for ordinary overload selection.
		The result retains both the static declaration and the using provider, so
		backends do not repeat directive precedence or inheritance lookup.

		Resolution is speculative. Callers remain responsible for typing the receiver
		and arguments once in source order; this helper uses an isolated inference
		snapshot so a receiver-local declaration cannot enter the function catalog a
		second time while candidates are inspected. The owning traversal may apply
		the winning parameter contexts to its existing argument terms after selection.
	**/
	static function resolveExtensionCall(receiver:HxExpr, field:String, args:Array<HxExpr>, scope:TyFunctionEnv, ctx:TyperContext, pos:HxPos,
			applyContext:Bool = false):Null<TyExtensionCallResolution> {
		final inferenceScope = scope.copyForInference();
		final receiverType = inferExprType(receiver, inferenceScope, ctx, pos);
		final receiverOwner = nominalInfoForType(ctx.getIndex(), receiverType);
		if (receiverOwner != null && receiverOwner.instanceMethodCandidates(field).length > 0)
			return null;
		final extensionArguments = [receiver].concat(args == null ? [] : args);
		for (extension in ctx.extensionMethods(field, receiverType)) {
			final resolution = resolveMethodCall(extension.getDeclaringProvider(), extension.getMemberName(), true, extensionArguments,
				inferenceScope.copyForInference(), ctx, pos, extension.getCandidates());
			if (resolution.declaration != null) {
				if (applyContext && resolution.order != null && resolution.actual != null) {
					final expected = resolution.order.sourceContexts(TyMethodGenericBinding.specializeParameters(resolution.declaration,
						resolution.declaration.getSignature(), resolution.order.rankedTypes(resolution.actual), ctx.getIndex()));
					if (!scope.getInference().constrain(extensionArguments, expected, scope, ctx.getIndex()))
						throw new TyperError(ctx.getFilePath(), pos, "selected extension arguments conflict with their parameter types");
				}
				return {
					type: resolution.type,
					declaration: resolution.declaration,
					usingProvider: extension.getUsingProvider(),
					order: resolution.order
				};
			}
		}
		return null;
	}

	/**
		Retain one unambiguous declaration when its call arity is invalid.

		The ordinary type result stays unresolved, but the structural typed call keeps
		the exact declaration. Backends can then reject a missing required argument
		instead of replacing the call with an unbound-expression fallback.
	**/
	static function resolveCallSelectionCandidate(owner:TyNominalInfo, field:String, isStatic:Bool, args:Array<HxExpr>, scope:TyFunctionEnv, ctx:TyperContext,
			pos:HxPos, ?admittedCandidates:Array<TyFunSig>, ?receiver:TyCallReceiverContext):Null<TyMethodCallResolution> {
		final resolved = resolveMethodCall(owner, field, isStatic, args, scope, ctx, pos, admittedCandidates, receiver);
		if (resolved.declaration != null)
			return resolved;
		final candidates = admittedCandidates == null ? (isStatic ? owner.staticMethodCandidates(field) : owner.instanceMethodCandidates(field)) : admittedCandidates;
		if (candidates.length != 1)
			return null;
		final candidate = candidates[0];
		final optional = candidate.getArgOptional();
		final rest = candidate.getArgRest();
		var required = 0;
		for (index in 0...candidate.getArgs().length)
			if (!(index < optional.length && optional[index]) && !(index < rest.length && rest[index]))
				required++;
		return args.length < required ? {type: TyType.unknown(), declaration: owner.declarationForSignature(candidate)} : null;
	}

	/** Keep the winning argument order with its declaration for typed-body publication. */
	static function resolveCallSelection(callee:HxExpr, args:Array<HxExpr>, scope:TyFunctionEnv, ctx:TyperContext, pos:HxPos):Null<TyMethodCallResolution> {
		switch (callee) {
			case EParenthesized(inner, _) | EPrivateAccess(inner, _):
				return resolveCallSelection(inner, args, scope, ctx, pos);
			case EIdent(name):
				if (scope.resolveSymbol(name) != null)
					return null;
				final owner = ctx.currentClass();
				final instanceOwner = !scope.isStaticContext() ? ctx.instanceMethodOwner(name) : null;
				if (instanceOwner != null)
					return resolveCallSelectionCandidate(instanceOwner, name, false, args, scope, ctx, pos);
				if (owner != null && owner.staticMethodCandidates(name).length > 0)
					return resolveCallSelectionCandidate(owner, name, true, args, scope, ctx, pos);
				final moduleEnumConstructor = ctx.moduleEnumConstructorMethod(name);
				if (moduleEnumConstructor != null)
					return resolveCallSelectionCandidate(moduleEnumConstructor.getProvider(), moduleEnumConstructor.getMemberName(), true, args, scope, ctx,
						pos, moduleEnumConstructor.getCandidates());
				final importedMethod = ctx.importedStaticMethod(name);
				return importedMethod == null ? null : resolveCallSelectionCandidate(importedMethod.getProvider(), importedMethod.getMemberName(), true, args,
					scope, ctx, pos, importedMethod.getCandidates());
			case EEnumValue(name):
				final moduleEnumConstructor = ctx.moduleEnumConstructorMethod(name);
				if (moduleEnumConstructor != null)
					return resolveCallSelectionCandidate(moduleEnumConstructor.getProvider(), moduleEnumConstructor.getMemberName(), true, args, scope, ctx,
						pos, moduleEnumConstructor.getCandidates());
				final importedMethod = ctx.importedStaticMethod(name);
				return importedMethod == null ? null : resolveCallSelectionCandidate(importedMethod.getProvider(), importedMethod.getMemberName(), true, args,
					scope, ctx, pos, importedMethod.getCandidates());
			case EField(object, field) | ENullSafeField(object, field):
				switch (object) {
					case EIdent(typeOrValue):
						final staticOwner = scope.resolveSymbol(typeOrValue) == null
							&& isUpperStartName(typeOrValue) ? ctx.resolveType(typeOrValue) : null;
						if (staticOwner != null) return resolveCallSelectionCandidate(staticOwner, field, true, args, scope, ctx, pos);
					case _:
						final dotted = dottedFieldPath(object);
						if (dotted.length > 0) {
							final parts = dotted.split(".");
							final last = parts.length == 0 ? "" : parts[parts.length - 1];
							if (scope.resolveSymbol(parts[0]) == null && isUpperStartName(last)) {
								final staticOwner = ctx.resolveType(dotted);
								if (staticOwner != null)
									return resolveCallSelectionCandidate(staticOwner, field, true, args, scope, ctx, pos);
							}
						}
				}

				final receiverType = inferExprType(object, scope, ctx, pos);
				final index = ctx.getIndex();
				final owner = nominalInfoForType(index, receiverType);
				return owner == null ? null : resolveCallSelectionCandidate(owner, field, false, args, scope, ctx, pos, null,
					{expression: object, type: receiverType});
			case _:
		}
		return null;
	}

	static function functionReferenceType(sig:TyFunSig):TyType {
		return TyType.functionSignature([
			for (index in 0...sig.getArgs().length)
				TyCallableSignature.argumentParameter(sig, index)
		], sig.getReturnType());
	}

	/**
		Named functions and ordinary typed class literals are not writable locals.
		Explicit untyped syntax may replace a runtime type binding, but it does not
		remove a named local function's write restriction.
		Resolve the nearest declaration so a writable shadow or copied callable
		does not inherit the original function name's write restriction.
	 */
	static function assertWritableLocal(expression:HxExpr, scope:TyFunctionEnv, ctx:TyperContext, pos:HxPos):Void {
		if (!scope.isUntypedContext()
			&& !expression.match(EUntyped(_))
			&& TypedRuntimeTypeResolver.resolve(expression, scope, ctx, ValueExpression) != null)
			throw new TyperError(ctx.getFilePath(), pos, "Invalid assign");
		switch (expression) {
			case EIdent(name):
				final symbol = scope.resolveSymbol(name);
				if (symbol != null && symbol.getKind() == NamedFunction)
					throw new TyperError(ctx.getFilePath(), pos, "Cannot access function " + name + " for writing");
			case EParenthesized(_, position):
				throw new TyperError(ctx.getFilePath(), position, "Invalid assign");
			case EPrivateAccess(inner, position):
				assertWritableLocal(inner, scope, ctx, position);
			case EUntyped(inner):
				scope.withUntyped(() -> {
					assertWritableLocal(inner, scope, ctx, pos);
					return true;
				});
			case _:
		}
	}

	/**
		Infer a function-value call without inventing a declaration identity.
		A selected structural callable reuses the already inferred receiver type;
		repeating receiver inference could allocate another generic occurrence.
	**/
	static function inferFunctionValueCall(callee:HxExpr, args:Array<HxExpr>, scope:TyFunctionEnv, ctx:TyperContext, pos:HxPos, ?expectedResult:TyType,
			?selectedCallable:TyType):TyType {
		switch (callee) {
			case ELambda(names, body, signature) if (names.length == args.length):
				final argumentTypes = [for (argument in args) inferExprType(argument, scope, ctx, pos)];
				return inferLambdaType(names, body, argumentTypes, scope, ctx, pos, signature, expectedResult).getFunctionReturn();
			case ESourceFunction(facts, body, defaults, sourcePosition) if (facts.getArguments().length == args.length):
				final argumentTypes = [for (argument in args) inferExprType(argument, scope, ctx, pos)];
				final context = TyType.functionType(argumentTypes, expectedResult == null ? TyType.unknown() : expectedResult);
				return inferSourceFunctionType(callee, facts, body, defaults, scope, ctx, sourcePosition, context).getFunctionReturn();
			case _:
		}
		final calleeType = selectedCallable == null ? inferExprType(callee, scope, ctx, pos) : selectedCallable;
		final argumentTypes = [
			for (argument in args)
				switch (argument) {
					case ECall(EIdent("__hxhx_spread"), [container]):
						inferExprType(container, scope, ctx, pos);
					case _:
						inferExprType(argument, scope, ctx, pos);
				}
		];
		final captured = scope.getInference()
			.callCaptured(callee, args, argumentTypes, scope, ctx.getIndex(),
				(expected, supplied) -> overloadArgScore(expected, supplied, [], ctx.getIndex()) >= 0);
		if (captured != null)
			return captured;
		if (!calleeType.isFunction())
			return TyType.unknown();
		final signature = TyCallableSignature.fromFunctionValue(calleeType);
		final kinds:Array<TyCallAlignment.TyCallOperandKind> = [
			for (argument in args)
				argument.match(ECall(EIdent("__hxhx_spread"), [_])) ? Spread : Value
		];
		switch (TyCallbackArgumentContext.resolve(signature, args, argumentTypes, kinds, scope, ctx.getIndex(), callee)) {
			case Rejected(failure):
				throw new TyperError(ctx.getFilePath(), pos, TyCallValidation.describeFailure(failure, signature, argumentTypes, kinds));
			case Aligned(_):
		}
		return signature.getResultType();
	}

	/**
		Type an authored function while retaining its body and exact return destination.
		Full functions collect explicit returns. Only arrows use normal body completion
		as an implicit result. Defaults are checked separately from body completion.
	 */
	static function inferSourceFunctionType(source:HxExpr, facts:HxSourceFunction, body:HxExpr, defaults:Array<HxExpr>, scope:TyFunctionEnv, ctx:TyperContext,
			pos:HxPos, ?context:TyType):TyType {
		facts.assertDefaultCount(defaults.length);
		final retained = scope.getInference().sourceFunctionType(source);
		if (retained != null)
			return retained;
		final signature = facts.getSignature();
		final parameters = signature.getParameters();
		final names = facts.getArguments();
		final contextual = context != null
			&& context.isFunction()
			&& context.getFunctionArguments().length == names.length ? context : null;
		final argumentTypes = new Array<TyType>();
		for (index in 0...parameters.length) {
			final parameter = parameters[index];
			final hint = parameter.typeHint;
			final selected = hint == null ? (contextual == null ? TyType.unknown() : contextual.getFunctionArguments()[index]) : typeFromHintInContext(parameter.isRest ? "haxe.Rest<"
				+ hint + ">" : hint, ctx, scope);
			// Upstream exposes nullable body variables for optional and defaulted source parameters.
			argumentTypes.push((parameter.isOptional || parameter.hasDefault)
				&& !selected.isNullable() ? TyType.nullable(selected) : selected);
		}
		final written = signature.getReturnTypeHint();
		final contextReturn = contextual == null ? null : contextual.getFunctionReturn();
		final expected = written == null ? (contextReturn == null
			|| contextReturn.isUnknown() ? null : contextReturn) : typeFromHintInContext(written, ctx, scope);
		final declaredName = facts.getDeclaredName();
		final declared = declaredName == null ? null : scope.declareLocal(declaredName,
			TyCallableSignature.sourceFunctionType(names, signature, argumentTypes, expected == null ? TyType.unknown() : expected), NamedFunction);
		final controls = scope.requireControlScope();
		final target = controls.enter(Function, TypedBodyFingerprint.forExpression(source));
		scope.enterLexicalScope();
		final parameterSymbols = [
			for (index in 0...names.length)
				scope.declareLocal(names[index], argumentTypes[index], LambdaParameter)
		];
		final defaultIndexes = facts.getDefaultParameterIndexes();
		for (index in 0...defaults.length) {
			final valueType = inferExprType(defaults[index], scope, ctx, pos);
			final parameterIndex = defaultIndexes[index];
			final parameterType = argumentTypes[parameterIndex];
			if (isStrict() && !parameterType.unwrapNull().isUnknown() && TyType.unify(parameterType, valueType) == null)
				throw new TyperError(ctx.getFilePath(), pos, "function default is not compatible with its parameter");
			if (parameterType.unwrapNull().isUnknown()) {
				final selected = valueType.isNullable() ? valueType : TyType.nullable(valueType);
				argumentTypes[parameterIndex] = selected;
				parameterSymbols[parameterIndex].setType(selected);
			}
		}
		controls.beginReturns(target, expected);
		final bodyType = TyEmptySourceGroup.isEmpty(body) ? TyType.fromHintText("Void") : inferExprType(body, scope, ctx, pos,
			facts.getKind() == Arrow ? expected : null);
		final returned = new Array<TyType>();
		for (evidence in controls.finishReturns(target)) {
			final type = scope.getInference().termType(evidence.term);
			TyLambdaResultContract.check(type, expected, ctx.getFilePath(), evidence.position, isStrict());
			returned.push(type);
		}
		if (facts.getKind() == Arrow && !bodyType.isNoNormalCompletion()) {
			TyLambdaResultContract.check(bodyType, expected, ctx.getFilePath(), pos, isStrict());
			returned.push(bodyType);
		}
		var inferred = TyType.fromHintText("Void");
		if (returned.length > 0) {
			inferred = returned[0];
			for (index in 1...returned.length) {
				final unified = TyType.unify(inferred, returned[index]);
				if (unified == null && isStrict())
					throw new TyperError(ctx.getFilePath(), pos, "function returns have incompatible types");
				inferred = unified == null ? TyType.fromHintText("Dynamic") : unified;
			}
		}
		final selected = expected == null ? inferred : expected;
		if (facts.getKind() != Arrow && !bodyType.isNoNormalCompletion())
			TyLambdaResultContract.check(TyType.fromHintText("Void"), selected, ctx.getFilePath(), pos, isStrict());
		for (index in 0...parameterSymbols.length)
			argumentTypes[index] = scope.getInference().localType(parameterSymbols[index]);
		scope.exitLexicalScope();
		controls.exit(target);
		final callableType = TyCallableSignature.sourceFunctionType(names, signature, argumentTypes, selected);
		if (declared != null)
			declared.setType(callableType);
		scope.getInference().recordSourceFunction(source, callableType);
		return callableType;
	}

	/** Type a lambda with the parameter contract supplied by its call or written signature. */
	static function inferLambdaType(names:Array<String>, body:HxExpr, argumentTypes:Array<TyType>, scope:TyFunctionEnv, ctx:TyperContext, pos:HxPos,
			?signature:HxLambdaSignature, ?contextResult:TyType):TyType {
		final selectedArguments = argumentTypes.copy();
		if (signature != null) {
			final parameters = signature.getParameters();
			if (parameters.length != names.length)
				throw new TyperError(ctx.getFilePath(), pos, "lambda signature does not match its parameters");
			for (index in 0...parameters.length) {
				final parameter = parameters[index];
				if (parameter.typeHint != null) {
					var hint = parameter.typeHint;
					if (parameter.isRest && !StringTools.startsWith(hint, "haxe.Rest<") && !StringTools.startsWith(hint, "Rest<"))
						hint = "haxe.Rest<" + hint + ">";
					selectedArguments[index] = typeFromHintInContext(hint, ctx, scope);
				}
			}
		}
		scope.enterLexicalScope();
		final parameterSymbols = [
			for (index in 0...names.length)
				scope.declareLocal(names[index], selectedArguments[index], LambdaParameter)
		];
		final writtenResult = signature == null ? null : signature.getReturnTypeHint();
		final writtenType = writtenResult == null ? null : typeFromHintInContext(writtenResult, ctx, scope);
		final expected = writtenType == null ? contextResult : writtenType;
		final result = if (TyEmptySourceGroup.isEmpty(body)) {
			final empty = TyType.fromHintText("Void");
			TyLambdaResultContract.check(empty, expected, ctx.getFilePath(), pos, isStrict());
			empty;
		} else {
			inferExprType(body, scope, ctx, pos, expected);
		};
		for (index in 0...parameterSymbols.length)
			selectedArguments[index] = scope.getInference().localType(parameterSymbols[index]);
		scope.exitLexicalScope();
		// A contextual return contract does not change the Dynamic body's own type.
		// Targets must adapt that body value when returning through this callable.
		final contextualResult = result.isDynamic()
			&& contextResult != null
			&& !contextResult.hasUnknownComponent() ? contextResult : result;
		final selectedResult = writtenType == null ? contextualResult : writtenType;
		return TyCallableSignature.sourceFunctionType(names, signature, selectedArguments, selectedResult);
	}

	/**
		Select the value type produced by the parser's expression-level try sentinel.

		A normally completing concrete try branch remains authoritative when a
		`Dynamic` catch branch flows into it. This matches Haxe's typed expression:
		the catch expression itself stays Dynamic, while the complete try expression
		keeps the concrete successful result. Other branch combinations continue to
		use the typer's ordinary bounded unification.
	**/
	static function inferStructuralTryResult(args:Array<HxExpr>, scope:TyFunctionEnv, ctx:TyperContext, pos:HxPos, ?expectedResult:TyType):Null<TyType> {
		final structure = switch (args) {
			case [ELambda(tryArguments, tryBody, signature), EArrayDecl(entries), tail] if (tryArguments.length == 0):
				final lambda:HxExpr = ELambda(tryArguments, tryBody, signature);
				{tryLambda: lambda, catches: entries, continuation: tail};
			case _: null;
		};
		if (structure == null)
			return null;

		final handlers = new Array<{name:String, typeHint:String, body:HxExpr}>();
		for (entry in structure.catches)
			switch (entry) {
				case EArrayDecl([EString(name), EString(typeHint), ELambda(handlerArguments, handlerBody)])
					if (handlerArguments.length == 1 && handlerArguments[0] == name):
					handlers.push({name: name, typeHint: typeHint, body: handlerBody});
				case _:
					return null;
			}

		var result = inferFunctionValueCall(structure.tryLambda, [], scope, ctx, pos, expectedResult);
		if (result == null)
			result = TyType.unknown();
		for (handler in handlers) {
			// The parser uses a lambda to carry the handler body, but its parameter
			// is a catch declaration with a source-owned type, not an untyped lambda argument.
			scope.enterLexicalScope();
			final hint = StringTools.trim(handler.typeHint);
			scope.declareLocal(handler.name, typeFromHintInContext(hint.length == 0 ? "haxe.Exception" : hint, ctx, scope), CatchVariable);
			final catchResult = inferExprType(handler.body, scope, ctx, pos, expectedResult);
			scope.exitLexicalScope();
			if (!result.isUnknown() && !result.isDynamic() && catchResult.isDynamic())
				continue;
			final unified = TyType.unify(result, catchResult);
			result = unified == null ? TyType.fromHintText("Dynamic") : unified;
		}
		inferExprType(structure.continuation, scope, ctx, pos);
		return result;
	}

	static function inferNullCoalesceType(left:TyType, right:TyType):TyType {
		if (right != null && right.isNoNormalCompletion())
			return left == null || left.isUnknown() ? TyType.unknown() : (left.isNullWrapped() ? left.unwrapNull() : left);
		if (right != null && !right.isUnknown())
			return right;
		if (left != null && !left.isUnknown())
			return left.isNullWrapped() ? left.unwrapNull() : left;
		return TyType.unknown();
	}

	static function currentStaticMethodReferenceType(name:String, ctx:TyperContext):Null<TyType> {
		final c = ctx.currentClass();
		if (c == null)
			return null;
		final candidates = c.staticMethodCandidates(name);
		if (candidates.length != 1)
			return null;
		final declaration = c.declarationForSignature(candidates[0]);
		return TyCallableSignature.fromDeclaration(declaration, ctx.getIndex().getMethodBodyResults().signature(declaration)).getFunctionType();
	}

	/** Bare method values use the lexical instance and its first declaring ancestor. */
	static function currentInstanceMethodReferenceType(name:String, scope:TyFunctionEnv, ctx:TyperContext):Null<TyType> {
		final owner = scope.isStaticContext() ? null : ctx.instanceMethodOwner(name);
		if (owner == null)
			return null;
		final candidates = owner.instanceMethodCandidates(name);
		return candidates.length == 1 ? functionReferenceType(TyNominalApplication.signature(ctx.getIndex(), owner, currentThisType(ctx),
			candidates[0])) : null;
	}

	/**
		Select an unambiguous static method without inventing a call or its arguments.
		Lexical locals and data fields take precedence. Instance receivers and
		overloaded method values need separate contextual binding and remain outside
		this selection boundary.
	 */
	static function resolveStaticMethodValue(expression:HxExpr, scope:TyFunctionEnv, ctx:TyperContext):Null<TyDeclarationInfo> {
		function select(owner:TyNominalInfo, name:String):Null<TyDeclarationInfo> {
			if (owner == null || owner.fieldInfo(name) != null)
				return null;
			final candidates = owner.staticMethodCandidates(name);
			return candidates.length == 1 ? owner.declarationForSignature(candidates[0]) : null;
		}
		return switch (expression) {
			case EIdent(name) | EEnumValue(name):
				if (scope.resolveSymbol(name) != null
					|| currentFieldReferenceType(name, ctx) != null
					|| (!scope.isStaticContext() && ctx.instanceMethodOwner(name) != null)
					|| ctx.importedStaticField(name) != null) {
					null;
				} else {
					final current = select(ctx.currentClass(), name);
					final imported = current == null ? ctx.importedStaticMethod(name) : null;
					current != null ? current : imported != null
					&& imported.getCandidates().length == 1 ? imported.getProvider().declarationForSignature(imported.getCandidates()[0]) : null;
				}
			case EField(object, name):
				final target = TypedRuntimeTypeResolver.resolve(object, scope, ctx, ValueExpression);
				final identity = target == null ? null : target.getDeclarationIdentity();
				identity == null ? null : select(ctx.getIndex().getByFullName(identity.getCanonicalName()), name);
			case _: null;
		};
	}

	static function importedStaticMethodReferenceType(name:String, ctx:TyperContext):Null<TyType> {
		final importedMethod = ctx.importedStaticMethod(name);
		if (importedMethod == null)
			return null;
		final candidates = importedMethod.getCandidates();
		if (candidates.length != 1)
			return null;
		final declaration = importedMethod.getProvider().declarationForSignature(candidates[0]);
		return TyCallableSignature.fromDeclaration(declaration, ctx.getIndex().getMethodBodyResults().signature(declaration)).getFunctionType();
	}

	/** Select exact instance methods; bare reads require a lexical instance rather than a static context. */
	static function resolveInstanceMethodValue(expression:HxExpr, scope:TyFunctionEnv, ctx:TyperContext, position:HxPos):Null<TyDeclarationInfo> {
		return switch (expression) {
			case EIdent(name) | EEnumValue(name):
				final owner = scope.isStaticContext()
					|| scope.resolveSymbol(name) != null
					|| currentFieldReferenceType(name, ctx) != null ? null : ctx.instanceMethodOwner(name);
				final candidates = owner == null ? [] : owner.instanceMethodCandidates(name);
				candidates.length == 1 ? owner.declarationForSignature(candidates[0]) : null;
			case EField(receiver, name):
				final target = TypedRuntimeTypeResolver.resolve(receiver, scope, ctx, ValueExpression);
				if (target != null) {
					null;
				} else {
					final receiverOwner = switch (receiver) {
						case EThis: nominalInfoForType(ctx.getIndex(), currentThisType(ctx));
						case _: nominalInfoForType(ctx.getIndex(), inferExprType(receiver, scope.copyForInference(), ctx, position));
					};
					final owner = receiverOwner == null
						|| receiverOwner.fieldInfo(name) != null ? null : ctx.instanceMethodOwner(name, receiverOwner);
					if (owner == null) {
						null;
					} else {
						final candidates = owner.instanceMethodCandidates(name);
						candidates.length == 1 ? owner.declarationForSignature(candidates[0]) : null;
					}
				}
			case _: null;
		};
	}

	/** Return the current class field selected by ordinary value lookup. **/
	static function currentFieldReferenceType(name:String, ctx:TyperContext):Null<TyType> {
		final current = ctx.currentClass();
		if (current == null)
			return null;
		final own = current.fieldInfo(name);
		final inherited = own == null ? ctx.instanceField(name, current) : null;
		final selected = inherited == null ? own : inherited;
		return selected == null ? null : TyNominalApplication.fieldType(ctx.getIndex(), selected, currentThisType(ctx));
	}

	/**
		Resolve the exact field declaration selected by the current typed subset.

		This follows the same current-class, fully qualified static, and typed receiver
		paths as expression typing. The immutable field record then travels with the
		typed read so later analyses do not have to reconstruct the receiver path.
	**/
	static function resolveFieldDeclaration(expression:HxExpr, scope:TyFunctionEnv, ctx:TyperContext, pos:HxPos):Null<TyFieldInfo> {
		return switch (expression) {
			case EIdent(name) | EEnumValue(name):
				if (scope.resolveSymbol(name) != null) {
					null;
				} else {
					final current = ctx.currentClass();
					final own = current == null ? null : current.fieldInfo(name);
					final localField = own != null || scope.isStaticContext() ? own : ctx.instanceField(name, current);
					final enumField = localField == null ? ctx.moduleEnumConstructorField(name) : null;
					localField != null ? localField : enumField != null ? enumField : ctx.importedStaticField(name);
				}
			case EField(object, field):
				final dotted = dottedFieldPath(object);
				final dottedParts = dotted.split(".");
				final dottedLast = dottedParts.length == 0 ? "" : dottedParts[dottedParts.length - 1];
				final staticOwner = dotted.length == 0
					|| scope.resolveSymbol(dottedParts[0]) != null
					|| !isUpperStartName(dottedLast) ? null : ctx.resolveType(dotted);
				if (staticOwner != null) {
					final selected = staticOwner.fieldInfo(field);
					selected != null
					&& selected.getIsStatic() ? selected : null;
				} else {
					final owner = switch (object) {
						case EThis: nominalInfoForType(ctx.getIndex(), currentThisType(ctx));
						case _: nominalInfoForType(ctx.getIndex(), inferExprType(object, scope.copyForInference(), ctx, pos));
					};
					owner == null ? null : ctx.instanceField(field, owner);
				}
			case ENullSafeField(object, field):
				resolveFieldDeclaration(EField(object, field), scope, ctx, pos);
			case _:
				null;
		};
	}

	/** Untyped local annotations may reinterpret complete values, but still solve compatible omitted type arguments. */
	static function inferLocalInitializer(initializer:HxExpr, expected:Null<TyType>, scope:TyFunctionEnv, ctx:TyperContext, pos:HxPos):TyType {
		if (expected == null || !scope.isUntypedContext())
			return inferExprType(initializer, scope, ctx, pos, expected);
		final actual = inferExprType(initializer, scope, ctx, pos);
		// A rejected candidate leaves the initializer's original constraints intact.
		if (actual.hasUnknownComponent()
			&& scope.getInference().canReceiveContext(initializer, scope)
			&& scope.getInference().constrain([initializer], [expected], scope, ctx.getIndex()))
			return scope.getInference().expressionType(initializer, actual, scope);
		return actual;
	}

	/** Validate result-producing branches before their types are merged, without revisiting lexical declarations. */
	static function inferExprType(expr:HxExpr, scope:TyFunctionEnv, ctx:TyperContext, pos:HxPos, ?expectedResult:TyType):TyType {
		final capture:Null<TyMethodCallCapture> = expr.match(ECall(_, _)) ? {selection: null} : null;
		var result = inferExprValueType(expr, scope, ctx, pos, expectedResult, capture);
		// Only an unresolved call inside authored untyped syntax gains a result
		// variable. Known calls retain their declared argument and result types.
		if (result.isUnknown() && scope.isUntypedContext() && expr.match(ECall(_, _)))
			result = scope.getInference().untypedResult(expr);
		// Field requirements belong to the receiver's inference variable, including
		// reads through aliases. Resolve that shared fact before applying context.
		result = scope.getInference().expressionType(expr, result, scope);
		var selectedGenericResult = false;
		// A concrete result does not prove that a selected generic call's input
		// parameters are solved. Inspect the whole selected callable before seal.
		switch expr {
			case ECall(callee, arguments):
				final selection = capture.selection;
				final declaration = selection == null ? null : selection.declaration;
				// An omitted result annotation belongs to body inference. It is not a
				// declared method parameter that this call can instantiate or solve.
				selectedGenericResult = declaration != null
					&& declaration.getTypeParameterIds().length > 0
					&& !declaration.getSignature().getReturnType().isUnknown();
				if (selectedGenericResult) {
					if (selection.order == null)
						throw new TyperError(ctx.getFilePath(), pos, "generic call requires a complete selected argument mapping");
					final signature = appliedCallSignature(declaration, callee, scope, ctx, pos);
					final actual = selection.actual;
					if (actual == null || actual.length != arguments.length)
						throw "selected generic call lost its typed source operands";
					final ranked = selection.order.rankedTypes(actual);
					final contexts = TyMethodGenericBinding.specializeParameters(declaration, signature, ranked, ctx.getIndex());
					if (result.hasUnknownComponent() || contexts.filter(type -> type.hasUnknownComponent()).length > 0) {
						result = scope.getInference().inferDirectCall({
							expression: expr,
							declaration: declaration,
							callable: TyMethodGenericBinding.inferenceCallable(declaration, signature, ranked, ctx.getIndex()),
							signature: signature,
							order: selection.order,
							arguments: arguments,
							actual: actual,
							environment: scope,
							index: ctx.getIndex(),
							accepts: (expected, supplied) -> overloadArgScore(expected, supplied, [], ctx.getIndex()) >= 0
						});
						if (expectedResult != null && !scope.getInference().constrain([expr], [expectedResult], scope, ctx.getIndex()))
							throw new TyperError(ctx.getFilePath(), pos, "generic call conflicts with its expected type");
						result = scope.getInference().expressionType(expr, result, scope);
					}
				}
			case _:
		}
		if (result.isFunction()) {
			final staticMethod = resolveStaticMethodValue(expr, scope, ctx);
			final method = staticMethod == null ? resolveInstanceMethodValue(expr, scope, ctx, pos) : staticMethod;
			if (method != null && method.getTypeParameterIds().length > 0) {
				result = scope.getInference().captureMethod(expr, result, method.getTypeParameterIds(), method.getSignature());
				if (expectedResult != null && !scope.getInference().constrain([expr], [expectedResult], scope, ctx.getIndex()))
					throw new TyperError(ctx.getFilePath(), pos, "generic callback conflicts with its expected type");
				result = scope.getInference().expressionType(expr, result, scope);
			}
		}
		// A local or alias keeps its initializer's inference term. Written return
		// and local annotations constrain that same term without allocating again
		// or replaying the initializer. Complete values still use ordinary checks.
		if (expectedResult != null && result.hasUnknownComponent() && scope.getInference().canReceiveContext(expr, scope)) {
			if (!scope.getInference().constrain([expr], [expectedResult], scope, ctx.getIndex()))
				throw new TyperError(ctx.getFilePath(), pos, "generic value conflicts with its expected type");
			result = scope.getInference().expressionType(expr, result, scope);
		}
		if (expectedResult != null
			&& !expectedResult.hasUnknownComponent()
			&& !result.hasUnknownComponent()
			&& (selectedGenericResult || scope.getInference().canReceiveContext(expr, scope))
			&& overloadArgScore(expectedResult, result, [], ctx.getIndex()) < 0)
			throw new TyperError(ctx.getFilePath(), pos, "inferred value "
				+ result.getDisplay()
				+ " is not compatible with "
				+ expectedResult.getDisplay());
		if (expectedResult != null
			&& expectedResult.unwrapNull().isAnonymous()
			&& result.unwrapNull().getNominalIdentity() != null
			&& !result.hasUnknownComponent()) {
			final validation = new TyInferenceSolver("structural-assignment");
			if (!TyStructuralConstraint.constrain(ctx.getIndex(), validation, TyInferenceSolver.fromType(result.unwrapNull()), expectedResult.unwrapNull())
				&& TyAbstractMethodConversion.select(ctx.getIndex(), expectedResult, result) == null)
				throw new TyperError(ctx.getFilePath(), pos, "class value does not satisfy its structural type");
		}
		if (expectedResult != null)
			TyLambdaResultContract.check(result, expectedResult, ctx.getFilePath(), pos, isStrict());
		return result;
	}

	/** Retain an ephemeral selection from this traversal; this is not a cache or another overload query. */
	static function selectedCallType(selection:TyMethodCallResolution, capture:Null<TyMethodCallCapture>):TyType {
		if (capture != null)
			capture.selection = selection;
		return selection.type;
	}

	static function inferExprValueType(expr:HxExpr, scope:TyFunctionEnv, ctx:TyperContext, pos:HxPos, expectedResult:Null<TyType>,
			?capture:TyMethodCallCapture):TyType {
		switch HxLiteralCharacterCode.resolve(expr) {
			case Character(_):
				return TyType.fromHintText("Int");
			case InvalidLiteral:
				throw new TyperError(ctx.getFilePath(), pos, "String must be a single UTF8 char");
			case NotApplicable:
		}
		final runtimeTarget = TypedRuntimeTypeResolver.resolve(expr, scope, ctx, ValueExpression);
		if (runtimeTarget != null)
			return runtimeTarget.getValueType();
		return switch (expr) {
			case EParenthesized(inner, sourcePosition) | EPrivateAccess(inner, sourcePosition):
				inferExprType(inner, scope, ctx, sourcePosition, expectedResult);
			case ESourceFunction(facts, body, defaults, sourcePosition):
				inferSourceFunctionType(expr, facts, body, defaults, scope, ctx, sourcePosition, expectedResult);
			case ESourceTry(catches, bodies, sourcePosition):
				if (catches.length == 0 || bodies.length != catches.length + 1)
					throw "source try requires one body and ordered handlers";
				scope.enterLexicalScope();
				var result = inferExprType(bodies[0], scope, ctx, sourcePosition, expectedResult);
				scope.exitLexicalScope();
				for (index in 0...catches.length) {
					final entry = catches[index];
					scope.enterLexicalScope();
					final hint = StringTools.trim(entry.getTypeHint());
					final type = typeFromHintInContext(hint.length == 0 ? "haxe.Exception" : hint, ctx, scope);
					scope.declareLocal(entry.getName(), type, CatchVariable);
					final handler = inferExprType(bodies[index + 1], scope, ctx, entry.getPosition(), expectedResult);
					scope.exitLexicalScope();
					final joined = TyType.unify(result, handler);
					result = joined == null ? TyType.fromHintText("Dynamic") : joined;
				}
				result;
			case ELoweredControl(_, _, _, _):
				throw "executable control cannot re-enter source typing";
			case ESourceFor(binding, iterable, body, sourcePosition):
				final loop = TySourceFor.infer({
					expression: expr,
					scope: scope,
					filePath: ctx.getFilePath(),
					typeExpression: value -> inferExprType(value, scope, ctx, sourcePosition),
					typeBody: value -> inferExprType(value, scope, ctx, sourcePosition)
				});
				loop.iterableType.isNoNormalCompletion() ? TyType.noNormalCompletion() : TyType.fromHintText("Void");
			case ESourceIf(condition, whenTrue, whenFalse, sourcePosition):
				final conditionType = inferExprType(condition, scope, ctx, sourcePosition, TyType.fromHintText("Bool"));
				scope.enterLexicalScope();
				final trueType = inferExprType(whenTrue, scope, ctx, sourcePosition, whenFalse == null ? null : expectedResult);
				scope.exitLexicalScope();
				var falseType = TyType.fromHintText("Void");
				if (whenFalse != null) {
					scope.enterLexicalScope();
					falseType = inferExprType(whenFalse, scope, ctx, sourcePosition, expectedResult);
					scope.exitLexicalScope();
				}
				if (conditionType.isNoNormalCompletion()) {
					TyType.noNormalCompletion();
				} else if (whenFalse == null) {
					TyType.fromHintText("Void");
				} else {
					final joined = TyConditionalResult.join(trueType, falseType);
					joined == null ? TyType.fromHintText("Dynamic") : joined;
				}
			case EThrow(value, sourcePosition):
				inferExprType(value, scope, ctx, sourcePosition);
				TyType.noNormalCompletion();
			case ESourceGroup(children, sourcePosition):
				scope.enterLexicalScope();
				var result = children.length == 0 ? TyType.anonymous([], []) : TyType.fromHintText("Void");
				for (child in children) {
					final childType = inferExprType(child, scope, ctx, sourcePosition);
					if (!result.isNoNormalCompletion())
						result = childType;
				}
				scope.exitLexicalScope();
				result;
			case ENull:
				TyType.fromHintText("Null");
			case EDiscardThen(effect, continuation):
				final effectType = inferExprType(effect, scope, ctx, pos);
				final resultType = inferExprType(continuation, scope, ctx, pos, effectType.isNoNormalCompletion() ? null : expectedResult);
				effectType.isNoNormalCompletion() ? effectType : resultType;
			case EBool(_):
				TyType.fromHintText("Bool");
			case EString(_):
				TyType.fromHintText("String");
			case EInt(_):
				TyType.fromHintText("Int");
			case EFloat(_):
				TyType.fromHintText("Float");
			case EThis:
				currentThisType(ctx);
			case ESuper:
				TySuperType.resolve(ctx.currentClass(), scope.isStaticContext());
			case EIdent(name) | EEnumValue(name):
				final sym = scope.resolveSymbol(name);
				if (sym != null) {
					scope.getInference().localType(sym);
				} else {
					final fieldType = currentFieldReferenceType(name, ctx);
					final enumField = fieldType == null ? ctx.moduleEnumConstructorField(name) : null;
					final importedField = enumField != null ? enumField : fieldType == null ? ctx.importedStaticField(name) : null;
					final instanceMethod = fieldType == null
						&& importedField == null ? currentInstanceMethodReferenceType(name, scope, ctx) : null;
					final currentMethod = instanceMethod != null ? instanceMethod : fieldType == null
						&& importedField == null ? currentStaticMethodReferenceType(name, ctx) : null;
					final methodRef = currentMethod == null
						&& fieldType == null
						&& importedField == null ? importedStaticMethodReferenceType(name, ctx) : currentMethod;
					if (fieldType != null) {
						fieldType;
					} else if (importedField != null) {
						TyNominalApplication.fieldType(ctx.getIndex(), importedField, null);
					} else if (methodRef != null) {
						methodRef;
					} else {
						// Runtime class values were resolved above. Preserve the existing enum
						// constructor path until its separate typed-enum owner replaces it.
						switch (expr) {
							case EEnumValue(_): TyType.fromHintText("String");
							case _: TyType.unknown();
						}
					}
				}
			case EField(obj, _field):
				// Add an open input's field requirement before strict lookup examines
				// its current structural snapshot. Written records cannot grow here.
				scope.getInference().sourceTerm(expr, scope);
				// Stage 3 bring-up: type a tiny set of `Math` constants used in upstream unit tests.
				//
				// Why
				// - Upstream `unit/TestNaN.hx` uses `Math.NaN` as a `Float` value and then compares it
				//   against numeric literals in `if` conditions.
				// - Without recognizing `Math.NaN` as `Float`, our function return inference widens to
				//   `Void`, and the bootstrap emitter produces OCaml like:
				//     `let a : unit = foo () in if a > 0 then ...`
				//   which fails typechecking.
				//
				// Scope
				// - This is intentionally narrow (bring-up only). A real typer should derive these
				//   from the standard library model.
				switch ({
					obj:obj, field:_field
				}) {
					case {obj: EIdent("Math"), field: "NaN" | "POSITIVE_INFINITY" | "NEGATIVE_INFINITY" | "PI"}:
						return TyType.fromHintText("Float");
					case _:
				}

				// Static field access through a (possibly fully-qualified) type path.
				//
				// Why
				// - Upstream suites access module-local helper values via fully-qualified paths, e.g.:
				//     `unit.MyAbstract.FakeEnumAbstract.NotFound`
				// - If we don't recognize `unit.MyAbstract.FakeEnumAbstract` as a type path here, the
				//   lazy ModuleLoader never gets a chance to load the defining module, and Stage3
				//   emission can fail later with OCaml errors like:
				//     `Error: Unbound module Unit_MyAbstract_FakeEnumAbstract`.
				//
				// How
				// - When `obj` is a dotted field chain whose last segment looks like a type name
				//   (UpperStart), ask the context to resolve it as a type.
				// - This triggers ModuleLoader-based on-demand loading.
				final dotted = dottedFieldPath(obj);
				if (dotted.length > 0) {
					final parts = dotted.split(".");
					final last = parts.length == 0 ? "" : parts[parts.length - 1];
					if (scope.resolveSymbol(parts[0]) == null && isUpperStartName(last)) {
						final c = ctx.resolveType(dotted);
						if (c != null) {
							final memberType = declaredMemberReadType(c, _field, true, ctx);
							if (memberType != null)
								return memberType;
							// Bring-up default: static fields without hints are treated as dynamic.
							return TyType.fromHintText("Dynamic");
						}
					}
				}
				switch (obj) {
					case _:
						// Best-effort: infer child for locals; actual field typing depends on the index.
						final objTy = inferExprType(obj, scope, ctx, pos);
						final nativeString = TyNekoNativeStringRead.resolve(objTy, _field, ctx);
						if (nativeString != null)
							return nativeString;
						final structuralField = TyStructuralFieldRead.resolve(objTy, _field);
						if (structuralField != null)
							return structuralField;
						if (objTy.unwrapNull().isAnonymous() && isStrict())
							throw new TyperError(ctx.getFilePath(), pos, "Unknown field " + _field + " on " + objTy.getDisplay());
						if (_field == "code" && objTy.getSemanticKey() == "primitive:String")
							throw new TyperError(ctx.getFilePath(), pos, "String has no field code");
						final idx = ctx.getIndex();
						final c = nominalInfoForType(idx, objTy);
						if (c != null) {
							final memberType = declaredMemberReadType(c, _field, false, ctx, objTy);
							if (memberType != null) {
								memberType;
							} else {
								if (isStrict()) {
									throw new TyperError(ctx.getFilePath(), pos, "Unknown field " + _field + " on " + objTy.getDisplay());
								}
								TyType.unknown();
							}
						} else {
							TyType.unknown();
						}
				}
			case ENullSafeField(obj, field):
				final fieldType = inferExprType(EField(obj, field), scope, ctx, pos);
				fieldType.isNullable() ? fieldType : TyType.nullable(fieldType);
			case ECall(sourceCallee, args):
				var callee = sourceCallee;
				while (true)
					switch callee {
						case EParenthesized(inner, _) | EPrivateAccess(inner, _): callee = inner;
						case _: break;
					}
				final compileTimeProbe = helperCompileTimeProbeName(callee);
				if (args.length == 1 && compileTimeProbe != null) {
					if (compileTimeProbe == "typeError") {
						try {
							typeErrorProbe(args[0], scope, ctx, pos);
						} catch (_:TyperError) {}
						return TyType.fromHintText("Bool");
					}
					// These helpers inspect intentionally invalid syntax and turn
					// its diagnostic into text. Their argument belongs to the
					// compile-time probe and must not mutate or fail the enclosing
					// function's ordinary typing scope.
					return TyType.fromHintText("String");
				}
				switch (callee) {
					case ESuper:
						// Parent construction completes with Void; it never produces a new receiver.
						for (argument in args)
							inferExprType(argument, scope, ctx, pos);
						return TyType.fromHintText("Void");
					case EIdent("__hxhx_throw") if (args.length == 1):
						inferExprType(args[0], scope, ctx, pos);
						return TyType.noNormalCompletion();
					case EIdent("__hxhx_optional_lambda") | EIdent("__hxhx_rest_lambda") if (args.length == 2):
						// These parser wrappers describe argument omission; they return the same callable.
						final callable = inferExprType(args[0], scope, ctx, pos);
						inferExprType(args[1], scope, ctx, pos);
						return callable;
					case EIdent("__hxhx_try"):
						final tryResult = inferStructuralTryResult(args, scope, ctx, pos, expectedResult);
						if (tryResult != null) return tryResult;
					case ENullSafeField(obj, field):
						final result = inferExprType(ECall(EField(obj, field), args), scope, ctx, pos);
						return result.isNullable() ? result : TyType.nullable(result);
					case _:
				}

				// Stage 3 bring-up: type a small set of `Sys.*` primitives explicitly.
				//
				// Why
				// - Gate2/Stage3 emit-runner harnesses rely on `Sys.command` for spawning sub-invocations.
				// - Without recognizing these return types, simple code like:
				//     `var code = Sys.command("haxe", ["-version"]); trace(code);`
				//   loses the `Int` type for `code` and degrades into `<unsupported>` printing.
				//
				// What
				// - This is *not* a complete stdlib typing story.
				// - It is a targeted bring-up bridge so the bootstrap emitter can produce runnable OCaml.
				switch (callee) {
					case EField(EIdent("Sys"), "command"):
						for (a in args)
							inferExprType(a, scope, ctx, pos);
						return TyType.fromHintText("Int");
					case EField(EIdent("Sys"), "getEnv"):
						for (a in args)
							inferExprType(a, scope, ctx, pos);
						return TyType.fromHintText("String");
					case EField(EIdent("Sys"), "putEnv"), EField(EIdent("Sys"), "setCwd"):
						for (a in args)
							inferExprType(a, scope, ctx, pos);
						return TyType.fromHintText("Void");
					case EField(EIdent("Sys"), "getCwd"), EField(EIdent("Sys"), "systemName"):
						for (a in args)
							inferExprType(a, scope, ctx, pos);
						return TyType.fromHintText("String");
					case EField(EIdent("Sys"), "programPath"):
						for (a in args)
							inferExprType(a, scope, ctx, pos);
						return TyType.fromHintText("String");
					case EField(EIdent("Sys"), "args"):
						for (a in args)
							inferExprType(a, scope, ctx, pos);
						return TyType.fromHintText("Array<String>");
					case EField(EIdent("Timer"), "stamp"):
						// Gate2 bring-up: RunCi uses `Timer.stamp()` for timing logs.
						// We map it to a float so `Math.round(Timer.stamp() - t)` can type.
						for (a in args)
							inferExprType(a, scope, ctx, pos);
						return TyType.fromHintText("Float");
					case EField(EIdent("Math"), "round"):
						// Gate2 bring-up: RunCi computes `final dt = Math.round(Timer.stamp() - t);`.
						// If this stays unknown, string interpolation of `${dt}s` degrades to `<unsupported>`.
						for (a in args)
							inferExprType(a, scope, ctx, pos);
						return TyType.fromHintText("Int");
					case _:
				}

				// Best-effort: type children for local inference, and use the index when we can.
				switch (callee) {
					case EIdent(name):
						// A bare call inside a class can name one of that class's static
						// methods. Keep local function values authoritative, then use the
						// same declaration lookup as the structural typed-call builder so
						// the expression result retains its nominal semantic type.
						final owner = scope.resolveSymbol(name) == null ? ctx.currentClass() : null;
						final instanceOwner = owner != null && !scope.isStaticContext() ? ctx.instanceMethodOwner(name) : null;
						if (instanceOwner != null) {
							selectedCallType(resolveMethodCall(instanceOwner, name, false, args, scope, ctx, pos), capture);
						} else if (owner != null && owner.staticMethodCandidates(name).length > 0) {
							selectedCallType(resolveMethodCall(owner, name, true, args, scope, ctx, pos), capture);
						} else {
							final moduleEnumConstructor = scope.resolveSymbol(name) == null ? ctx.moduleEnumConstructorMethod(name) : null;
							if (moduleEnumConstructor != null) {
								selectedCallType(resolveMethodCall(moduleEnumConstructor.getProvider(), moduleEnumConstructor.getMemberName(), true, args,
									scope, ctx, pos, moduleEnumConstructor.getCandidates()),
									capture);
							} else {
								final importedMethod = scope.resolveSymbol(name) == null ? ctx.importedStaticMethod(name) : null;
								if (importedMethod != null) {
									selectedCallType(resolveMethodCall(importedMethod.getProvider(), importedMethod.getMemberName(), true, args, scope, ctx,
										pos, importedMethod.getCandidates()),
										capture);
								} else {
									inferFunctionValueCall(callee, args, scope, ctx, pos);
								}
							}
						}
					case EEnumValue(name):
						final moduleEnumConstructor = ctx.moduleEnumConstructorMethod(name);
						if (moduleEnumConstructor != null) {
							selectedCallType(resolveMethodCall(moduleEnumConstructor.getProvider(), moduleEnumConstructor.getMemberName(), true, args, scope,
								ctx, pos, moduleEnumConstructor.getCandidates()),
								capture);
						} else {
							final importedMethod = ctx.importedStaticMethod(name);
							if (importedMethod != null)
								selectedCallType(resolveMethodCall(importedMethod.getProvider(), importedMethod.getMemberName(), true, args, scope, ctx, pos,
									importedMethod.getCandidates()),
									capture);
							else
								inferFunctionValueCall(callee, args, scope, ctx, pos);
						}
					case EField(obj, field):
						// A declared data field can contain a function. Its argument and
						// result contract belongs to callback typing, not method lookup.
						// Resolve speculatively, then type the selected read once in this scope.
						if (resolveFieldDeclaration(callee, scope, ctx, pos) != null) {
							final candidate = inferExprType(callee, scope.copyForInference(), ctx, pos);
							if (candidate.isFunction()) {
								final callable = inferExprType(callee, scope, ctx, pos);
								return inferFunctionValueCall(sourceCallee, args, scope, ctx, pos, expectedResult, callable);
							}
						}
						// Static call through a type name (imported or same-package): `Util.ping()`.
						switch (obj) {
							case EIdent(typeName):
								final c = scope.resolveSymbol(typeName) == null
									&& isUpperStartName(typeName) ? ctx.resolveType(typeName) : null;
								if (c != null) {
									selectedCallType(resolveMethodCall(c, field, true, args, scope, ctx, pos), capture);
								} else {
									// `obj` is a value identifier (local/param), not a type name.
									final objTy = inferExprType(obj, scope, ctx, pos);
									final structural = TyStructuralFieldRead.resolve(objTy, field);
									if (structural != null && structural.isFunction())
										return inferFunctionValueCall(callee, args, scope, ctx, pos, expectedResult, structural);
									final idx = ctx.getIndex();
									final c2 = nominalInfoForType(idx, objTy);
									if (c2 != null && ctx.instanceMethodOwner(field, c2) != null) {
										selectedCallType(resolveMethodCall(c2, field, false, args, scope, ctx, pos, null, {expression: obj, type: objTy}),
											capture);
									} else {
										for (a in args)
											inferExprType(a, scope, ctx, pos);
										final extension = resolveExtensionCall(obj, field, args, scope, ctx, pos, true);
										if (extension == null) {
											TyType.unknown();
										} else {
											extension.type;
										}
									}
								}
							case _:
								// Fully-qualified static call: `pack.sub.Type.method(...)`.
								//
								// The upstream RunCi harness uses this shape heavily without imports,
								// so we must resolve the type path and let the ModuleLoader pull it in.
								final dotted = dottedFieldPath(obj);
								if (dotted.length > 0) {
									final parts = dotted.split(".");
									final last = parts.length == 0 ? "" : parts[parts.length - 1];
									if (scope.resolveSymbol(parts[0]) == null && isUpperStartName(last)) {
										final c = ctx.resolveType(dotted);
										if (c != null) {
											return selectedCallType(resolveMethodCall(c, field, true, args, scope, ctx, pos), capture);
										}
									}
								}

								// `obj` is a value identifier (local/param), not a type name.
								final objTy = inferExprType(obj, scope, ctx, pos);
								final structural = TyStructuralFieldRead.resolve(objTy, field);
								if (structural != null && structural.isFunction())
									return inferFunctionValueCall(callee, args, scope, ctx, pos, expectedResult, structural);
								final idx = ctx.getIndex();
								final c2 = nominalInfoForType(idx, objTy);
								if (c2 != null && ctx.instanceMethodOwner(field, c2) != null) {
									selectedCallType(resolveMethodCall(c2, field, false, args, scope, ctx, pos, null, {expression: obj, type: objTy}), capture);
								} else {
									for (a in args)
										inferExprType(a, scope, ctx, pos);
									final extension = resolveExtensionCall(obj, field, args, scope, ctx, pos, true);
									if (extension == null) {
										TyType.unknown();
									} else {
										extension.type;
									}
								}
						}
					case _:
						inferFunctionValueCall(callee, args, scope, ctx, pos, expectedResult);
				}
			case EReturn(value):
				if (scope.getRootControlTarget() != null)
					scope.requireControlScope().returnTarget();
				final valueType = value == null ? TyType.fromHintText("Void") : inferExprType(value, scope, ctx, pos);
				final returns = scope.currentSourceReturns();
				if (returns != null) {
					TyLambdaResultContract.check(valueType, returns.expected, ctx.getFilePath(), pos, isStrict());
					if (!valueType.isNoNormalCompletion()) {
						final term = value == null ? null : scope.getInference().sourceTerm(value, scope);
						returns.record(term == null ? Known(valueType) : term, pos);
					}
					TyType.noNormalCompletion();
				} else {
					TyType.fromHintText("Void");
				}
			case EVars(declarations):
				var completesNormally = true;
				for (declaration in declarations) {
					final initializer = HxExprVarDecl.getInitializer(declaration);
					final writtenType = StringTools.trim(HxExprVarDecl.getTypeHint(declaration));
					final hinted = writtenType.length == 0 ? null : typeFromHintInContext(writtenType, ctx, scope);
					final initializerType = initializer == null ? TyType.unknown() : inferLocalInitializer(initializer, hinted, scope, ctx,
						HxExprVarDecl.getPosition(declaration));
					final initializerTerm = initializer == null ? null : scope.getInference().sourceTerm(initializer, scope);
					if (initializerType.isNoNormalCompletion())
						completesNormally = false;
					final localType = hinted == null ? initializerType : hinted;
					final symbol = scope.declareLocal(HxExprVarDecl.getName(declaration), localType, Variable);
					if (initializerTerm != null
						&& (hinted == null
							|| !hinted.isDynamic()
							&& (!scope.isUntypedContext() || hinted.getSemanticKey() == initializerType.getSemanticKey())))
						scope.getInference().recordLocal(symbol, initializerTerm);
				}
				completesNormally ? TyType.fromHintText("Void") : TyType.noNormalCompletion();
			case EVariableDeclaration(_, _, _, _, _, _):
				throw new TyperError(ctx.getFilePath(), pos, "expression-level variable declaration must be nested inside EVars");
			case EWhile(condition, body, _, loopPosition, loopKind):
				inferExprType(condition, scope, ctx, loopPosition);
				final controls = scope.requireControlScope();
				final target = controls.enter(Loop, TypedBodyFingerprint.forExpression(expr));
				scope.enterLexicalScope();
				for (entry in body)
					inferExprType(entry, scope, ctx, loopPosition);
				scope.exitLexicalScope();
				controls.exit(target);
				TyType.fromHintText("Void");
			case EBreak(controlPosition) | EContinue(controlPosition):
				if (scope.requireControlScope().loopTarget() == null)
					throw new TyperError(ctx.getFilePath(), controlPosition, "loop control requires an enclosing loop in the same function");
				TyType.noNormalCompletion();
			case ELambda(argNames, body, signature):
				// Lambda parameters shadow outer names while unresolved reads still
				// select the captured declaration from the enclosing scope.
				final context = expectedResult != null
					&& expectedResult.isFunction()
					&& expectedResult.getFunctionArguments().length == argNames.length ? expectedResult : null;
				inferLambdaType(argNames, body, context == null ? [for (_ in argNames) TyType.unknown()] : context.getFunctionArguments(), scope, ctx, pos,
					signature, context == null ? null : context.getFunctionReturn());
			case EMacroExpr(inner, _wrappers):
				TyType.fromHintText("haxe.macro.Expr");
			case EMacroType(_typeText):
				TyType.fromHintText("haxe.macro.ComplexType");
			case ETryCatchRaw(raw):
				final recovered = TypedBodyBuilder.recoveredOpaqueBlockStatements(raw);
				if (recovered == null) {
					final structural = TypedBodyBuilder.recoveredStructuralExpression(raw);
					if (structural == null) {
						// Stage 3 bring-up: richer try/catch expressions remain an
						// explicitly dynamic structural leaf until their typed control
						// model is available.
						TyType.fromHintText("Dynamic");
					} else {
						inferExprType(structural, scope, ctx, pos);
					}
				} else {
					scope.enterLexicalScope();
					var resultType = TyType.fromHintText("Void");
					for (statement in recovered)
						switch (statement) {
							case SVar(name, typeHint, initializer, declarationPosition, _):
								final initializerType = initializer == null ? TyType.unknown() : inferExprType(initializer, scope, ctx, declarationPosition);
								final writtenType = StringTools.trim(typeHint == null ? "" : typeHint);
								final localType = writtenType.length == 0 ? initializerType : typeFromHintInContext(writtenType, ctx, scope);
								scope.declareLocal(name, localType, Variable);
								resultType = TyType.fromHintText("Void");
							case SExpr(value, expressionPosition):
								resultType = inferExprType(value, scope, ctx, expressionPosition);
							case _:
						}
					scope.exitLexicalScope();
					resultType;
				}
			case ESwitchRaw(_raw):
				// Stage 3 bring-up: we only preserve the shape of `switch` expressions so parsing/typing
				// can proceed deterministically through upstream-shaped code (notably runci).
				// Correct semantics (pattern matching + guards + value typing) are Stage 4+ work.
				TyType.fromHintText("Dynamic");
			case ESwitch(scrutinee, patterns, exprs):
				// Bring-up: type the scrutinee and unify case-expression types best-effort.
				// This is intentionally permissive; if unification fails we widen to Dynamic.
				final scrutTy = inferSwitchInput(scrutinee, patterns, scope, ctx, pos);
				TySwitchTyping.check(scrutTy, patterns, exprs == null ? -1 : exprs.length, ctx, pos);
				var out:TyType = TyType.unknown();
				if (patterns != null && exprs != null) {
					final count = patterns.length < exprs.length ? patterns.length : exprs.length;
					for (i in 0...count) {
						final pattern = patterns[i];
						final branchExpr = exprs[i];
						var branchTy:TyType = TyType.unknown();
						scope.enterLexicalScope();
						try {
							declarePatternBindings(scope, pattern, scrutTy, ctx, pos);
							branchTy = inferExprType(branchExpr, scope, ctx, pos, expectedResult);
						} catch (error:Dynamic) {
							// Opaque rethrow is required to restore scope for every Haxe failure.
							scope.exitLexicalScope();
							throw error;
						}
						scope.exitLexicalScope();

						if (out.isUnknown())
							out = branchTy;
						else {
							final u = TyType.unify(out, branchTy);
							if (u != null)
								out = u;
							else if (!isStrict())
								out = TyType.fromHintText("Dynamic");
						}
					}
				}
				out.isUnknown() ? TyType.fromHintText("Dynamic") : out;
			case ENew(_typePath, args):
				final argumentTypes = [for (argument in args) inferExprType(argument, scope, ctx, pos)];
				// The parsed constructor path may be an applied type such as
				// `Box<Int->Int>`. Resolve the structural hint so the exact
				// nominal identity and its arguments reach local facts together.
				final written = typeFromHintInContext(_typePath, ctx, scope);
				final owner = nominalInfoForType(ctx.getIndex(), written);
				final arity = owner == null ? 0 : TyNominalApplication.parameterIds(owner).length;
				final constructed = scope.getInference().construct(expr, written, arity);
				if (!scope.getInference().constrainConstructor({
					expression: expr,
					provider: owner,
					argumentTypes: argumentTypes,
					environment: scope,
					index: ctx.getIndex(),
					score: (signature, parameters) -> overloadCandidateScore(signature, argumentTypes, args.length, parameters, ctx.getIndex())
				}))
					throw new TyperError(ctx.getFilePath(), pos, "generic constructor has no unique applicable declaration");
				// Constructor operands fix omitted arguments before an enclosing context
				// checks the result: Box<Float> = new Box(1) must not rewrite Box<Int>.
				if (expectedResult != null && !scope.getInference().constrain([expr], [expectedResult], scope, ctx.getIndex()))
					throw new TyperError(ctx.getFilePath(), pos, "generic constructor conflicts with its expected type");
				final applied = scope.getInference().expressionType(expr, constructed, scope);
				validateClassArguments(applied, ctx, pos);
				applied;
			case EUnop(_op, _fixity, e):
				if (_op == Increment || _op == Decrement)
					assertWritableLocal(e, scope, ctx, pos);
				final inner = inferExprType(e, scope, ctx, pos);
				final semanticIndex = ctx.getIndex();
				final isPropertyUpdate = (_op == Increment || _op == Decrement)
					&& semanticIndex != null
					&& inner.getNominalIdentity() != null
					&& semanticIndex.getAbstractByFullName(inner.getNominalIdentity().getCanonicalName()) != null
					&& accessorPropertyForAccess(e, scope, ctx, pos) != null;
				// Haxe 4.3.7 updates explicit properties through their getter/setter
				// contract; it does not select the abstract value's increment helper.
				final bound = isPropertyUpdate ? null : TyAbstractUnaryBinding.select(semanticIndex, inner, _op, _fixity, ctx.getFilePath(), pos);
				if (bound != null) {
					bound.getResultType();
				} else {
					if (_op == LogicalNot)
						TyType.fromHintText("Bool");
					else if (_op == Negate)
						inner.isNumeric() ? inner : TyType.unknown();
					else {
						// Haxe types `Null<Int>` and `Null<Float>` updates as nullable numeric
						// expressions. Strict null-safety reports unsafe access later.
						if ((_op == Increment || _op == Decrement)
							&& !isPropertyUpdate // Stage3 still models an abstract backing carrier as
							// `this` in a small compatibility subset. Its explicit
							// write-back is validated by the typed abstract lowering.
							&& !e.match(EThis)
							&& !inner.unwrapNull().isNumeric()
							&& !inner.isDynamic()
							&& !inner.isUnknown()
							&& !inner.isUnresolved())
							throw new TyperError(ctx.getFilePath(), pos, inner.getDisplay() + " should be Int");
						// Bitwise-not and accepted increment/decrement operations keep
						// the operand type when no abstract operator overrides it.
						inner;
					}
				}
			case EBinop(op, a, b):
				if (op == "??=")
					assertWritableLocal(a, scope, ctx, pos);
				switch (op) {
					case "is":
						inferExprType(a, scope, ctx, pos);
						if (TypedRuntimeTypeResolver.resolve(b, scope, ctx, TypeOperand) == null)
							throw new TyperError(ctx.getFilePath(), pos, "runtime type test requires a resolved target");
						TyType.fromHintText("Bool");
					case "??":
						final ta = inferExprType(a, scope, ctx, pos);
						final tb = inferExprType(b, scope, ctx, pos);
						inferNullCoalesceType(ta, tb);
					case "=":
						assertWritableLocal(a, scope, ctx, pos);
						// Assignment as expression.
						final destination = inferExprType(a, scope, ctx, pos);
						final rhs = inferExprType(b, scope, ctx, pos, destination);
						final assignedField = resolveFieldDeclaration(a, scope, ctx, pos);
						TyFieldAssignment.check({
							declaration: assignedField,
							expected: destination,
							actual: rhs,
							expression: b,
							index: ctx.getIndex(),
							filePath: ctx.getFilePath(),
							position: pos,
							unchecked: scope.isUntypedContext()
						});
						if (assignedField != null)
							return destination;
						switch (a) {
							case EIdent(name):
								final sym = scope.resolveSymbol(name);
								if (sym != null) {
									if (scope.getInference().sourceTerm(a, scope) != null) {
										final inferred = scope.getInference().expressionType(a, sym.getType(), scope);
										final compatible = inferred.hasUnknownComponent() ? scope.getInference()
											.constrain([a], [rhs], scope, ctx.getIndex()) : overloadArgScore(inferred, rhs, [], ctx.getIndex()) >= 0;
										if (!compatible)
											throw new TyperError(ctx.getFilePath(), pos, "assignment conflicts with inferred generic result");
									}
									final u = assignedLocalType(sym.getType(), rhs);
									if (u == null) {
										if (isStrict()) {
											throw new TyperError(ctx.getFilePath(), pos,
												"assigned type " + rhs + " is not compatible with local " + name + ":" + sym.getType());
										}
										// An already-known local type remains the semantic contract
										// in permissive bring-up mode. Conversion typing is incomplete,
										// so widening it to Dynamic here would erase exact written or
										// inferred facts before a backend can apply the required
										// assignment conversion.
										rhs;
									} else {
										sym.setType(u);
										rhs;
									}
								} else {
									rhs;
								}
							case _:
								rhs;
						}
					case _ if (HxBinaryOperatorTools.isCompoundAssignment(op)):
						assertWritableLocal(a, scope, ctx, pos);
						final leftType = inferExprType(a, scope, ctx, pos);
						final rightType = inferExprType(b, scope, ctx, pos);
						final bound = TyAbstractBinaryBinding.select(ctx.getIndex(), leftType, rightType, op, ctx.getFilePath(), pos);
						if (bound != null) {
							bound.getRequiresWriteback() ? leftType : bound.getOperatorInfo().getResultType();
						} else {
							switch (a) {
								case EIdent(name):
									final symbol = scope.resolveSymbol(name);
									if (symbol != null) {
										final unified = assignedLocalType(symbol.getType(), rightType);
										if (unified != null)
											symbol.setType(unified);
									}
								case _:
							}
							leftType;
						}
					case "==" | "!=" | "<" | "<=" | ">" | ">=":
						final leftType = inferExprType(a, scope, ctx, pos);
						final rightType = inferExprType(b, scope, ctx, pos);
						final bound = TyAbstractBinaryBinding.select(ctx.getIndex(), leftType, rightType, op, ctx.getFilePath(), pos);
						bound == null ? TyType.fromHintText("Bool") : bound.getOperatorInfo().getResultType();
					case "&&" | "||":
						inferExprType(a, scope, ctx, pos);
						inferExprType(b, scope, ctx, pos);
						TyType.fromHintText("Bool");
					case "&" | "|" | "^" | "<<" | ">>" | ">>>":
						final ta = inferExprType(a, scope, ctx, pos);
						final tb = inferExprType(b, scope, ctx, pos);
						final bound = TyAbstractBinaryBinding.select(ctx.getIndex(), ta, tb, op, ctx.getFilePath(), pos);
						if (bound != null) bound.getOperatorInfo()
							.getResultType(); else // Best-effort: treat as Bool if both operands are Bool; otherwise Int.
							(ta.getDisplay() == "Bool" && tb.getDisplay() == "Bool") ? TyType.fromHintText("Bool") : TyType.fromHintText("Int");
					case "+":
						final ta = inferExprType(a, scope, ctx, pos);
						final tb = inferExprType(b, scope, ctx, pos);
						final bound = TyAbstractBinaryBinding.select(ctx.getIndex(), ta, tb, op, ctx.getFilePath(), pos);
						if (bound != null) {
							bound.getOperatorInfo().getResultType();
						} else if (ta.getDisplay() == "String" || tb.getDisplay() == "String") {
							TyType.fromHintText("String");
						} else if (ta.isDynamic() || tb.isDynamic()) {
							// Dynamic addition keeps a runtime-selected result category. It is
							// not an unresolved type hole that a callback may silently erase.
							TyType.fromHintText("Dynamic");
						} else {
							final integer = TyNullableIntegerResult.result(ta, tb);
							final u = integer == null ? TyType.unify(ta, tb) : integer;
							u != null
							&& u.isNumeric() ? u : TyType.unknown();
						}
					case "-" | "*" | "/" | "%":
						final ta = inferExprType(a, scope, ctx, pos);
						final tb = inferExprType(b, scope, ctx, pos);
						final bound = TyAbstractBinaryBinding.select(ctx.getIndex(), ta, tb, op, ctx.getFilePath(), pos);
						if (bound != null) bound.getOperatorInfo().getResultType(); else {
							final integer = op == "/" ? null : TyNullableIntegerResult.result(ta, tb);
							final unified = integer == null ? TyType.unify(ta, tb) : integer;
							unified != null
							&& unified.isNumeric() ? unified : TyType.unknown();
						}
					case _:
						inferExprType(a, scope, ctx, pos);
						inferExprType(b, scope, ctx, pos);
						TyType.unknown();
				}
			case ETernary(cond, thenExpr, elseExpr):
				inferExprType(cond, scope, ctx, pos);
				final t1 = inferExprType(thenExpr, scope, ctx, pos, expectedResult);
				final t2 = inferExprType(elseExpr, scope, ctx, pos, expectedResult);
				final u = TyConditionalResult.join(t1, t2);
				u == null ? TyType.fromHintText("Dynamic") : u;
			case EAnon(names, values):
				TypedAnonymousLiteral.infer({
					names: names,
					values: values,
					expected: expectedResult,
					typeExpression: (value, expected) -> inferExprType(value, scope, ctx, pos, expected),
					accepts: (expected,
						actual) -> overloadArgScore(expected, actual, [], ctx.getIndex()) >= 0
							|| (actual.isNullLiteral() && TyNullArgument.acceptsLiteral(expected, ctx.getIndex())),
					filePath: ctx.getFilePath(),
					position: pos
				});
			case EArrayComprehension(name, iterable, guardExpr, yieldExpr):
				// Bring-up: type the iterable and bind the loop variable for the yield expression.
				final itTy = inferExprType(iterable, scope, ctx, pos);
				final elemTy = arrayElementType(itTy);
				scope.enterLexicalScope();
				scope.declareLocal(name, (elemTy != null && !elemTy.isUnknown()) ? elemTy : TyType.fromHintText("Dynamic"), ComprehensionVariable);
				if (guardExpr != null)
					inferExprType(guardExpr, scope, ctx, pos);
				inferExprType(yieldExpr, scope, ctx, pos);
				scope.exitLexicalScope();
				TyType.fromHintText("Array<Dynamic>");
			case EArrayDecl(values):
				final comprehension = TyArrayComprehension.infer({
					values: values,
					expected: expectedResult,
					scope: scope,
					filePath: ctx.getFilePath(),
					position: pos,
					typeExpression: (value, expected) -> inferExprType(value, scope, ctx, pos, expected),
					typeMapEntry: entry -> {
						final map = TypedMapLiteral.infer({
							values: [entry],
							typeExpression: value -> inferExprType(value, scope, ctx, pos),
							resolveProvider: () -> ctx.resolveType("haxe.ds.Map"),
							filePath: ctx.getFilePath(),
							position: pos
						});
						if (map == null)
							throw "map comprehension requires an authored arrow entry";
						return map;
					},
					resolveArray: element -> resolveTypeInContext(TyType.unresolved("Array", [element]), ctx)
				});
				if (comprehension != null)
					return comprehension;
				final contextual = TypedCollectionExpectation.select(expr, expectedResult);
				if (contextual != null)
					return contextual;
				if (values.length == 0) {
					final array = ctx.resolveType("Array");
					if (array != null)
						return scope.getInference().emptyArray(expr, array.getIdentity());
				}
				final mapType = TypedMapLiteral.infer({
					values: values,
					typeExpression: value -> inferExprType(value, scope, ctx, pos),
					resolveProvider: () -> ctx.resolveType("haxe.ds.Map"),
					filePath: ctx.getFilePath(),
					position: pos
				});
				if (mapType != null)
					return mapType;
				final contextualArray = TypedArrayLiteral.infer({
					values: values,
					expected: expectedResult,
					typeExpression: (value, expected) -> inferExprType(value, scope, ctx, pos, expected),
					accepts: (expected,
						actual) -> actual.isDynamic()
							|| TyImplicitConversionPlan.select(ctx.getIndex(), expected.unwrapNull(), actual.unwrapNull()) != null
							|| (actual.isNullLiteral() && TyNullArgument.acceptsLiteral(expected, ctx.getIndex())),
					filePath: ctx.getFilePath(),
					position: pos
				});
				if (contextualArray != null)
					return contextualArray;
				var elem:TyType = TyType.unknown();
				var saw = false;
				for (v in values) {
					final vt = inferExprType(v, scope, ctx, pos);
					if (!saw) {
						saw = true;
						elem = vt;
						continue;
					}
					final u = TyType.unify(elem, vt);
					if (u == null) {
						elem = TyType.fromHintText("Dynamic");
						break;
					}
					elem = u;
				}
				if (!saw)
					elem = TyType.fromHintText("Dynamic");
				// Preserve the inferred element object: display text cannot carry
				// structural fields or exact generic binder identity. Resolve the
				// Array provider without reparsing those already-typed facts.
				resolveTypeInContext(TyType.unresolved("Array", [elem]), ctx);
			case EArrayAccess(array, index):
				final arrayType = inferExprType(array, scope, ctx, pos);
				inferExprType(index, scope, ctx, pos);
				final elementType = arrayElementType(arrayType);
				// Other indexed containers remain explicit Dynamic until their access
				// contracts are represented in the shared semantic model.
				elementType == null ? TyType.fromHintText("Dynamic") : elementType;
			case ERange(start, end):
				for (bound in [start, end]) {
					final actual = inferExprType(bound, scope, ctx, pos, TyType.fromHintText("Int"));
					if (TyAssignmentCompatibility.classify(TyType.fromHintText("Int"), actual, Unchecked) == Incompatible)
						throw new TyperError(ctx.getFilePath(), pos, actual.getDisplay() + " should be Int for a range bound");
				}
				// Bring-up: `start...end` is primarily used as a loop iterable; model it as Dynamic.
				TyType.fromHintText("Dynamic");
			case ECast(expr, typeHint): final hinted = typeFromHintInContext(typeHint, ctx, scope); final inner = switch (expr) {
					case ELambda(names, body, signature) if (hinted.isFunction() && hinted.getFunctionArguments().length == names.length):
						inferLambdaType(names, body, hinted.getFunctionArguments(), scope, ctx, pos, signature);
					case ESourceFunction(facts, body, defaults, sourcePosition):
						inferSourceFunctionType(expr, facts, body, defaults, scope, ctx, sourcePosition, hinted);
					case _: inferExprType(expr, scope, ctx, pos);
				}; // An unchecked cast changes the result's contextual type, never the operand's type.
				// Written cast hints retain their own contract, independently of the destination.
				typeHint.length == 0 && expectedResult != null && !expectedResult.isUnknown() ? expectedResult : hinted.isUnknown() ? inner : hinted;
			case EUntyped(inner):
				scope.withUntyped(() -> inferExprType(inner, scope, ctx, pos));
				// The wrapper has its own result variable, even when its operand has
				// a known type. Upstream permits the surrounding use to constrain it.
				scope.getInference().untypedResult(expr);
			case EUnsupported(_):
				TyType.unknown();
		}
	}
}
