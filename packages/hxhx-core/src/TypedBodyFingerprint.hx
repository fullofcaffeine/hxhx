/**
	Deterministic compact fingerprints and exact identities for parsed bodies.

	Both forms walk every parsed node and scalar explicitly. The compact hash
	retains existing revision diagnostics but can collide. Freshness checks and
	capture publication also compare the complete framed identity, including Float
	payload bits. These are process-local checks, not persistent cache keys.
**/
class TypedBodyFingerprint {
	/** Keep revision behavior outside the scalar enum module so HxExpr has no reverse dependency on this walker. */
	static function loweredControlName(kind:HxLoweredControlKind):String
		return switch kind {
			case FunctionBody: "function-body";
			case Initializer(hasValue): hasValue ? "initializer-value" : "initializer-abrupt";
			case Scope: "scope";
			case TargetScope(CsUnsafe): "cs-unsafe";
			case Return: "return";
			case Branch: "branch";
			case Throw: "throw";
			case While(kind): kind == DoWhile ? "do-while" : "while";
			case For(binding): CompilerCacheIdentity.encode(["for"].concat(HxForBinding.names(binding)));
			case Switch(patterns, exhaustive): "switch:" + (exhaustive == true ? "complete:" : "partial:") + forExpression(ESwitch(ENull, patterns, []));
			case Try(catches): CompilerCacheIdentity.encode(["try"].concat([for (entry in catches) entry.getCanonicalIdentity()]));
			case Break: "break";
			case Continue: "continue";
			case ArrayAppend: "array-append";
			case MapInsert: "map-insert";
		};

	static function addInt(state:BodyIdentityState, value:Int):Void
		state.addInt(value);

	static function addString(state:BodyIdentityState, value:Null<String>):Void
		state.addString(value);

	static function addPosition(state:BodyIdentityState, position:HxPos):Void {
		if (position == null) {
			addInt(state, -1);
			return;
		}
		addInt(state, position.getIndex());
		addInt(state, position.getLine());
		addInt(state, position.getColumn());
	}

	static function addStrings(state:BodyIdentityState, values:Array<String>):Void {
		addInt(state, values == null ? -1 : values.length);
		if (values != null)
			for (value in values)
				addString(state, value);
	}

	static function addUnaryOperator(state:BodyIdentityState, op:HxUnaryOperator):Void {
		addString(state, switch (op) {
			case Increment: "increment";
			case Decrement: "decrement";
			case Negate: "negate";
			case LogicalNot: "logical-not";
			case BitwiseNot: "bitwise-not";
		});
	}

	static function addUnaryFixity(state:BodyIdentityState, fixity:HxUnaryFixity):Void {
		addString(state, switch (fixity) {
			case Prefix: "prefix";
			case Postfix: "postfix";
		});
	}

	static function addPatterns(state:BodyIdentityState, patterns:Array<HxSwitchPattern>):Void {
		addInt(state, patterns == null ? -1 : patterns.length);
		if (patterns != null)
			for (pattern in patterns)
				addPattern(state, pattern);
	}

