import TypedExpr.TypedExprTag;

/**
	Structural invariant checks for the typed-body boundary.

	The traversal visits every child, validates exact-call identities, and rejects
	opaque raw payloads that could hide an operator or mutation. This checker is
	run when a `TypedModule` is sealed and again at backend dispatch.
**/
class TypedBodyInvariant {
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
		}
		if (expression.getTag() == Temporary) {
			if (expression.getTexts().length != 2 || expression.getExpressions().length != 1)
				throw "typed temporary has an invalid structural payload in " + owner;
		}
		if (expression.getTag() == ReturnExpr && expression.getExpressions().length > 1)
			throw "typed return expression has more than one value in " + owner;
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
	}

	public static function assertFunction(typedFunction:TypedFunction):Void {
		final owner = typedFunction.getStableIdentity();
		for (statement in typedFunction.getBody().getStatements())
			assertStmt(statement, owner);
	}

	public static function assertClasses(classes:Array<TypedClass>):Void {
		if (classes == null)
			return;
		for (typedClass in classes)
			for (typedFunction in typedClass.getFunctions())
				assertFunction(typedFunction);
	}
}
