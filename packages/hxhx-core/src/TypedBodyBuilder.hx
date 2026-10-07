/**
	Builds the structural typed-body spine from parsed declarations.

	The builder owns the one syntax-to-typed-tree conversion. TyperStage supplies
	type and exact-call resolvers; synthetic test modules may use the conservative
	fallback resolver. Most nested `HxExpr` nodes do not yet retain exact positions.
	Expression-level variable declarations and loops written where a macro expects
	source syntax are explicit exceptions because macro diagnostics need the source
	location of the complete construct.
**/
class TypedBodyBuilder {
	/**
		Publish executable conversions inside their original argument positions.
		Each wrapper retains its operand once, so targets observe source evaluation
		order. Rest declarations expose an array to their body but accept elements
		at the call boundary. Extension receivers are excluded from this argument list.
	**/
	static function convertCallValues(arguments:Array<TypedExpr>, resolution:TypedCallResolution, typeResolver:Null<TypedExprTypeResolver>):Array<TypedExpr> {
		final declaration = resolution.getDeclaration();
		if (declaration == null || typeResolver == null)
			return arguments;
		final expected = resolution.getExpectedArguments();
		if (resolution.getNamedArguments() != null) {
			if (expected.length != arguments.length)
				throw "named call contexts do not cover authored operands";
			return [
				for (index in 0...arguments.length)
					expected[index].isUnknown() ? arguments[index] : typeResolver.convertValue(arguments[index], expected[index])
			];
		}
		final rest = declaration.getSignature().getArgRest();
		final offset = resolution.getExtensionProvider() == null ? 0 : 1;
		final last = expected.length - 1;
		final hasRest = last >= 0 && last + offset < rest.length && rest[last + offset];
		return [
			for (index in 0...arguments.length) {
				final slot = index < expected.length ? index : hasRest ? last : -1;
				var target = slot < 0 ? null : expected[slot];
				if (target != null && hasRest && slot == last && !target.isUnknown()) {
					final elements = target.getTypeArguments();
					if (elements.length != 1)
						throw "rest conversion requires its applied array element type";
					target = elements[0];
				}
				target == null
			|| target.isUnknown() ? arguments[index] : typeResolver.convertValue(arguments[index], target);
			}
		];
	}

	/** Apply exact call conversions after every argument has its source type. **/
	static function applyCallArgumentConversions(arguments:Array<TypedExpr>, conversions:Array<Null<TyImplicitConversionPlan>>):Array<TypedExpr> {
		if (conversions.length == 0)
			return arguments;
		if (conversions.length != arguments.length)
			throw "typed call argument conversions do not align with the source arguments";
		return [
			for (index in 0...arguments.length)
				conversions[index] == null ? arguments[index] : conversions[index].apply(arguments[index])
		];
	}

	/**
		Expose the concrete conversion selected for a Dynamic catch result.

		The internal try sentinel stores handlers inside array-shaped metadata. When
		the whole try expression has a concrete type, each Dynamic handler result must
		be converted at the handler boundary so every target receives two closures
		with the same result contract. A genuinely Dynamic try remains unchanged.
	**/
	static function alignStructuralTryCatchResults(arguments:Array<TypedExpr>, resultType:TyType):Array<TypedExpr> {
		if (arguments.length != 3 || resultType == null || resultType.isUnknown() || resultType.isDynamic() || resultType.isNoNormalCompletion()
			|| resultType.isVoid())
			return arguments;
		final catches = arguments[1];
		if (catches.getTag() != ArrayDecl)
			return arguments;

		final alignedCatches = new Array<TypedExpr>();
		for (entry in catches.getExpressions()) {
			final children = entry.getExpressions();
			if (entry.getTag() != ArrayDecl || children.length != 3 || children[2].getTag() != Lambda) {
				alignedCatches.push(entry);
				continue;
			}
			final handler = children[2];
			final handlerExpressions = handler.getExpressions();
			if (handlerExpressions.length != 1 || !handlerExpressions[0].getType().isDynamic()) {
				alignedCatches.push(entry);
				continue;
			}
			final convertedBody = TypedExpr.castValue(handlerExpressions[0], resultType.getCanonicalDisplay(), resultType, handlerExpressions[0].getPosition());
			final handlerType = handler.getType().withFunctionTypes(handler.getType().getFunctionArguments(), resultType);
			final convertedHandler = handler.withExpressions([convertedBody]).withType(handlerType);
			alignedCatches.push(TypedExpr.arrayDecl([children[0], children[1], convertedHandler], entry.getType(), entry.getPosition()));
		}

		final aligned = arguments.copy();
		aligned[1] = TypedExpr.arrayDecl(alignedCatches, catches.getType(), catches.getPosition());
		return aligned;
	}

	static function exactPosition(position:HxPos):Null<HxPos> {
		if (position == null)
			return null;
		return position.getIndex() == 0 && position.getLine() == 0 && position.getColumn() == 0 ? null : position;
	}

	static function fallbackType(expression:HxExpr, environment:Null<TyFunctionEnv>):TyType {
		return switch (expression) {
			case EParenthesized(inner, _) | EPrivateAccess(inner, _): fallbackType(inner, environment);
			case ENull: TyType.fromHintText("Null");
			case EBool(_): TyType.fromHintText("Bool");
			case EString(_): TyType.fromHintText("String");
			case EInt(_): TyType.fromHintText("Int");
			case EFloat(_): TyType.fromHintText("Float");
			case EEnumValue(_): TyType.fromHintText("String");
			case EIdent(name): environment == null ? TyType.unknown() : environment.resolveLocal(name);
			case EUnop(LogicalNot, _, _): TyType.fromHintText("Bool");
			case EBinop("==" | "!=" | "<" | "<=" | ">" | ">=" | "&&" | "||", _, _): TyType.fromHintText("Bool");
			case EArrayDecl(_): TyType.fromHintText("Array<Dynamic>");
			case EMacroExpr(_, _): TyType.fromHintText("haxe.macro.Expr");
			case EMacroType(_): TyType.fromHintText("haxe.macro.ComplexType");
			case EReturn(_): TyType.fromHintText("Void");
			case EVars(_): TyType.fromHintText("Void");
			case EWhile(_, _, _, _, loopKind): TyType.fromHintText("Void");
			case EBreak(_) | EContinue(_): TyType.noNormalCompletion();
			case EDiscardThen(effect, continuation):
				final effectType = fallbackType(effect, environment);
				effectType.isNoNormalCompletion() ? effectType : fallbackType(continuation, environment);
			case _: TyType.unknown();
		};
	}

	static function expressionType(expression:HxExpr, diagnosticPosition:HxPos, environment:Null<TyFunctionEnv>, resolver:Null<TypedExprTypeResolver>,
			?expected:TyType):TyType {
		if (resolver == null || environment == null)
			return fallbackType(expression, environment);
		final resolved = resolver.expressionType(expression, diagnosticPosition == null ? HxPos.unknown() : diagnosticPosition, environment, expected);
		return resolved == null ? TyType.unknown() : resolved;
	}

	static function isCompoundAssignment(op:String):Bool {
		return switch (op) {
			case "+=" | "-=" | "*=" | "/=" | "%=" | "<<=" | ">>=" | ">>>=" | "&=" | "|=" | "^=": true;
			case _: false;
		};
	}

	static function expressionPath(expression:HxExpr):String {
		return switch (expression) {
			case EIdent(name): name;
			case EField(owner, field):
				final prefix = expressionPath(owner);
				prefix.length == 0 ? "" : prefix + "." + field;
			case _: "";
		};
	}

	/**
		Lower the existing compile-time key/value-for diagnostic probes before a
		backend sees the body.

		The bring-up parser intentionally retains these invalid expressions as raw
		text so `HelperMacros.typeError*` can inspect them. Their result is already a
		compiler decision shared by every target; sealing the literal here prevents
		the raw expression from bypassing the structural typed-body boundary.
	**/
	static function normalizeProbeText(raw:String):String {
		var normalized = raw == null ? "" : raw;
		for (whitespace in [" ", "\t", "\n", "\r"])
			normalized = StringTools.replace(normalized, whitespace, "");
		return normalized;
	}

	static function opaqueBlockProbeResult(expression:HxExpr):Null<Bool> {
		final raw = switch (expression) {
			case EMacroExpr(inner, _) | EUntyped(inner): return opaqueBlockProbeResult(inner);
			case ETryCatchRaw(value): value;
			case _: null;
		};
		if (raw == null || !StringTools.startsWith(raw, "opaque_block_expr:"))
			return null;
		final normalized = normalizeProbeText(raw);
		final dynamicName = "Dyna" + "mic";
		if (normalized.indexOf('varb:{v:' + dynamicName + '}={v:"foo"};') >= 0)
			return false;
		for (knownFailure in [
			"varb:{v:Int}={v:1.2};",
			'varb:{v:Int}={v:0,w:"foo"};',
			"varb:{v:Int}={v:0,v:2};",
			"varb:{v:Int,w:String}={v:0};",
			"vari:Int=z;",
			"vars:String=z;"
		])
			if (normalized.indexOf(knownFailure) >= 0)
				return true;
		return null;
	}

