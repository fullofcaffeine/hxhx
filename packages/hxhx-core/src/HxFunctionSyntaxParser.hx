import HxParsedFunction.HxParsedFunctionArgument;

/**
	Read function syntax without reducing statements to a lambda result.

	This helper shares HxParser's token stream, expression grammar, and statement
	parser. It owns only the function boundary and written signature facts. It
	neither infers types nor substitutes parameter defaults into body reads.

	Method declarations use the shared argument reader. The standalone function
	entry point proves the complete payload during the AST migration; nested
	function bodies still require their producer and consumer cutover.
 */
@:access(HxParser)
@:access(HxTypedefParser)
class HxFunctionSyntaxParser {
	final parser:HxParser;

	public function new(parser:HxParser) {
		this.parser = parser;
	}

	/** Parse one complete function and reject any trailing source tokens. */
	public static function parse(source:String):HxParsedFunction {
		final parser = new HxParser(source);
		final value = new HxFunctionSyntaxParser(parser).read(() -> parser.cur.kind.match(TEof));
		if (!parser.cur.kind.match(TEof))
			parser.fail("Unexpected token after function");
		return value;
	}

	/** Read the compiler's function-valued overload metadata with the ordinary signature grammar. */
	public static function parseOverloadMetadata(source:String):Null<HxParsedFunction> {
		final parser = new HxParser(source);
		if (!parser.acceptOtherChar("@") || !parser.cur.kind.match(TColon))
			return null;
		parser.bump();
		if (!parser.cur.kind.match(TIdent("overload")))
			return null;
		parser.bump();
		// A bare @:overload marks a normal method declaration, not an added signature.
		if (!parser.cur.kind.match(TLParen))
			return null;
		parser.bump();
		if (!parser.cur.kind.match(TKeyword(KFunction)))
			parser.fail("Overload requires a function declaration");
		final parsed = new HxFunctionSyntaxParser(parser).read(() -> parser.cur.kind.match(TRParen));
		if (!parser.cur.kind.match(TRParen))
			parser.fail("Expected ')' after overload declaration");
		parser.bump();
		if (!parser.cur.kind.match(TEof))
			parser.fail("Unexpected token after overload declaration");
		switch (parsed.body) {
			case Statements(body) if (body.length == 0):
			case _:
				parser.fail("Overload must only declare an empty method body {}");
		}
		if (parsed.resultTypeHint == null)
			parser.fail("Explicit type required");
		for (argument in parsed.arguments)
			if (!argument.hasTypeAnnotation)
				parser.fail("Explicit type required");
		return parsed;
	}

	/** Method bodies currently bind a written rest parameter as an omittable Array<T>. */
	public static function methodArgument(declaration:HxFunctionArg):HxFunctionArg {
		if (!HxFunctionArg.getIsRest(declaration))
			return declaration;
		final writtenHint = HxFunctionArg.getTypeHint(declaration);
		final elementHint = StringTools.trim(writtenHint).length == 0 ? "Dynamic" : writtenHint;
		return new HxFunctionArg(HxFunctionArg.getName(declaration), "Array<" + elementHint + ">", HxFunctionArg.getDefaultValue(declaration), true, true,
			HxFunctionArg.getDefaultValueText(declaration), HxFunctionArg.getMetadata(declaration));
	}

	/** Consume one function on the caller's token stream, bounded by its expression delimiter. */
	public function read(stop:() -> Bool):HxParsedFunction {
		final pos = parser.cur.getPos();
		final metadata = new Array<String>();
		while (parser.isOtherChar("@"))
			metadata.push(parser.parseMetadataText());
		return parser.cur.kind.match(TKeyword(KFunction)) ? readOrdinary(pos, metadata) : readArrow(stop, pos, metadata);
	}

	function readOrdinary(pos:HxPos, metadata:Array<String>):HxParsedFunction {
		if (!parser.acceptKeyword(KFunction))
			parser.fail("Expected 'function'");
		final name = parser.cur.kind.match(TIdent(_)) ? parser.readIdent("function name") : null;
		final typeParameters = new HxTypedefParser(parser).parameters();
		final arguments = readParenthesizedArguments();
		var resultTypeHint:Null<String> = null;
		if (parser.cur.kind.match(TColon)) {
			parser.bump();
			resultTypeHint = parser.readFunctionReturnTypeHint(() -> parser.cur.kind.match(TLBrace)
				|| parser.cur.kind.match(TKeyword(KReturn))
				|| parser.cur.kind.match(TKeyword(KThrow))
				|| parser.cur.kind.match(TSemicolon)
				|| parser.cur.kind.match(TEof));
			if (StringTools.trim(resultTypeHint).length == 0)
				parser.fail("Expected function result type");
		}
		var body = new Array<HxStmt>();
		var endPos:HxPos;
		if (parser.cur.kind.match(TLBrace)) {
			final block = readBlock();
			body = block.statements;
			endPos = block.endPos;
		} else {
			if (parser.cur.kind.match(TEof) || parser.cur.kind.match(TSemicolon))
				parser.fail("Expected function body");
			parser.parseStmtInto(body, () -> parser.cur.kind.match(TEof) || parser.cur.kind.match(TRBrace));
			endPos = parser.cur.getPos();
		}
		return {
			form: Ordinary,
			origin: Authored,
			name: name,
			typeParameters: typeParameters,
			arguments: arguments,
			resultTypeHint: resultTypeHint,
			metadata: metadata,
			pos: pos,
			endPos: endPos,
			body: Statements(body)
		};
	}

