import haxe.ds.StringMap;
import TypedExpr.TypedExprTag;

/**
	Structural invariant checks for the typed-body boundary.

	The traversal visits every child, validates exact-call identities, and rejects
	opaque raw payloads that could hide an operator or mutation. This checker is
	run when a `TypedModule` is sealed and again at backend dispatch.
**/
class TypedBodyInvariant {
	static function assertBinding(binding:TyLocalBinding, owner:String):Void {
		if (binding == null || binding.getIdentity() == null || binding.getIdentity().getCanonicalKey().length == 0)
			throw "typed local binding has an empty identity in " + owner;
		if (binding.getType() == null)
			throw "typed local binding has no semantic type in " + owner;
	}

	static function assertBindingNames(bindings:Array<TyLocalBinding>, names:Array<String>, owner:String):Void {
		if (bindings.length != names.length)
			throw "typed local binding/name count mismatch in " + owner;
		for (index in 0...bindings.length) {
			assertBinding(bindings[index], owner);
			if (bindings[index].getSourceName() != names[index])
				throw "typed local binding/name mismatch in " + owner;
		}
	}

	static function scrubQuotedAndCommentText(raw:String):String {
		if (raw == null || raw.length == 0)
			return "";
		final out = new StringBuf();
		var index = 0;
		var quote = "";
		var escaped = false;
		var lineComment = false;
		var blockComment = false;
		while (index < raw.length) {
			final current = raw.charAt(index);
			final next = index + 1 < raw.length ? raw.charAt(index + 1) : "";
			if (lineComment) {
				if (current == "\n") {
					lineComment = false;
					out.add("\n");
				}
				index++;
				continue;
			}
			if (blockComment) {
				if (current == "*" && next == "/") {
					blockComment = false;
					index += 2;
				} else {
					index++;
				}
				continue;
			}
			if (quote.length > 0) {
				if (escaped) {
					escaped = false;
				} else if (current == "\\") {
					escaped = true;
				} else if (current == quote) {
					quote = "";
				}
				index++;
				continue;
			}
			if (current == "/" && next == "/") {
				lineComment = true;
				index += 2;
				continue;
			}
			if (current == "/" && next == "*") {
				blockComment = true;
				index += 2;
				continue;
			}
			if (current == "\"" || current == "'") {
				quote = current;
				index++;
				continue;
			}
			out.add(current);
			index++;
		}
		return out.toString();
	}

