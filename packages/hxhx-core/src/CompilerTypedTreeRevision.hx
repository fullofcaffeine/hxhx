import TypedExpr.TypedExprTag;
import TypedStmt.TypedStmtTag;

/**
	Builds exact in-memory revisions for sealed target-neutral typed trees.

	This semantic serializer is shared by module invalidation and strict backend
	projections. It remains independent of `TypedModule` and `TypedBodySource`, so
	the revision owner does not depend on the source-shaped adapter it identifies.
	These values are process-local facts, not persistent cryptographic digests.
**/
class CompilerTypedTreeRevision {
	/**
		Identify one sealed typed function body together with the environment needed
		to interpret it.

		The parsed-body fingerprint is deliberately excluded: that fingerprint
		detects stale source mutation, while this revision identifies the semantic
		tree consumed by backends.
	**/
	public static function functionBody(typedFunction:TypedFunction):String {
		if (typedFunction == null)
			throw "cannot revise a null typed function body";
		final facts = new Array<Null<String>>();
		facts.push("typed-function-body-v2");
		facts.push(typedFunction.getStableIdentity());
		final environment = typedFunction.getEnvironment();
		final parameters = environment == null ? [] : environment.getParams();
		facts.push(Std.string(parameters.length));
		for (parameter in parameters)
			facts.push(parameter == null ? null : parameter.toBinding().getCanonicalIdentity());
		final statements = typedFunction.getBody().getStatements();
		facts.push(Std.string(statements.length));
		for (statement in statements)
			addStatement(facts, statement);
		return CompilerCacheIdentity.encode(facts);
	}

	/** Identify one typed expression under the exact declaration that owns it. **/
	public static function expression(ownerIdentity:String, expression:TypedExpr):String {
		if (ownerIdentity == null || ownerIdentity.length == 0)
			throw "typed expression revision requires an owner identity";
		final facts = new Array<Null<String>>();
		facts.push("typed-expression-v2");
		facts.push(ownerIdentity);
		addExpression(facts, expression);
		return CompilerCacheIdentity.encode(facts);
	}

	static function addStatement(out:Array<Null<String>>, statement:TypedStmt):Void {
		if (statement == null) {
			out.push("null-statement");
			return;
		}
		out.push("statement:" + statementTagName(statement.getTag()));
		addStrings(out, statement.getNames());
		addStrings(out, statement.getCatchNames());
		addStrings(out, statement.getCatchTypeHints());
		addStrings(out, statement.getMetadata());
		addLocalBindings(out, statement.getLocalBindings());
		final patterns = statement.getPatterns();
		out.push(Std.string(patterns.length));
		for (pattern in patterns)
			addPattern(out, pattern);
		final expressions = statement.getExpressions();
		out.push(Std.string(expressions.length));
		for (expression in expressions)
			addExpression(out, expression);
		final statements = statement.getStatements();
		out.push(Std.string(statements.length));
		for (child in statements)
			addStatement(out, child);
	}

	static function addExpression(out:Array<Null<String>>, expression:TypedExpr):Void {
		if (expression == null) {
			out.push("null-expression");
			return;
		}
		out.push("expression:" + expressionTagName(expression.getTag()));
		out.push(expression.getType().getSemanticKey());
		addStrings(out, expression.getTexts());
		out.push(expression.getBoolValue() ? "true" : "false");
		out.push(Std.string(expression.getIntValue()));
		out.push(Std.string(expression.getFloatValue()));
		final declaration = expression.getDeclaration();
		out.push(declaration == null ? null : declaration.getIdentity().getCanonicalKey());
		final fieldInfo = expression.getFieldInfo();
		out.push(fieldInfo == null ? null : fieldInfo.getCanonicalKey());
		addLocalBindings(out, expression.getLocalBindings());
		final extensionProvider = expression.getExtensionProvider();
		out.push(extensionProvider == null ? null : extensionProvider.getCanonicalName());
		out.push(unaryOperatorName(expression.getUnaryOperator()));
		out.push(unaryFixityName(expression.getUnaryFixity()));
		out.push(opaqueKindName(expression.getOpaqueKind()));
		final patterns = expression.getPatterns();
		out.push(Std.string(patterns.length));
		for (pattern in patterns)
			addPattern(out, pattern);
		final expressions = expression.getExpressions();
		out.push(Std.string(expressions.length));
		for (child in expressions)
			addExpression(out, child);
	}

	static function addLocalBindings(out:Array<Null<String>>, bindings:Array<TyLocalBinding>):Void {
		out.push(bindings == null ? "-1" : Std.string(bindings.length));
		if (bindings != null)
			for (binding in bindings)
				out.push(binding == null ? null : binding.getCanonicalIdentity());
	}