	/** Keep arrow block statements intact; the Arrow form gives their tail implicit-result meaning. */
	function readArrow(stop:() -> Bool, pos:HxPos, metadata:Array<String>):HxParsedFunction {
		final arguments = if (parser.cur.kind.match(TLParen)) readParenthesizedArguments() else {
			final argumentPos = parser.cur.getPos();
			final name = parser.readIdent("arrow argument name");
			[
				{
					declaration: new HxFunctionArg(name, "", NoDefault),
					hasTypeAnnotation: false,
					pos: argumentPos,
					endPos: parser.cur.getPos()
				}
			];
		};
		if (!parser.acceptOtherChar("-") || !parser.acceptOtherChar(">"))
			parser.fail("Expected '->'");
		if (stop() || parser.cur.kind.match(TEof) || parser.cur.kind.match(TSemicolon) || parser.cur.kind.match(TRBrace))
			parser.fail("Expected arrow body");
		// A field followed by ':' starts an object value, not a statement block.
		final objectResult = (parser.peekKind().match(TIdent(_)) || parser.peekKind().match(TString(_, _)))
			&& parser.peekKind2().match(TColon);
		var endPos:HxPos;
		final body:HxParsedFunction.HxParsedFunctionBody = if (parser.cur.kind.match(TLBrace) && !objectResult) {
			final block = readBlock();
			endPos = block.endPos;
			Statements(block.statements);
		} else {
			final expression = parser.parseExpr(stop);
			endPos = parser.cur.getPos();
			ImplicitResult(expression);
		};
		return {
			form: Arrow,
			origin: Authored,
			name: null,
			typeParameters: [],
			arguments: arguments,
			resultTypeHint: null,
			metadata: metadata,
			pos: pos,
			endPos: endPos,
			body: body
		};
	}

	/** Read the written argument list for methods and function expressions on one token stream. */
	public function readParenthesizedArguments():Array<HxParsedFunctionArgument> {
		parser.expect(TLParen, "'('");
		final arguments = new Array<HxParsedFunctionArgument>();
		if (!parser.cur.kind.match(TRParen)) {
			while (true) {
				arguments.push(readArgument());
				if (!parser.cur.kind.match(TComma))
					break;
				parser.bump();
			}
		}
		parser.expect(TRParen, "')'");
		return arguments;
	}

	/** Preserve explicit returns and the closing-brace span without adding a result expression. */
	function readBlock():{statements:Array<HxStmt>, endPos:HxPos} {
		parser.expect(TLBrace, "'{'");
		final statements = new Array<HxStmt>();
		while (!parser.cur.kind.match(TRBrace)) {
			if (parser.cur.kind.match(TEof))
				parser.fail("Unterminated function body");
			parser.parseStmtInto(statements, () -> parser.cur.kind.match(TRBrace) || parser.cur.kind.match(TEof));
		}
		final close = parser.cur.getPos();
		final endPos = new HxPos(close.getIndex() + 1, close.getLine(), close.getColumn() + 1);
		parser.bump();
		return {statements: statements, endPos: endPos};
	}

	/** Retain each default once, without making it a substitute for later parameter reads. */
	function readArgument():HxParsedFunctionArgument {
		final pos = parser.cur.getPos();
		final metadata = new Array<String>();
		while (parser.isOtherChar("@"))
			metadata.push(parser.parseMetadataText());
		final rest = parser.cur.kind.match(TDot) && parser.peekKind().match(TDot) && parser.peekKind2().match(TDot);
		if (rest) {
			parser.bump();
			parser.bump();
			parser.bump();
		}
		final optional = parser.acceptOtherChar("?");
		final name = parser.readIdent("argument name");
		final hasTypeAnnotation = parser.cur.kind.match(TColon);
		var hint = "";
		if (hasTypeAnnotation) {
			parser.bump();
			hint = parser.readTypeHintText(() -> parser.cur.kind.match(TComma) || parser.cur.kind.match(TRParen) || parser.cur.kind.match(TEof)
				|| parser.isOtherChar("="));
			if (StringTools.trim(hint).length == 0)
				parser.fail("Expected argument type");
		}
		var defaultValue:HxDefaultValue = NoDefault;
		var defaultValueText = "";
		if (parser.acceptOtherChar("=")) {
			if (parser.cur.kind.match(TComma) || parser.cur.kind.match(TRParen) || parser.cur.kind.match(TEof))
				parser.fail("Expected argument default expression");
			final start = parser.currentIndex();
			defaultValue = Default(parser.parseExpr(() -> parser.cur.kind.match(TComma) || parser.cur.kind.match(TRParen) || parser.cur.kind.match(TEof)));
			defaultValueText = StringTools.trim(parser.sliceSource(start, parser.currentIndex()));
		}
		return {
			declaration: new HxFunctionArg(name, hint, defaultValue, optional, rest, defaultValueText, metadata),
			hasTypeAnnotation: hasTypeAnnotation,
			pos: pos,
			endPos: parser.cur.getPos()
		};
	}
}