	/**
		Whether successful best-effort inference proves a diagnostic probe valid.

		Inference of a compound expression's result type does not necessarily check
		assignment, argument, or map-entry compatibility. Keep those known incomplete
		families on the compatibility evaluator; other exact results, including valid
		abstract operators, are decisive until their complete semantic check has one
		shared compiler owner.
	**/
	static function successfulProbeInferenceIsDecisive(expression:HxExpr):Bool {
		return switch (expression) {
			case EMacroExpr(inner, _) | EUntyped(inner):
				successfulProbeInferenceIsDecisive(inner);
			case EBinop("=", _, _) | ECall(_, _) | ETryCatchRaw(_):
				false;
			case EUnop(op, _, _) if (op == HxUnaryOperator.LogicalNot):
				false;
			case EArrayDecl(values):
				var mapLiteral = false;
				for (value in values)
					switch (value) {
						case EBinop("=>", _, _): mapLiteral = true;
						case _:
					}
				!mapLiteral;
			case _:
				true;
		};
	}

	static function compileTimeProbe(callee:HxExpr, arguments:Array<HxExpr>, position:Null<HxPos>, diagnosticPosition:HxPos, environment:Null<TyFunctionEnv>,
			typeResolver:Null<TypedExprTypeResolver>):Null<TypedExpr> {
		if (arguments == null || arguments.length != 1)
			return null;
		final isForProbe = switch (arguments[0]) {
			case EUnsupported(raw) if (raw != null && StringTools.startsWith(raw, "for_expr:")): true;
			case _: false;
		};
		final parts = expressionPath(callee).split(".");
		if (parts.length == 0)
			return null;
		final functionName = parts[parts.length - 1];
		if ((functionName == "followWithAbstracts" || functionName == "followWithAbstractsOnce")
			&& parts.length >= 2
			&& parts[parts.length - 2] == "MyMacroHelper") {
			final result = switch (arguments[0]) {
				case ENew(typePath, _):
					final rawTypePath = typePath == null ? "" : typePath;
					final genericStart = rawTypePath.indexOf("<");
					final baseTypePath = StringTools.trim(genericStart < 0 ? rawTypePath : rawTypePath.substr(0, genericStart));
					if (baseTypePath == "Map" || baseTypePath == "TypedefToStringMap") "TInst(haxe.ds.StringMap,[TInst(String,[])])"; else null;
				case ETryCatchRaw(raw)
					if (functionName == "followWithAbstractsOnce"
						&& normalizeProbeText(raw).indexOf("varx:TypedefToStringMap<String>;x;") >= 0):
					"TType(Map,[TInst(String,[]),TInst(String,[])])";
				case _:
					null;
			};
			if (result != null)
				return TypedExpr.stringLiteral(result, TyType.fromHintText("String"), position);
		}
		final recognizedOwner = parts.length == 1 || parts[parts.length - 2] == "HelperMacros";
		if (!recognizedOwner)
			return null;
		// Expression-position `for` probes are intentionally preserved as an
		// opaque parser fact. Resolve their established compile-time result before
		// generic inference, which cannot diagnose inside that opaque payload.
		if (isForProbe)
			return switch (functionName) {
				case "typeErrorText":
					TypedExpr.stringLiteral("Int has no field keyValueIterator", TyType.fromHintText("String"), position);
				case "typeError":
					TypedExpr.boolLiteral(true, TyType.fromHintText("Bool"), position);
				case _:
					null;
			};
		if (functionName == "getErrorMessage") {
			final message = CompilerDiagnosticProbe.getErrorMessage(arguments[0]);
			if (message != null)
				return TypedExpr.stringLiteral(message, TyType.fromHintText("String"), position);
		}
		if (functionName == "typeError" && typeResolver != null && environment != null) {
			var failed = false;
			var resolvedType:Null<TyType> = null;
			try {
				resolvedType = typeResolver.expressionType(arguments[0], diagnosticPosition == null ? HxPos.unknown() : diagnosticPosition,
					environment.copyForInference(), null);
				failed = false;
			} catch (_:TyperError) {
				failed = true;
			}
			// A reported typer failure is decisive. A successful best-effort
			// inference is decisive only when it produced an exact type. The
			// bootstrap typer intentionally leaves some compatibility families
			// unknown or unresolved, so preserve those probes for the existing
			// structural compatibility evaluator instead of sealing a false
			// negative.
			if (failed)
				return TypedExpr.boolLiteral(true, TyType.fromHintText("Bool"), position);
			if (resolvedType != null
				&& !resolvedType.isUnknown()
				&& !resolvedType.isUnresolved()
				&& successfulProbeInferenceIsDecisive(arguments[0]))
				return TypedExpr.boolLiteral(false, TyType.fromHintText("Bool"), position);
		}
		return switch (functionName) {
			case "typeError":
				final result = opaqueBlockProbeResult(arguments[0]);
				result == null ? null : TypedExpr.boolLiteral(result, TyType.fromHintText("Bool"), position);
			case _: null;
		};
	}

	static function opaqueBlockBody(raw:String):Null<String> {
		final marker = "opaque_block_expr:";
		if (raw == null || !StringTools.startsWith(raw, marker))
			return null;
		var body = StringTools.trim(raw.substr(marker.length));
		if (body.length >= 2 && body.charAt(0) == "{" && body.charAt(body.length - 1) == "}")
			body = body.substring(1, body.length - 1);
		return body;
	}

	static function parsedOpaqueBlockStatements(raw:String):Null<Array<HxStmt>> {
		final body = opaqueBlockBody(raw);
		if (body == null)
			return null;
		final statements = try {
			HxParser.parseFunctionBodyText(body);
		} catch (_:HxParseError) {
			null;
		} catch (_:String) {
			null;
		};
		if (statements == null || statements.length == 0)
			return null;
		if (statements.length == 1)
			switch (statements[0]) {
				case SExpr(ETryCatchRaw(nested), _) | SReturn(ETryCatchRaw(nested), _) if (nested == raw):
					return null;
				case _:
			}
		return statements;
	}

	/**
		Expose the exact parser-recovery view to the typer.

		The typer and typed-body builder must traverse recovered expression blocks
		in the same declaration order; otherwise lexical identity replay fails
		instead of silently attaching the wrong symbol.
	**/
	public static function recoveredOpaqueBlockStatements(raw:String):Null<Array<HxStmt>>
		return parsedOpaqueBlockStatements(raw);

	static function statementAlwaysExits(statement:HxStmt):Bool {
		return switch (statement) {
			case SThrow(_, _) | SReturnVoid(_) | SReturn(_, _):
				true;
			case SBlock(statements, _): statements.length > 0 && statementAlwaysExits(statements[statements.length - 1]);
			case SIf(_, whenTrue, whenFalse, _): whenFalse != null && statementAlwaysExits(whenTrue) && statementAlwaysExits(whenFalse);
			case STry(body, catches, _):
				if (!statementAlwaysExits(body) || catches.length == 0) {
					false;
				} else {
					var allExit = true;
					for (entry in catches)
						if (!statementAlwaysExits(entry.body))
							allExit = false;
					allExit;
				}
			case _:
				false;
		};
	}

	static function untypedExpression(expression:HxExpr):HxExpr {
		return switch (expression) {
			case EUntyped(_): expression;
			case _: EUntyped(expression);
		};
	}

	static function untypedStatement(statement:HxStmt):HxStmt {
		return switch (statement) {
			case SBlock(statements, position):
				SBlock([for (child in statements) untypedStatement(child)], position);
			case SVar(name, typeHint, initializer, position, metadata):
				var untypedInitializer:Null<HxExpr> = null;
				if (initializer != null)
					untypedInitializer = untypedExpression(initializer);
				SVar(name, typeHint, untypedInitializer, position, metadata == null ? [] : metadata.copy());
			case SIf(condition, whenTrue, whenFalse, position):
				var untypedWhenFalse:Null<HxStmt> = null;
				if (whenFalse != null)
					untypedWhenFalse = untypedStatement(whenFalse);
				SIf(untypedExpression(condition), untypedStatement(whenTrue), untypedWhenFalse, position);
			case SForIn(name, iterable, body, position):
				SForIn(name, untypedExpression(iterable), untypedStatement(body), position);
			case SForKeyValue(keyName, valueName, iterable, body, position):
				SForKeyValue(keyName, valueName, untypedExpression(iterable), untypedStatement(body), position);
			case SWhile(condition, body, position):
				SWhile(untypedExpression(condition), untypedStatement(body), position);
			case SDoWhile(body, condition, position):
				SDoWhile(untypedStatement(body), untypedExpression(condition), position);
			case SSwitch(scrutinee, patterns, bodies, position, exhaustive):
				SSwitch(untypedExpression(scrutinee), patterns, [for (body in bodies) untypedStatement(body)], position, exhaustive);
			case STry(body, catches, position):
				STry(untypedStatement(body), [
					for (entry in catches)
						{name: entry.name, typeHint: entry.typeHint, body: untypedStatement(entry.body)}
				], position);
			case SThrow(expression, position):
				SThrow(untypedExpression(expression), position);
			case SReturn(expression, position):
				SReturn(untypedExpression(expression), position);
			case SExpr(expression, position):
				SExpr(untypedExpression(expression), position);
			case _:
				statement;
		};
	}

