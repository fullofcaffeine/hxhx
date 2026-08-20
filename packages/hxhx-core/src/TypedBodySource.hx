/**
	Projects a structural typed body to the source-shaped nodes understood by the
	current backend emitters.

	This adapter is a migration seam: it reads only typed nodes, never a parsed
	function body. Typed expression blocks become structural continuation calls,
	so no source text is reparsed and later semantic lowering remains authoritative.
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

	static function collectExpressionBindings(expression:TypedExpr, bindings:haxe.ds.StringMap<TyLocalBinding>):Void {
		for (binding in expression.getLocalBindings())
			addBinding(bindings, binding);
		for (child in expression.getExpressions())
			collectExpressionBindings(child, bindings);
	}

	static function collectStatementBindings(statement:TypedStmt, bindings:haxe.ds.StringMap<TyLocalBinding>):Void {
		for (binding in statement.getLocalBindings())
			addBinding(bindings, binding);
		for (expression in statement.getExpressions())
			collectExpressionBindings(expression, bindings);
		for (child in statement.getStatements())
			collectStatementBindings(child, bindings);
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
		for (statement in typedFunction.getBody().getStatements())
			collectStatementFieldReads(statement, reads);
		return new TypedBackendFieldReadCatalog(reads);
	}

	static function fieldReadCatalogForExpression(expression:TypedExpr):TypedBackendFieldReadCatalog {
		final reads = new Array<TypedBackendFieldReadProjection>();
		collectExpressionFieldReads(expression, reads);
		return new TypedBackendFieldReadCatalog(reads);
	}

	static function localCatalog(typedFunction:TypedFunction, reservedProjectedNames:Array<String>):TypedBackendLocalCatalog {
		final bindings = new haxe.ds.StringMap<TyLocalBinding>();
		final environment = typedFunction.getEnvironment();
		if (environment != null)
			for (parameter in environment.getParams())
				addBinding(bindings, parameter.toBinding());
		for (statement in typedFunction.getBody().getStatements())
			collectStatementBindings(statement, bindings);
		final ordered = new Array<TyLocalBinding>();
		for (binding in bindings)
			ordered.push(binding);
		return new TypedBackendLocalCatalog(ordered, reservedProjectedNames);
	}

	static function localCatalogForExpression(expression:TypedExpr, reservedProjectedNames:Array<String>):TypedBackendLocalCatalog {
		final bindings = new haxe.ds.StringMap<TyLocalBinding>();
		collectExpressionBindings(expression, bindings);
		final ordered = new Array<TyLocalBinding>();
		for (binding in bindings)
			ordered.push(binding);
		return new TypedBackendLocalCatalog(ordered, reservedProjectedNames);
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
		if (resolved == sourceName || resolved.indexOf(".") < 0)
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
			case _: initializer.getType().getDisplay();
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

	static function expressionTail(expressions:Array<TypedExpr>, start:Int, ?catalog:TypedBackendLocalCatalog):Array<HxExpr> {
		final out = new Array<HxExpr>();
		for (index in start...expressions.length)
			out.push(expression(expressions[index], catalog));
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
	static function optionalLambdaCall(expressions:Array<TypedExpr>, catalog:Null<TypedBackendLocalCatalog>):HxExpr {
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
		return ECall(expression(expressions[0], catalog), [expression(wrapped, catalog), EArrayDecl(projectedOptionalNames)]);
	}

	static function blockExpression(children:Array<TypedExpr>, ?catalog:TypedBackendLocalCatalog):HxExpr {
		var continuation:HxExpr = ENull;
		var hasContinuation = false;
		var sequenceIndex = 0;
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
					var binder:HxExpr = ELambda([projectedName], continuation);
					if (StringTools.trim(texts[1]).length > 0)
						binder = ECast(binder, "(" + texts[1] + ")->Dynamic");
					continuation = ECall(binder, [expression(values[0], catalog)]);
					hasContinuation = true;
				case _:
					final projected = expression(child, catalog);
					if (!hasContinuation) {
						continuation = projected;
					} else {
						final ignored = "__hxhx_lambda_seq_" + sequenceIndex;
						sequenceIndex++;
						continuation = ECall(ELambda([ignored], continuation), [projected]);
					}
					hasContinuation = true;
			}
			index--;
		}
		return continuation;
	}

	public static function expression(typedExpression:TypedExpr, ?catalog:TypedBackendLocalCatalog):HxExpr {
		final texts = typedExpression.getTexts();
		final expressions = typedExpression.getExpressions();
		return switch (typedExpression.getTag()) {
			case NullValue: ENull;
			case BoolValue: EBool(typedExpression.getBoolValue());
			case StringValue: EString(texts[0]);
			case IntValue: EInt(typedExpression.getIntValue());
			case FloatValue: EFloat(typedExpression.getFloatValue());
			case EnumValue: EEnumValue(texts[0]);
			case ThisValue: EThis;
			case SuperValue: ESuper;
			case LocalRead: EIdent(exactProjectedName(catalog, typedExpression.getLocalBindings(), texts[0], "typed local read"));
			case NameRead:
				final nameField = typedExpression.getFieldInfo();
				if (nameField != null) {
					typedExpression.getRequiresOwnerQualification() ? EField(resolvedTypeExpression("", nameField.getOwner()),
						nameField.getName()) : EIdent(texts[0]);
				} else {
					final identity = typedExpression.getType().getNominalIdentity();
					resolvedTypeExpression(texts[0], identity);
				}
			case FieldRead:
				var receiver = expression(expressions[0], catalog);
				final field = typedExpression.getFieldInfo();
				if (field != null && field.getIsStatic()) {
					switch (receiver) {
						case EIdent(name): receiver = resolvedTypeExpression(name, field.getOwner());
						case _:
					}
				}
				EField(receiver, texts[0]);
			case NullSafeFieldRead: ENullSafeField(expression(expressions[0], catalog), texts[0]);
			case Call:
				final callee = expression(expressions[0], catalog);
				final arguments = expressionTail(expressions, 1, catalog);
				final declaration = typedExpression.getDeclaration();
				final extensionProvider = typedExpression.getExtensionProvider();
				if (extensionProvider != null) {
					if (declaration == null || !declaration.getIsStatic())
						throw "typed extension call is missing its exact static declaration";
					switch (callee) {
						case EField(receiver, _):
							ECall(EField(resolvedTypeExpression("", extensionProvider), declaration.getSignature().getName()), [receiver].concat(arguments));
						case _:
							throw "typed extension call does not retain its receiver field shape";
					}
				} else if (declaration == null
					&& expressions[0].getTag() == NameRead
					&& expressions[0].getTexts().length == 1
					&& expressions[0].getTexts()[0] == "__hxhx_optional_lambda") {
					optionalLambdaCall(expressions, catalog);
				} else if (declaration != null && declaration.getIsEnumConstructor()) {
					TypedExactEnumConstructorSource.encode(declaration.getOwner().getCanonicalName(), declaration.getModulePath(),
						declaration.getIdentity().getCanonicalKey(), declaration.getSignature().getName(), callee, arguments);
				} else if (declaration == null || declaration.getIsStatic()) {
					if (declaration != null) {
						switch (callee) {
							case EIdent(_) if (typedExpression.getRequiresOwnerQualification()):
								ECall(EField(resolvedTypeExpression("", declaration.getOwner()), declaration.getSignature().getName()), arguments);
							case EField(EIdent(name), method):
								ECall(EField(resolvedTypeExpression(name, declaration.getOwner()), method), arguments);
							case _: ECall(callee, arguments);
						}
					} else {
						ECall(callee, arguments);
					}
				} else {
					switch (callee) {
						case EField(receiver, method):
							TypedExactCallSource.encodeInstance(declaration.getOwner().getCanonicalName(), declaration.getIdentity().getCanonicalKey(),
								method, typedExpression.getType().getDisplay(), receiver, arguments);
						case _:
							ECall(callee, arguments);
					}
				}
			case ReturnExpr: EReturn(expressions.length == 0 ? null : expression(expressions[0], catalog));
			case VariableDeclarations:
				final declarations = new Array<HxExpr>();
				for (declaration in expressions) {
					if (declaration.getTag() != VariableDeclaration)
						throw "typed variable declaration list contains a non-declaration child";
					final declarationTexts = declaration.getTexts();
					final declarationValues = declaration.getExpressions();
					final projectedName = exactProjectedName(catalog, declaration.getLocalBindings(), declarationTexts[0], "typed expression variable");
					declarations.push(HxExprVarDecl.make(projectedName, declarationTexts[1],
						declarationValues.length == 0 ? null : expression(declarationValues[0], catalog), sourcePosition(declaration.getPosition()),
						declaration.getVariableIsFinal(), declaration.getVariableIsStatic()));
				}
				EVars(declarations);
			case VariableDeclaration:
				throw "typed variable declaration must be nested inside a declaration list";
			case WhileExpr:
				EWhile(expression(expressions[0], catalog), expressionTail(expressions, 1, catalog), typedExpression.getBoolValue(),
					sourcePosition(typedExpression.getPosition()));
			case BreakExpr: EBreak(sourcePosition(typedExpression.getPosition()));
			case ContinueExpr: EContinue(sourcePosition(typedExpression.getPosition()));
			case MacroExpr: EMacroExpr(expression(expressions[0], catalog), texts.copy());
			case MacroType: EMacroType(texts[0]);
			case Lambda:
				ELambda(exactProjectedNames(catalog, typedExpression.getLocalBindings(), texts, "typed lambda"), expression(expressions[0], catalog));
			case SwitchExpr:
				ESwitch(expression(expressions[0], catalog), projectPatterns(typedExpression.getPatterns(), typedExpression.getLocalBindings(), catalog),
					expressionTail(expressions, 1, catalog));
			case NewValue:
				final identity = typedExpression.getType().getNominalIdentity();
				ENew(resolvedNameWhenAliased(texts[0], identity), expressionTail(expressions, 0, catalog));
			case Unary: EUnop(typedExpression.getUnaryOperator(), typedExpression.getUnaryFixity(), expression(expressions[0], catalog));
			case Binary: EBinop(texts[0], expression(expressions[0], catalog), expression(expressions[1], catalog));
			case Assign: EBinop("=", expression(expressions[0], catalog), expression(expressions[1], catalog));
			case CompoundAssign: EBinop(texts[0], expression(expressions[0], catalog), expression(expressions[1], catalog));
			case Ternary:
				ETernary(expression(expressions[0], catalog), expression(expressions[1], catalog), expression(expressions[2], catalog));
			case Anonymous: EAnon(texts.copy(), expressionTail(expressions, 0, catalog));
			case ArrayComprehension:
				var guard:Null<HxExpr> = null;
				if (typedExpression.getBoolValue())
					guard = expression(expressions[1], catalog);
				final valueIndex = typedExpression.getBoolValue() ? 2 : 1;
				final projectedName = exactProjectedName(catalog, typedExpression.getLocalBindings(), texts[0], "typed array comprehension");
				EArrayComprehension(projectedName, expression(expressions[0], catalog), guard, expression(expressions[valueIndex], catalog));
			case ArrayDecl: EArrayDecl(expressionTail(expressions, 0, catalog));
			case ArrayAccess: EArrayAccess(expression(expressions[0], catalog), expression(expressions[1], catalog));
			case Range: ERange(expression(expressions[0], catalog), expression(expressions[1], catalog));
			case Cast: ECast(expression(expressions[0], catalog), texts[0]);
			case Untyped: EUntyped(expression(expressions[0], catalog));
			case Opaque:
				switch (typedExpression.getOpaqueKind()) {
					case TryCatch: ETryCatchRaw(texts[0]);
					case Switch: ESwitchRaw(texts[0]);
					case Unsupported: EUnsupported(texts[0]);
					case null: throw "typed opaque expression is missing its kind";
				}
			case Block: blockExpression(expressions, catalog);
			case Temporary:
				throw "typed temporary must be nested inside a typed block expression";
		};
	}

	public static function statement(typedStatement:TypedStmt, ?catalog:TypedBackendLocalCatalog):HxStmt {
		final position = sourcePosition(typedStatement.getPosition());
		final names = typedStatement.getNames();
		final expressions = typedStatement.getExpressions();
		final statements = typedStatement.getStatements();
		return switch (typedStatement.getTag()) {
			case Block: SBlock([for (entry in statements) statement(entry, catalog)], position);
			case Var:
				final typedInitializer = expressions.length == 1 ? expressions[0] : null;
				final typeHint = variableTypeHint(names[1], typedInitializer);
				var initializer:Null<HxExpr> = null;
				if (expressions.length > 0)
					initializer = expression(expressions[0], catalog);
				final projectedName = exactProjectedName(catalog, typedStatement.getLocalBindings(), names[0], "typed variable statement");
				SVar(projectedName, typeHint, initializer, position, typedStatement.getMetadata());
			case If:
				var whenFalse:Null<HxStmt> = null;
				if (statements.length > 1)
					whenFalse = statement(statements[1], catalog);
				SIf(expression(expressions[0], catalog), statement(statements[0], catalog), whenFalse, position);
			case ForIn:
				final projectedName = exactProjectedName(catalog, typedStatement.getLocalBindings(), names[0], "typed for-in statement");
				SForIn(projectedName, expression(expressions[0], catalog), statement(statements[0], catalog), position);
			case ForKeyValue:
				final projectedNames = exactProjectedNames(catalog, typedStatement.getLocalBindings(), names, "typed key/value for-in statement");
				SForKeyValue(projectedNames[0], projectedNames[1], expression(expressions[0], catalog), statement(statements[0], catalog), position);
			case While: SWhile(expression(expressions[0], catalog), statement(statements[0], catalog), position);
			case DoWhile: SDoWhile(statement(statements[0], catalog), expression(expressions[0], catalog), position);
			case Switch:
				SSwitch(expression(expressions[0], catalog), projectPatterns(typedStatement.getPatterns(), typedStatement.getLocalBindings(), catalog),
					[for (body in statements) statement(body, catalog)], position);
			case Try:
				final catchNames = typedStatement.getCatchNames();
				final catchTypeHints = typedStatement.getCatchTypeHints();
				final projectedCatchNames = exactProjectedNames(catalog, typedStatement.getLocalBindings(), catchNames, "typed catch statement");
				final catches = new Array<{name:String, typeHint:String, body:HxStmt}>();
				for (index in 0...catchNames.length)
					catches.push({
						name: projectedCatchNames[index],
						typeHint: catchTypeHints[index],
						body: statement(statements[index + 1], catalog)
					});
				STry(statement(statements[0], catalog), catches, position);
			case Break: SBreak(position);
			case Continue: SContinue(position);
			case Throw: SThrow(expression(expressions[0], catalog), position);
			case ReturnVoid: SReturnVoid(position);
			case Return: SReturn(expression(expressions[0], catalog), position);
			case Expression: SExpr(expression(expressions[0], catalog), position);
		};
	}

	public static function statements(body:TypedFunctionBody, ?catalog:TypedBackendLocalCatalog):Array<HxStmt>
		return [for (entry in body.getStatements()) statement(entry, catalog)];

	public static function functionDeclaration(typedFunction:TypedFunction, ?catalog:TypedBackendLocalCatalog):HxFunctionDecl {
		final source = typedFunction.getSourceDeclaration();
		var arguments = HxFunctionDecl.getArgs(source);
		var returnTypeHint = HxFunctionDecl.getReturnTypeHint(source);
		final declaration = typedFunction.getDeclaration();
		final environment = typedFunction.getEnvironment();
		final parameterBindings = environment == null ? [] : [for (parameter in environment.getParams()) parameter.toBinding()];
		if (catalog != null && environment != null && parameterBindings.length != arguments.length)
			throw "typed backend function projection parameter count mismatch for " + typedFunction.getStableIdentity();
		final semanticArguments = declaration == null ? [] : declaration.getSignature().getArgs();
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
				new HxFunctionArg(projectedName, renderedHint, HxFunctionArg.getDefaultValue(argument), HxFunctionArg.getIsOptional(argument),
					HxFunctionArg.getIsRest(argument), HxFunctionArg.getDefaultValueText(argument), HxFunctionArg.getMetadata(argument));
			}
		];
		if (declaration != null) {
			final signature = declaration.getSignature();
			if (returnTypeHint.length > 0 && containsAliasSpelling(signature.getReturnType()))
				returnTypeHint = canonicalTypeHint(signature.getReturnType());
		}
		return new HxFunctionDecl(HxFunctionDecl.getName(source), HxFunctionDecl.getVisibility(source), HxFunctionDecl.getIsStatic(source), arguments,
			returnTypeHint, statements(typedFunction.getBody(), catalog), HxFunctionDecl.getReturnStringLiteral(source), HxFunctionDecl.getMetadata(source),
			HxFunctionDecl.getPos(source), HxFunctionDecl.getEndPos(source), "", HxFunctionDecl.getHasBody(source));
	}

	/** Project one function while keeping its exact local and bare field-read catalogs inseparable from the source-shaped body. **/
	public static function functionProjection(typedFunction:TypedFunction):TypedBackendFunctionProjection {
		final fields = fieldReadCatalog(typedFunction);
		final locals = localCatalog(typedFunction, fields.getReservedProjectedNames());
		final environment = typedFunction.getEnvironment();
		final parameterBindingIdentities = environment == null ? [] : [
			for (parameter in environment.getParams())
				parameter.getIdentity().getCanonicalKey()
		];
		return new TypedBackendFunctionProjection(typedFunction.getStableIdentity(), CompilerTypedTreeRevision.functionBody(typedFunction),
			functionDeclaration(typedFunction, locals), locals, fields, parameterBindingIdentities);
	}

	/** Project one field from its resolved type and typed initializer when available. **/
	static function fieldDeclaration(source:HxFieldDecl, semanticInfo:Null<TyNominalInfo>, initializer:Null<TypedExpr>,
			?catalog:TypedBackendLocalCatalog):HxFieldDecl {
		var typeHint = HxFieldDecl.getTypeHint(source);
		if (typeHint.length > 0 && semanticInfo != null) {
			final fieldInfo = semanticInfo.fieldInfo(HxFieldDecl.getName(source));
			if (fieldInfo != null && containsAliasSpelling(fieldInfo.getType()))
				typeHint = canonicalTypeHint(fieldInfo.getType());
		}
		final projectedInitializer = initializer == null ? HxFieldDecl.getInit(source) : expression(initializer, catalog);
		return new HxFieldDecl(HxFieldDecl.getName(source), HxFieldDecl.getVisibility(source), HxFieldDecl.getIsStatic(source), typeHint,
			projectedInitializer, HxFieldDecl.getMetadata(source), HxFieldDecl.getPos(source), HxFieldDecl.getEndPos(source), HxFieldDecl.getIsFinal(source),
			HxFieldDecl.getPropertyGet(source), HxFieldDecl.getPropertySet(source), initializer == null ? HxFieldDecl.getInitText(source) : "");
	}

	static function fieldInitializerProjection(source:HxFieldDecl, semanticInfo:Null<TyNominalInfo>,
			initializer:TypedFieldInitializer):TypedBackendFieldInitializerProjection {
		final typedExpression = initializer.getExpression();
		final fieldReads = fieldReadCatalogForExpression(typedExpression);
		final locals = localCatalogForExpression(typedExpression, fieldReads.getReservedProjectedNames());
		final declaration = fieldDeclaration(source, semanticInfo, typedExpression, locals);
		final field = initializer.getField();
		final identity = field.getCanonicalKey() + "|initializer";
		final revision = CompilerTypedTreeRevision.expression(field.getCanonicalKey(), typedExpression);
		return new TypedBackendFieldInitializerProjection(identity, revision, field, declaration, locals, fieldReads);
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
		return new HxClassDecl(HxClassDecl.getName(source), HxClassDecl.getHasStaticMain(source), functions, fields, extendsPath,
			HxClassDecl.getMetadata(source), HxClassDecl.getIsInterface(source), implementsPaths, HxClassDecl.getVisibility(source));
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
		for (field in HxClassDecl.getFields(typedClass.getSourceDeclaration())) {
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
		final semanticFacts = semanticInfo == null ? null : new TypedBackendClassSemanticFacts(semanticInfo, null);
		return new TypedBackendClassProjection(declaration, functions, fieldInitializers, semanticFacts);
	}

	public static function classDeclaration(typedClass:TypedClass):HxClassDecl
		return classProjection(typedClass).getDeclaration();

	static function projectedModuleDeclaration(parsed:ParsedModule, typedClasses:Array<TypedClass>, classes:Array<HxClassDecl>):HxModuleDecl {
		if (typedClasses.length != classes.length)
			throw "typed module projection class count mismatch";
		final source = parsed.getDecl();
		final sourceMain = HxModuleDecl.getMainClass(source);
		var mainClass:Null<HxClassDecl> = null;
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
		if (mainClass == null)
			throw "typed module projection is missing its main declaration";
		return new HxModuleDecl(HxModuleDecl.getPackagePath(source), HxModuleDecl.getDirectives(source), mainClass, classes,
			HxModuleDecl.getHeaderOnly(source), HxModuleDecl.getHasToplevelMain(source));
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
		final functionEntries = new Array<{
			backendClass:HxClassDecl,
			backendFunction:HxFunctionDecl,
			stableIdentity:String
		}>();
		for (typedClass in typedClasses) {
			final projectedFunctions = new Array<HxFunctionDecl>();
			final classFunctions = new Array<{
				declaration:HxFunctionDecl,
				stableIdentity:String
			}>();
			for (typedFunction in typedClass.getFunctions()) {
				final projectedFunction = functionDeclaration(typedFunction);
				projectedFunctions.push(projectedFunction);
				classFunctions.push({
					declaration: projectedFunction,
					stableIdentity: typedFunction.getStableIdentity()
				});
			}
			final initializerByField = new Map<String, TypedExpr>();
			for (initializer in typedClass.getFieldInitializers())
				initializerByField.set(initializer.getField().getName(), initializer.getExpression());
			final projectedFields = [
				for (field in HxClassDecl.getFields(typedClass.getSourceDeclaration()))
					fieldDeclaration(field, typedClass.getSemanticInfo(), initializerByField.get(HxFieldDecl.getName(field)))
			];
			final projectedClass = projectedClassDeclaration(typedClass, projectedFunctions, projectedFields);
			classes.push(projectedClass);
			for (classFunction in classFunctions)
				functionEntries.push({
					backendClass: projectedClass,
					backendFunction: classFunction.declaration,
					stableIdentity: classFunction.stableIdentity
				});
		}
		return new TypedBackendDeclarationCatalog(projectedModuleDeclaration(parsed, typedClasses, classes), functionEntries);
	}
}