	static function opaqueContainsSemanticSyntax(raw:String):Bool {
		final clean = scrubQuotedAndCommentText(raw);
		for (token in ["++", "--", "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "<<=", ">>=", ">>>="])
			if (clean.indexOf(token) >= 0)
				return true;
		for (op in ["+", "-", "*", "/", "%", "!", "~", "=", "<", ">", "&", "|", "^", "["])
			if (clean.indexOf(op) >= 0)
				return true;
		return false;
	}

	static function assertExpr(expression:TypedExpr, owner:String):Void {
		if (expression == null)
			throw "typed body contains a null expression in " + owner;
		expression.assertArgumentBinding();
		if (expression.getTag() == TargetScope)
			TypedTargetScope.kind(expression);
		if (expression.getTag() == FeatureDefinition || expression.getTag() == FeatureSelection) {
			final children = expression.getExpressions();
			final definition = expression.getTag() == FeatureDefinition;
			if (expression.getTexts().length != 1
				|| expression.getTexts()[0] == null
				|| children.length < 1
				|| children.length > (definition ? 1 : 2)
				|| expression.getDeclaration() != null
				|| expression.getFieldInfo() != null
				|| expression.getLocalBindings().length != 0
				|| expression.getControlTarget() != null)
				throw "feature intrinsic has invalid typed ownership or operands in " + owner;
			if (definition && expression.getType().getSemanticKey() != children[0].getType().getSemanticKey())
				throw "feature definition changed its operand type in " + owner;
			if (!definition && !expression.getType().isDynamic())
				throw "unselected feature expression lost its untyped boundary in " + owner;
		}
		// Source try handlers are lexical regions. Their selected runtime uses
		// stay on the try node alongside the ordered catch declarations, rather
		// than requiring the old synthetic handler lambda representation.
		if (expression.getCatchUses().length > 0
			&& expression.getTag() != Lambda
			&& expression.getTag() != SourceTry
			&& expression.getTag() != ControlTry)
			throw "implicit catch uses require a try region or handler lambda in " + owner;
		assertCatchUses(expression.getCatchUses(), expression.getLocalBindings(), owner);
		final member = expression.getDeclaration();
		if (member != null && expression.getTag() != Call && expression.getTag() != NewValue && expression.getTag() != TargetScope) {
			if ((expression.getTag() != NameRead && expression.getTag() != FieldRead)
				|| (!member.getIsStatic() && (expression.getTag() != FieldRead || expression.getRequiresOwnerQualification()))
				|| member.getIsEnumConstructor()
				|| expression.getFieldInfo() != null
				|| expression.getTexts().length != 1
				|| !expression.getType().isFunction()
				|| expression.getExpressions().length != (expression.getTag() == NameRead ? 0 : 1))
				throw "typed method value has an invalid selected declaration in "
					+ owner
					+ ": "
					+ member.getIdentity().getCanonicalKey()
					+ " ("
					+ expression.getTag()
					+ ", "
					+ expression.getType().getSemanticKey()
					+ ")";
		}
		final runtimeTarget = expression.getRuntimeTypeTarget();
		switch (expression.getTag()) {
			case RuntimeTypeValue | RuntimeTypeTest:
				if (runtimeTarget == null)
					throw "runtime type expression has no exact target in " + owner;
				final isTest = expression.getTag() == RuntimeTypeTest;
				final expectedType = isTest ? TyType.fromHintText("Bool") : runtimeTarget.getValueType();
				if (expression.getType().getSemanticKey() != expectedType.getSemanticKey()
					|| expression.getExpressions().length != (isTest ? 1 : 0)
					|| expression.getTexts().length != 0)
					throw "runtime type expression has an invalid structural shape in " + owner;
			case _:
				if (runtimeTarget != null)
					throw "ordinary expression carries a runtime type target in " + owner;
		}
		for (child in expression.getExpressions())
			assertExpr(child, owner);
		if (expression.getTag() == ArrayAppend) {
			final children = expression.getExpressions();
			if (children.length != 2 || !expression.getType().isVoid())
				throw "array append requires two operands and a Void result in " + owner;
			final type = children[0].getType();
			final identity = type.getNominalIdentity();
			final path = identity == null ? type.getUnresolvedPath() : identity.getCanonicalName();
			final arguments = type.getTypeArguments();
			if (path != "Array" || arguments.length != 1 || arguments[0].getSemanticKey() != children[1].getType().getSemanticKey())
				throw "array append lost its selected element type in " + owner;
		}
		if (expression.getTag() == MapInsert) {
			final children = expression.getExpressions();
			if (children.length != 3 || !expression.getType().isVoid())
				throw "map insertion requires three operands and a Void result in " + owner;
			final type = children[0].getType();
			final identity = type.getNominalIdentity();
			final arguments = type.getTypeArguments();
			if (identity == null
				|| identity.getCanonicalName() != "haxe.ds.Map"
				|| arguments.length != 2
				|| arguments[0].getSemanticKey() != children[1].getType().getSemanticKey()
				|| arguments[1].getSemanticKey() != children[2].getType().getSemanticKey())
				throw "map insertion lost its selected key or value type in " + owner;
		}
		if (expression.getTag() == Parenthesized) {
			final children = expression.getExpressions();
			if (children.length != 1
				|| expression.getTexts().length != 0
				|| expression.getLocalBindings().length != 0
				|| expression.getControlTarget() != null
				|| children[0].getType().getSemanticKey() != expression.getType().getSemanticKey())
				throw "parenthesized expression changed its child type or acquired semantic ownership in " + owner;
		}
		if (expression.getTag() == NewValue && expression.getDeclaration() != null) {
			final constructor = expression.getDeclaration();
			final constructedOwner = expression.getType().getNominalIdentity();
			final application = expression.getConstructorApplication();
			if (constructedOwner == null
				|| (application == null ? !constructor.getOwner()
					.equals(constructedOwner) : !constructor.getOwner().equals(application.getOwnerType().getNominalIdentity()))
				|| constructor.getIsStatic()
				|| constructor.getSignature().getName() != "new")
				throw "typed construction carries a foreign or non-constructor declaration in " + owner;
			if (application != null)
				application.assertResult(expression.getType());
		}
		if (expression.getTag() == Call) {
			final declaration = expression.getDeclaration();
			if (declaration != null && declaration.getIdentity().getCanonicalKey().length == 0)
				throw "typed call contains an empty declaration identity in " + owner;
			final extensionProvider = expression.getExtensionProvider();
			if (extensionProvider != null && (declaration == null || !declaration.getIsStatic()))
				throw "typed extension call must carry an exact static declaration in " + owner;
		} else if (expression.getExtensionProvider() != null) {
			throw "non-call typed expression carries an extension provider in " + owner;
		}
		final localBindings = expression.getLocalBindings();
		final sourceCatches = expression.getSourceCatches();
		if (expression.getTag() == SourceTry || expression.getTag() == ControlTry) {
			if (sourceCatches.length == 0
				|| expression.getExpressions().length != sourceCatches.length + 1
				|| expression.getControlTarget() != null)
				throw "typed source try must retain ordered lexical handlers in " + owner;
			if (localBindings.length > 0) {
				assertBindingNames(localBindings, [for (entry in sourceCatches) entry.getName()], owner);
				for (binding in localBindings)
					if (binding.getKind() != CatchVariable)
						throw "typed source catch requires a catch declaration in " + owner;
			}
			if (expression.getTag() == ControlTry && localBindings.length != sourceCatches.length)
				throw "lowered try requires every exact catch declaration in " + owner;
			if (expression.getTag() == ControlTry)
				for (child in expression.getExpressions())
					if (child.getTag() != ControlRegion || child.getControlTarget() != null)
						throw "lowered try requires lexical body regions in " + owner;
		} else if (sourceCatches.length != 0) {
			throw "ordinary typed expression cannot carry source catch facts in " + owner;
		}
		if (expression.getTag() == FixedRange) {
			final bounds = expression.getExpressions();
			if (bounds.length != 2)
				throw "fixed range requires two bound snapshots in " + owner;
			for (bound in bounds) {
				final bindings = bound.getLocalBindings();
				if (bound.getTag() != LocalRead || bindings.length != 1 || !bindings[0].getIdentity().isCompilerTemporary())
					throw "fixed range must read compiler-owned bound snapshots in " + owner;
			}
		}
		for (binding in localBindings)
			assertBinding(binding, owner);
		if (expression.getTag() == LocalRead) {
			if (localBindings.length != 1)
				throw "typed local read must carry exactly one binding in " + owner;
			assertBindingNames(localBindings, [expression.getTexts()[0]], owner);
		}
		if (expression.getTag() == Temporary) {
			if (localBindings.length != 1)
				throw "typed temporary must carry exactly one binding in " + owner;
			assertBindingNames(localBindings, [expression.getTexts()[0]], owner);
		}
		if ((expression.getTag() == VariableDeclaration || expression.getTag() == ArrayComprehension) && localBindings.length > 0)
			assertBindingNames(localBindings, [expression.getTexts()[0]], owner);
		if ((expression.getTag() == Lambda || expression.getTag() == SourceFunction) && localBindings.length > 0)
			assertBindingNames(localBindings, expression.getTexts(), owner);
		if (expression.getTag() == Temporary) {
			if (expression.getTexts().length != 2 || expression.getExpressions().length != 1)
				throw "typed temporary has an invalid structural payload in " + owner;
		}
		if (expression.getTag() == ReturnExpr && expression.getExpressions().length > 1)
			throw "typed return expression has more than one value in " + owner;
		if (expression.getTag() == SourceIf && expression.getExpressions().length != 2 && expression.getExpressions().length != 3)
			throw "typed source conditional must retain its condition and authored branches in " + owner;
		if (expression.getTag() == ControlSwitch) {
			final children = expression.getExpressions();
			if (children.length != expression.getPatterns().length + 1 || expression.getControlTarget() != null)
				throw "lowered switch must retain one scrutinee and its exact arm count in " + owner;
			for (index in 1...children.length)
				if (children[index].getTag() != ControlRegion || children[index].getControlTarget() != null)
					throw "lowered switch arm requires a lexical region in " + owner;
		}
		if (expression.getTag() == SourceFor || expression.getTag() == ControlFor) {
			HxForBinding.fromNames(expression.getTexts());
			if (expression.getExpressions().length != 2)
				throw "source for requires iterable and body children in " + owner;
			if (localBindings.length > 0)
				assertBindingNames(localBindings, expression.getTexts(), owner);
			if (expression.getTag() == ControlFor
				&& (expression.getControlTarget() == null
					|| localBindings.length == 0
					|| expression.getExpressions()[1].getTag() != ControlRegion
					|| expression.getExpressions()[1].getControlTarget() != null))
				throw "lowered for requires exact bindings, loop target, and lexical body in " + owner;
		}
		if (expression.getTag() == ControlBranch) {
			final children = expression.getExpressions();
			if (children.length != 2 && children.length != 3)
				throw "lowered conditional must retain its condition and branches in " + owner;
			for (index in 1...children.length)
				if (children[index].getTag() != ControlRegion || children[index].getControlTarget() != null)
					throw "lowered conditional branch must be a lexical region in " + owner;
		}
		if (expression.getTag() == ThrowExpr && (expression.getExpressions().length != 1 || !expression.getType().isNoNormalCompletion()))
			throw "typed throw must have one operand and abrupt completion in " + owner;
		if (expression.getTag() == WhileExpr && expression.getExpressions().length < 1)
			throw "typed while expression is missing its condition in " + owner;
		if (expression.getTag() == WhileExpr || expression.getTag() == ControlWhile)
			expression.getWhileKind();
		if (expression.getTag() == ControlWhile) {
			final children = expression.getExpressions();
			if (expression.getControlTarget() == null
				|| children.length != 2
				|| children[1].getTag() != ControlRegion
				|| children[1].getControlTarget() != null)
				throw "lowered while requires an exact loop and one lexical body in " + owner;
		}
		if (expression.getTag() == WhileExpr && !expression.getBoolValue() && expression.getExpressions().length != 2)
			throw "typed while expression without braces must have exactly one body expression in " + owner;
		if ((expression.getTag() == BreakExpr || expression.getTag() == ContinueExpr) && !expression.getType().isNoNormalCompletion())
			throw "typed loop-control expression must not claim to produce a runtime value in " + owner;
		if (expression.getTag() == VariableDeclarations)
			for (declaration in expression.getExpressions())
				if (declaration.getTag() != VariableDeclaration)
					throw "typed variable declaration list contains a non-declaration child in " + owner;
		if (expression.getTag() == VariableDeclaration && (expression.getTexts().length != 2 || expression.getExpressions().length > 1))
			throw "typed variable declaration has an invalid structural payload in " + owner;
		if (expression.getTag() == Opaque) {
			final texts = expression.getTexts();
			final raw = texts.length == 0 ? "" : texts[0];
			if (opaqueContainsSemanticSyntax(raw))
				throw "typed body opaque expression can hide operator or mutation semantics in " + owner + ": " + raw;
		}
	}

	static function assertStmt(statement:TypedStmt, owner:String):Void {
		if (statement == null)
			throw "typed body contains a null statement in " + owner;
		if (statement.getCatchUses().length > 0 && !statement.getTag().match(Try))
			throw "implicit catch uses require a try statement in " + owner;
		assertCatchUses(statement.getCatchUses(), statement.getLocalBindings(), owner);
		for (expression in statement.getExpressions())
			assertExpr(expression, owner);
		for (child in statement.getStatements())
			assertStmt(child, owner);
		final localBindings = statement.getLocalBindings();
		for (binding in localBindings)
			assertBinding(binding, owner);
		if (localBindings.length == 0)
			return;
		final tag = statement.getTag();
		if (tag == Var || tag == ForIn) {
			assertBindingNames(localBindings, [statement.getNames()[0]], owner);
		} else if (tag == ForKeyValue) {
			assertBindingNames(localBindings, statement.getNames(), owner);
		} else if (tag == Try) {
			assertBindingNames(localBindings, statement.getCatchNames(), owner);
		}
	}

	/** Catch dependency facts must belong to these exact declarations, in source order. */
	static function assertCatchUses(uses:Array<TypedCatchUse>, bindings:Array<TyLocalBinding>, owner:String):Void {
		if (uses.length == 0)
			return;
		if (uses.length != bindings.length)
			throw "implicit catch use count differs from its declarations in " + owner;
		for (index in 0...uses.length) {
			final use = uses[index];
			if (use == null
				|| !bindings[index].getKind().match(CatchVariable)
				|| use.binding.getCanonicalIdentity() != bindings[index].getCanonicalIdentity())
				throw "implicit catch use belongs to another binding in " + owner;
		}
	}

	public static function assertFunction(typedFunction:TypedFunction):Void {
		final owner = typedFunction.getStableIdentity();
		final declared = new StringMap<TyLocalBinding>();
		function register(binding:TyLocalBinding):Void {
			assertBinding(binding, owner);
			final key = binding.getIdentity().getCanonicalKey();
			final existing = declared.get(key);
			if (existing != null && existing.getCanonicalIdentity() != binding.getCanonicalIdentity())
				throw "typed local identity has conflicting facts in " + owner + ": " + key;
			declared.set(key, binding);
		}
		final environment = typedFunction.getEnvironment();
		if (environment != null)
			for (parameter in environment.getParams())
				register(parameter.toBinding());
		function collectExpression(expression:TypedExpr):Void {
			if (expression.getTag() != LocalRead)
				for (binding in expression.getLocalBindings())
					register(binding);
			for (child in expression.getExpressions())
				collectExpression(child);
		}
		function collectStatement(statement:TypedStmt):Void {
			for (binding in statement.getLocalBindings())
				register(binding);
			for (expression in statement.getExpressions())
				collectExpression(expression);
			for (child in statement.getStatements())
				collectStatement(child);
		}
		function assertExpressionReads(expression:TypedExpr):Void {
			if (expression.getTag() == LocalRead)
				for (binding in expression.getLocalBindings())
					if (!declared.exists(binding.getIdentity().getCanonicalKey()))
						throw "typed local read references an undeclared identity in " + owner + ": " + binding.getIdentity().getCanonicalKey();
			for (child in expression.getExpressions())
				assertExpressionReads(child);
		}
		function assertStatementReads(statement:TypedStmt):Void {
			for (expression in statement.getExpressions())
				assertExpressionReads(expression);
			for (child in statement.getStatements())
				assertStatementReads(child);
		}
		for (value in typedFunction.getDefaults()) {
			collectExpression(value.getExpression());
			assertExpr(value.getExpression(), owner);
			assertExpressionReads(value.getExpression());
		}
		for (statement in typedFunction.getBody().getStatements()) {
			collectStatement(statement);
			assertStmt(statement, owner);
		}
		for (statement in typedFunction.getBody().getStatements())
			assertStatementReads(statement);
	}

	public static function assertClasses(classes:Array<TypedClass>):Void {
		if (classes == null)
			return;
		for (typedClass in classes)
			for (typedFunction in typedClass.getFunctions())
				assertFunction(typedFunction);
	}
}
