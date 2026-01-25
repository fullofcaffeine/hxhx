class Parser {
	final lex:Lexer;
	var cur:Token;

	public function new(src:String) {
		lex = new Lexer(src);
		cur = lex.next();
	}

	inline function bump():Void {
		cur = lex.next();
	}

	function expectPunct(expected:Token, label:String):Void {
		final ok = switch (cur) {
			case TPlus:
				switch (expected) {
					case TPlus: true;
					case _: false;
				}
			case TMinus:
				switch (expected) {
					case TMinus: true;
					case _: false;
				}
			case TStar:
				switch (expected) {
					case TStar: true;
					case _: false;
				}
			case TSlash:
				switch (expected) {
					case TSlash: true;
					case _: false;
				}
			case TLParen:
				switch (expected) {
					case TLParen: true;
					case _: false;
				}
			case TRParen:
				switch (expected) {
					case TRParen: true;
					case _: false;
				}
			case TEof:
				switch (expected) {
					case TEof: true;
					case _: false;
				}
			case TInt(_):
				false;
		}

		if (!ok) throw "Expected " + label;
		bump();
	}

	public function parse():Expr {
		final e = parseExpr();
		expectPunct(TEof, "end of input");
		return e;
	}

	function parseExpr():Expr {
		return parseExprTail(parseTerm());
	}

	function parseExprTail(left:Expr):Expr {
		return switch (cur) {
			case TPlus:
				bump();
				parseExprTail(EBin(Add, left, parseTerm()));
			case TMinus:
				bump();
				parseExprTail(EBin(Sub, left, parseTerm()));
			case _:
				left;
		}
	}

	function parseTerm():Expr {
		return parseTermTail(parseFactor());
	}

	function parseTermTail(left:Expr):Expr {
		return switch (cur) {
			case TStar:
				bump();
				parseTermTail(EBin(Mul, left, parseFactor()));
			case TSlash:
				bump();
				parseTermTail(EBin(Div, left, parseFactor()));
			case _:
				left;
		}
	}

	function parseFactor():Expr {
		return switch (cur) {
			case TInt(v):
				bump();
				EInt(v);
			case TLParen:
				bump();
				final e = parseExpr();
				expectPunct(TRParen, "')'");
				e;
			case _:
				throw "Expected factor";
		}
	}
}
