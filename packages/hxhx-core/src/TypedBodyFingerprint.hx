/**
	Deterministic structural fingerprint for parsed function bodies.

	The fingerprint is a lifecycle guard, not a persistent cache key. It walks
	every parsed node and scalar explicitly so native targets never depend on a
	target-specific `Array.toString` implementation. Retyping creates a new
	`TypedModule` revision instead of mutating a sealed typed body.
**/
class TypedBodyFingerprint {
	static function addInt(state:Array<Int>, value:Int):Void {
		state[0] = state[0] * 31 + value;
		state[1]++;
	}

	static function addString(state:Array<Int>, value:Null<String>):Void {
		if (value == null) {
			addInt(state, -1);
			return;
		}
		addInt(state, value.length);
		for (index in 0...value.length)
			addInt(state, value.charCodeAt(index));
	}

	static function addPosition(state:Array<Int>, position:HxPos):Void {
		if (position == null) {
			addInt(state, -1);
			return;
		}
		addInt(state, position.getIndex());
		addInt(state, position.getLine());
		addInt(state, position.getColumn());
	}

	static function addStrings(state:Array<Int>, values:Array<String>):Void {
		addInt(state, values == null ? -1 : values.length);
		if (values != null)
			for (value in values)
				addString(state, value);
	}

	static function addUnaryOperator(state:Array<Int>, op:HxUnaryOperator):Void {
		addString(state, switch (op) {
			case Increment: "increment";
			case Decrement: "decrement";
			case Negate: "negate";
			case LogicalNot: "logical-not";
			case BitwiseNot: "bitwise-not";
		});
	}

	static function addUnaryFixity(state:Array<Int>, fixity:HxUnaryFixity):Void {
		addString(state, switch (fixity) {
			case Prefix: "prefix";
			case Postfix: "postfix";
		});
	}

	static function addPatterns(state:Array<Int>, patterns:Array<HxSwitchPattern>):Void {
		addInt(state, patterns == null ? -1 : patterns.length);
		if (patterns != null)
			for (pattern in patterns)
				addPattern(state, pattern);
	}

	static function addPattern(state:Array<Int>, pattern:HxSwitchPattern):Void {
		switch (pattern) {
			case PNull:
				addString(state, "pattern-null");
			case PWildcard:
				addString(state, "pattern-wildcard");
			case PBool(value):
				addString(state, "pattern-bool");
				addInt(state, value ? 1 : 0);
			case PString(value):
				addString(state, "pattern-string");
				addString(state, value);
			case PInt(value):
				addString(state, "pattern-int");
				addInt(state, value);
			case PEnumValue(name):
				addString(state, "pattern-enum-value");
				addString(state, name);
			case PEnumExtract(name, arguments):
				addString(state, "pattern-enum-extract");
				addString(state, name);
				addPatterns(state, arguments);
			case PObject(fieldNames, fieldPatterns):
				addString(state, "pattern-object");
				addStrings(state, fieldNames);
				addPatterns(state, fieldPatterns);
			case PCapture(name, inner):
				addString(state, "pattern-capture");
				addString(state, name);
				addPattern(state, inner);
			case PArray(items):
				addString(state, "pattern-array");
				addPatterns(state, items);
			case PExtractor(extractorText, resultPattern):
				addString(state, "pattern-extractor");
				addString(state, extractorText);
				addPattern(state, resultPattern);
			case PLengthGuard(inner, bindingName, length):
				addString(state, "pattern-length-guard");
				addPattern(state, inner);
				addString(state, bindingName);
				addInt(state, length);
			case PStartsWithGuard(inner, bindingName, prefix):
				addString(state, "pattern-starts-with-guard");
				addPattern(state, inner);
				addString(state, bindingName);
				addString(state, prefix);
			case PIntEqualsGuard(inner, bindingName, value):
				addString(state, "pattern-int-equals-guard");
				addPattern(state, inner);
				addString(state, bindingName);
				addInt(state, value);
			case PIntCompareGuard(inner, bindingName, op, value):
				addString(state, "pattern-int-compare-guard");
				addPattern(state, inner);
				addString(state, bindingName);
				addString(state, op);
				addInt(state, value);
			case PParsedIntSwitchGuard(inner, bindingName, multiplier, matchValue):
				addString(state, "pattern-parsed-int-switch-guard");
				addPattern(state, inner);
				addString(state, bindingName);
				addInt(state, multiplier);
				addInt(state, matchValue);
			case PUnsupportedGuard(inner):
				addString(state, "pattern-unsupported-guard");
				addPattern(state, inner);
			case PBind(name):
				addString(state, "pattern-bind");
				addString(state, name);
			case POr(patterns):
				addString(state, "pattern-or");
				addPatterns(state, patterns);
		}
	}

