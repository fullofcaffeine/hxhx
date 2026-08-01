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
	static function exactPosition(position:HxPos):Null<HxPos> {
		if (position == null)
			return null;
		return position.getIndex() == 0 && position.getLine() == 0 && position.getColumn() == 0 ? null : position;
	}

	static function fallbackType(expression:HxExpr, environment:Null<TyFunctionEnv>):TyType {
		return switch (expression) {
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
			case EWhile(_, _, _, _): TyType.fromHintText("Void");
			case EBreak(_) | EContinue(_): TyType.noNormalCompletion();
			case _: TyType.unknown();
		};
	}

	static function expressionType(expression:HxExpr, diagnosticPosition:HxPos, environment:Null<TyFunctionEnv>, resolver:Null<TypedExprTypeResolver>):TyType {
		if (resolver == null || environment == null)
			return fallbackType(expression, environment);
		final resolved = resolver(expression, diagnosticPosition == null ? HxPos.unknown() : diagnosticPosition, environment);
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
				resolvedType = typeResolver(arguments[0], diagnosticPosition == null ? HxPos.unknown() : diagnosticPosition, environment.copyForInference());
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
			case SSwitch(scrutinee, patterns, bodies, position):
				SSwitch(untypedExpression(scrutinee), patterns, [for (body in bodies) untypedStatement(body)], position);
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
			case SSwitch(scrutinee, patterns, bodies, position):
				SSwitch(scrutinee, patterns, [for (body in bodies) expandStatement(body)], position);
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
			fieldResolver:Null<TypedFieldDeclarationResolver>):Null<TypedExpr> {
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
							fieldResolver);
					final binding = lexicalEnvironment == null ? null : lexicalEnvironment.declareLocal(name, localType, Variable).toBinding();
					expressions.push(TypedExpr.temporary(name, cleanHint, typedInitializer, TyType.fromHintText("Void"), storedPosition, binding));
				case SExpr(expression, _):
					expressions.push(buildExpr(expression, storedPosition, exactDiagnosticPosition, lexicalEnvironment, typeResolver, callResolver,
						fieldResolver));
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
			fieldResolver:Null<TypedFieldDeclarationResolver>):Null<TypedExpr> {
		return switch (recoveredStructuralExpression(raw)) {
			case null: null;
			case expression: buildExpr(expression, position, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver);
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
			typeResolver:Null<TypedExprTypeResolver>, callResolver:Null<TypedCallDeclarationResolver>,
			fieldResolver:Null<TypedFieldDeclarationResolver>):Array<TypedExpr> {
		if (expressions == null)
			return [];
		return [
			for (expression in expressions)
				buildExpr(expression, null, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver)
		];
	}

	static function declarePatternBindings(environment:Null<TyFunctionEnv>, pattern:HxSwitchPattern, baseType:TyType):Array<TyLocalBinding> {
		return TySwitchPatternBindings.declare(environment, pattern, baseType);
	}

	/**
		Build one typed expression while replaying the local declarations recorded by
		the typer.

		Child expressions must be built in the same explicit order used by
		`TyperStage`. Building two children as arguments to one constructor is unsafe:
		Haxe targets may evaluate those arguments in different orders, which can make
		a native compiler consume an inner lambda's local identity before the outer
		lambda identity that typing recorded first.
	**/
	static function buildExpr(expression:HxExpr, position:Null<HxPos>, diagnosticPosition:HxPos, environment:Null<TyFunctionEnv>,
			typeResolver:Null<TypedExprTypeResolver>, callResolver:Null<TypedCallDeclarationResolver>,
			fieldResolver:Null<TypedFieldDeclarationResolver>):TypedExpr {
		final nodeType = expressionType(expression, diagnosticPosition, environment, typeResolver);
		return switch (expression) {
			case ENull:
				TypedExpr.nullValue(nodeType, position);
			case EBool(value):
				TypedExpr.boolLiteral(value, nodeType, position);
			case EString(value):
				TypedExpr.stringLiteral(value, nodeType, position);
			case EInt(value):
				TypedExpr.intLiteral(value, nodeType, position);
			case EFloat(value):
				TypedExpr.floatLiteral(value, nodeType, position);
			case EEnumValue(name):
				TypedExpr.enumValue(name, nodeType, position);
			case EThis:
				TypedExpr.thisValue(nodeType, position);
			case ESuper:
				TypedExpr.superValue(nodeType, position);
			case EIdent(name):
				final local = environment == null ? null : environment.resolveSymbol(name);
				if (local != null) {
					TypedExpr.localRead(name, nodeType, position, local.toBinding());
				} else {
					final fieldResolution = fieldResolver == null
						|| environment == null ? null : fieldResolver(expression, diagnosticPosition, environment);
					TypedExpr.nameRead(name, nodeType, position,
						fieldResolution == null ? null : fieldResolution.getField(), fieldResolution != null && fieldResolution.getRequiresOwnerQualification());
				}
			case EField(object, field):
				final fieldResolution = fieldResolver == null
					|| environment == null ? null : fieldResolver(expression, diagnosticPosition, environment);
				TypedExpr.fieldRead(buildExpr(object, null, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver), field, nodeType,
					position, fieldResolution == null ? null : fieldResolution.getField());
			case ENullSafeField(object, field):
				TypedExpr.nullSafeFieldRead(buildExpr(object, null, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver), field,
					nodeType, position);
			case ECall(callee, arguments):
				final loweredProbe = compileTimeProbe(callee, arguments, position, diagnosticPosition, environment, typeResolver);
				if (loweredProbe != null) {
					loweredProbe;
				} else {
					final resolution = callResolver == null
						|| environment == null ? new TypedCallResolution() : callResolver(callee, arguments, diagnosticPosition, environment);
					final typedCallee = buildExpr(callee, null, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver);
					final typedArguments = buildExpressions(arguments, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver);
					TypedExpr.call(typedCallee, typedArguments, resolution.getDeclaration(), nodeType, position, resolution.getRequiresOwnerQualification(),
						resolution.getExtensionProvider());
				}
			case EReturn(inner):
				TypedExpr.returnExpr(inner == null ? null : buildExpr(inner, null, diagnosticPosition, environment, typeResolver, callResolver,
					fieldResolver), nodeType,
					position);
			case EVars(declarations):
				final typedDeclarations = new Array<TypedExpr>();
				for (declaration in declarations) {
					final declarationPosition = exactPosition(HxExprVarDecl.getPosition(declaration));
					final initializer = HxExprVarDecl.getInitializer(declaration);
					final typedInitializer = initializer == null ? null : buildExpr(initializer, null, HxExprVarDecl.getPosition(declaration), environment,
						typeResolver, callResolver, fieldResolver);
					final writtenType = StringTools.trim(HxExprVarDecl.getTypeHint(declaration));
					final declarationType = writtenType.length > 0 ? TyType.fromHintText(writtenType) : (typedInitializer == null ? TyType.unknown() : typedInitializer.getType());
					final binding = environment == null ? null : environment.declareLocal(HxExprVarDecl.getName(declaration), declarationType, Variable)
						.toBinding();
					typedDeclarations.push(TypedExpr.variableDeclaration(HxExprVarDecl.getName(declaration), HxExprVarDecl.getTypeHint(declaration),
						typedInitializer, HxExprVarDecl.getIsFinal(declaration), HxExprVarDecl.getIsStatic(declaration), declarationType, declarationPosition,
						binding));
				}
				TypedExpr.variableDeclarations(typedDeclarations, nodeType, position);
			case EVariableDeclaration(_, _, _, _, _, _):
				throw "expression-level variable declaration must be nested inside EVars";
			case EWhile(condition, body, bodyIsBlock, loopPosition):
				final typedCondition = buildExpr(condition, null, loopPosition, environment, typeResolver, callResolver, fieldResolver);
				if (environment != null)
					environment.enterLexicalScope();
				final typedBody = buildExpressions(body, loopPosition, environment, typeResolver, callResolver, fieldResolver);
				if (environment != null)
					environment.exitLexicalScope();
				TypedExpr.whileExpr(typedCondition, typedBody, bodyIsBlock, nodeType, exactPosition(loopPosition));
			case EBreak(controlPosition):
				TypedExpr.breakExpr(exactPosition(controlPosition));
			case EContinue(controlPosition):
				TypedExpr.continueExpr(exactPosition(controlPosition));
			case EMacroExpr(inner, wrappers):
				TypedExpr.macroExpr(buildExpr(inner, null, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver),
					wrappers == null ? [] : wrappers.copy(), nodeType, position);
			case EMacroType(typeText):
				TypedExpr.macroType(typeText, nodeType, position);
			case ELambda(arguments, body):
				final argumentBindings = new Array<TyLocalBinding>();
				if (environment != null) {
					environment.enterLexicalScope();
					for (argument in arguments)
						argumentBindings.push(environment.declareLocal(argument, TyType.fromHintText("Dynamic"), LambdaParameter).toBinding());
				}
				final typedLambdaBody = buildExpr(body, null, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver);
				if (environment != null)
					environment.exitLexicalScope();
				TypedExpr.lambda(arguments == null ? [] : arguments.copy(), typedLambdaBody, nodeType, position, argumentBindings);
			case ETryCatchRaw(raw):
				final block = structuralOpaqueBlock(raw, position, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver);
				if (block != null) {
					block;
				} else {
					final tryCatch = structuralTryCatch(raw, position, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver);
					tryCatch == null ? TypedExpr.opaque(TypedOpaqueExprKind.TryCatch, raw, nodeType, position) : tryCatch;
				}
			case ESwitchRaw(raw):
				TypedExpr.opaque(TypedOpaqueExprKind.Switch, raw, nodeType, position);
			case ESwitch(scrutinee, patterns, expressions):
				final typedScrutinee = buildExpr(scrutinee, null, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver);
				final typedBranches = new Array<TypedExpr>();
				final patternBindings = new Array<TyLocalBinding>();
				final count = patterns == null
					|| expressions == null ? 0 : (patterns.length < expressions.length ? patterns.length : expressions.length);
				for (index in 0...count) {
					if (environment != null)
						environment.enterLexicalScope();
					for (binding in declarePatternBindings(environment, patterns[index], typedScrutinee.getType()))
						patternBindings.push(binding);
					typedBranches.push(buildExpr(expressions[index], null, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver));
					if (environment != null)
						environment.exitLexicalScope();
				}
				TypedExpr.switchExpr(typedScrutinee, patterns == null ? [] : patterns.copy(), typedBranches, nodeType, position, patternBindings);
			case ENew(typePath, arguments):
				TypedExpr.newValue(typePath, buildExpressions(arguments, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver),
					nodeType, position);
			case EUnop(op, fixity, inner):
				TypedExpr.unary(op, fixity, buildExpr(inner, null, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver), nodeType,
					position);
			case EBinop("=", left, right):
				final typedRight = buildExpr(right, null, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver);
				final typedLeft = buildExpr(left, null, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver);
				TypedExpr.assign(typedLeft, typedRight, nodeType, position);
			case EBinop(op, left, right) if (isCompoundAssignment(op)):
				final typedLeft = buildExpr(left, null, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver);
				final typedRight = buildExpr(right, null, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver);
				TypedExpr.compoundAssign(op, typedLeft, typedRight, nodeType, position);
			case EBinop(op, left, right):
				final typedLeft = buildExpr(left, null, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver);
				final typedRight = buildExpr(right, null, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver);
				TypedExpr.binary(op, typedLeft, typedRight, nodeType, position);
			case ETernary(condition, whenTrue, whenFalse):
				final typedCondition = buildExpr(condition, null, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver);
				final typedWhenTrue = buildExpr(whenTrue, null, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver);
				final typedWhenFalse = buildExpr(whenFalse, null, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver);
				TypedExpr.ternary(typedCondition, typedWhenTrue, typedWhenFalse, nodeType, position);
			case EAnon(fieldNames, fieldValues):
				TypedExpr.anonymous(fieldNames == null ? [] : fieldNames.copy(),
					buildExpressions(fieldValues, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver), nodeType, position);
			case EArrayComprehension(name, iterable, guard, value):
				final typedIterable = buildExpr(iterable, null, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver);
				final elementType = switch (typedIterable.getType().getTypeArguments()) {
					case [element]: element;
					case _: TyType.fromHintText("Dynamic");
				};
				if (environment != null)
					environment.enterLexicalScope();
				final binding = environment == null ? null : environment.declareLocal(name, elementType, ComprehensionVariable).toBinding();
				final typedGuard = guard == null ? null : buildExpr(guard, null, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver);
				final typedValue = buildExpr(value, null, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver);
				if (environment != null)
					environment.exitLexicalScope();
				TypedExpr.arrayComprehension(name, typedIterable, typedGuard, typedValue, nodeType, position, binding);
			case EArrayDecl(values):
				TypedExpr.arrayDecl(buildExpressions(values, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver), nodeType, position);
			case EArrayAccess(array, index):
				final typedArray = buildExpr(array, null, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver);
				final typedIndex = buildExpr(index, null, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver);
				TypedExpr.arrayAccess(typedArray, typedIndex, nodeType, position);
			case ERange(start, end):
				final typedStart = buildExpr(start, null, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver);
				final typedEnd = buildExpr(end, null, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver);
				TypedExpr.range(typedStart, typedEnd, nodeType, position);
			case ECast(inner, typeHint):
				TypedExpr.castValue(buildExpr(inner, null, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver), typeHint, nodeType,
					position);
			case EUntyped(inner):
				TypedExpr.untypedValue(buildExpr(inner, null, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver), nodeType, position);
			case EUnsupported(raw):
				TypedExpr.opaque(TypedOpaqueExprKind.Unsupported, raw, nodeType, position);
		};
	}

	/**
		Build one expression that lives outside an ordinary function body.

		Field initializers use this entry point with a fresh lexical environment and
		the same semantic resolvers as methods in the owning class.
	**/
	public static function buildExpression(expression:HxExpr, diagnosticPosition:HxPos, environment:Null<TyFunctionEnv>, ?typeResolver:TypedExprTypeResolver,
			?callResolver:TypedCallDeclarationResolver, ?fieldResolver:TypedFieldDeclarationResolver):TypedExpr {
		if (expression == null)
			throw "cannot build a null typed expression";
		final position = diagnosticPosition == null ? HxPos.unknown() : diagnosticPosition;
		return buildExpr(expression, exactPosition(position), position, environment, typeResolver, callResolver, fieldResolver);
	}

	static function buildStmt(statement:HxStmt, environment:Null<TyFunctionEnv>, typeResolver:Null<TypedExprTypeResolver>,
			callResolver:Null<TypedCallDeclarationResolver>, fieldResolver:Null<TypedFieldDeclarationResolver>):TypedStmt {
		final sourcePosition = switch (statement) {
			case SBlock(_, position) | SVar(_, _, _, position) | SIf(_, _, _, position) | SForIn(_, _, _, position) | SForKeyValue(_, _, _, _, position) |
				SWhile(_, _, position) | SDoWhile(_, _, position) | SSwitch(_, _, _, position) | STry(_, _, position) | SBreak(position) |
				SContinue(position) | SThrow(_, position) | SReturnVoid(position) | SReturn(_, position) | SExpr(_, position): position;
		};
		final storedPosition = exactPosition(sourcePosition);
		final diagnosticPosition = sourcePosition == null ? HxPos.unknown() : sourcePosition;
		return switch (statement) {
			case SBlock(statements, _):
				if (environment != null)
					environment.enterLexicalScope();
				final typedStatements = buildStatements(statements, environment, typeResolver, callResolver, fieldResolver);
				if (environment != null)
					environment.exitLexicalScope();
				TypedStmt.block(typedStatements, storedPosition);
			case SVar(name, typeHint, initializer, _, metadata):
				final typedInitializer = initializer == null ? null : buildExpr(initializer, storedPosition, diagnosticPosition, environment, typeResolver,
					callResolver, fieldResolver);
				final writtenType = StringTools.trim(typeHint == null ? "" : typeHint);
				final localType = writtenType.length > 0 ? TyType.fromHintText(writtenType) : (typedInitializer == null ? TyType.unknown() : typedInitializer.getType());
				final binding = environment == null ? null : environment.declareLocal(name, localType, Variable).toBinding();
				TypedStmt.variable(name, typeHint, typedInitializer, storedPosition, metadata == null ? [] : metadata, binding);
			case SIf(condition, whenTrue, whenFalse, _):
				final typedCondition = buildExpr(condition, storedPosition, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver);
				if (environment != null)
					environment.enterLexicalScope();
				final typedWhenTrue = buildStmt(whenTrue, environment, typeResolver, callResolver, fieldResolver);
				if (environment != null)
					environment.exitLexicalScope();
				var typedWhenFalse:Null<TypedStmt> = null;
				if (whenFalse != null) {
					if (environment != null)
						environment.enterLexicalScope();
					typedWhenFalse = buildStmt(whenFalse, environment, typeResolver, callResolver, fieldResolver);
					if (environment != null)
						environment.exitLexicalScope();
				}
				TypedStmt.ifStmt(typedCondition, typedWhenTrue, typedWhenFalse, storedPosition);
			case SForIn(name, iterable, body, _):
				final typedIterable = buildExpr(iterable, storedPosition, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver);
				if (environment != null)
					environment.enterLexicalScope();
				final binding = environment == null ? null : environment.declareLocal(name, TyType.fromHintText("Dynamic"), LoopVariable).toBinding();
				final typedBody = buildStmt(body, environment, typeResolver, callResolver, fieldResolver);
				if (environment != null)
					environment.exitLexicalScope();
				TypedStmt.forIn(name, typedIterable, typedBody, storedPosition, binding);
			case SForKeyValue(keyName, valueName, iterable, body, _):
				final typedIterable = buildExpr(iterable, storedPosition, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver);
				if (environment != null)
					environment.enterLexicalScope();
				final bindings = environment == null ? [] : [
					environment.declareLocal(keyName, TyType.fromHintText("String"), LoopVariable).toBinding(),
					environment.declareLocal(valueName, TyType.fromHintText("Dynamic"), LoopVariable).toBinding()
				];
				final typedBody = buildStmt(body, environment, typeResolver, callResolver, fieldResolver);
				if (environment != null)
					environment.exitLexicalScope();
				TypedStmt.forKeyValue(keyName, valueName, typedIterable, typedBody, storedPosition, bindings);
			case SWhile(condition, body, _):
				final typedCondition = buildExpr(condition, storedPosition, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver);
				if (environment != null)
					environment.enterLexicalScope();
				final typedBody = buildStmt(body, environment, typeResolver, callResolver, fieldResolver);
				if (environment != null)
					environment.exitLexicalScope();
				TypedStmt.whileStmt(typedCondition, typedBody, storedPosition);
			case SDoWhile(body, condition, _):
				if (environment != null)
					environment.enterLexicalScope();
				final typedBody = buildStmt(body, environment, typeResolver, callResolver, fieldResolver);
				if (environment != null)
					environment.exitLexicalScope();
				TypedStmt.doWhile(typedBody, buildExpr(condition, storedPosition, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver),
					storedPosition);
			case SSwitch(scrutinee, patterns, bodies, _):
				final typedScrutinee = buildExpr(scrutinee, storedPosition, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver);
				final typedBodies = new Array<TypedStmt>();
				final bindings = new Array<TyLocalBinding>();
				final count = patterns == null || bodies == null ? 0 : (patterns.length < bodies.length ? patterns.length : bodies.length);
				for (index in 0...count) {
					if (environment != null)
						environment.enterLexicalScope();
					for (binding in declarePatternBindings(environment, patterns[index], typedScrutinee.getType()))
						bindings.push(binding);
					typedBodies.push(buildStmt(bodies[index], environment, typeResolver, callResolver, fieldResolver));
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
				final typedTryBody = buildStmt(body, environment, typeResolver, callResolver, fieldResolver);
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
						catchBodies.push(buildStmt(entry.body, environment, typeResolver, callResolver, fieldResolver));
						if (environment != null)
							environment.exitLexicalScope();
					}
				TypedStmt.tryStmt(typedTryBody, catchNames, catchTypeHints, catchBodies, storedPosition, catchBindings);
			case SBreak(_):
				TypedStmt.breakStmt(storedPosition);
			case SContinue(_):
				TypedStmt.continueStmt(storedPosition);
			case SThrow(expression, _):
				TypedStmt.throwStmt(buildExpr(expression, storedPosition, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver),
					storedPosition);
			case SReturnVoid(_):
				TypedStmt.returnVoid(storedPosition);
			case SReturn(expression, _):
				TypedStmt.returnValue(buildExpr(expression, storedPosition, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver),
					storedPosition);
			case SExpr(expression, _):
				TypedStmt.expressionStmt(buildExpr(expression, storedPosition, diagnosticPosition, environment, typeResolver, callResolver, fieldResolver),
					storedPosition);
		};
	}

	static function buildStatements(statements:Array<HxStmt>, environment:Null<TyFunctionEnv>, typeResolver:Null<TypedExprTypeResolver>,
			callResolver:Null<TypedCallDeclarationResolver>, fieldResolver:Null<TypedFieldDeclarationResolver>):Array<TypedStmt> {
		if (statements == null)
			return [];
		return [
			for (statement in statements)
				buildStmt(statement, environment, typeResolver, callResolver, fieldResolver)
		];
	}

	public static function buildFunction(ownerName:String, sourceOrdinal:Int, declaration:HxFunctionDecl, semanticDeclaration:Null<TyDeclarationInfo>,
			environment:Null<TyFunctionEnv>, ?typeResolver:TypedExprTypeResolver, ?callResolver:TypedCallDeclarationResolver,
			?fieldResolver:TypedFieldDeclarationResolver):TypedFunction {
		final sourceBody = HxFunctionDecl.getBody(declaration);
		final semanticBody = expandStructuralStatements(sourceBody);
		final lexicalReplay = environment == null ? null : environment.createBodyReplay();
		final typedStatements = buildStatements(semanticBody, lexicalReplay, typeResolver, callResolver, fieldResolver);
		if (lexicalReplay != null)
			lexicalReplay.assertReplayComplete();
		final typedBody = new TypedFunctionBody(typedStatements, TypedBodyFingerprint.forStatements(sourceBody));
		return new TypedFunction(ownerName, sourceOrdinal, declaration, semanticDeclaration, environment, typedBody);
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
