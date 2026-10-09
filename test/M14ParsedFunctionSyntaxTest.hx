/** The new function parser retains source distinctions before any result inference. */
class M14ParsedFunctionSyntaxTest {
	static function statements(source:String):Array<HxStmt> {
		return switch (HxFunctionSyntaxParser.parse(source).body) {
			case Statements(body): body;
			case _: throw "ordinary function did not retain statements";
		};
	}

	static function main():Void {
		if (statements("function local() {}").length != 0)
			throw "empty body acquired a synthetic expression";
		switch (statements("function local() { return; }")) {
			case [SReturnVoid(_)]:
			case _:
				throw "bare return lost its statement kind";
		}
		switch (statements("function local() { return null; }")) {
			case [SReturn(ENull, _)]:
			case _:
				throw "explicit null return lost its value";
		}
		switch (statements("function local() { ping(); return null; }")) {
			case [SExpr(ECall(EIdent("ping"), []), _), SReturn(ENull, _)]:
			case _:
				throw "effect and explicit null return were reduced";
		}
		switch (statements("function local() { ping(); }")) {
			case [SExpr(ECall(EIdent("ping"), []), _)]:
			case _:
				throw "fallthrough acquired a synthetic return";
		}
		final annotated = HxFunctionSyntaxParser.parse("function local(value:Int) { return value; }");
		final argument = annotated.arguments[0];
		if (!argument.hasTypeAnnotation || HxFunctionArg.getTypeHint(argument.declaration) != "Int")
			throw "parameter annotation was erased";
		if (annotated.resultTypeHint != null || annotated.name != "local")
			throw "missing result annotation or declared name changed";
		final unannotated = HxFunctionSyntaxParser.parse("function(value) { return value; }");
		if (unannotated.name != null || unannotated.arguments[0].hasTypeAnnotation)
			throw "anonymous function invented source facts";
		final explicit = HxFunctionSyntaxParser.parse("function(value:Dynamic):Void { return; }");
		if (!explicit.arguments[0].hasTypeAnnotation || explicit.resultTypeHint != "Void")
			throw "explicit annotations became absent";
		checkSignatureFacts();
		checkArrows();
		switch (statements("function local():Int return 7;")) {
			case [SReturn(EInt(7), _)]:
			case _:
				throw "short return body lost its statement";
		}
		for (source in [
			"function f() {",
			"function f(value:) {}",
			"function f(value=) {}",
			"function f(): {}",
			"function f() {} trailing",
			"() ->",
			"() -> ;",
			"(value:Int) value",
			"() -> {",
			"value -> value trailing"
		]) {
			var rejected = false;
			try
				HxFunctionSyntaxParser.parse(source)
			catch (_:HxParseError)
				rejected = true;
			if (!rejected)
				throw "function parser accepted malformed source: " + source;
		}
		Sys.println("PARSED_FUNCTION_SYNTAX:PASS");
	}

