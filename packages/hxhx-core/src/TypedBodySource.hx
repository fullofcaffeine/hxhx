/**
	Projects a structural typed body to the source-shaped nodes understood by the
	current backend emitters.

	This adapter is a migration seam: it reads only typed nodes, never a parsed
	function body. Ordered effects remain name-free sequencing operations; only
	value-bearing temporaries use continuation calls to retain their exact binding.
**/
class TypedBodySource {
	static function sourcePosition(position:Null<HxPos>):HxPos
		return position == null ? HxPos.unknown() : position;

	static function exactProjectedName(catalog:Null<TypedBackendLocalCatalog>, bindings:Array<TyLocalBinding>, fallback:String, owner:String):String {
		if (catalog == null)
			return fallback;
		if (bindings == null || bindings.length != 1)
			throw owner + " requires exactly one typed local binding during backend projection";
		return catalog.projectedName(bindings[0]);
	}

	static function exactProjectedNames(catalog:Null<TypedBackendLocalCatalog>, bindings:Array<TyLocalBinding>, fallbacks:Array<String>,
			owner:String):Array<String> {
		if (catalog == null)
			return fallbacks == null ? [] : fallbacks.copy();
		if (bindings == null || fallbacks == null || bindings.length != fallbacks.length)
			throw owner + " has inconsistent typed local bindings during backend projection";
		return [for (binding in bindings) catalog.projectedName(binding)];
	}

	static function addBinding(bindings:haxe.ds.StringMap<TyLocalBinding>, binding:TyLocalBinding):Void {
		if (binding == null)
			throw "typed backend projection encountered a null local binding";
		final identity = binding.getIdentity().getCanonicalKey();
		final existing = bindings.get(identity);
		if (existing == null) {
			bindings.set(identity, binding);
		} else if (existing.getCanonicalIdentity() != binding.getCanonicalIdentity()) {
			throw "typed backend projection encountered conflicting local facts for " + identity;
		}
	}

	static function collectExpressionBindings(expression:TypedExpr, bindings:haxe.ds.StringMap<TyLocalBinding>, uses:Array<TypedCatchUse>):Void {
		for (use in expression.getCatchUses())
			uses.push(use);
		for (binding in expression.getLocalBindings())
			addBinding(bindings, binding);
		for (child in expression.getExpressions())
			collectExpressionBindings(child, bindings, uses);
	}

	static function collectStatementBindings(statement:TypedStmt, bindings:haxe.ds.StringMap<TyLocalBinding>, uses:Array<TypedCatchUse>):Void {
		for (use in statement.getCatchUses())
			uses.push(use);
		for (binding in statement.getLocalBindings())
			addBinding(bindings, binding);
		for (expression in statement.getExpressions())
			collectExpressionBindings(expression, bindings, uses);
		for (child in statement.getStatements())
			collectStatementBindings(child, bindings, uses);
	}

	static function collectExpressionFieldReads(expression:TypedExpr, reads:Array<TypedBackendFieldReadProjection>):Void {
		if (expression.getTag() == NameRead && !expression.getRequiresOwnerQualification()) {
			final field = expression.getFieldInfo();
			if (field != null) {
				final names = expression.getTexts();
				if (names.length != 1 || names[0].length == 0)
					throw "typed backend projection encountered a bare field read without one transport name";
				reads.push(new TypedBackendFieldReadProjection(names[0], field));
			}
		}
		for (child in expression.getExpressions())
			collectExpressionFieldReads(child, reads);
	}

	static function collectStatementFieldReads(statement:TypedStmt, reads:Array<TypedBackendFieldReadProjection>):Void {
		for (expression in statement.getExpressions())
			collectExpressionFieldReads(expression, reads);
		for (child in statement.getStatements())
			collectStatementFieldReads(child, reads);
	}

	static function fieldReadCatalog(typedFunction:TypedFunction):TypedBackendFieldReadCatalog {
		final reads = new Array<TypedBackendFieldReadProjection>();
		for (value in typedFunction.getDefaults())
			collectExpressionFieldReads(value.getExpression(), reads);
		for (statement in typedFunction.getBody().getStatements())
			collectStatementFieldReads(statement, reads);
		return new TypedBackendFieldReadCatalog(reads);
	}

	static function localCatalog(typedFunction:TypedFunction, reservedProjectedNames:Array<String>):TypedBackendLocalCatalog {
		final bindings = new haxe.ds.StringMap<TyLocalBinding>();
		final uses = new Array<TypedCatchUse>();
		final environment = typedFunction.getEnvironment();
		if (environment != null)
			for (parameter in environment.getParams())
				addBinding(bindings, parameter.toBinding());
		for (value in typedFunction.getDefaults())
			collectExpressionBindings(value.getExpression(), bindings, uses);
		for (statement in typedFunction.getBody().getStatements())
			collectStatementBindings(statement, bindings, uses);
		final ordered = new Array<TyLocalBinding>();
		for (binding in bindings)
			ordered.push(binding);
		return new TypedBackendLocalCatalog(ordered, reservedProjectedNames, uses);
	}

	/**
		Render the exact type selected by shared typing as a Haxe-shaped hint for
		backends that still consume the source projection. In particular, an import
		alias such as `Service` becomes its canonical provider path `model.Api` so a
		target does not need to repeat Haxe name resolution.
	**/
	static function canonicalTypeHint(type:TyType):String {
		return type == null ? "" : type.getCanonicalDisplay();
	}

	/** Open method variables retain typed identities while legacy target hints select an opaque carrier. */
	static function projectedTypeHint(type:TyType):String {
		return type.hasOpenMethodParameter() ? canonicalTypeHint(type) : type.getDisplay();
	}

	/** Find source annotation facts through parser-owned callable wrappers only. */
	static function callableSignature(value:TypedExpr):Null<HxLambdaSignature> {
		if (value.getTag() == Lambda)
			return value.getLambdaSignature();
		final children = value.getExpressions();
		if (value.getTag() == Cast && children.length == 1)
			return callableSignature(children[0]);
		if (value.getTag() == Call && children.length == 3 && children[0].getTag() == NameRead) {
			final name = children[0].getTexts()[0];
			if (name == "__hxhx_optional_lambda" || name == "__hxhx_rest_lambda")
				return callableSignature(children[1]);
		}
		return null;
	}

	/** Transport selected types and omission flags without converting them into source annotations. */
	static function callableTypeHint(type:TyType, signature:Null<HxLambdaSignature>):String {
		final arguments = type.getFunctionArguments();
		final parameters = signature == null ? [] : signature.getParameters();
		final parts = new Array<String>();
		for (index in 0...arguments.length)
			parts.push((index < parameters.length && parameters[index].isOptional ? "?" : "") + canonicalTypeHint(arguments[index]));
		return "(" + parts.join(", ") + ")->" + canonicalTypeHint(type.getFunctionReturn());
	}

	static function ascribeCallable(source:HxExpr, value:TypedExpr, suppress:Bool, ?projectionFacts:TypedBodyProjectionBuilder):HxExpr {
		final type = value.getType();
		if (suppress || !type.isFunction() || type.hasUnknownComponent())
			return source;
		final hint = callableTypeHint(type, callableSignature(value));
		return projectionFacts == null ? ECast(source, hint) : projectionFacts.ascribeCallable(source, hint);
	}

	static function containsNominalType(type:TyType):Bool {
		if (type == null)
			return false;
		if (type.getNominalIdentity() != null)
			return true;
		if (type.isNullable())
			return containsNominalType(type.getNullableInner());
		if (type.isFunction()) {
			for (argument in type.getFunctionArguments())
				if (containsNominalType(argument))
					return true;
			return containsNominalType(type.getFunctionReturn());
		}
		if (type.isAnonymous()) {
			for (fieldType in type.getAnonymousFieldTypes())
				if (containsNominalType(fieldType))
					return true;
			return false;
		}
		for (argument in type.getTypeArguments())
			if (containsNominalType(argument))
				return true;
		return false;
	}