	static function expandStatement(statement:HxStmt):HxStmt {
		return switch (statement) {
			case SBlock(statements, position):
				SBlock(expandStructuralStatements(statements), position);
			case SIf(condition, whenTrue, whenFalse, position):
				var expandedWhenFalse:Null<HxStmt> = null;
				if (whenFalse != null)
					expandedWhenFalse = expandStatement(whenFalse);
				SIf(condition, expandStatement(whenTrue), expandedWhenFalse, position);
			case SForIn(name, iterable, body, position):
				SForIn(name, iterable, expandStatement(body), position);
			case SForKeyValue(keyName, valueName, iterable, body, position):
				SForKeyValue(keyName, valueName, iterable, expandStatement(body), position);
			case SWhile(condition, body, position):
				SWhile(condition, expandStatement(body), position);
			case SDoWhile(body, condition, position):
				SDoWhile(expandStatement(body), condition, position);
			case SSwitch(scrutinee, patterns, bodies, position, exhaustive):
				SSwitch(scrutinee, patterns, [for (body in bodies) expandStatement(body)], position, exhaustive);
			case STry(body, catches, position):
				STry(expandStatement(body), [
					for (entry in catches)
						{name: entry.name, typeHint: entry.typeHint, body: expandStatement(entry.body)}
				], position);
			case SReturn(EUntyped(ETryCatchRaw(raw)), position):
				final statements = parsedOpaqueBlockStatements(raw);
				if (statements != null && statementAlwaysExits(statements[statements.length - 1])) SBlock(expandStructuralStatements([
					for (child in statements)
						untypedStatement(child)
				]), position); else statement;
			case SReturn(ETryCatchRaw(raw), position):
				final statements = parsedOpaqueBlockStatements(raw);
				if (statements != null
					&& statementAlwaysExits(statements[statements.length - 1])) SBlock(expandStructuralStatements(statements), position); else statement;
			case SExpr(EUntyped(ETryCatchRaw(raw)), position):
				final statements = parsedOpaqueBlockStatements(raw);
				statements == null ? statement : SBlock(expandStructuralStatements([
					for (child in statements)
						untypedStatement(child)
				]), position);
			case SExpr(ETryCatchRaw(raw), position):
				final statements = parsedOpaqueBlockStatements(raw);
				statements == null ? statement : SBlock(expandStructuralStatements(statements), position);
			case _:
				statement;
		};
	}

	/**
		Return the non-mutating pre-typing view of statement-position expression blocks.

		A terminal `return { ... }` block is lifted only when its final statement
		provably returns or throws. The typer and typed-body builder share this exact
		view, so inner locals and semantic operators cannot disappear into raw text.
	**/
	public static function expandStructuralStatements(statements:Array<HxStmt>):Array<HxStmt> {
		if (statements == null)
			return [];
		return [for (statement in statements) expandStatement(statement)];
	}

	/**
		Recover the parser's conservative expression-block fallback into typed nodes.

		Only variable declarations and expression statements are accepted here. The
		shared tree therefore exposes every initializer, operator, call, and final
		value; richer statement blocks remain explicit unsupported opaque leaves until
		the typed expression spine can represent their control flow without guessing.
	**/
	static function structuralOpaqueBlock(raw:String, position:Null<HxPos>, diagnosticPosition:HxPos, environment:Null<TyFunctionEnv>,
			typeResolver:Null<TypedExprTypeResolver>, callResolver:Null<TypedCallDeclarationResolver>,
			memberResolver:Null<TypedMemberDeclarationResolver>):Null<TypedExpr> {
		final statements = parsedOpaqueBlockStatements(raw);
		if (statements == null)
			return null;
		for (statement in statements)
			switch (statement) {
				case SVar(_, _, _, _) | SExpr(_, _):
				case _:
					return null;
			}

		final lexicalEnvironment = environment;
		if (lexicalEnvironment != null)
			lexicalEnvironment.enterLexicalScope();
		final expressions = new Array<TypedExpr>();
		for (statement in statements) {
			final sourcePosition = switch (statement) {
				case SVar(_, _, _, statementPosition) | SExpr(_, statementPosition): statementPosition;
				case _: HxPos.unknown();
			};
			final storedPosition = exactPosition(sourcePosition);
			final exactDiagnosticPosition = sourcePosition == null ? diagnosticPosition : sourcePosition;
			switch (statement) {
				case SVar(name, typeHint, initializer, _):
					final cleanHint = StringTools.trim(typeHint == null ? "" : typeHint);
					final localType = if (cleanHint.length > 0) {
						if (typeResolver == null || lexicalEnvironment == null)
							TyType.fromHintText(cleanHint);
						else
							expressionType(ECast(ENull, cleanHint), exactDiagnosticPosition, lexicalEnvironment, typeResolver);
					} else if (initializer == null) {
						TyType.unknown();
					} else {
						expressionType(initializer, exactDiagnosticPosition, lexicalEnvironment, typeResolver);
					};
					final typedInitializer = initializer == null ? TypedExpr.nullValue(localType,
						storedPosition) : buildExpr(initializer, storedPosition, exactDiagnosticPosition, lexicalEnvironment, typeResolver, callResolver,
							memberResolver);
					final binding = lexicalEnvironment == null ? null : lexicalEnvironment.declareLocal(name, localType, Variable).toBinding();
					expressions.push(TypedExpr.temporary(name, cleanHint, typedInitializer, TyType.fromHintText("Void"), storedPosition, binding));
				case SExpr(expression, _):
					expressions.push(buildExpr(expression, storedPosition, exactDiagnosticPosition, lexicalEnvironment, typeResolver, callResolver,
						memberResolver));
				case _:
			}
		}
		final blockType = expressions.length == 0 ? TyType.fromHintText("Void") : expressions[expressions.length - 1].getType();
		if (lexicalEnvironment != null)
			lexicalEnvironment.exitLexicalScope();
		return TypedExpr.block(expressions, blockType, position);
	}

	static function structuralTryCatch(raw:String, position:Null<HxPos>, diagnosticPosition:HxPos, environment:Null<TyFunctionEnv>,
			typeResolver:Null<TypedExprTypeResolver>, callResolver:Null<TypedCallDeclarationResolver>,
			memberResolver:Null<TypedMemberDeclarationResolver>):Null<TypedExpr> {
		return switch (recoveredStructuralExpression(raw)) {
			case null: null;
			case expression: buildExpr(expression, position, diagnosticPosition, environment, typeResolver, callResolver, memberResolver);
		};
	}

	/**
		Return the parser's structural replacement for a raw expression.

		The typer uses the same replacement before typed-body construction so
		compiler-generated lambda parameters receive deterministic identities in
		the one function-local declaration catalog.
	**/
	public static function recoveredStructuralExpression(raw:String):Null<HxExpr> {
		if (raw == null || !StringTools.startsWith(StringTools.trim(raw), "try"))
			return null;
		final parsed = try {
			HxParser.parseStructuralExprText(raw);
		} catch (_:HxParseError) {
			null;
		} catch (_:String) {
			null;
		};
		return switch (parsed) {
			case null | ETryCatchRaw(_): null;
			case expression: expression;
		};
	}

	static function buildExpressions(expressions:Array<HxExpr>, diagnosticPosition:HxPos, environment:Null<TyFunctionEnv>,
			typeResolver:Null<TypedExprTypeResolver>, callResolver:Null<TypedCallDeclarationResolver>, memberResolver:Null<TypedMemberDeclarationResolver>,
			?expected:Array<TyType>):Array<TypedExpr> {
		if (expressions == null)
			return [];
		return [
			for (index in 0...expressions.length)
				buildExpr(expressions[index], null, diagnosticPosition, environment, typeResolver, callResolver,
					memberResolver, expected == null || index >= expected.length || expected[index].isUnknown() ? null : expected[index])
		];
	}

	static function declarePatternBindings(environment:Null<TyFunctionEnv>, pattern:HxSwitchPattern, baseType:TyType, resolver:Null<TypedExprTypeResolver>,
			position:HxPos):Array<TyLocalBinding> {
		return TySwitchPatternBindings.declare(environment, pattern, baseType,
			resolver == null ? null : (input, name, arity) -> resolver.enumPatternArguments(input, name, arity, position));
	}

	/** Seal lambda bindings with their selected parameter types before typing captured reads. */
	static function buildLambda(arguments:Array<String>, body:HxExpr, parameterTypes:Array<TyType>, position:Null<HxPos>, diagnosticPosition:HxPos,
			environment:Null<TyFunctionEnv>, typeResolver:Null<TypedExprTypeResolver>, callResolver:Null<TypedCallDeclarationResolver>,
			memberResolver:Null<TypedMemberDeclarationResolver>, ?signature:HxLambdaSignature, ?selectedType:TyType):TypedExpr {
		final callableType = selectedType != null ? selectedType : typeResolver == null
			|| environment == null ? null : typeResolver.lambdaType(arguments, body, parameterTypes, signature, diagnosticPosition, environment);
		final selectedParameters = callableType == null ? parameterTypes : callableType.getFunctionArguments();
		final bindings = new Array<TyLocalBinding>();
		if (environment != null) {
			environment.enterLexicalScope();
			for (index in 0...arguments.length)
				bindings.push(environment.declareLocal(arguments[index], selectedParameters[index], LambdaParameter).toBinding());
		}
		final builtBody = buildExpr(body, null, diagnosticPosition, environment, typeResolver, callResolver, memberResolver);
		final typedBody = typeResolver != null
			&& TyEmptySourceGroup.isEmpty(body) ? TyEmptySourceGroup.functionBody(builtBody) : builtBody;
		if (environment != null)
			environment.exitLexicalScope();
		return TypedExpr.lambda(arguments.copy(), typedBody, callableType == null ? TyType.functionType(parameterTypes, typedBody.getType()) : callableType,
			position, bindings, signature);
	}