	static function addPattern(state:BodyIdentityState, pattern:HxSwitchPattern):Void {
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

	static function addExpressions(state:BodyIdentityState, expressions:Array<HxExpr>):Void {
		addInt(state, expressions == null ? -1 : expressions.length);
		if (expressions != null)
			for (expression in expressions)
				addExpression(state, expression);
	}

	static function addExpression(state:BodyIdentityState, expression:HxExpr):Void {
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
				if (state.isExact()) {
					// Metadata identity preserves the host value's payload, without choosing
					// target arithmetic or decimal formatting behavior.
					final bits = haxe.io.FPHelper.doubleToI64(value);
					addInt(state, bits.high);
					addInt(state, bits.low);
				} else {
					addString(state, Std.string(value));
				}
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
			case EDiscardThen(effect, continuation):
				addString(state, "expr-discard-then");
				addExpression(state, effect);
				addExpression(state, continuation);
			case ESourceGroup(expressions, position):
				addString(state, "expr-source-group");
				addPosition(state, position);
				addExpressions(state, expressions);
			case EParenthesized(inner, position):
				addString(state, "expr-parenthesized");
				addPosition(state, position);
				addExpression(state, inner);
			case EPrivateAccess(inner, position):
				addString(state, "expr-private-access");
				addPosition(state, position);
				addExpression(state, inner);
			case ESourceIf(condition, whenTrue, whenFalse, position):
				addString(state, "expr-source-if");
				addPosition(state, position);
				addExpression(state, condition);
				addExpression(state, whenTrue);
				addInt(state, whenFalse == null ? 0 : 1);
				if (whenFalse != null)
					addExpression(state, whenFalse);
			case EThrow(value, position):
				addString(state, "expr-throw");
				addPosition(state, position);
				addExpression(state, value);
			case ELoweredControl(kind, target, expressions, position):
				addString(state, "expr-lowered-control");
				addString(state, loweredControlName(kind));
				if (state.isExact())
					switch kind {
						case Switch(patterns): addPatterns(state, patterns);
						case _:
					}
				addString(state, target);
				addPosition(state, position);
				addExpressions(state, expressions);
			case ESourceFunction(facts, body, defaults, position):
				facts.assertDefaultCount(defaults.length);
				addString(state, "expr-source-function");
				addString(state, facts.getCanonicalIdentity());
				addPosition(state, position);
				addExpression(state, body);
				addExpressions(state, defaults);
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
			case EWhile(condition, body, bodyIsBlock, position, loopKind):
				addString(state, "expr-while");
				addInt(state, loopKind == DoWhile ? 1 : 0);
				addExpression(state, condition);
				addExpressions(state, body);
				addInt(state, bodyIsBlock ? 1 : 0);
				addPosition(state, position);
			case ESourceFor(binding, iterable, body, position):
				addString(state, "source-for");
				final names = HxForBinding.names(binding);
				addInt(state, names.length);
				for (name in names)
					addString(state, name);
				addExpression(state, iterable);
				addExpression(state, body);
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
			case ELambda(arguments, body, signature):
				addString(state, "expr-lambda");
				addString(state, signature == null ? null : signature.getCanonicalIdentity());
				addStrings(state, arguments);
				addExpression(state, body);
			case ESourceTry(catches, bodies, position):
				addString(state, "source-try");
				addPosition(state, position);
				addStrings(state, [for (entry in catches) entry.getCanonicalIdentity()]);
				addExpressions(state, bodies);
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

	static function addStatements(state:BodyIdentityState, statements:Array<HxStmt>):Void {
		addInt(state, statements == null ? -1 : statements.length);
		if (statements != null)
			for (statement in statements)
				addStatement(state, statement);
	}

	static function addStatement(state:BodyIdentityState, statement:HxStmt):Void {
		switch (statement) {
			case STargetScope(kind, body, position):
				addString(state, loweredControlName(TargetScope(kind)));
				addPosition(state, position);
				addStatement(state, body);
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
			case SSwitch(scrutinee, patterns, bodies, position, exhaustive):
				addString(state, "stmt-switch");
				addString(state, exhaustive == true ? "complete" : "partial");
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
		final state = new BodyIdentityState(false);
		addStatements(state, statements);
		return state.fingerprint();
	}

	/** Fingerprint one parsed expression for enclosing immutable-artifact checks. **/
	public static function forExpression(expression:Null<HxExpr>):String {
		final state = new BodyIdentityState(false);
		if (expression == null)
			addInt(state, -1);
		else
			addExpression(state, expression);
		return state.fingerprint();
	}

	/** Exact structure for source freshness and capture publication; compact hashes alone cannot authorize either boundary. */
	public static function exactStatements(statements:Array<HxStmt>):String {
		final state = new BodyIdentityState(true);
		addStatements(state, statements);
		return state.identity();
	}

	/** Exact structure detects nested edits before a backend consumes retained expression facts. */
	public static function exactExpression(expression:HxExpr):String {
		final state = new BodyIdentityState(true);
		addExpression(state, expression);
		return state.identity();
	}
}

/** One structural walk can retain exact typed tokens or preserve the existing compact lifecycle fingerprint. */
private class BodyIdentityState {
	var hash:Int = 17;
	var count:Int = 0;
	final tokens:Null<Array<Null<String>>>;

	public function new(exact:Bool) {
		tokens = exact ? ["source-body-exact-v1"] : null;
	}

	public function isExact():Bool
		return tokens != null;

	function hashInt(value:Int):Void {
		hash = hash * 31 + value;
		count++;
	}

	public function addInt(value:Int):Void {
		if (tokens != null) {
			tokens.push("int");
			tokens.push(Std.string(value));
		} else {
			hashInt(value);
		}
	}

	public function addString(value:Null<String>):Void {
		if (tokens != null) {
			tokens.push("string");
			tokens.push(value);
			return;
		}
		if (value == null) {
			hashInt(-1);
			return;
		}
		hashInt(value.length);
		for (index in 0...value.length)
			hashInt(value.charCodeAt(index));
	}

	public function fingerprint():String
		return count + ":" + hash;

	public function identity():String {
		if (tokens == null)
			throw "exact body identity was not requested";
		return CompilerCacheIdentity.encode(tokens);
	}
}
