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

	static function expressionTail(expressions:Array<TypedExpr>, start:Int):Array<HxExpr> {
		final out = new Array<HxExpr>();
		for (index in start...expressions.length)
			out.push(expression(expressions[index]));
		return out;
	}

	static function blockExpression(children:Array<TypedExpr>):HxExpr {
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
					var binder:HxExpr = ELambda([texts[0]], continuation);
					if (StringTools.trim(texts[1]).length > 0)
						binder = ECast(binder, "(" + texts[1] + ")->Dynamic");
					continuation = ECall(binder, [expression(values[0])]);
					hasContinuation = true;
				case _:
					final projected = expression(child);
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

	public static function expression(typedExpression:TypedExpr):HxExpr {
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
			case LocalRead: EIdent(texts[0]);
			case NameRead: EIdent(texts[0]);
			case FieldRead: EField(expression(expressions[0]), texts[0]);
			case Call: ECall(expression(expressions[0]), expressionTail(expressions, 1));
			case MacroExpr: EMacroExpr(expression(expressions[0]), texts.copy());
			case MacroType: EMacroType(texts[0]);
			case Lambda: ELambda(texts.copy(), expression(expressions[0]));
			case SwitchExpr: ESwitch(expression(expressions[0]), typedExpression.getPatterns(), expressionTail(expressions, 1));
			case NewValue: ENew(texts[0], expressionTail(expressions, 0));
			case Unary: EUnop(typedExpression.getUnaryOperator(), typedExpression.getUnaryFixity(), expression(expressions[0]));
			case Binary: EBinop(texts[0], expression(expressions[0]), expression(expressions[1]));
			case Assign: EBinop("=", expression(expressions[0]), expression(expressions[1]));
			case CompoundAssign: EBinop(texts[0], expression(expressions[0]), expression(expressions[1]));
			case Ternary: ETernary(expression(expressions[0]), expression(expressions[1]), expression(expressions[2]));
			case Anonymous: EAnon(texts.copy(), expressionTail(expressions, 0));
			case ArrayComprehension:
				final guard = typedExpression.getBoolValue() ? expression(expressions[1]) : null;
				final valueIndex = typedExpression.getBoolValue() ? 2 : 1;
				EArrayComprehension(texts[0], expression(expressions[0]), guard, expression(expressions[valueIndex]));
			case ArrayDecl: EArrayDecl(expressionTail(expressions, 0));
			case ArrayAccess: EArrayAccess(expression(expressions[0]), expression(expressions[1]));
			case Range: ERange(expression(expressions[0]), expression(expressions[1]));
			case Cast: ECast(expression(expressions[0]), texts[0]);
			case Untyped: EUntyped(expression(expressions[0]));
			case Opaque:
				switch (typedExpression.getOpaqueKind()) {
					case TryCatch: ETryCatchRaw(texts[0]);
					case Switch: ESwitchRaw(texts[0]);
					case Unsupported: EUnsupported(texts[0]);
					case null: throw "typed opaque expression is missing its kind";
				}
			case Block: blockExpression(expressions);
			case Temporary:
				throw "typed temporary must be nested inside a typed block expression";
		};
	}

	public static function statement(typedStatement:TypedStmt):HxStmt {
		final position = sourcePosition(typedStatement.getPosition());
		final names = typedStatement.getNames();
		final expressions = typedStatement.getExpressions();
		final statements = typedStatement.getStatements();
		return switch (typedStatement.getTag()) {
			case Block: SBlock([for (entry in statements) statement(entry)], position);
			case Var:
				var typeHint = names[1];
				if (StringTools.trim(typeHint).length == 0
					&& expressions.length == 1
					&& expressions[0].getType().getNominalIdentity() != null)
					typeHint = expressions[0].getType().getDisplay();
				SVar(names[0], typeHint, expressions.length == 0 ? null : expression(expressions[0]), position);
			case If: SIf(expression(expressions[0]), statement(statements[0]), statements.length == 1 ? null : statement(statements[1]), position);
			case ForIn: SForIn(names[0], expression(expressions[0]), statement(statements[0]), position);
			case ForKeyValue: SForKeyValue(names[0], names[1], expression(expressions[0]), statement(statements[0]), position);
			case While: SWhile(expression(expressions[0]), statement(statements[0]), position);
			case DoWhile: SDoWhile(statement(statements[0]), expression(expressions[0]), position);
			case Switch:
				SSwitch(expression(expressions[0]), typedStatement.getPatterns(), [for (body in statements) statement(body)], position);
			case Try:
				final catchNames = typedStatement.getCatchNames();
				final catchTypeHints = typedStatement.getCatchTypeHints();
				final catches = new Array<{name:String, typeHint:String, body:HxStmt}>();
				for (index in 0...catchNames.length)
					catches.push({name: catchNames[index], typeHint: catchTypeHints[index], body: statement(statements[index + 1])});
				STry(statement(statements[0]), catches, position);
			case Break: SBreak(position);
			case Continue: SContinue(position);
			case Throw: SThrow(expression(expressions[0]), position);
			case ReturnVoid: SReturnVoid(position);
			case Return: SReturn(expression(expressions[0]), position);
			case Expression: SExpr(expression(expressions[0]), position);
		};
	}

	public static function statements(body:TypedFunctionBody):Array<HxStmt>
		return [for (entry in body.getStatements()) statement(entry)];

	public static function functionDeclaration(typedFunction:TypedFunction):HxFunctionDecl {
		final source = typedFunction.getSourceDeclaration();
		return new HxFunctionDecl(HxFunctionDecl.getName(source), HxFunctionDecl.getVisibility(source), HxFunctionDecl.getIsStatic(source),
			HxFunctionDecl.getArgs(source), HxFunctionDecl.getReturnTypeHint(source), statements(typedFunction.getBody()),
			HxFunctionDecl.getReturnStringLiteral(source), HxFunctionDecl.getMetadata(source), HxFunctionDecl.getPos(source),
			HxFunctionDecl.getEndPos(source), "");
	}

	public static function classDeclaration(typedClass:TypedClass):HxClassDecl {
		final source = typedClass.getSourceDeclaration();
		return new HxClassDecl(HxClassDecl.getName(source), HxClassDecl.getHasStaticMain(source), [
			for (typedFunction in typedClass.getFunctions())
				functionDeclaration(typedFunction)
		],
			HxClassDecl.getFields(source), HxClassDecl.getExtendsPath(source), HxClassDecl.getMetadata(source), HxClassDecl.getIsInterface(source),
			HxClassDecl.getImplementsPaths(source));
	}

	/** Build the declaration/signature projection consumed during backend migration. **/
	public static function moduleDeclaration(parsed:ParsedModule, typedClasses:Array<TypedClass>):HxModuleDecl {
		final source = parsed.getDecl();
		final sourceMain = HxModuleDecl.getMainClass(source);
		final classes = new Array<HxClassDecl>();
		var mainClass:Null<HxClassDecl> = null;
		for (typedClass in typedClasses) {
			final projected = classDeclaration(typedClass);
			classes.push(projected);
			if (typedClass.getSourceDeclaration() == sourceMain)
				mainClass = projected;
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
		return new HxModuleDecl(HxModuleDecl.getPackagePath(source), HxModuleDecl.getImports(source), mainClass, classes, HxModuleDecl.getHeaderOnly(source),
			HxModuleDecl.getHasToplevelMain(source));
	}
}