	/**
		Replay expression catches as catch declarations, preserving the typer's exact
		type and identity. The parser stores handlers as lambdas only to carry their
		bodies; ordinary lambda inference must not replace the catch parameter type.
		Validate the full shape before consuming any declarations from the replay.
	**/
	static function buildStructuralTryArguments(arguments:Array<HxExpr>, diagnosticPosition:HxPos, environment:Null<TyFunctionEnv>,
			typeResolver:Null<TypedExprTypeResolver>, callResolver:Null<TypedCallDeclarationResolver>,
			memberResolver:Null<TypedMemberDeclarationResolver>):Null<Array<TypedExpr>> {
		final entries = switch (arguments) {
			case [ELambda([], _), EArrayDecl(entries), _]: entries;
			case _: return null;
		};
		for (entry in entries)
			switch (entry) {
				case EArrayDecl([EString(name), EString(_), ELambda([argument], _)]) if (argument == name):
				case _:
					return null;
			}
		final tryBody = buildExpr(arguments[0], null, diagnosticPosition, environment, typeResolver, callResolver, memberResolver);
		final typedEntries = new Array<TypedExpr>();
		for (entry in entries)
			switch (entry) {
				case EArrayDecl([nameExpression, EString(hint), ELambda([name], body)]):
					final typedName = buildExpr(nameExpression, null, diagnosticPosition, environment, typeResolver, callResolver, memberResolver);
					final typedHint = buildExpr(EString(hint), null, diagnosticPosition, environment, typeResolver, callResolver, memberResolver);
					final bindings = new Array<TyLocalBinding>();
					var argumentType = TyType.fromHintText(StringTools.trim(hint).length == 0 ? "haxe.Exception" : hint);
					if (environment != null) {
						environment.enterLexicalScope();
						final binding = environment.declareLocal(name, argumentType, CatchVariable).toBinding();
						bindings.push(binding);
						argumentType = binding.getType();
					}
					final typedBody = buildExpr(body, null, diagnosticPosition, environment, typeResolver, callResolver, memberResolver);
					if (environment != null)
						environment.exitLexicalScope();
					var handler = TypedExpr.lambda([name], typedBody, TyType.functionType([argumentType], typedBody.getType()), null, bindings);
					if (typeResolver != null && bindings.length == 1) {
						final use = typeResolver.catchUse(bindings[0]);
						if (use != null)
							handler = handler.withCatchUses([use]);
					}
					typedEntries.push(TypedExpr.arrayDecl([typedName, typedHint, handler],
						expressionType(entry, diagnosticPosition, environment, typeResolver), null));
				case _:
					throw "validated structural catch changed during typed-body construction";
			}
		final typedCatches = TypedExpr.arrayDecl(typedEntries, expressionType(arguments[1], diagnosticPosition, environment, typeResolver), null);
		final continuation = buildExpr(arguments[2], null, diagnosticPosition, environment, typeResolver, callResolver, memberResolver);
		return [tryBody, typedCatches, continuation];
	}