	static function addExpressions(state:Array<Int>, expressions:Array<HxExpr>):Void {
		addInt(state, expressions == null ? -1 : expressions.length);
		if (expressions != null)
			for (expression in expressions)
				addExpression(state, expression);
	}

	static function addExpression(state:Array<Int>, expression:HxExpr):Void {
		switch (expression) {
			case ENull:
				addString(state, "expr-null");
			case EBool(value):
				addString(state, "expr-bool");
				addInt(state, value ? 1 : 0);
			case EString(value):
				addString(state, "expr-string");
				addString(state, value);
			case EInt(value):
				addString(state, "expr-int");
				addInt(state, value);
			case EFloat(value):
				addString(state, "expr-float");
				addString(state, Std.string(value));
			case EEnumValue(name):
				addString(state, "expr-enum-value");
				addString(state, name);
			case EThis:
				addString(state, "expr-this");
			case ESuper:
				addString(state, "expr-super");
			case EIdent(name):
				addString(state, "expr-ident");
				addString(state, name);
			case EField(object, field):
				addString(state, "expr-field");
				addExpression(state, object);
				addString(state, field);
			case ENullSafeField(object, field):
				addString(state, "expr-null-safe-field");
				addExpression(state, object);
				addString(state, field);
			case ECall(callee, arguments):
				addString(state, "expr-call");
				addExpression(state, callee);
				addExpressions(state, arguments);
			case EReturn(value):
				addString(state, "expr-return");
				addInt(state, value == null ? 0 : 1);
				if (value != null)
					addExpression(state, value);
			case EVars(declarations):
				addString(state, "expr-variable-declarations");
				addInt(state, declarations == null ? -1 : declarations.length);
				if (declarations != null)
					for (declaration in declarations)
						addExpression(state, declaration);
			case EVariableDeclaration(name, typeHint, initializer, position, isFinal, isStatic):
				addString(state, "expr-variable-declaration");
				addString(state, name);
				addString(state, typeHint);
				addInt(state, isFinal ? 1 : 0);
				addInt(state, isStatic ? 1 : 0);
				addPosition(state, position);
				addInt(state, initializer == null ? 0 : 1);
				if (initializer != null)
					addExpression(state, initializer);
			case EWhile(condition, body, bodyIsBlock, position):
				addString(state, "expr-while");
				addExpression(state, condition);
				addExpressions(state, body);
				addInt(state, bodyIsBlock ? 1 : 0);
				addPosition(state, position);
			case EBreak(position):
				addString(state, "expr-break");
				addPosition(state, position);
			case EContinue(position):
				addString(state, "expr-continue");
				addPosition(state, position);
			case EMacroExpr(inner, wrappers):
				addString(state, "expr-macro");
				addExpression(state, inner);
				addStrings(state, wrappers);
			case EMacroType(typeText):
				addString(state, "expr-macro-type");
				addString(state, typeText);
			case ELambda(arguments, body):
				addString(state, "expr-lambda");
				addStrings(state, arguments);
				addExpression(state, body);
			case ETryCatchRaw(raw):
				addString(state, "expr-try-raw");
				addString(state, raw);
			case ESwitchRaw(raw):
				addString(state, "expr-switch-raw");
				addString(state, raw);
			case ESwitch(scrutinee, patterns, branches):
				addString(state, "expr-switch");
				addExpression(state, scrutinee);
				addPatterns(state, patterns);
				addExpressions(state, branches);
			case ENew(typePath, arguments):
				addString(state, "expr-new");
				addString(state, typePath);
				addExpressions(state, arguments);
			case EUnop(op, fixity, inner):
				addString(state, "expr-unary");
				addUnaryOperator(state, op);
				addUnaryFixity(state, fixity);
				addExpression(state, inner);
			case EBinop(op, left, right):
				addString(state, "expr-binary");
				addString(state, op);
				addExpression(state, left);
				addExpression(state, right);
			case ETernary(condition, whenTrue, whenFalse):
				addString(state, "expr-ternary");
				addExpression(state, condition);
				addExpression(state, whenTrue);
				addExpression(state, whenFalse);
			case EAnon(fieldNames, fieldValues):
				addString(state, "expr-anonymous");
				addStrings(state, fieldNames);
				addExpressions(state, fieldValues);
			case EArrayComprehension(name, iterable, guard, value):
				addString(state, "expr-array-comprehension");
				addString(state, name);
				addExpression(state, iterable);
				addInt(state, guard == null ? 0 : 1);
				if (guard != null)
					addExpression(state, guard);
				addExpression(state, value);
			case EArrayDecl(values):
				addString(state, "expr-array");
				addExpressions(state, values);
			case EArrayAccess(array, index):
				addString(state, "expr-array-access");
				addExpression(state, array);
				addExpression(state, index);
			case ERange(start, end):
				addString(state, "expr-range");
				addExpression(state, start);
				addExpression(state, end);
			case ECast(inner, typeHint):
				addString(state, "expr-cast");
				addExpression(state, inner);
				addString(state, typeHint);
			case EUntyped(inner):
				addString(state, "expr-untyped");
				addExpression(state, inner);
			case EUnsupported(raw):
				addString(state, "expr-unsupported");
				addString(state, raw);
		}
	}