	/** Arrow form preserves implicit results without turning explicit returns into null. */
	static function checkArrows():Void {
		final short = HxFunctionSyntaxParser.parse("value -> value");
		if (short.form != Arrow || short.name != null || short.arguments[0].hasTypeAnnotation)
			throw "short arrow invented signature facts";
		switch (short.body) {
			case ImplicitResult(EIdent("value")):
			case _:
				throw "short arrow lost its implicit result";
		}
		final block = HxFunctionSyntaxParser.parse("() -> { ping(); 7; }");
		if (block.form != Arrow || block.endPos.getIndex() != "() -> { ping(); 7; }".length)
			throw "arrow block became an ordinary function";
		switch (block.body) {
			case Statements([SExpr(ECall(EIdent("ping"), []), _), SExpr(EInt(7), _)]):
			case _:
				throw "arrow block lost its statements or tail expression";
		}
		switch (HxFunctionSyntaxParser.parse("() -> { null; }").body) {
			case Statements([SExpr(ENull, _)]):
			case _:
				throw "implicit null result became an explicit return";
		}
		final marked = HxFunctionSyntaxParser.parse("@:keep value -> value");
		if (marked.pos.getIndex() != 0 || marked.arguments[0].pos.getIndex() != 7)
			throw "arrow metadata changed the parameter source position";
		for (source in ["() -> {}", "() -> { return; }", "() -> { return null; }"]) {
			final arrow = HxFunctionSyntaxParser.parse(source);
			if (arrow.form != Arrow)
				throw "arrow block form changed";
			switch [source, arrow.body] {
				case ["() -> {}", Statements([])] | ["() -> { return; }", Statements([SReturnVoid(_)])] |
					["() -> { return null; }", Statements([SReturn(ENull, _)])]:
				case _:
					throw "arrow completion forms were collapsed";
			}
		}
		final annotated = HxFunctionSyntaxParser.parse("(value:Int, count:Int = 7) -> { count = 9; value + count; }");
		if (!annotated.arguments[0].hasTypeAnnotation || HxFunctionArg.getTypeHint(annotated.arguments[0].declaration) != "Int")
			throw "arrow parameter type disappeared";
		switch (HxFunctionArg.getDefaultValue(annotated.arguments[1].declaration)) {
			case Default(EInt(7)):
			case _:
				throw "arrow default was erased";
		}
		final callback = HxFunctionSyntaxParser.parse("@:keep() (callback:(Int, Int)->Int) -> callback(1, 2)");
		if (callback.metadata[0] != "@:keep()" || HxFunctionArg.getTypeHint(callback.arguments[0].declaration) != "(Int,Int)->Int")
			throw "arrow metadata or nested function annotation was lost: "
				+ callback.metadata[0]
				+ " / "
				+ HxFunctionArg.getTypeHint(callback.arguments[0].declaration);
		switch (annotated.body) {
			case Statements([
				SExpr(EBinop("=", EIdent("count"), EInt(9)), _),
				SExpr(EBinop("+", EIdent("value"), EIdent("count")), _)
			]):
			case _:
				throw "arrow default replaced a parameter read";
		}
		switch (HxFunctionSyntaxParser.parse("() -> {value: 7}").body) {
			case ImplicitResult(EAnon(["value"], [EInt(7)])):
			case _:
				throw "arrow object result became a statement block";
		}
	}

	/** Generic constraints, defaults, and marker spelling remain source facts. */
	static function checkSignatureFacts():Void {
		final source = "@:keep function choose<T:{var length:Int;}>(@:tag ?value:T, count:Int = 3 + 4, ...tail:Int):Void { count = 9; ping(count); }  ";
		final parsed = HxFunctionSyntaxParser.parse(source);
		if (parsed.form != Ordinary || parsed.origin != Authored || parsed.metadata[0] != "@:keep")
			throw "function form, origin, or metadata changed";
		if (parsed.pos.getIndex() != 0 || parsed.endPos.getIndex() != source.lastIndexOf("}") + 1)
			throw "function source range changed";
		if (parsed.typeParameters.length != 1 || parsed.typeParameters[0].name != "T")
			throw "generic binder was skipped";
		switch (parsed.typeParameters[0].constraints[0].getKind()) {
			case AnonymousType(fields, []) if (fields.length == 1 && fields[0].name == "length"):
			case _:
				throw "generic constraint lost its structure";
		}
		final optional = parsed.arguments[0];
		if (!HxFunctionArg.getIsOptional(optional.declaration)
			|| HxFunctionArg.getMetadata(optional.declaration)[0] != "@:tag"
			|| optional.pos.getIndex() != source.indexOf("@:tag"))
			throw "optional argument source facts changed";
		final defaulted = parsed.arguments[1].declaration;
		if (HxFunctionArg.getIsOptional(defaulted) || HxFunctionArg.getDefaultValueText(defaulted) != "3 + 4")
			throw "default presence was confused with the written optional marker";
		switch (HxFunctionArg.getDefaultValue(defaulted)) {
			case Default(EBinop("+", EInt(3), EInt(4))):
			case _:
				throw "default expression was replaced or flattened";
		}
		final rest = parsed.arguments[2].declaration;
		if (!HxFunctionArg.getIsRest(rest) || HxFunctionArg.getIsOptional(rest) || HxFunctionArg.getTypeHint(rest) != "Int")
			throw "rest syntax was replaced by a runtime array parameter";
		switch (parsed.body) {
			case Statements([
				SExpr(EBinop("=", EIdent("count"), EInt(9)), _),
				SExpr(ECall(EIdent("ping"), [EIdent("count")]), _)
			]):
			case _:
				throw "default expression was substituted into a later parameter read";
		}
	}
}