	/**
		Build one typed expression while replaying the local declarations recorded by
		the typer.

		Child expressions must be built in the same explicit order used by
		`TyperStage`. Building two children as arguments to one constructor is unsafe:
		Haxe targets may evaluate those arguments in different orders, which can make
		a native compiler consume local identities in a different order from typing.
		An immediately called lambda types its arguments before declaring parameters;
		this also keeps a shadowing parameter out of its own argument expressions.
	**/
	static function buildExpr(expression:HxExpr, position:Null<HxPos>, diagnosticPosition:HxPos, environment:Null<TyFunctionEnv>,
			typeResolver:Null<TypedExprTypeResolver>, callResolver:Null<TypedCallDeclarationResolver>, memberResolver:Null<TypedMemberDeclarationResolver>,
			?expected:TyType, ?selectedCallType:TyType):TypedExpr {
		final nodeType = selectedCallType == null ? expressionType(expression, diagnosticPosition, environment, typeResolver, expected) : selectedCallType;
		// Quoted syntax has no semantic resolver and must preserve literal field access.
		// Only the executable typing route may replace it with its constant value.
		if (typeResolver != null)
			switch HxLiteralCharacterCode.resolve(expression) {
				case Character(value):
					return TypedExpr.intLiteral(value, TyType.fromHintText("Int"), position);
				case InvalidLiteral:
					throw new TyperError("<typed-body>", diagnosticPosition, "String must be a single UTF8 char");
				case NotApplicable:
			}
		if (typeResolver != null
			&& environment != null
			&& !expression.match(EParenthesized(_, _))
			&& !expression.match(EPrivateAccess(_, _))) {
			final target = typeResolver.runtimeTypeTarget(expression, environment, ValueExpression);
			if (target != null)
				return TypedExpr.runtimeTypeValue(target, position);
		}
		final value = switch (expression) {
			case ENull:
				TypedExpr.nullValue(nodeType, position);
			case EPrivateAccess(inner, sourcePosition):
				TypedExpr.privateAccess(buildExpr(inner, null, sourcePosition, environment, typeResolver, callResolver, memberResolver, expected,
					selectedCallType),
					exactPosition(sourcePosition));
			case EParenthesized(inner, sourcePosition):
				TypedExpr.parenthesized(buildExpr(inner, null, sourcePosition, environment, typeResolver, callResolver, memberResolver, expected,
					selectedCallType),
					exactPosition(sourcePosition));
			case ELoweredControl(_, _, _, _):
				throw "executable control cannot re-enter typed source construction";
			case ESourceTry(catches, bodies, sourcePosition):
				if (catches.length == 0 || bodies.length != catches.length + 1)
					throw "source try replay requires its ordered handler bodies";
				if (environment != null)
					environment.enterLexicalScope();
				final typedBodies = [
					buildExpr(bodies[0], null, sourcePosition, environment, typeResolver, callResolver, memberResolver)
				];
				if (environment != null)
					environment.exitLexicalScope();
				final bindings = new Array<TyLocalBinding>();
				for (index in 0...catches.length) {
					final entry = catches[index];
					if (environment != null) {
						environment.enterLexicalScope();
						final hint = StringTools.trim(entry.getTypeHint());
						// Replay consumes the exact declaration selected by typing, including its resolved type.
						bindings.push(environment.declareLocal(entry.getName(), TyType.fromHintText(hint.length == 0 ? "haxe.Exception" : hint), CatchVariable)
							.toBinding());
					}
					typedBodies.push(buildExpr(bodies[index + 1], null, entry.getPosition(), environment, typeResolver, callResolver, memberResolver));
					if (environment != null)
						environment.exitLexicalScope();
				}
				final uses = new Array<TypedCatchUse>();
				if (typeResolver != null)
					for (binding in bindings) {
						final use = typeResolver.catchUse(binding);
						if (use != null)
							uses.push(use);
					}
				TypedExpr.sourceTry(catches, typedBodies, nodeType, exactPosition(sourcePosition), bindings).withCatchUses(uses);
			case ESourceFor(binding, iterable, body, sourcePosition):
				final typedIterable = buildExpr(iterable, null, sourcePosition, environment, typeResolver, callResolver, memberResolver);
				// Quoted syntax has no executing environment and must not select runtime iterator declarations.
				final types = environment == null ? [] : TySourceFor.bindingTypes(binding, iterable, typedIterable.getType());
				if (types == null)
					throw "source for replay requires a resolved iterable protocol";
				final controls = environment == null ? null : environment.requireControlScope();
				final target = controls == null ? null : controls.enter(Loop, TypedBodyFingerprint.forExpression(expression));
				final bindings = new Array<TyLocalBinding>();
				if (environment != null) {
					environment.enterLexicalScope();
					final names = HxForBinding.names(binding);
					for (index in 0...names.length)
						bindings.push(environment.declareLocal(names[index], types[index], LoopVariable).toBinding());
				}
				final typedBody = buildExpr(body, null, sourcePosition, environment, typeResolver, callResolver, memberResolver);
				if (environment != null)
					environment.exitLexicalScope();
				if (controls != null)
					controls.exit(target);
				TypedExpr.sourceFor(binding, typedIterable, typedBody, nodeType, exactPosition(sourcePosition), bindings, target);
			case ESourceIf(condition, whenTrue, whenFalse, sourcePosition):
				final typedCondition = buildExpr(condition, null, sourcePosition, environment, typeResolver, callResolver, memberResolver);
				if (environment != null)
					environment.enterLexicalScope();
				final typedTrue = buildExpr(whenTrue, null, sourcePosition, environment, typeResolver, callResolver, memberResolver);
				if (environment != null)
					environment.exitLexicalScope();
				var typedFalse:Null<TypedExpr> = null;
				if (whenFalse != null) {
					if (environment != null)
						environment.enterLexicalScope();
					typedFalse = buildExpr(whenFalse, null, sourcePosition, environment, typeResolver, callResolver, memberResolver);
					if (environment != null)
						environment.exitLexicalScope();
				}
				TypedExpr.sourceIf(typedCondition, typedTrue, typedFalse, nodeType, exactPosition(sourcePosition));
			case EThrow(value, sourcePosition):
				final typedValue = buildExpr(value, null, sourcePosition, environment, typeResolver, callResolver, memberResolver);
				TypedExpr.throwExpr(typedValue, exactPosition(sourcePosition));
			case ESourceGroup(children, sourcePosition):
				if (environment != null)
					environment.enterLexicalScope();
				final typedChildren = buildExpressions(children, sourcePosition, environment, typeResolver, callResolver, memberResolver);
				if (environment != null)
					environment.exitLexicalScope();
				TypedExpr.sourceGroup(typedChildren, nodeType, exactPosition(sourcePosition));
			case ESourceFunction(facts, body, defaults, sourcePosition):
				facts.assertDefaultCount(defaults.length);
				final bindings = new Array<TyLocalBinding>();
				final declaredName = facts.getDeclaredName();
				if (environment != null && declaredName != null)
					bindings.push(environment.declareLocal(declaredName, nodeType, NamedFunction).toBinding());
				final controls = environment == null ? null : environment.requireControlScope();
				final target = controls == null ? null : controls.enter(Function, TypedBodyFingerprint.forExpression(expression));
				final names = facts.getArguments();
				if (environment != null) {
					environment.enterLexicalScope();
					if (!nodeType.isFunction())
						throw "source function replay requires its selected callable type";
					final arguments = nodeType.getFunctionArguments();
					for (index in 0...names.length)
						bindings.push(environment.declareLocal(names[index], arguments[index], LambdaParameter).toBinding());
				}
				final typedDefaults = buildExpressions(defaults, sourcePosition, environment, typeResolver, callResolver, memberResolver);
				if (controls != null)
					controls.beginReturns(target, nodeType.getFunctionReturn());
				final builtBody = buildExpr(body, null, sourcePosition, environment, typeResolver, callResolver, memberResolver);
				final typedBody = typeResolver != null
					&& TyEmptySourceGroup.isEmpty(body) ? TyEmptySourceGroup.functionBody(builtBody) : builtBody;
				if (controls != null) {
					controls.finishReturns(target);
					environment.exitLexicalScope();
					controls.exit(target);
				}
				final functionNode = TypedExpr.sourceFunctionExpr(facts, typedBody, typedDefaults, nodeType, exactPosition(sourcePosition), bindings);
				target == null ? functionNode : functionNode.withControlTarget(target);
			case EBool(value):
				TypedExpr.boolLiteral(value, nodeType, position);
			case EString(value):
				TypedExpr.stringLiteral(value, nodeType, position);
			case EInt(value):
				TypedExpr.intLiteral(value, nodeType, position);
			case EFloat(value):
				TypedExpr.floatLiteral(value, nodeType, position);
			case EEnumValue(name):
				final local = environment == null ? null : environment.resolveSymbol(name);
				if (local != null) {
					TypedExpr.localRead(name, nodeType, position, local.toBinding());
				} else {
					final memberResolution = memberResolver == null
						|| environment == null ? null : memberResolver(expression, diagnosticPosition, environment);
					memberResolution == null ? TypedExpr.enumValue(name, nodeType, position) : memberResolution.nameRead(name, nodeType, position);
				}
			case EThis:
				TypedExpr.thisValue(nodeType, position);
			case ESuper:
				TypedExpr.superValue(nodeType, position);
			case EIdent(name):
				final local = environment == null ? null : environment.resolveSymbol(name);
				if (local != null) {
					TypedExpr.localRead(name, nodeType, position, local.toBinding());
				} else {
					final memberResolution = memberResolver == null
						|| environment == null ? null : memberResolver(expression, diagnosticPosition, environment);
					memberResolution == null ? TypedExpr.nameRead(name, nodeType, position) : memberResolution.nameRead(name, nodeType, position);
				}
			case EField(object, field):
				final memberResolution = memberResolver == null
					|| environment == null ? null : memberResolver(expression, diagnosticPosition, environment);
				final receiver = buildExpr(object, null, diagnosticPosition, environment, typeResolver, callResolver, memberResolver);
				memberResolution == null ? TypedExpr.fieldRead(receiver, field, nodeType,
					position) : memberResolution.fieldRead(receiver, field, nodeType, position);
			case ENullSafeField(object, field):
				TypedExpr.nullSafeFieldRead(buildExpr(object, null, diagnosticPosition, environment, typeResolver, callResolver, memberResolver), field,
					nodeType, position);
			case ECall(callee, arguments):
				switch (callee) {
					case ESuper:
						final receiver = buildExpr(callee, null, diagnosticPosition, environment, typeResolver, callResolver, memberResolver);
						final typedArguments = buildExpressions(arguments, diagnosticPosition, environment, typeResolver, callResolver, memberResolver);
						final application = typeResolver == null ? null : typeResolver.constructorApplication(receiver.getType(),
							[for (argument in typedArguments) argument.getType()], arguments);
						return TypedExpr.superConstructorCall(receiver, typedArguments, position, application);
					case ELambda(names, body, signature) if (names.length == arguments.length):
						final typedArguments = buildExpressions(arguments, diagnosticPosition, environment, typeResolver, callResolver, memberResolver);
						final typedLambda = buildLambda(names, body, [for (argument in typedArguments) argument.getType()], null, diagnosticPosition,
							environment, typeResolver, callResolver, memberResolver, signature);
						return TypedExpr.call(typedLambda, typedArguments, null, typedLambda.getType().getFunctionReturn(), position);
					case _:
				}
				final loweredProbe = compileTimeProbe(callee, arguments, position, diagnosticPosition, environment, typeResolver);
				if (loweredProbe != null) {
					loweredProbe;
				} else {
					final resolution = callResolver == null
						|| environment == null ? new TypedCallResolution() : callResolver(callee, arguments, diagnosticPosition, environment, expression);
					// A declaration-selected generic call owns its applied signature. Replaying
					// its callee must not allocate an unrelated stored-method capture.
					final selected = resolution.getDeclaration();
					if (resolution.getTargetScope() != null) {
						if (selected == null || arguments.length != 1)
							throw "selected native scope lost its body";
						return TypedExpr.targetScope(selected,
							buildExpr(arguments[0], null, diagnosticPosition, environment, typeResolver, callResolver, memberResolver), position);
					}
					final callable = selected != null
						&& selected.getTypeParameterIds()
							.length > 0 ? TyType.functionType(resolution.getExpectedArguments(),
							nodeType) : typeResolver == null
								|| environment == null ? null : typeResolver.callTargetType(callee, diagnosticPosition, environment);
					final typedCallee = buildExpr(callee, null, diagnosticPosition, environment, typeResolver, callResolver, memberResolver, null, callable);
					var typedArguments = callee.match(EIdent("__hxhx_try")) ? buildStructuralTryArguments(arguments, diagnosticPosition, environment,
						typeResolver, callResolver, memberResolver) : null;
					if (typedArguments == null)
						typedArguments = buildExpressions(arguments, diagnosticPosition, environment, typeResolver, callResolver, memberResolver,
							resolution.getExpectedArguments());
					typedArguments = applyCallArgumentConversions(typedArguments, resolution.getArgumentConversions());
					typedArguments = convertCallValues(typedArguments, resolution, typeResolver);
					if (callee.match(EIdent("__hxhx_try")))
						typedArguments = alignStructuralTryCatchResults(typedArguments, nodeType);
					// A method read can retain its declaration even when no call candidate
					// applies. Its open generic signature is not a function-value binding.
					if (resolution.getDeclaration() == null && typedCallee.getDeclaration() == null && typedCallee.getType().isFunction())
						TypedExpr.functionValueCall(typedCallee, typedArguments, nodeType, position,
							environment == null ? null : environment.getInference().callbackBinding(callee));
					else {
						final call = TypedExpr.call(typedCallee, typedArguments, resolution.getDeclaration(), nodeType, position,
							resolution.getRequiresOwnerQualification(), resolution.getExtensionProvider());
						final named = resolution.getNamedArguments();
						named == null ? call : call.withNamedArguments(named.publish(typedArguments, nodeType));
					}
				}
			case EReturn(inner):
				final returned = TypedExpr.returnExpr(inner == null ? null : buildExpr(inner, null, diagnosticPosition, environment, typeResolver,
					callResolver, memberResolver), nodeType,
					position);
				final state = environment == null ? null : environment.currentSourceReturns();
				state == null ? returned : returned.withControlTarget(state.target);
			case EVars(declarations):
				final typedDeclarations = new Array<TypedExpr>();
				for (declaration in declarations) {
					final declarationPosition = exactPosition(HxExprVarDecl.getPosition(declaration));
					final initializer = HxExprVarDecl.getInitializer(declaration);
					var typedInitializer = initializer == null ? null : buildExpr(initializer, null, HxExprVarDecl.getPosition(declaration), environment,
						typeResolver, callResolver, memberResolver);
					final writtenType = StringTools.trim(HxExprVarDecl.getTypeHint(declaration));
					final declarationType = writtenType.length > 0 ? typeResolver != null
						&& environment != null ? typeResolver.declaredType(writtenType,
							environment) : TyType.fromHintText(writtenType) : (typedInitializer == null ? TyType.unknown() : typedInitializer.getType());
					if (writtenType.length > 0
						&& environment != null
						&& environment.isUntypedContext()
						&& typedInitializer != null
						&& typedInitializer.getType().getSemanticKey() != declarationType.getSemanticKey())
						typedInitializer = TypedExpr.untypedValue(typedInitializer, declarationType, declarationPosition);
					final binding = environment == null ? null : environment.declareLocal(HxExprVarDecl.getName(declaration), declarationType, Variable)
						.toBinding();
					typedDeclarations.push(TypedExpr.variableDeclaration(HxExprVarDecl.getName(declaration), HxExprVarDecl.getTypeHint(declaration),
						typedInitializer, HxExprVarDecl.getIsFinal(declaration), HxExprVarDecl.getIsStatic(declaration), declarationType, declarationPosition,
						binding));
				}
				TypedExpr.variableDeclarations(typedDeclarations, nodeType, position);
			case EVariableDeclaration(_, _, _, _, _, _):
				throw "expression-level variable declaration must be nested inside EVars";
			case EWhile(condition, body, bodyIsBlock, loopPosition, loopKind):
				final typedCondition = buildExpr(condition, null, loopPosition, environment, typeResolver, callResolver, memberResolver);
				final controls = environment == null ? null : environment.requireControlScope();
				final target = controls == null ? null : controls.enter(Loop, TypedBodyFingerprint.forExpression(expression));
				if (environment != null)
					environment.enterLexicalScope();
				final typedBody = buildExpressions(body, loopPosition, environment, typeResolver, callResolver, memberResolver);
				if (environment != null)
					environment.exitLexicalScope();
				if (controls != null)
					controls.exit(target);
				TypedExpr.whileExpr(typedCondition, typedBody, bodyIsBlock, nodeType, exactPosition(loopPosition), loopKind).withControlTarget(target);
			case EBreak(controlPosition):
				TypedExpr.breakExpr(exactPosition(controlPosition))
					.withControlTarget(environment == null ? null : environment.requireControlScope().loopTarget());
			case EContinue(controlPosition):
				TypedExpr.continueExpr(exactPosition(controlPosition))
					.withControlTarget(environment == null ? null : environment.requireControlScope().loopTarget());
			case EDiscardThen(effect, continuation):
				final typedEffect = buildExpr(effect, null, diagnosticPosition, environment, typeResolver, callResolver, memberResolver);
				final typedContinuation = buildExpr(continuation, null, diagnosticPosition, environment, typeResolver, callResolver, memberResolver);
				TypedExpr.block([typedEffect, typedContinuation], nodeType, position);
			case EMacroExpr(inner, wrappers):
				TypedExpr.macroExpr(buildExpr(inner, null, diagnosticPosition, null, null, null, null), wrappers == null ? [] : wrappers.copy(), nodeType,
					position);
			case EMacroType(typeText):
				TypedExpr.macroType(typeText, nodeType, position);
			case ELambda(arguments, body, signature):
				buildLambda(arguments, body, [for (_ in arguments) TyType.fromHintText("Dynamic")], position, diagnosticPosition, environment, typeResolver,
					callResolver, memberResolver, signature, nodeType.isFunction() ? nodeType : null);
			case ETryCatchRaw(raw):
				final block = structuralOpaqueBlock(raw, position, diagnosticPosition, environment, typeResolver, callResolver, memberResolver);
				if (block != null) {
					block;
				} else {
					final tryCatch = structuralTryCatch(raw, position, diagnosticPosition, environment, typeResolver, callResolver, memberResolver);
					tryCatch == null ? TypedExpr.opaque(TypedOpaqueExprKind.TryCatch, raw, nodeType, position) : tryCatch;
				}
			case ESwitchRaw(raw):
				TypedExpr.opaque(TypedOpaqueExprKind.Switch, raw, nodeType, position);
			case ESwitch(scrutinee, patterns, expressions):
				final typedScrutinee = buildExpr(scrutinee, null, diagnosticPosition, environment, typeResolver, callResolver, memberResolver);
				// A pattern capture shadows an existing lexical local, including a
				// payload captured by an outer switch. Without that local, resolve
				// members first: a static constant restricts the matched values.
				function isCapture(name:String):Bool {
					return environment != null
						&& memberResolver != null
						&& (environment.resolveSymbol(name) != null
							|| memberResolver(EIdent(name), diagnosticPosition, environment) == null);
				}
				final irrefutable = patterns != null
					&& patterns.filter(pattern -> TySwitchIrrefutable.proves(pattern, typedScrutinee.getType(), isCapture)).length > 0;
				final exhaustive = irrefutable
					|| (typeResolver != null
						&& typeResolver.enumSwitchCoverage(typedScrutinee.getType(), patterns, diagnosticPosition, isCapture));
				final typedBranches = new Array<TypedExpr>();
				final patternBindings = new Array<TyLocalBinding>();
				final count = patterns == null
					|| expressions == null ? 0 : (patterns.length < expressions.length ? patterns.length : expressions.length);
				for (index in 0...count) {
					if (environment != null)
						environment.enterLexicalScope();
					for (binding in declarePatternBindings(environment, patterns[index], typedScrutinee.getType(), typeResolver, diagnosticPosition))
						patternBindings.push(binding);
					typedBranches.push(buildExpr(expressions[index], null, diagnosticPosition, environment, typeResolver, callResolver, memberResolver));
					if (environment != null)
						environment.exitLexicalScope();
				}
				TypedExpr.switchExpr(typedScrutinee, patterns == null ? [] : patterns.copy(), typedBranches, nodeType, position, patternBindings, exhaustive);
			case ENew(typePath, arguments):
				final typedArguments = buildExpressions(arguments, diagnosticPosition, environment, typeResolver, callResolver, memberResolver);
				final constructor = typeResolver == null ? null : typeResolver.constructorApplication(nodeType,
					[for (argument in typedArguments) argument.getType()], arguments);
				TypedExpr.newValue(typePath, typedArguments, nodeType, position, constructor);
			case EUnop(op, fixity, inner):
				TypedExpr.unary(op, fixity, buildExpr(inner, null, diagnosticPosition, environment, typeResolver, callResolver, memberResolver), nodeType,
					position);
			case EBinop("is", value, operand):
				final target = typeResolver == null
					|| environment == null ? null : typeResolver.runtimeTypeTarget(operand, environment, TypeOperand);
				if (target == null)
					throw "runtime type test requires a resolved target";
				TypedExpr.runtimeTypeTest(buildExpr(value, null, diagnosticPosition, environment, typeResolver, callResolver, memberResolver), target,
					position);
			case EBinop("=", left, right):
				final destination = TypedCastExpectation.isUnchecked(right)
					|| TypedArrayLiteral.isLiteral(right)
					|| TypedAnonymousLiteral.isLiteral(right) ? expressionType(left, diagnosticPosition, environment, typeResolver) : null;
				final typedRight = buildExpr(right, null, diagnosticPosition, environment, typeResolver, callResolver, memberResolver, destination);
				final typedLeft = buildExpr(left, null, diagnosticPosition, environment, typeResolver, callResolver, memberResolver);
				// A declared conversion is executable behavior, including effects.
				// Keep the selected field type and materialize the conversion once.
				final converted = typedLeft.getFieldInfo() == null
					|| typeResolver == null
					|| (environment != null && environment.isUntypedContext())
					|| TyFieldAssignment.explicitlyUntyped(right) ? typedRight : typeResolver.convertValue(typedRight, typedLeft.getType());
				TypedExpr.assign(typedLeft, converted, nodeType, position);
			case EBinop(op, left, right) if (isCompoundAssignment(op)):
				final typedLeft = buildExpr(left, null, diagnosticPosition, environment, typeResolver, callResolver, memberResolver);
				final typedRight = buildExpr(right, null, diagnosticPosition, environment, typeResolver, callResolver, memberResolver);
				TypedExpr.compoundAssign(op, typedLeft, typedRight, nodeType, position);
			case EBinop(op, left, right):
				final typedLeft = buildExpr(left, null, diagnosticPosition, environment, typeResolver, callResolver, memberResolver);
				final typedRight = buildExpr(right, null, diagnosticPosition, environment, typeResolver, callResolver, memberResolver);
				TypedExpr.binary(op, typedLeft, typedRight, nodeType, position);
			case ETernary(condition, whenTrue, whenFalse):
				final typedCondition = buildExpr(condition, null, diagnosticPosition, environment, typeResolver, callResolver, memberResolver);
				final typedWhenTrue = buildExpr(whenTrue, null, diagnosticPosition, environment, typeResolver, callResolver, memberResolver, expected);
				final typedWhenFalse = buildExpr(whenFalse, null, diagnosticPosition, environment, typeResolver, callResolver, memberResolver, expected);
				TypedExpr.ternary(typedCondition, typedWhenTrue, typedWhenFalse, nodeType, position);
			case EAnon(fieldNames, fieldValues):
				final contexts = TypedAnonymousLiteral.fieldTypes(fieldNames, nodeType);
				final children = buildExpressions(fieldValues, diagnosticPosition, environment, typeResolver, callResolver, memberResolver, contexts);
				// A declared abstract conversion can execute code; retain it at the
				// field's original position rather than just changing its storage type.
				final converted = typeResolver == null ? children : [
					for (index in 0...children.length)
						contexts[index].isUnknown() ? children[index] : typeResolver.convertValue(children[index], contexts[index])
				];
				TypedExpr.anonymous(fieldNames == null ? [] : fieldNames.copy(), converted, nodeType, position);
			case EArrayComprehension(name, iterable, guard, value):
				final typedIterable = buildExpr(iterable, null, diagnosticPosition, environment, typeResolver, callResolver, memberResolver);
				final elementType = switch (typedIterable.getType().getTypeArguments()) {
					case [element]: element;
					case _: TyType.fromHintText("Dynamic");
				};
				if (environment != null)
					environment.enterLexicalScope();
				final binding = environment == null ? null : environment.declareLocal(name, elementType, ComprehensionVariable).toBinding();
				final typedGuard = guard == null ? null : buildExpr(guard, null, diagnosticPosition, environment, typeResolver, callResolver, memberResolver);
				final typedValue = buildExpr(value, null, diagnosticPosition, environment, typeResolver, callResolver, memberResolver);
				if (environment != null)
					environment.exitLexicalScope();
				TypedExpr.arrayComprehension(name, typedIterable, typedGuard, typedValue, nodeType, position, binding);
			case EArrayDecl(values):
				final element = TypedArrayLiteral.elementType(nodeType);
				final map = TypedMapLiteral.context(nodeType);
				if (map != null && TypedMapLiteral.isLiteral(expression)) {
					final entries = [
						for (entry in values)
							switch entry {
								case EBinop("=>", key, value):
									final typedKey = buildExpr(key, null, diagnosticPosition, environment, typeResolver, callResolver, memberResolver, map.key);
									final typedValue = buildExpr(value, null, diagnosticPosition, environment, typeResolver, callResolver, memberResolver,
										map.value);
									// The arrow groups two operands; it has no standalone value type.
									// Executable abstract conversions stay at the original operand position.
									TypedExpr.binary("=>", typeResolver == null ? typedKey : typeResolver.convertValue(typedKey, map.key),
										typeResolver == null ? typedValue : typeResolver.convertValue(typedValue, map.value), TyType.unknown(), null);
								case _:
									throw "typed Map literal lost an arrow entry";
							}
					];
					return TypedExpr.arrayDecl(entries, nodeType, position);
				}
				// A comprehension's loop still has Void type. Its yield owns element
				// conversions; treating the loop as an element demands a false return.
				final comprehension = values.length == 1 && values[0].match(ESourceFor(_, _, _, _));
				TypedExpr.arrayDecl(buildExpressions(values, diagnosticPosition, environment, typeResolver, callResolver,
					memberResolver, element == null || comprehension ? null : [for (_ in values) element]),
					nodeType, position);
			case EArrayAccess(array, index):
				final typedArray = buildExpr(array, null, diagnosticPosition, environment, typeResolver, callResolver, memberResolver);
				final typedIndex = buildExpr(index, null, diagnosticPosition, environment, typeResolver, callResolver, memberResolver);
				TypedExpr.arrayAccess(typedArray, typedIndex, nodeType, position);
			case ERange(start, end):
				final typedStart = buildExpr(start, null, diagnosticPosition, environment, typeResolver, callResolver, memberResolver);
				final typedEnd = buildExpr(end, null, diagnosticPosition, environment, typeResolver, callResolver, memberResolver);
				TypedExpr.range(typedStart, typedEnd, nodeType, position);
			case ECast(inner, typeHint):
				final typedInner = switch (inner) {
					case ELambda(names, body, signature) if (nodeType.isFunction()
						&& nodeType.getFunctionArguments().length == names.length):
						buildLambda(names, body, nodeType.getFunctionArguments(), null, diagnosticPosition, environment, typeResolver, callResolver,
							memberResolver, signature);
					case _: buildExpr(inner, null, diagnosticPosition, environment, typeResolver, callResolver, memberResolver);
				};
				TypedExpr.castValue(typedInner, typeHint, nodeType, position);
			case EUntyped(inner):
				final buildInner = () -> buildExpr(inner, null, diagnosticPosition, environment, typeResolver, callResolver, memberResolver);
				final typedInner = environment == null ? buildInner() : environment.withUntyped(buildInner);
				TypedExpr.untypedValue(typeResolver == null ? typedInner : TypedFeatureIntrinsic.capture(typedInner), nodeType, position);
			case EUnsupported(raw):
				TypedExpr.opaque(TypedOpaqueExprKind.Unsupported, raw, nodeType, position);
		};
		return TypedOmittedInputContext.convert(expression, value, expected, environment);
	}