	static function addStatements(state:Array<Int>, statements:Array<HxStmt>):Void {
		addInt(state, statements == null ? -1 : statements.length);
		if (statements != null)
			for (statement in statements)
				addStatement(state, statement);
	}

	static function addStatement(state:Array<Int>, statement:HxStmt):Void {
		switch (statement) {
			case SBlock(statements, position):
				addString(state, "stmt-block");
				addStatements(state, statements);
				addPosition(state, position);
			case SVar(name, typeHint, initializer, position, metadata):
				addString(state, "stmt-var");
				addString(state, name);
				addString(state, typeHint);
				final safeMetadata = metadata == null ? [] : metadata;
				addInt(state, safeMetadata.length);
				for (entry in safeMetadata)
					addString(state, entry);
				addInt(state, initializer == null ? 0 : 1);
				if (initializer != null)
					addExpression(state, initializer);
				addPosition(state, position);
			case SIf(condition, whenTrue, whenFalse, position):
				addString(state, "stmt-if");
				addExpression(state, condition);
				addStatement(state, whenTrue);
				addInt(state, whenFalse == null ? 0 : 1);
				if (whenFalse != null)
					addStatement(state, whenFalse);
				addPosition(state, position);
			case SForIn(name, iterable, body, position):
				addString(state, "stmt-for-in");
				addString(state, name);
				addExpression(state, iterable);
				addStatement(state, body);
				addPosition(state, position);
			case SForKeyValue(keyName, valueName, iterable, body, position):
				addString(state, "stmt-for-key-value");
				addString(state, keyName);
				addString(state, valueName);
				addExpression(state, iterable);
				addStatement(state, body);
				addPosition(state, position);
			case SWhile(condition, body, position):
				addString(state, "stmt-while");
				addExpression(state, condition);
				addStatement(state, body);
				addPosition(state, position);
			case SDoWhile(body, condition, position):
				addString(state, "stmt-do-while");
				addStatement(state, body);
				addExpression(state, condition);
				addPosition(state, position);
			case SSwitch(scrutinee, patterns, bodies, position):
				addString(state, "stmt-switch");
				addExpression(state, scrutinee);
				addPatterns(state, patterns);
				addStatements(state, bodies);
				addPosition(state, position);
			case STry(body, catches, position):
				addString(state, "stmt-try");
				addStatement(state, body);
				addInt(state, catches == null ? -1 : catches.length);
				if (catches != null)
					for (entry in catches) {
						addString(state, entry.name);
						addString(state, entry.typeHint);
						addStatement(state, entry.body);
					}
				addPosition(state, position);
			case SBreak(position):
				addString(state, "stmt-break");
				addPosition(state, position);
			case SContinue(position):
				addString(state, "stmt-continue");
				addPosition(state, position);
			case SThrow(expression, position):
				addString(state, "stmt-throw");
				addExpression(state, expression);
				addPosition(state, position);
			case SReturnVoid(position):
				addString(state, "stmt-return-void");
				addPosition(state, position);
			case SReturn(expression, position):
				addString(state, "stmt-return");
				addExpression(state, expression);
				addPosition(state, position);
			case SExpr(expression, position):
				addString(state, "stmt-expression");
				addExpression(state, expression);
				addPosition(state, position);
		}
	}

	public static function forStatements(statements:Array<HxStmt>):String {
		final state = [17, 0];
		addStatements(state, statements);
		return state[1] + ":" + state[0];
	}

	/** Fingerprint one parsed expression for enclosing immutable-artifact checks. **/
	public static function forExpression(expression:Null<HxExpr>):String {
		final state = [17, 0];
		if (expression == null)
			addInt(state, -1);
		else
			addExpression(state, expression);
		return state[1] + ":" + state[0];
	}
}
