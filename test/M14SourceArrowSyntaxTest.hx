/** Authored arrows retain syntax for macros and select callable context before body replay. */
class M14SourceArrowSyntaxTest {
	static function syntax():Void {
		for (source in [
			       "item -> item",         "(item:Int) -> { return item; }", "(item:Int = 5) -> item",
			"(?item:Int) -> item", "(items:haxe.Rest<Int>) -> items.length", "(fn:(Int)->Int) -> fn(7)"
		])
			switch HxParser.parseExprText(source) {
				case ESourceFunction(facts, _, defaults, _):
					if (facts.getKind() != Arrow || facts.getArguments().length != 1)
						throw "authored arrow lost its function kind or parameter";
					if (source.indexOf("= 5") >= 0) {
						final parameter = facts.getSignature().getParameters()[0];
						if (parameter.isOptional || !parameter.hasDefault || defaults.length != 1 || !defaults[0].match(EInt(5)))
							throw "default became an optional marker or parameter-read substitution";
					}
				case _:
					throw "authored arrow retained the transport-lambda path: " + source;
			}
		switch HxParser.parseExprText("() /* ) -> */ -> () -> { return 7; }") {
			case ESourceFunction(_, ESourceFunction(_, ESourceGroup([EReturn(EInt(7))], _), [], _), [], _):
			case _:
				throw "nested arrow or return body lost its source structure";
		}
		switch HxParser.parseExprText("(7 + 1)") {
			case EParenthesized(EBinop("+", EInt(7), EInt(1)), _):
			case _:
				throw "arrow lookahead consumed an ordinary parenthesized value";
		}
		var rejected = false;
		try {
			HxParser.parseCompleteExprText("(...items:Int) -> { return items.length; }");
		} catch (_:HxParseError) {
			rejected = true;
		}
		if (!rejected)
			throw "arrow parameter parser admitted unsupported upstream rest syntax";
	}

	static function typed(source:String):TypedModule {
		final path = "ArrowTypes.hx";
		final module = new ResolvedModule("ArrowTypes", path, ParserStage.parse("class ArrowTypes { static function main():Void { " + source + " } }", path));
		return TyperStage.typeResolvedModule(module, TyperIndex.build([module]), null, true);
	}

	static function typing():Void {
		for (source in [
			                  "var read:Int->Int = item -> item;", "var read = (item:Int) -> { if (item < 0) return 3; return item + 2; };",
			"var read:Void->(Int->Int) = () -> item -> item + 4;",                                               "var read = () -> { 7; };"
		]) {
			final module = typed(source);
			final value = module.getTypedClasses()[0].getFunctions()[0].getBody().getStatements()[0].getExpressions()[0];
			if (value.getTag() != SourceFunction || value.getControlTarget() == null || value.getType().hasUnknownComponent())
				throw "arrow lost its callable context or exact return scope: " + source;
			module.getBackendDeclaration();
		}
		final immediate = typed("var result = ((item) -> item)(7);");
		if (immediate.getTypedClasses()[0].getFunctions()[0].getBody().getStatements()[0].getExpressions()[0].getType().getSemanticKey() != "primitive:Int")
			throw "immediate arrow call lost its argument context";
		immediate.getBackendDeclaration();
	}

	static function main():Void {
		syntax();
		typing();
		Sys.println("SOURCE_ARROW_SYNTAX:PASS");
	}
}