	static function simpleTypeName(path:String):String {
		if (path == null)
			return "";
		final dot = path.lastIndexOf(".");
		return dot < 0 ? path : path.substr(dot + 1);
	}

	static function sourceTypeBase(display:String):String {
		var value = StringTools.trim(display == null ? "" : display);
		final generic = value.indexOf("<");
		if (generic >= 0)
			value = StringTools.trim(value.substr(0, generic));
		return simpleTypeName(value);
	}

	/** Whether a source hint contains a local alias rather than the provider's real type name. **/
	static function containsAliasSpelling(type:TyType):Bool {
		if (type == null)
			return false;
		final identity = type.getNominalIdentity();
		if (identity != null && sourceTypeBase(type.getDisplay()) != simpleTypeName(identity.getCanonicalName()))
			return true;
		if (type.isNullable() && containsAliasSpelling(type.getNullableInner()))
			return true;
		if (type.isFunction()) {
			for (argument in type.getFunctionArguments())
				if (containsAliasSpelling(argument))
					return true;
			if (containsAliasSpelling(type.getFunctionReturn()))
				return true;
		}
		if (type.isAnonymous())
			for (fieldType in type.getAnonymousFieldTypes())
				if (containsAliasSpelling(fieldType))
					return true;
		for (argument in type.getTypeArguments())
			if (containsAliasSpelling(argument))
				return true;
		return false;
	}

	static function resolvedNameWhenAliased(sourceName:String, identity:Null<TyNominalTypeId>):String {
		if (identity == null || sourceTypeBase(sourceName) == simpleTypeName(identity.getCanonicalName()))
			return sourceName;
		return identity.getCanonicalName();
	}

	/**
		Build a structural expression for the provider selected by alias resolution.

		A qualified provider such as `model.Api` is represented as `model` followed by
		an `Api` field access. Keeping the path structural lets each target render its
		own package or namespace syntax; storing the whole path in one identifier would
		instead produce invalid names such as `model_Api` in Python.
	**/
	static function resolvedTypeExpression(sourceName:String, identity:Null<TyNominalTypeId>):HxExpr {
		final resolved = resolvedNameWhenAliased(sourceName, identity);
		if (resolved.indexOf(".") < 0)
			return EIdent(resolved);
		final parts = resolved.split(".");
		var expression:HxExpr = EIdent(parts.shift());
		for (part in parts)
			expression = EField(expression, part);
		return expression;
	}

	/**
		Preserve whether a local type was actually written in source.

		A constructor keeps its semantic nominal type on the typed expression, but
		its omitted generic arguments may be refined by later uses. Projecting that
		nominal display as a source annotation would turn inference into an explicit
		bare type and prevent a backend from using that later evidence. Other nominal
		results retain the existing migration hint until every backend consumes their
		semantic representation directly.
	**/
	static function variableTypeHint(sourceHint:String, initializer:Null<TypedExpr>):String {
		final typeHint = sourceHint == null ? "" : sourceHint;
		if (StringTools.trim(typeHint).length > 0)
			return initializer != null
				&& containsNominalType(initializer.getType())
				&& containsAliasSpelling(initializer.getType()) ? canonicalTypeHint(initializer.getType()) : typeHint;
		if (initializer == null || initializer.getType().getNominalIdentity() == null)
			return typeHint;
		return switch (initializer.getTag()) {
			case NewValue: typeHint;
			case _: projectedTypeHint(initializer.getType());
		};
	}

	static function projectedPatternBinding(bindings:Array<TyLocalBinding>, cursor:Array<Int>, catalog:TypedBackendLocalCatalog, sourceName:String,
			names:haxe.ds.StringMap<String>):String {
		if (cursor[0] >= bindings.length)
			throw "switch pattern projection produced more local declarations than typing";
		final binding = bindings[cursor[0]++];
		if (binding.getSourceName() != sourceName)
			throw "switch pattern projection expected " + sourceName + " but typing selected " + binding.getSourceName();
		final projected = catalog.projectedName(binding);
		final existing = names.get(sourceName);
		if (existing != null && existing != projected)
			throw "switch pattern projection assigned conflicting identities to " + sourceName;
		names.set(sourceName, projected);
		return projected;
	}

	static function projectedPatternReference(names:haxe.ds.StringMap<String>, sourceName:String):String {
		final projected = names.get(sourceName);
		if (projected == null)
			throw "switch guard references a pattern local without an exact typed binding: " + sourceName;
		return projected;
	}

	static function projectPattern(pattern:HxSwitchPattern, bindings:Array<TyLocalBinding>, cursor:Array<Int>, catalog:TypedBackendLocalCatalog,
			names:haxe.ds.StringMap<String>):HxSwitchPattern {
		return switch (pattern) {
			case PBind(name):
				PBind(projectedPatternBinding(bindings, cursor, catalog, name, names));
			case PCapture(name, inner):
				final projectedName = projectedPatternBinding(bindings, cursor, catalog, name, names);
				PCapture(projectedName, projectPattern(inner, bindings, cursor, catalog, names));
			case PEnumExtract(name, arguments):
				PEnumExtract(name, [
					for (argument in arguments)
						projectPattern(argument, bindings, cursor, catalog, names)
				]);
			case PObject(fieldNames, fieldPatterns):
				PObject(fieldNames.copy(), [
					for (fieldPattern in fieldPatterns)
						projectPattern(fieldPattern, bindings, cursor, catalog, names)
				]);
			case PArray(items):
				PArray([for (item in items) projectPattern(item, bindings, cursor, catalog, names)]);
			case PExtractor(extractorText, resultPattern):
				PExtractor(extractorText, projectPattern(resultPattern, bindings, cursor, catalog, names));
			case PLengthGuard(inner, bindingName, length):
				final projectedInner = projectPattern(inner, bindings, cursor, catalog, names);
				PLengthGuard(projectedInner, projectedPatternReference(names, bindingName), length);
			case PStartsWithGuard(inner, bindingName, prefix):
				final projectedInner = projectPattern(inner, bindings, cursor, catalog, names);
				PStartsWithGuard(projectedInner, projectedPatternReference(names, bindingName), prefix);
			case PIntEqualsGuard(inner, bindingName, value):
				final projectedInner = projectPattern(inner, bindings, cursor, catalog, names);
				PIntEqualsGuard(projectedInner, projectedPatternReference(names, bindingName), value);
			case PIntCompareGuard(inner, bindingName, op, value):
				final projectedInner = projectPattern(inner, bindings, cursor, catalog, names);
				PIntCompareGuard(projectedInner, projectedPatternReference(names, bindingName), op, value);
			case PParsedIntSwitchGuard(inner, bindingName, multiplier, matchValue):
				final projectedInner = projectPattern(inner, bindings, cursor, catalog, names);
				PParsedIntSwitchGuard(projectedInner, projectedPatternReference(names, bindingName), multiplier, matchValue);
			case PUnsupportedGuard(inner):
				PUnsupportedGuard(projectPattern(inner, bindings, cursor, catalog, names));
			case POr(patterns):
				POr([
					for (child in patterns)
						projectPattern(child, bindings, cursor, catalog, names)
				]);
			case PNull: PNull;
			case PWildcard: PWildcard;
			case PBool(value): PBool(value);
			case PString(value): PString(value);
			case PInt(value): PInt(value);
			case PEnumValue(name): PEnumValue(name);
		};
	}

	static function projectPatterns(patterns:Array<HxSwitchPattern>, bindings:Array<TyLocalBinding>,
			catalog:Null<TypedBackendLocalCatalog>):Array<HxSwitchPattern> {
		if (catalog == null)
			return patterns == null ? [] : patterns.copy();
		final exactBindings = bindings == null ? [] : bindings;
		final cursor = [0];
		final projected = [
			for (pattern in patterns)
				projectPattern(pattern, exactBindings, cursor, catalog, new haxe.ds.StringMap<String>())
		];
		if (cursor[0] != exactBindings.length)
			throw "switch pattern projection consumed " + cursor[0] + " of " + exactBindings.length + " typed local bindings";
		return projected;
	}