	static function addPattern(out:Array<Null<String>>, pattern:HxSwitchPattern):Void {
		switch (pattern) {
			case PNull:
				out.push("pattern:null");
			case PWildcard:
				out.push("pattern:wildcard");
			case PBool(value):
				out.push(value ? "pattern:bool:true" : "pattern:bool:false");
			case PString(value):
				out.push("pattern:string");
				out.push(value);
			case PInt(value):
				out.push("pattern:int");
				out.push(Std.string(value));
			case PEnumValue(name):
				out.push("pattern:enum-value");
				out.push(name);
			case PEnumExtract(name, arguments):
				out.push("pattern:enum-extract");
				out.push(name);
				out.push(Std.string(arguments.length));
				for (argument in arguments)
					addPattern(out, argument);
			case PObject(fieldNames, fieldPatterns):
				out.push("pattern:object");
				addStrings(out, fieldNames);
				out.push(Std.string(fieldPatterns.length));
				for (fieldPattern in fieldPatterns)
					addPattern(out, fieldPattern);
			case PCapture(name, inner):
				out.push("pattern:capture");
				out.push(name);
				addPattern(out, inner);
			case PArray(items):
				out.push("pattern:array");
				out.push(Std.string(items.length));
				for (item in items)
					addPattern(out, item);
			case PExtractor(extractorText, resultPattern):
				out.push("pattern:extractor");
				out.push(extractorText);
				addPattern(out, resultPattern);
			case PLengthGuard(inner, bindingName, length):
				out.push("pattern:length-guard");
				out.push(bindingName);
				out.push(Std.string(length));
				addPattern(out, inner);
			case PStartsWithGuard(inner, bindingName, prefix):
				out.push("pattern:starts-with-guard");
				out.push(bindingName);
				out.push(prefix);
				addPattern(out, inner);
			case PIntEqualsGuard(inner, bindingName, value):
				out.push("pattern:int-equals-guard");
				out.push(bindingName);
				out.push(Std.string(value));
				addPattern(out, inner);
			case PIntCompareGuard(inner, bindingName, op, value):
				out.push("pattern:int-compare-guard");
				out.push(bindingName);
				out.push(op);
				out.push(Std.string(value));
				addPattern(out, inner);
			case PParsedIntSwitchGuard(inner, bindingName, multiplier, matchValue):
				out.push("pattern:parsed-int-switch-guard");
				out.push(bindingName);
				out.push(Std.string(multiplier));
				out.push(Std.string(matchValue));
				addPattern(out, inner);
			case PUnsupportedGuard(inner):
				out.push("pattern:unsupported-guard");
				addPattern(out, inner);
			case PBind(name):
				out.push("pattern:bind");
				out.push(name);
			case POr(patterns):
				out.push("pattern:or");
				out.push(Std.string(patterns.length));
				for (child in patterns)
					addPattern(out, child);
		}
	}

	static function statementTagName(tag:TypedStmtTag):String {
		return switch (tag) {
			case Block: "block";
			case Var: "var";
			case If: "if";
			case ForIn: "for-in";
			case ForKeyValue: "for-key-value";
			case While: "while";
			case DoWhile: "do-while";
			case Switch: "switch";
			case Try: "try";
			case Break: "break";
			case Continue: "continue";
			case Throw: "throw";
			case ReturnVoid: "return-void";
			case Return: "return";
			case Expression: "expression";
		};
	}

	static function expressionTagName(tag:TypedExprTag):String {
		return switch (tag) {
			case NullValue: "null";
			case BoolValue: "bool";
			case StringValue: "string";
			case IntValue: "int";
			case FloatValue: "float";
			case EnumValue: "enum";
			case ThisValue: "this";
			case SuperValue: "super";
			case LocalRead: "local-read";
			case NameRead: "name-read";
			case FieldRead: "field-read";
			case NullSafeFieldRead: "null-safe-field-read";
			case Call: "call";
			case MacroExpr: "macro-expr";
			case MacroType: "macro-type";
			case Lambda: "lambda";
			case SwitchExpr: "switch";
			case NewValue: "new";
			case Unary: "unary";
			case Binary: "binary";
			case Assign: "assign";
			case CompoundAssign: "compound-assign";
			case Ternary: "ternary";
			case Anonymous: "anonymous";
			case ArrayComprehension: "array-comprehension";
			case ArrayDecl: "array";
			case ArrayAccess: "array-access";
			case Range: "range";
			case Cast: "cast";
			case Untyped: "untyped";
			case Opaque: "opaque";
			case Block: "block";
			case Temporary: "temporary";
			case ReturnExpr: "return";
			case VariableDeclarations: "variable-declarations";
			case VariableDeclaration: "variable-declaration";
			case WhileExpr: "while";
			case BreakExpr: "break";
			case ContinueExpr: "continue";
		};
	}

	static function unaryOperatorName(unaryOperator:Null<HxUnaryOperator>):Null<String> {
		return switch (unaryOperator) {
			case null: null;
			case Increment: "increment";
			case Decrement: "decrement";
			case Negate: "negate";
			case LogicalNot: "logical-not";
			case BitwiseNot: "bitwise-not";
		};
	}

	static function unaryFixityName(fixity:Null<HxUnaryFixity>):Null<String> {
		return switch (fixity) {
			case null: null;
			case Prefix: "prefix";
			case Postfix: "postfix";
		};
	}

	static function opaqueKindName(kind:Null<TypedOpaqueExprKind>):Null<String> {
		return switch (kind) {
			case null: null;
			case TryCatch: "try-catch";
			case Switch: "switch";
			case Unsupported: "unsupported";
		};
	}

	static function addStrings(out:Array<Null<String>>, values:Array<String>):Void {
		out.push(values == null ? "-1" : Std.string(values.length));
		if (values != null)
			for (value in values)
				out.push(value);
	}
}
