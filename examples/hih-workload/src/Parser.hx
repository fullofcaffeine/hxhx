import Ast;
import LetDecl;
import Module;

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

	function expectId(label:String):String {
		return switch (cur) {
			case TId(name):
				bump();
				name;
			case _:
				throw "Expected identifier (" + label + ")";
		}
	}

	function expectPunct(expected:Token, label:String):Void {
		final ok = switch (cur) {
			case TPlus: expected == TPlus;
			case TMinus: expected == TMinus;
			case TStar: expected == TStar;
			case TSlash: expected == TSlash;
			case TEquals: expected == TEquals;
			case TSemi: expected == TSemi;
			case TLParen: expected == TLParen;
			case TRParen: expected == TRParen;
			case TEof: expected == TEof;
			case TInt(_), TId(_): false;
		}
		if (!ok) throw "Expected " + label;
		bump();
	}

	public function parseModule(name:String):Module {
		final decls:Array<LetDecl> = [];

		function loop():Module {
			return switch (cur) {
				case TEof:
					new Module(name, decls);
				case TId(id) if (id == "let"):
					bump();
					final n = expectId("let name");
					expectPunct(TEquals, "'='");
					final e = parseExpr();
					expectPunct(TSemi, "';'");
					decls.push(new LetDecl(n, e));
					loop();
				case _:
					throw "Unexpected token in module body";
			}
		}

		return loop();
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
			case TId(name):
				bump();
				EVar(name);
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