	static function expressionTail(expressions:Array<TypedExpr>, start:Int, ?catalog:TypedBackendLocalCatalog,
			?projectionFacts:TypedBodyProjectionBuilder):Array<HxExpr> {
		final out = new Array<HxExpr>();
		for (index in start...expressions.length)
			out.push(expression(expressions[index], catalog, projectionFacts));
		return out;
	}

	/**
		Project the compiler-owned optional-lambda marker with the exact backend
		parameter names selected for its lambda.

		The parser records optional parameters as source names beside the lambda.
		Once two same-spelled locals need different backend names, those metadata
		names must move with the lambda bindings or the target can silently lose
		the optional default.
	**/
	static function optionalLambdaCall(expressions:Array<TypedExpr>, catalog:Null<TypedBackendLocalCatalog>,
			?projectionFacts:TypedBodyProjectionBuilder):HxExpr {
		if (expressions.length != 3)
			throw "typed optional-lambda marker has an invalid structural payload";
		final wrapped = expressions[1];
		final optionalArguments = expressions[2];
		final lambda = switch (wrapped.getTag()) {
			case Lambda:
				wrapped;
			case Call:
				final restChildren = wrapped.getExpressions();
				if (restChildren.length != 3
					|| restChildren[0].getTag() != NameRead
					|| restChildren[0].getTexts().length != 1
					|| restChildren[0].getTexts()[0] != "__hxhx_rest_lambda"
					|| restChildren[1].getTag() != Lambda)
					throw "typed optional-lambda marker does not wrap a lambda";
				restChildren[1];
			case _:
				throw "typed optional-lambda marker does not wrap a lambda";
		};
		if (optionalArguments.getTag() != ArrayDecl)
			throw "typed optional-lambda marker is missing its optional parameter list";
		final sourceNames = lambda.getTexts();
		final projectedNames = exactProjectedNames(catalog, lambda.getLocalBindings(), sourceNames, "typed optional lambda");
		final projectedOptionalNames = new Array<HxExpr>();
		for (optionalArgument in optionalArguments.getExpressions()) {
			if (optionalArgument.getTag() != StringValue || optionalArgument.getTexts().length != 1)
				throw "typed optional-lambda marker has a non-name parameter entry";
			final sourceName = optionalArgument.getTexts()[0];
			final index = sourceNames.indexOf(sourceName);
			if (index < 0)
				throw "typed optional-lambda marker references unknown parameter " + sourceName;
			projectedOptionalNames.push(EString(projectedNames[index]));
		}
		return ECall(expression(expressions[0], catalog, projectionFacts), [
			expression(wrapped, catalog, projectionFacts, true),
			EArrayDecl(projectedOptionalNames)
		]);
	}

	static function blockExpression(children:Array<TypedExpr>, resultType:TyType, ?catalog:TypedBackendLocalCatalog,
			?projectionFacts:TypedBodyProjectionBuilder):HxExpr {
		var continuation:HxExpr = ENull;
		var hasContinuation = false;
		var index = children.length - 1;
		while (index >= 0) {
			final child = children[index];
			switch (child.getTag()) {
				case Temporary:
					final texts = child.getTexts();
					final values = child.getExpressions();
					if (texts.length != 2 || values.length != 1)
						throw "typed temporary has an invalid structural payload";
					final projectedName = exactProjectedName(catalog, child.getLocalBindings(), texts[0], "typed temporary");
					final storageType = child.getLocalBindings()[0].getType();
					final binder:HxExpr = ECast(ELambda([projectedName], continuation), callableTypeHint(TyType.functionType([storageType], resultType), null));
					continuation = ECall(binder, [expression(values[0], catalog, projectionFacts)]);
					hasContinuation = true;
				case _:
					final projected = expression(child, catalog, projectionFacts);
					if (!hasContinuation) {
						continuation = projected;
					} else {
						continuation = EDiscardThen(projected, continuation);
					}
					hasContinuation = true;
			}
			index--;
		}
		return continuation;
	}

	/** Constant embedding must not discard evaluation of a value receiver. */
	static function constantTypeReceiver(receiver:TypedExpr):Bool {
		if (receiver.getFieldInfo() != null || receiver.getLocalBindings().length != 0)
			return false;
		return switch (receiver.getTag()) {
			case RuntimeTypeValue: true;
			case NameRead: true;
			case FieldRead: constantTypeReceiver(receiver.getExpressions()[0]);
			case _: false;
		};
	}

	/** Preserve the selected field and distinguish type qualification from receiver evaluation. */
	static function projectFieldRead(source:TypedExpr, catalog:Null<TypedBackendLocalCatalog>, facts:Null<TypedBodyProjectionBuilder>,
			use:TypedBackendMethodOccurrence.TypedMethodUse):HxExpr {
		final children = source.getExpressions();
		final field = source.getFieldInfo();
		final method = source.getDeclaration();
		// A class literal qualifies a static member; a class object in a local is a value.
		final target = children[0].getTag() == RuntimeTypeValue ? children[0].getRuntimeTypeTarget() : null;
		final owner = target == null ? null : target.getDeclarationIdentity();
		// Undeclared fields access the runtime class object, including a replaced
		// source binding. Only a selected static declaration permits qualification.
		final declaredStatic = (field != null && field.getIsStatic()) || (method != null && method.getIsStatic());
		var receiver = owner == null
			|| !declaredStatic ? expression(children[0], catalog,
				facts) : resolvedTypeExpression(target.getSourceSpelling(), field != null && field.getIsStatic() ? field.getOwner() : owner);
		if (field != null && field.getIsStatic()) {
			switch receiver {
				case EIdent(name):
					receiver = resolvedTypeExpression(name, field.getOwner());
				case _:
			}
		}
		final constant = field == null ? null : field.getConstant().project();
		if (constant != null && !constantTypeReceiver(children[0]))
			throw "enum constant read cannot discard a value receiver: " + field.getCanonicalKey();
		final projected:HxExpr = constant == null ? EField(receiver, source.getTexts()[0]) : constant;
		// Direct calls already retain their declaration on the call transport.
		// Its temporary callee field does not survive that projection.
		if (method != null && !method.getIsStatic() && facts != null && use != DirectCall)
			return facts.projectMethod(source, projected, use);
		if (constant == null && facts != null)
			facts.projectObjectAccess(source, projected);
		return constant != null
			|| field == null
			|| facts == null ? projected : facts.projectField(source, projected, constantTypeReceiver(children[0]) ? TypeQualifier : ValueReceiver);
	}