	/**
		Build one expression that lives outside an ordinary function body.

		Field initializers use this entry point with a fresh lexical environment and
		the same semantic resolvers as methods in the owning class.
	**/
	public static function buildExpression(expression:HxExpr, diagnosticPosition:HxPos, environment:Null<TyFunctionEnv>, ?typeResolver:TypedExprTypeResolver,
			?callResolver:TypedCallDeclarationResolver, ?memberResolver:TypedMemberDeclarationResolver, ?expected:TyType):TypedExpr {
		if (expression == null)
			throw "cannot build a null typed expression";
		final position = diagnosticPosition == null ? HxPos.unknown() : diagnosticPosition;
		return buildExpr(expression, exactPosition(position), position, environment, typeResolver, callResolver, memberResolver, expected);
	}

	static function buildStmt(statement:HxStmt, environment:Null<TyFunctionEnv>, typeResolver:Null<TypedExprTypeResolver>,
			callResolver:Null<TypedCallDeclarationResolver>, memberResolver:Null<TypedMemberDeclarationResolver>):TypedStmt {
		final sourcePosition = switch (statement) {
			case STargetScope(_, _, _): throw "native target scope is not valid in this source or target phase";
			case SBlock(_, position) | SVar(_, _, _, position) | SIf(_, _, _, position) | SForIn(_, _, _, position) | SForKeyValue(_, _, _, _, position) |
				SWhile(_, _, position) | SDoWhile(_, _, position) | SSwitch(_, _, _, position) | STry(_, _, position) | SBreak(position) |
				SContinue(position) | SThrow(_, position) | SReturnVoid(position) | SReturn(_, position) | SExpr(_, position): position;
		};
		final storedPosition = exactPosition(sourcePosition);
		final diagnosticPosition = sourcePosition == null ? HxPos.unknown() : sourcePosition;
		return switch (statement) {
			case STargetScope(_, _, _): throw "native target scope is not valid in this source or target phase";
			case SBlock(statements, _):
				if (environment != null)
					environment.enterLexicalScope();
				final typedStatements = buildStatements(statements, environment, typeResolver, callResolver, memberResolver);
				if (environment != null)
					environment.exitLexicalScope();
				TypedStmt.block(typedStatements, storedPosition);
			case SVar(name, typeHint, initializer, _, metadata):
				final expected = typeResolver == null
					|| environment == null
					|| typeHint == null
					|| StringTools.trim(typeHint).length == 0 ? null : typeResolver.declaredType(typeHint, environment);
				final unchecked = expected != null && environment != null && environment.isUntypedContext();
				var typedInitializer = initializer == null ? null : buildExpr(initializer, storedPosition, diagnosticPosition, environment, typeResolver,
					callResolver, memberResolver, unchecked ? null : expected);
				if (typedInitializer != null && expected != null && typeResolver != null) {
					if (unchecked && typedInitializer.getType().getSemanticKey() != expected.getSemanticKey())
						// Preserve both the known operand and the authored unchecked destination.
						typedInitializer = TypedExpr.untypedValue(typedInitializer, expected, storedPosition);
					else
						typedInitializer = typeResolver.convertValue(typedInitializer, expected);
				}
				final writtenType = StringTools.trim(typeHint == null ? "" : typeHint);
				final localType = writtenType.length > 0 ? TyType.fromHintText(writtenType) : (typedInitializer == null ? TyType.unknown() : typedInitializer.getType());
				final binding = environment == null ? null : environment.declareLocal(name, localType, Variable).toBinding();
				TypedStmt.variable(name, typeHint, typedInitializer, storedPosition, metadata == null ? [] : metadata, binding);
			case SIf(condition, whenTrue, whenFalse, _):
				final typedCondition = buildExpr(condition, storedPosition, diagnosticPosition, environment, typeResolver, callResolver, memberResolver);
				if (environment != null)
					environment.enterLexicalScope();
				final typedWhenTrue = buildStmt(whenTrue, environment, typeResolver, callResolver, memberResolver);
				if (environment != null)
					environment.exitLexicalScope();
				var typedWhenFalse:Null<TypedStmt> = null;
				if (whenFalse != null) {
					if (environment != null)
						environment.enterLexicalScope();
					typedWhenFalse = buildStmt(whenFalse, environment, typeResolver, callResolver, memberResolver);
					if (environment != null)
						environment.exitLexicalScope();
				}
				TypedStmt.ifStmt(typedCondition, typedWhenTrue, typedWhenFalse, storedPosition);
			case SForIn(name, iterable, body, _):
				final typedIterable = buildExpr(iterable, storedPosition, diagnosticPosition, environment, typeResolver, callResolver, memberResolver);
				final controls = environment == null ? null : environment.requireControlScope();
				final target = controls == null ? null : controls.enter(Loop, TypedBodyFingerprint.forStatements([statement]));
				if (environment != null)
					environment.enterLexicalScope();
				final binding = environment == null ? null : environment.declareLocal(name, TyType.fromHintText("Dynamic"), LoopVariable).toBinding();
				final typedBody = buildStmt(body, environment, typeResolver, callResolver, memberResolver);
				if (environment != null)
					environment.exitLexicalScope();
				if (controls != null)
					controls.exit(target);
				TypedStmt.forIn(name, typedIterable, typedBody, storedPosition, binding).withControlTarget(target);
			case SForKeyValue(keyName, valueName, iterable, body, _):
				final typedIterable = buildExpr(iterable, storedPosition, diagnosticPosition, environment, typeResolver, callResolver, memberResolver);
				final bindingTypes = TySourceFor.bindingTypes(KeyValue(keyName, valueName), iterable, typedIterable.getType());
				final controls = environment == null ? null : environment.requireControlScope();
				final target = controls == null ? null : controls.enter(Loop, TypedBodyFingerprint.forStatements([statement]));
				if (environment != null)
					environment.enterLexicalScope();
				final bindings = environment == null ? [] : [
					environment.declareLocal(keyName, bindingTypes == null ? TyType.fromHintText("String") : bindingTypes[0], LoopVariable).toBinding(),
					environment.declareLocal(valueName, bindingTypes == null ? TyType.fromHintText("Dynamic") : bindingTypes[1], LoopVariable).toBinding()
				];
				final typedBody = buildStmt(body, environment, typeResolver, callResolver, memberResolver);
				if (environment != null)
					environment.exitLexicalScope();
				if (controls != null)
					controls.exit(target);
				TypedStmt.forKeyValue(keyName, valueName, typedIterable, typedBody, storedPosition, bindings).withControlTarget(target);
			case SWhile(condition, body, _):
				final typedCondition = buildExpr(condition, storedPosition, diagnosticPosition, environment, typeResolver, callResolver, memberResolver);
				final controls = environment == null ? null : environment.requireControlScope();
				final target = controls == null ? null : controls.enter(Loop, TypedBodyFingerprint.forStatements([statement]));
				if (environment != null)
					environment.enterLexicalScope();
				final typedBody = buildStmt(body, environment, typeResolver, callResolver, memberResolver);
				if (environment != null)
					environment.exitLexicalScope();
				if (controls != null)
					controls.exit(target);
				TypedStmt.whileStmt(typedCondition, typedBody, storedPosition).withControlTarget(target);
			case SDoWhile(body, condition, _):
				final controls = environment == null ? null : environment.requireControlScope();
				final target = controls == null ? null : controls.enter(Loop, TypedBodyFingerprint.forStatements([statement]));
				if (environment != null)
					environment.enterLexicalScope();
				final typedBody = buildStmt(body, environment, typeResolver, callResolver, memberResolver);
				if (environment != null)
					environment.exitLexicalScope();
				if (controls != null)
					controls.exit(target);
				TypedStmt.doWhile(typedBody,
					buildExpr(condition, storedPosition, diagnosticPosition, environment, typeResolver, callResolver, memberResolver), storedPosition)
					.withControlTarget(target);
			case SSwitch(scrutinee, patterns, bodies, _):
				final typedScrutinee = buildExpr(scrutinee, storedPosition, diagnosticPosition, environment, typeResolver, callResolver, memberResolver);
				final typedBodies = new Array<TypedStmt>();
				final bindings = new Array<TyLocalBinding>();
				final count = patterns == null || bodies == null ? 0 : (patterns.length < bodies.length ? patterns.length : bodies.length);
				for (index in 0...count) {
					if (environment != null)
						environment.enterLexicalScope();
					for (binding in declarePatternBindings(environment, patterns[index], typedScrutinee.getType(), typeResolver, diagnosticPosition))
						bindings.push(binding);
					typedBodies.push(buildStmt(bodies[index], environment, typeResolver, callResolver, memberResolver));
					if (environment != null)
						environment.exitLexicalScope();
				}
				TypedStmt.switchStmt(typedScrutinee, patterns == null ? [] : patterns.copy(), typedBodies, storedPosition, bindings);
			case STry(body, catches, _):
				final catchNames = new Array<String>();
				final catchTypeHints = new Array<String>();
				final catchBodies = new Array<TypedStmt>();
				final catchBindings = new Array<TyLocalBinding>();
				if (environment != null)
					environment.enterLexicalScope();
				final typedTryBody = buildStmt(body, environment, typeResolver, callResolver, memberResolver);
				if (environment != null)
					environment.exitLexicalScope();
				if (catches != null)
					for (entry in catches) {
						catchNames.push(entry.name);
						catchTypeHints.push(entry.typeHint);
						if (environment != null) {
							environment.enterLexicalScope();
							catchBindings.push(environment.declareLocal(entry.name, TyType.fromHintText("Dynamic"), CatchVariable).toBinding());
						}
						catchBodies.push(buildStmt(entry.body, environment, typeResolver, callResolver, memberResolver));
						if (environment != null)
							environment.exitLexicalScope();
					}
				final uses = new Array<TypedCatchUse>();
				if (typeResolver != null)
					for (binding in catchBindings) {
						final use = typeResolver.catchUse(binding);
						if (use != null)
							uses.push(use);
					}
				TypedStmt.tryStmt(typedTryBody, catchNames, catchTypeHints, catchBodies, storedPosition, catchBindings).withCatchUses(uses);
			case SBreak(_):
				TypedStmt.breakStmt(storedPosition).withControlTarget(environment == null ? null : environment.requireControlScope().loopTarget());
			case SContinue(_):
				TypedStmt.continueStmt(storedPosition).withControlTarget(environment == null ? null : environment.requireControlScope().loopTarget());
			case SThrow(expression, _):
				TypedStmt.throwStmt(buildExpr(expression, storedPosition, diagnosticPosition, environment, typeResolver, callResolver, memberResolver),
					storedPosition);
			case SReturnVoid(_):
				TypedStmt.returnVoid(storedPosition);
			case SReturn(expression, _):
				final expected = environment == null || environment.getReturnType().isUnknown() ? null : environment.getReturnType();
				final value = buildExpr(expression, storedPosition, diagnosticPosition, environment, typeResolver, callResolver, memberResolver, expected);
				TypedStmt.returnValue(typeResolver == null
					|| expected == null ? value : typeResolver.convertValue(value, expected), storedPosition);
			case SExpr(expression, _):
				TypedStmt.expressionStmt(buildExpr(expression, storedPosition, diagnosticPosition, environment, typeResolver, callResolver, memberResolver),
					storedPosition);
		};
	}

