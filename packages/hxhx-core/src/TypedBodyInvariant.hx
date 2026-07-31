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
		for (child in expression.getExpressions())
			assertExpr(child, owner);
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
		if (expression.getTag() == Lambda && localBindings.length > 0)
			assertBindingNames(localBindings, expression.getTexts(), owner);
		if (expression.getTag() == Temporary) {
			if (expression.getTexts().length != 2 || expression.getExpressions().length != 1)
				throw "typed temporary has an invalid structural payload in " + owner;
		}
		if (expression.getTag() == ReturnExpr && expression.getExpressions().length > 1)
			throw "typed return expression has more than one value in " + owner;
		if (expression.getTag() == WhileExpr && expression.getExpressions().length < 1)
			throw "typed while expression is missing its condition in " + owner;
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