	public static function expression(typedExpression:TypedExpr, ?catalog:TypedBackendLocalCatalog, ?projectionFacts:TypedBodyProjectionBuilder,
			suppressCallableAscription:Bool = false, use:TypedBackendMethodOccurrence.TypedMethodUse = ValueRead):HxExpr {
		final texts = typedExpression.getTexts();
		final expressions = typedExpression.getExpressions();
		return switch (typedExpression.getTag()) {
			case ArrayAppend:
				ELoweredControl(ArrayAppend, "", expressionTail(expressions, 0, catalog, projectionFacts), sourcePosition(typedExpression.getPosition()));
			case MapInsert:
				ELoweredControl(MapInsert, "", expressionTail(expressions, 0, catalog, projectionFacts), sourcePosition(typedExpression.getPosition()));
			case Parenthesized:
				EParenthesized(expression(expressions[0], catalog, projectionFacts, suppressCallableAscription, use),
					typedExpression.getPosition() == null ? HxPos.unknown() : typedExpression.getPosition());
			case NullValue: ENull;
			case PrivateAccess:
				throw "source access permission must be consumed before backend projection";
			case FeatureDefinition | FeatureSelection:
				throw "feature intrinsics require program-owned selection before backend projection";
			case SourceGroup | SourceFunction | SourceIf | SourceFor | SourceTry:
				throw "source control must be lowered before backend projection (haxe_ocaml-o25kr)";
			case ControlTry:
				final catches = typedExpression.getSourceCatches();
				final names = exactProjectedNames(catalog, typedExpression.getLocalBindings(), [for (entry in catches) entry.getName()], "typed catch region");
				ELoweredControl(Try([
					for (index in 0...catches.length)
						new HxSourceCatch(names[index], catches[index].getTypeHint(), catches[index].getPosition())
				]), "",
					expressionTail(expressions, 0, catalog, projectionFacts), sourcePosition(typedExpression.getPosition()));
			case ControlBranch:
				ELoweredControl(Branch, "", expressionTail(expressions, 0, catalog, projectionFacts), sourcePosition(typedExpression.getPosition()));
			case ControlWhile:
				final target = typedExpression.getControlTarget();
				if (target == null)
					throw "lowered while requires an exact loop target";
				ELoweredControl(While(typedExpression.getWhileKind()), target.getCanonicalIdentity(),
					expressionTail(expressions, 0, catalog, projectionFacts), sourcePosition(typedExpression.getPosition()));
			case ThrowExpr:
				if (expressions.length != 1)
					throw "typed throw requires exactly one operand";
				final operand = expression(expressions[0], catalog, projectionFacts);
				ELoweredControl(Throw, "", [
					projectionFacts == null ? operand : projectionFacts.projectThrownValue(expressions[0], operand)
				], sourcePosition(typedExpression.getPosition()));
			case ControlSwitch:
				ELoweredControl(Switch(projectPatterns(typedExpression.getPatterns(), typedExpression.getLocalBindings(), catalog),
					typedExpression.getSwitchHasExhaustiveCoverage()),
					"", [for (child in expressions) expression(child, catalog, projectionFacts)], typedExpression.getPosition());
			case ControlFor:
				final target = typedExpression.getControlTarget();
				if (target == null)
					throw "lowered for requires an exact loop target";
				final names = exactProjectedNames(catalog, typedExpression.getLocalBindings(), texts, "typed for bindings");
				ELoweredControl(For(HxForBinding.fromNames(names)), target.getCanonicalIdentity(), expressionTail(expressions, 0, catalog, projectionFacts),
					sourcePosition(typedExpression.getPosition()));
			case ControlRegion:
				final target = typedExpression.getControlTarget();
				ELoweredControl(target == null ? Scope : FunctionBody, target == null ? "" : target.getCanonicalIdentity(),
					expressionTail(expressions, 0, catalog, projectionFacts), sourcePosition(typedExpression.getPosition()));
			case TargetScope:
				if (expressions.length != 1 || expressions[0].getTag() != ControlRegion)
					throw "native syntax scope requires its lowered lexical body";
				ELoweredControl(TargetScope(TypedTargetScope.kind(typedExpression)), "", expressionTail(expressions, 0, catalog, projectionFacts),
					sourcePosition(typedExpression.getPosition()));
			case BoolValue: EBool(typedExpression.getBoolValue());
			case StringValue: EString(texts[0]);
			case IntValue: EInt(typedExpression.getIntValue());
			case FloatValue: EFloat(typedExpression.getFloatValue());
			case EnumValue: EEnumValue(texts[0]);
			case RuntimeTypeValue | RuntimeTypeTest:
				if (projectionFacts == null)
					throw "runtime type expression requires an exact executable projection";
				final value = typedExpression.getTag() == RuntimeTypeTest ? expression(expressions[0], catalog, projectionFacts) : null;
				final valueType = typedExpression.getTag() == RuntimeTypeTest ? expressions[0].getType() : null;
				projectionFacts.projectRuntimeType(typedExpression.getRuntimeTypeTarget(), value, valueType);
			case ThisValue: EThis;
			case SuperValue: ESuper;
			case LocalRead: EIdent(exactProjectedName(catalog, typedExpression.getLocalBindings(), texts[0], "typed local read"));
			case NameRead:
				final nameField = typedExpression.getFieldInfo();
				final method = typedExpression.getDeclaration();
				if (method != null) {
					typedExpression.getRequiresOwnerQualification() ? EField(resolvedTypeExpression("", method.getOwner()),
						method.getSignature().getName()) : EIdent(method.getSignature().getName());
				} else if (nameField != null) {
					final constant = nameField.getConstant().project();
					final projected:HxExpr = constant != null ? constant : typedExpression.getRequiresOwnerQualification() ? EField(resolvedTypeExpression("",
						nameField.getOwner()), nameField.getName()) : EIdent(texts[0]);
					constant != null
					|| projectionFacts == null ? projected : projectionFacts.projectField(typedExpression, projected, ImplicitOwner);
				} else {
					final identity = typedExpression.getType().getNominalIdentity();
					resolvedTypeExpression(texts[0], identity);
				}
			case FieldRead: projectFieldRead(typedExpression, catalog, projectionFacts, use);
			case NullSafeFieldRead: ENullSafeField(expression(expressions[0], catalog, projectionFacts), texts[0]);
			case Call:
				if (expressions.length > 0 && expressions[0].getTag() == SuperValue) {
					final arguments = expressionTail(expressions, 1, catalog, projectionFacts);
					return projectionFacts == null ? ECall(ESuper, arguments) : projectionFacts.projectConstructor(typedExpression, "", arguments);
				}
				if (expressions.length == 3 && expressions[0].getTag() == NameRead) {
					final marker = expressions[0].getTexts()[0];
					if (marker == "__hxhx_optional_lambda")
						return ascribeCallable(optionalLambdaCall(expressions, catalog, projectionFacts), typedExpression, suppressCallableAscription,
							projectionFacts);
					if (marker == "__hxhx_rest_lambda")
						return ascribeCallable(ECall(EIdent(marker), [
							expression(expressions[1], catalog, projectionFacts, true),
							expression(expressions[2], catalog, projectionFacts)
						]), typedExpression, suppressCallableAscription, projectionFacts);
				}
				final declaration = typedExpression.getDeclaration();
				final extensionProvider = typedExpression.getExtensionProvider();
				final sourceCallee = expressions[0];
				final staticTypeQualifier = declaration != null
					&& declaration.getIsStatic()
					&& extensionProvider == null
					&& sourceCallee.getTag() == FieldRead
					&& sourceCallee.getExpressions()[0].getTag() == RuntimeTypeValue;
				final callee:HxExpr = staticTypeQualifier ? EField(resolvedTypeExpression(sourceCallee.getExpressions()[0].getRuntimeTypeTarget()
				.getSourceSpelling(), declaration.getOwner()),
					declaration.getSignature().getName()) : expression(sourceCallee, catalog, projectionFacts, false, DirectCall);
				final projectedArguments = expressionTail(expressions, 1, catalog, projectionFacts);
				if (projectionFacts != null)
					projectionFacts.projectCallArguments(typedExpression, projectedArguments);
				final named = typedExpression.getNamedArguments();
				final binding = named == null ? typedExpression.getArgumentBinding() : named.getArguments();
				final positionalArguments = binding == null ? projectedArguments : TypedCallArgumentSource.arguments(binding, projectedArguments);
				final arguments = declaration == null
					&& sourceCallee.getTag() == NameRead ? TypedControlBodySource.arguments(sourceCallee.getTexts()[0],
						positionalArguments) : positionalArguments;
				if (extensionProvider != null) {
					if (declaration == null || !declaration.getIsStatic())
						throw "typed extension call is missing its exact static declaration";
					switch (callee) {
						case EField(receiver, _):
							TypedExactStaticCallSource.encode(declaration.getOwner().getCanonicalName(), declaration.getIdentity().getCanonicalKey(),
								declaration.getSignature().getName(), projectedTypeHint(typedExpression.getType()),
								EField(resolvedTypeExpression("", extensionProvider), declaration.getSignature().getName()), [receiver].concat(arguments));
						case _:
							throw "typed extension call does not retain its receiver field shape";
					}
				} else if (declaration == null
					&& expressions[0].getTag() == NameRead
					&& expressions[0].getTexts().length == 1
					&& expressions[0].getTexts()[0] == "__hxhx_optional_lambda") {
					optionalLambdaCall(expressions, catalog, projectionFacts);
				} else if (declaration != null && declaration.getIsEnumConstructor()) {
					TypedExactEnumConstructorSource.encode(declaration.getOwner().getCanonicalName(), declaration.getModulePath(),
						declaration.getIdentity().getCanonicalKey(), declaration.getSignature().getName(), callee, arguments);
				} else if (declaration == null || declaration.getIsStatic()) {
					if (declaration != null) {
						final ordinary:HxExpr = switch (callee) {
							case EIdent(_) if (typedExpression.getRequiresOwnerQualification()):
								EField(resolvedTypeExpression("", declaration.getOwner()), declaration.getSignature().getName());
							case EField(EIdent(name), method):
								EField(resolvedTypeExpression(name, declaration.getOwner()), method);
							case _: callee;
						};
						TypedExactStaticCallSource.encode(declaration.getOwner().getCanonicalName(), declaration.getIdentity().getCanonicalKey(),
							declaration.getSignature().getName(), projectedTypeHint(typedExpression.getType()), ordinary, arguments);
					} else {
						ECall(callee, arguments);
					}
				} else {
					switch (callee) {
						case EField(receiver, method):
							final call = TypedExactCallSource.encodeInstance(declaration.getOwner().getCanonicalName(),
								declaration.getIdentity().getCanonicalKey(), method, projectedTypeHint(typedExpression.getType()), receiver, arguments);
							projectionFacts == null ? call : projectionFacts.projectInstanceCall(typedExpression, call);
						case EIdent(method):
							// A selected instance declaration supplies an implicit this
							// receiver even when no owner-name qualification is needed.
							final call = TypedExactCallSource.encodeInstance(declaration.getOwner().getCanonicalName(),
								declaration.getIdentity().getCanonicalKey(), method, projectedTypeHint(typedExpression.getType()), EThis, arguments);
							projectionFacts == null ? call : projectionFacts.projectInstanceCall(typedExpression, call);
						case _:
							ECall(callee, arguments);
					}
				}
			case ReturnExpr:
				final target = typedExpression.getControlTarget();
				if (target == null) EReturn(expressions.length == 0 ? null : expression(expressions[0], catalog,
					projectionFacts)); else ELoweredControl(Return, target.getCanonicalIdentity(), expressionTail(expressions, 0, catalog, projectionFacts),
					sourcePosition(typedExpression.getPosition()));
			case VariableDeclarations:
				final declarations = new Array<HxExpr>();
				for (declaration in expressions) {
					if (declaration.getTag() != VariableDeclaration)
						throw "typed variable declaration list contains a non-declaration child";
					final declarationTexts = declaration.getTexts();
					final declarationValues = declaration.getExpressions();
					final projectedName = exactProjectedName(catalog, declaration.getLocalBindings(), declarationTexts[0], "typed expression variable");
					var value = declarationValues.length == 0 ? null : expression(declarationValues[0], catalog, projectionFacts);
					if (value != null && catalog != null && projectionFacts != null)
						value = projectionFacts.projectLocalWrite(projectedName, declaration.getLocalBindings()[0], declarationValues[0], value);
					declarations.push(HxExprVarDecl.make(projectedName, declarationTexts[1], value, sourcePosition(declaration.getPosition()),
						declaration.getVariableIsFinal(), declaration.getVariableIsStatic()));
				}
				EVars(declarations);
			case VariableDeclaration:
				throw "typed variable declaration must be nested inside a declaration list";
			case WhileExpr:
				EWhile(expression(expressions[0], catalog, projectionFacts), expressionTail(expressions, 1, catalog, projectionFacts),
					typedExpression.getBoolValue(), sourcePosition(typedExpression.getPosition()), typedExpression.getWhileKind());
			case BreakExpr | ContinueExpr:
				final target = typedExpression.getControlTarget();
				final position = sourcePosition(typedExpression.getPosition());
				if (target == null) {
					typedExpression.getTag() == BreakExpr ? EBreak(position) : EContinue(position);
				} else {
					ELoweredControl(typedExpression.getTag() == BreakExpr ? Break : Continue, target.getCanonicalIdentity(), [], position);
				}
			case MacroExpr: EMacroExpr(TypedSourceSyntax.expression(expressions[0]), texts.copy());
			case MacroType: EMacroType(texts[0]);
			case Lambda:
				final lambda:HxExpr = ELambda(exactProjectedNames(catalog, typedExpression.getLocalBindings(), texts, "typed lambda"),
					expression(expressions[0], catalog, projectionFacts), typedExpression.getLambdaSignature());
				ascribeCallable(projectionFacts == null ? lambda : projectionFacts.projectLambda(typedExpression, lambda), typedExpression,
					suppressCallableAscription, projectionFacts);
			case SwitchExpr:
				ESwitch(expression(expressions[0], catalog, projectionFacts),
					projectPatterns(typedExpression.getPatterns(), typedExpression.getLocalBindings(), catalog),
					expressionTail(expressions, 1, catalog, projectionFacts));
			case NewValue:
				final identity = typedExpression.getType().getNominalIdentity();
				final path = resolvedNameWhenAliased(texts[0], identity);
				final arguments = expressionTail(expressions, 0, catalog, projectionFacts);
				projectionFacts == null ? ENew(path, arguments) : projectionFacts.projectConstructor(typedExpression, path, arguments);
			case Unary: EUnop(typedExpression.getUnaryOperator(), typedExpression.getUnaryFixity(), expression(expressions[0], catalog, projectionFacts));
			case Binary: EBinop(texts[0], expression(expressions[0], catalog, projectionFacts), expression(expressions[1], catalog, projectionFacts));
			case Assign | CompoundAssign:
				final target = expression(expressions[0], catalog, projectionFacts, false, WriteTarget);
				var value = expression(expressions[1], catalog, projectionFacts);
				if (projectionFacts != null && catalog != null && expressions[0].getTag() == LocalRead) {
					final binding = expressions[0].getLocalBindings()[0];
					value = projectionFacts.projectLocalWrite(catalog.projectedName(binding), binding, expressions[1], value);
				}
				final assignment:HxExpr = EBinop(typedExpression.getTag() == Assign ? "=" : texts[0], target, value);
				projectionFacts == null ? assignment : projectionFacts.projectObjectAccess(typedExpression, assignment);
			case Ternary:
				ETernary(expression(expressions[0], catalog, projectionFacts), expression(expressions[1], catalog, projectionFacts),
					expression(expressions[2], catalog, projectionFacts));
			case Anonymous:
				final children = expressionTail(expressions, 0, catalog, projectionFacts);
				projectionFacts == null ? EAnon(texts.copy(), children) : projectionFacts.projectAggregate(typedExpression, children);
			case ArrayComprehension:
				final children = expressionTail(expressions, 0, catalog, projectionFacts);
				final guard = typedExpression.getBoolValue() ? children[1] : null;
				final valueIndex = typedExpression.getBoolValue() ? 2 : 1;
				final projectedName = exactProjectedName(catalog, typedExpression.getLocalBindings(), texts[0], "typed array comprehension");
				EArrayComprehension(projectedName, children[0], guard, children[valueIndex]);
			case ArrayDecl:
				final children = expressionTail(expressions, 0, catalog, projectionFacts);
				projectionFacts == null ? EArrayDecl(children) : projectionFacts.projectAggregate(typedExpression, children);
			case ArrayAccess: EArrayAccess(expression(expressions[0], catalog, projectionFacts), expression(expressions[1], catalog, projectionFacts));
			case Range | FixedRange: ERange(expression(expressions[0], catalog, projectionFacts), expression(expressions[1], catalog, projectionFacts));
			case Cast:
				final operand = expression(expressions[0], catalog, projectionFacts);
				projectionFacts == null ? ECast(operand, texts[0]) : projectionFacts.projectCast(typedExpression, operand);
			case Untyped: EUntyped(expression(expressions[0], catalog, projectionFacts));
			case Opaque:
				switch (typedExpression.getOpaqueKind()) {
					case TryCatch: ETryCatchRaw(texts[0]);
					case Switch: ESwitchRaw(texts[0]);
					case Unsupported: EUnsupported(texts[0]);
					case null: throw "typed opaque expression is missing its kind";
				}
			case Block: blockExpression(expressions, typedExpression.getType(), catalog, projectionFacts);
			case Temporary:
				throw "typed temporary must be nested inside a typed block expression";
		};
	}