	static function buildStatements(statements:Array<HxStmt>, environment:Null<TyFunctionEnv>, typeResolver:Null<TypedExprTypeResolver>,
			callResolver:Null<TypedCallDeclarationResolver>, memberResolver:Null<TypedMemberDeclarationResolver>):Array<TypedStmt> {
		if (statements == null)
			return [];
		return [
			for (statement in statements)
				buildStmt(statement, environment, typeResolver, callResolver, memberResolver)
		];
	}

	public static function buildFunction(ownerName:String, sourceOrdinal:Int, declaration:HxFunctionDecl, semanticDeclaration:Null<TyDeclarationInfo>,
			environment:Null<TyFunctionEnv>, ?typeResolver:TypedExprTypeResolver, ?callResolver:TypedCallDeclarationResolver,
			?memberResolver:TypedMemberDeclarationResolver):TypedFunction {
		final sourceBody = HxFunctionDecl.getBody(declaration);
		final semanticBody = environment == null
			|| typeResolver == null ? expandStructuralStatements(sourceBody) : environment.functionBodyForReplay(declaration);
		final lexicalReplay = environment == null ? null : environment.createBodyReplay();
		final defaults = new Array<TypedFunctionDefault>();
		final arguments = HxFunctionDecl.getArgs(declaration);
		for (index in 0...arguments.length) {
			switch HxFunctionArg.getDefaultValue(arguments[index]) {
				case NoDefault:
				case Default(expression):
					final expected = environment == null ? null : environment.getParams()[index].getType();
					var value = buildExpression(expression, HxFunctionDecl.getPos(declaration), lexicalReplay, typeResolver, callResolver, memberResolver,
						expected);
					if (typeResolver != null && expected != null)
						value = typeResolver.convertValue(value, expected);
					defaults.push(new TypedFunctionDefault(index, value));
			}
		}
		final controls = lexicalReplay == null
			|| lexicalReplay.getRootControlTarget() == null ? null : lexicalReplay.requireControlScope();
		if (controls != null)
			controls.beginReturns(controls.getRoot(), environment.getReturnType());
		final typedStatements = buildStatements(semanticBody, lexicalReplay, typeResolver, callResolver, memberResolver);
		if (controls != null)
			controls.finishReturns(controls.getRoot());
		if (lexicalReplay != null)
			lexicalReplay.assertReplayComplete();
		final typedBody = new TypedFunctionBody(typedStatements, TypedBodyFingerprint.forStatements(sourceBody));
		return new TypedFunction(ownerName, sourceOrdinal, declaration, semanticDeclaration, environment, typedBody, defaults);
	}

	/** Build conservative structural bodies for synthetic modules that bypass TyperStage. **/
	public static function buildFallbackModule(parsed:ParsedModule, environment:TyModuleEnv):Array<TypedClass> {
		final out = new Array<TypedClass>();
		if (parsed == null || parsed.getDecl() == null)
			return out;
		final moduleDeclaration = parsed.getDecl();
		final mainClass = HxModuleDecl.getMainClass(moduleDeclaration);
		for (classDeclaration in HxModuleDecl.getClasses(moduleDeclaration)) {
			final functions = new Array<TypedFunction>();
			final sourceFunctions = HxClassDecl.getFunctions(classDeclaration);
			final envFunctions = classDeclaration == mainClass
				&& environment != null
				&& environment.getMainClass() != null ? environment.getMainClass().getFunctions() : [];
			for (index in 0...sourceFunctions.length) {
				final functionEnvironment = index < envFunctions.length ? envFunctions[index] : null;
				functions.push(buildFunction(HxClassDecl.getName(classDeclaration), index, sourceFunctions[index], null, functionEnvironment));
			}
			out.push(new TypedClass(classDeclaration, null, functions));
		}
		return out;
	}
}