	public static function statement(typedStatement:TypedStmt, ?catalog:TypedBackendLocalCatalog, ?projectionFacts:TypedBodyProjectionBuilder):HxStmt {
		final position = sourcePosition(typedStatement.getPosition());
		final names = typedStatement.getNames();
		final expressions = typedStatement.getExpressions();
		final statements = typedStatement.getStatements();
		final projected:HxStmt = switch (typedStatement.getTag()) {
			case Block: SBlock([for (entry in statements) statement(entry, catalog, projectionFacts)], position);
			case Var:
				final typedInitializer = expressions.length == 1 ? expressions[0] : null;
				final bindings = typedStatement.getLocalBindings();
				final storageType = bindings.length == 1 ? bindings[0].getType() : null;
				final typeHint = storageType != null
					&& storageType.isFunction()
					&& !storageType.hasUnknownComponent() ? callableTypeHint(storageType,
						typedInitializer == null ? null : callableSignature(typedInitializer)) : variableTypeHint(names[1], typedInitializer);
				var initializer:Null<HxExpr> = null;
				if (expressions.length > 0)
					initializer = expression(expressions[0], catalog, projectionFacts);
				final projectedName = exactProjectedName(catalog, typedStatement.getLocalBindings(), names[0], "typed variable statement");
				if (initializer != null && projectionFacts != null && catalog != null)
					initializer = projectionFacts.projectLocalWrite(projectedName, bindings[0], expressions[0], initializer);
				SVar(projectedName, typeHint, initializer, position, typedStatement.getMetadata());
			case If:
				var whenFalse:Null<HxStmt> = null;
				if (statements.length > 1)
					whenFalse = statement(statements[1], catalog, projectionFacts);
				SIf(expression(expressions[0], catalog, projectionFacts), statement(statements[0], catalog, projectionFacts), whenFalse, position);
			case ForIn:
				final projectedName = exactProjectedName(catalog, typedStatement.getLocalBindings(), names[0], "typed for-in statement");
				SForIn(projectedName, expression(expressions[0], catalog, projectionFacts), statement(statements[0], catalog, projectionFacts), position);
			case ForKeyValue:
				final projectedNames = exactProjectedNames(catalog, typedStatement.getLocalBindings(), names, "typed key/value for-in statement");
				SForKeyValue(projectedNames[0], projectedNames[1], expression(expressions[0], catalog, projectionFacts),
					statement(statements[0], catalog, projectionFacts), position);
			case While: SWhile(expression(expressions[0], catalog, projectionFacts), statement(statements[0], catalog, projectionFacts), position);
			case DoWhile: SDoWhile(statement(statements[0], catalog, projectionFacts), expression(expressions[0], catalog, projectionFacts), position);
			case Switch:
				SSwitch(expression(expressions[0], catalog, projectionFacts),
					projectPatterns(typedStatement.getPatterns(), typedStatement.getLocalBindings(), catalog),
					[for (body in statements) statement(body, catalog, projectionFacts)], position, typedStatement.getSwitchHasExhaustiveCoverage());
			case Try:
				final catchNames = typedStatement.getCatchNames();
				final catchTypeHints = typedStatement.getCatchTypeHints();
				final projectedCatchNames = exactProjectedNames(catalog, typedStatement.getLocalBindings(), catchNames, "typed catch statement");
				final catches = new Array<{name:String, typeHint:String, body:HxStmt}>();
				for (index in 0...catchNames.length)
					catches.push({
						name: projectedCatchNames[index],
						typeHint: catchTypeHints[index],
						body: statement(statements[index + 1], catalog, projectionFacts)
					});
				STry(statement(statements[0], catalog, projectionFacts), catches, position);
			case Break: SBreak(position);
			case Continue: SContinue(position);
			case Throw:
				final operand = expression(expressions[0], catalog, projectionFacts);
				SThrow(projectionFacts == null ? operand : projectionFacts.projectThrownValue(expressions[0], operand), position);
			case ReturnVoid: SReturnVoid(position);
			case Return: SReturn(expression(expressions[0], catalog, projectionFacts), position);
			case Expression: SExpr(expression(expressions[0], catalog, projectionFacts), position);
		};
		return projectionFacts == null ? projected : projectionFacts.projectStatementControl(typedStatement, projected);
	}

	public static function statements(body:TypedFunctionBody, ?catalog:TypedBackendLocalCatalog, ?projectionFacts:TypedBodyProjectionBuilder):Array<HxStmt>
		return [for (entry in body.getStatements()) statement(entry, catalog, projectionFacts)];

	public static function functionDeclaration(typedFunction:TypedFunction, ?catalog:TypedBackendLocalCatalog,
			?projectionFacts:TypedBodyProjectionBuilder):HxFunctionDecl {
		typedFunction.assertParsedBodyCurrent();
		typedFunction = TypedControlLowering.functionBody(typedFunction);
		final source = typedFunction.getSourceDeclaration();
		var arguments = HxFunctionDecl.getArgs(source);
		var returnTypeHint = HxFunctionDecl.getReturnTypeHint(source);
		final declaration = typedFunction.getDeclaration();
		final environment = typedFunction.getEnvironment();
		final parameterBindings = environment == null ? [] : [for (parameter in environment.getParams()) parameter.toBinding()];
		if (catalog != null && environment != null && parameterBindings.length != arguments.length)
			throw "typed backend function projection parameter count mismatch for " + typedFunction.getStableIdentity();
		final semanticArguments = declaration == null ? [] : declaration.getSignature().getArgs();
		final defaults = typedFunction.getDefaults();
		arguments = [
			for (index in 0...arguments.length) {
				final argument = arguments[index];
				final sourceHint = HxFunctionArg.getTypeHint(argument);
				final renderedHint = sourceHint.length == 0
					|| HxFunctionArg.getIsRest(argument)
					|| index >= semanticArguments.length
					|| !containsAliasSpelling(semanticArguments[index]) ? sourceHint : canonicalTypeHint(semanticArguments[index]);
				final projectedName = catalog == null
					|| environment == null ? HxFunctionArg.getName(argument) : catalog.projectedName(parameterBindings[index]);
				var projectedDefault = HxDefaultValue.NoDefault;
				for (value in defaults)
					if (value.getParameterIndex() == index)
						projectedDefault = HxDefaultValue.Default(expression(value.getExpression(), catalog, projectionFacts));
				new HxFunctionArg(projectedName, renderedHint, projectedDefault, HxFunctionArg.getIsOptional(argument), HxFunctionArg.getIsRest(argument), "",
					HxFunctionArg.getMetadata(argument));
			}
		];
		if (declaration != null) {
			final signature = declaration.getSignature();
			if (returnTypeHint.length > 0 && containsAliasSpelling(signature.getReturnType()))
				returnTypeHint = canonicalTypeHint(signature.getReturnType());
		}
		return new HxFunctionDecl(HxFunctionDecl.getName(source), HxFunctionDecl.getVisibility(source), HxFunctionDecl.getIsStatic(source), arguments,
			returnTypeHint, statements(typedFunction.getBody(), catalog, projectionFacts), HxFunctionDecl.getReturnStringLiteral(source),
			HxFunctionDecl.getMetadata(source), HxFunctionDecl.getPos(source), HxFunctionDecl.getEndPos(source), "", HxFunctionDecl.getHasBody(source));
	}

	/** Project one function while keeping its exact local and bare field-read catalogs inseparable from the source-shaped body. **/
	public static function functionProjection(typedFunction:TypedFunction):TypedBackendFunctionProjection {
		typedFunction.assertParsedBodyCurrent();
		final source = typedFunction;
		final identity = typedFunction.getStableIdentity();
		final revision = CompilerTypedTreeRevision.functionBody(typedFunction);
		typedFunction = TypedControlLowering.functionBody(typedFunction);
		final projectionFacts = new TypedBodyProjectionBuilder(identity, revision);
		final fields = fieldReadCatalog(typedFunction);
		final locals = localCatalog(typedFunction, fields.getReservedProjectedNames());
		final environment = typedFunction.getEnvironment();
		final parameterBindingIdentities = environment == null ? [] : [
			for (parameter in environment.getParams())
				parameter.getIdentity().getCanonicalKey()
		];
		final returnType = if (environment != null) {
			environment.getReturnType();
		} else {
			final declaration = typedFunction.getDeclaration();
			declaration == null ? TyType.fromHintText(HxFunctionDecl.getReturnTypeHint(typedFunction.getSourceDeclaration())) : declaration.getSignature()
				.getReturnType();
		};
		final projectedDeclaration = functionDeclaration(typedFunction, locals, projectionFacts);
		final facts = projectionFacts.seal(TypedRuntimeTypeSource.inFunction(projectedDeclaration), TypedConstructorSource.inFunction(projectedDeclaration));
		return new TypedBackendFunctionProjection(source, typedFunction, projectedDeclaration, locals, returnType, fields, parameterBindingIdentities,
			facts.runtimeTypes, facts.constructors, projectionFacts.getAggregates(), projectionFacts.getFields(), projectionFacts.getCasts(),
			projectionFacts.getThrownValues(), projectionFacts.getLocalWrites(), projectionFacts.getObjectAccesses(), projectionFacts.getCallArguments(),
			projectionFacts.getMethods(), projectionFacts.getLambdas(), projectionFacts.getInstanceCalls(), projectionFacts.getStatementControls());
	}

	/** Project one field from its resolved type and typed initializer when available. **/
	static function fieldDeclaration(source:HxFieldDecl, semanticInfo:Null<TyNominalInfo>, initializer:Null<HxExpr>):HxFieldDecl {
		var typeHint = HxFieldDecl.getTypeHint(source);
		if (typeHint.length > 0 && semanticInfo != null) {
			final fieldInfo = semanticInfo.fieldInfo(HxFieldDecl.getName(source));
			if (fieldInfo != null && containsAliasSpelling(fieldInfo.getType()))
				typeHint = canonicalTypeHint(fieldInfo.getType());
		}
		final projectedInitializer = initializer == null ? HxFieldDecl.getInit(source) : initializer;
		return new HxFieldDecl(HxFieldDecl.getName(source), HxFieldDecl.getVisibility(source), HxFieldDecl.getIsStatic(source), typeHint,
			projectedInitializer, HxFieldDecl.getMetadata(source), HxFieldDecl.getPos(source), HxFieldDecl.getEndPos(source), HxFieldDecl.getIsFinal(source),
			HxFieldDecl.getPropertyGet(source), HxFieldDecl.getPropertySet(source), initializer == null ? HxFieldDecl.getInitText(source) : "");
	}

	static function fieldInitializerProjection(source:HxFieldDecl, semanticInfo:Null<TyNominalInfo>,
			initializer:TypedFieldInitializer):TypedBackendFieldInitializerProjection {
		final typedExpression = initializer.getExpression();
		final lowered = TypedControlLowering.fieldInitializer(initializer);
		if (lowered.completes && lowered.value == null)
			throw "field initializer requires a normally produced value";
		final entries = lowered.steps.copy();
		if (lowered.value != null)
			entries.push(lowered.value);
		final reads = new Array<TypedBackendFieldReadProjection>();
		final bindings = new haxe.ds.StringMap<TyLocalBinding>();
		final uses = new Array<TypedCatchUse>();
		for (entry in entries) {
			collectExpressionFieldReads(entry, reads);
			collectExpressionBindings(entry, bindings, uses);
		}
		final fieldReads = new TypedBackendFieldReadCatalog(reads);
		final locals = new TypedBackendLocalCatalog([for (binding in bindings) binding], fieldReads.getReservedProjectedNames(), uses);
		final field = initializer.getField();
		// Typing and lowering already assign initializer locals to this exact field.
		final identity = field.getCanonicalKey();
		final revision = CompilerTypedTreeRevision.expression(field.getCanonicalKey(), typedExpression);
		final projectionFacts = new TypedBodyProjectionBuilder(identity, revision);
		final projected = [for (entry in entries) expression(entry, locals, projectionFacts)];
		final body:HxExpr = lowered.steps.length == 0
			&& lowered.value != null ? projected[0] : ELoweredControl(Initializer(lowered.value != null), identity, projected,
				sourcePosition(typedExpression.getPosition()));
		final declaration = fieldDeclaration(source, semanticInfo, body);
		final facts = projectionFacts.seal(TypedRuntimeTypeSource.inExpression(body), TypedConstructorSource.inExpression(body));
		return new TypedBackendFieldInitializerProjection(initializer, lowered, identity, revision, field, declaration, locals, fieldReads,
			facts.runtimeTypes, facts.constructors, projectionFacts.getFields(), projectionFacts.getAggregates(), projectionFacts.getCasts(),
			projectionFacts.getObjectAccesses(), projectionFacts.getLocalWrites(), projectionFacts.getCallArguments(), projectionFacts.getMethods(),
			projectionFacts.getLambdas(), projectionFacts.getInstanceCalls());
	}

	static function projectedClassDeclaration(typedClass:TypedClass, functions:Array<HxFunctionDecl>, fields:Array<HxFieldDecl>):HxClassDecl {
		final source = typedClass.getSourceDeclaration();
		var extendsPath = HxClassDecl.getExtendsPath(source);
		final resolvedExtends = typedClass.getResolvedExtends();
		if (resolvedExtends != null && containsAliasSpelling(resolvedExtends))
			extendsPath = canonicalTypeHint(resolvedExtends);
		final sourceImplements = HxClassDecl.getImplementsPaths(source);
		final resolvedImplements = typedClass.getResolvedImplements();
		final implementsPaths = [
			for (index in 0...sourceImplements.length) {
				final resolved = index < resolvedImplements.length ? resolvedImplements[index] : null;
				resolved != null
			&& containsAliasSpelling(resolved) ? canonicalTypeHint(resolved) : sourceImplements[index];
			}
		];
		final sourceInterfaceExtends = HxClassDecl.getInterfaceExtendsPaths(source);
		final resolvedInterfaceExtends = typedClass.getResolvedInterfaceExtends();
		final interfaceExtendsPaths = [
			for (index in 0...sourceInterfaceExtends.length) {
				final resolved = index < resolvedInterfaceExtends.length ? resolvedInterfaceExtends[index] : null;
				resolved != null
			&& containsAliasSpelling(resolved) ? canonicalTypeHint(resolved) : sourceInterfaceExtends[index];
			}
		];
		return new HxClassDecl(HxClassDecl.getName(source), HxClassDecl.getHasStaticMain(source), functions, fields, extendsPath,
			HxClassDecl.getMetadata(source), HxClassDecl.getIsInterface(source), implementsPaths, HxClassDecl.getVisibility(source), interfaceExtendsPaths,
			HxClassDecl.getIsExtern(source), HxClassDecl.getEnumDeclaration(source), HxClassDecl.getTypeParameters(source));
	}

	public static function classProjection(typedClass:TypedClass):TypedBackendClassProjection {
		final functions = [
			for (typedFunction in typedClass.getFunctions())
				functionProjection(typedFunction)
		];
		final initializerByField = new Map<String, TypedFieldInitializer>();
		for (initializer in typedClass.getFieldInitializers())
			initializerByField.set(initializer.getField().getName(), initializer);
		final fieldInitializers = new Array<TypedBackendFieldInitializerProjection>();
		final fields = new Array<HxFieldDecl>();
		for (field in typedClass.getFields()) {
			final initializer = initializerByField.get(HxFieldDecl.getName(field));
			if (initializer == null) {
				fields.push(fieldDeclaration(field, typedClass.getSemanticInfo(), null));
			} else {
				final projection = fieldInitializerProjection(field, typedClass.getSemanticInfo(), initializer);
				fieldInitializers.push(projection);
				fields.push(projection.getDeclaration());
			}
		}
		final declaration = projectedClassDeclaration(typedClass, [for (projectedFunction in functions) projectedFunction.getDeclaration()], fields);
		final semanticInfo = typedClass.getSemanticInfo();
		// The semantic index already owns the exact structural superclass,
		// including class-parameter binder identities. The older projected
		// `resolvedExtends` spelling may still contain unresolved type arguments
		// and must not become a competing backend semantic input.
		// Interface headers finish loading their providers during typing. Their
		// resolved types retain the indexed generic binders and refine early names.
		final interfaces = HxClassDecl.getIsInterface(typedClass.getSourceDeclaration()) ? typedClass.getResolvedInterfaceExtends() : typedClass.getResolvedImplements();
		final semanticFacts = semanticInfo == null ? null : new TypedBackendClassSemanticFacts(semanticInfo, null, typedClass.getFunctions(), interfaces,
			HxClassDecl.getEnumDeclaration(typedClass.getSourceDeclaration()), typedClass.getDeclaredFieldTypes());
		return new TypedBackendClassProjection(declaration, functions, fieldInitializers, semanticFacts);
	}

	public static function classDeclaration(typedClass:TypedClass):HxClassDecl
		return classProjection(typedClass).getDeclaration();

	static function projectedModuleDeclaration(parsed:ParsedModule, typedClasses:Array<TypedClass>, classes:Array<HxClassDecl>):HxModuleDecl {
		if (typedClasses.length != classes.length)
			throw "typed module projection class count mismatch";
		final source = parsed.getDecl();
		final sourceMain = HxModuleDecl.getMainClass(source);
		// Empty class catalogs retain header metadata without inventing a typed class.
		var mainClass:Null<HxClassDecl> = classes.length == 0 && HxModuleDecl.getClasses(source).length == 0 ? sourceMain : null;
		for (index in 0...typedClasses.length)
			if (typedClasses[index].getSourceDeclaration() == sourceMain) {
				mainClass = classes[index];
				break;
			}
		if (mainClass == null) {
			final expectedName = HxClassDecl.getName(sourceMain);
			for (projected in classes)
				if (HxClassDecl.getName(projected) == expectedName) {
					mainClass = projected;
					break;
				}
		}
		if (mainClass == null) {
			// Retention can leave only a secondary type. Preserve the module header
			// name without copying removed executable bodies into the projection.
			mainClass = projectedClassDeclaration(new TypedClass(sourceMain, null, []), [], []);
		}
		return new HxModuleDecl(HxModuleDecl.getPackagePath(source), HxModuleDecl.getDirectives(source), mainClass, classes,
			HxModuleDecl.getHeaderOnly(source), HxModuleDecl.getHasToplevelMain(source), HxModuleDecl.getTypedefs(source));
	}

	/** Build the declaration plus exact typed-local and bare field-read catalogs consumed during backend migration. **/
	public static function moduleProjection(parsed:ParsedModule, typedClasses:Array<TypedClass>):TypedBackendModuleProjection {
		final classProjections = new Array<TypedBackendClassProjection>();
		final classes = new Array<HxClassDecl>();
		for (typedClass in typedClasses) {
			final projectedClass = classProjection(typedClass);
			final projected = projectedClass.getDeclaration();
			classProjections.push(projectedClass);
			classes.push(projected);
		}
		final declaration = projectedModuleDeclaration(parsed, typedClasses, classes);
		return new TypedBackendModuleProjection(declaration, classProjections);
	}

	/**
		Build the legacy declaration-only view and exact stable-function lookup
		together, before either object leaves the typed owner.
	**/
	public static function moduleDeclarationCatalog(parsed:ParsedModule, typedClasses:Array<TypedClass>):TypedBackendDeclarationCatalog {
		final classes = new Array<HxClassDecl>();
		final runtimeTypeCatalogs = new Array<TypedBackendRuntimeTypeCatalog>();
		final initializerProjections = new Array<TypedBackendFieldInitializerProjection>();
		final functionEntries = new Array<TypedBackendDeclarationCatalog.TypedBackendFunctionDeclarationEntry>();
		for (typedClass in typedClasses) {
			final projectedFunctions = new Array<HxFunctionDecl>();
			final classFunctions = new Array<{
				declaration:HxFunctionDecl,
				stableIdentity:String,
				bodyRevision:String,
				constructorCatalog:TypedBackendConstructorCatalog
			}>();
			for (typedFunction in typedClass.getFunctions()) {
				final projectionFacts = new TypedBodyProjectionBuilder(typedFunction.getStableIdentity(),
					CompilerTypedTreeRevision.functionBody(typedFunction));
				final projectedFunction = functionDeclaration(typedFunction, null, projectionFacts);
				final body = HxFunctionDecl.getBody(projectedFunction);
				final facts = projectionFacts.seal(TypedRuntimeTypeSource.inStatements(body), TypedConstructorSource.inStatements(body));
				runtimeTypeCatalogs.push(facts.runtimeTypes);
				projectedFunctions.push(projectedFunction);
				classFunctions.push({
					declaration: projectedFunction,
					stableIdentity: typedFunction.getStableIdentity(),
					bodyRevision: CompilerTypedTreeRevision.functionBody(typedFunction),
					constructorCatalog: facts.constructors
				});
			}
			final initializerByField = new Map<String, TypedFieldInitializer>();
			for (initializer in typedClass.getFieldInitializers())
				initializerByField.set(initializer.getField().getName(), initializer);
			final projectedFields = [
				for (field in typedClass.getFields()) {
					final initializer = initializerByField.get(HxFieldDecl.getName(field));
					if (initializer == null) {
						fieldDeclaration(field, typedClass.getSemanticInfo(), null);
					} else {
						final projection = fieldInitializerProjection(field, typedClass.getSemanticInfo(), initializer);
						runtimeTypeCatalogs.push(projection.getRuntimeTypeCatalog());
						initializerProjections.push(projection);
						projection.getDeclaration();
					}
				}
			];
			final projectedClass = projectedClassDeclaration(typedClass, projectedFunctions, projectedFields);
			classes.push(projectedClass);
			for (classFunction in classFunctions)
				functionEntries.push({
					backendClass: projectedClass,
					backendFunction: classFunction.declaration,
					stableIdentity: classFunction.stableIdentity,
					bodyRevision: classFunction.bodyRevision,
					constructorCatalog: classFunction.constructorCatalog
				});
		}
		return new TypedBackendDeclarationCatalog(projectedModuleDeclaration(parsed, typedClasses, classes), functionEntries, runtimeTypeCatalogs,
			initializerProjections);
	}
}
