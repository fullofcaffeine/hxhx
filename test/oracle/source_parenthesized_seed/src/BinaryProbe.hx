import haxe.macro.Expr;

/** Observe public binary-operator constructors through the upstream macro parser. */
class BinaryProbe {
	static function shape(expression:Expr):String {
		return switch expression.expr {
			case EConst(CIdent(name)): name;
			case EBinop(operation, left, right): Std.string(operation) + "(" + shape(left) + "," + shape(right) + ")";
			case EParenthesis(inner): "paren(" + shape(inner) + ")";
			case ETernary(condition, yes, no): "if(" + shape(condition) + "," + shape(yes) + "," + shape(no) + ")";
			case _: throw "unexpected precedence probe syntax";
		};
	}

	public static macro function observePrecedence():Expr {
		final sources = sys.io.File.getContent("test/oracle/source_parenthesized_seed/binary.precedence").split("\n");
		return macro $v{
			[
				for (source in sources)
					if (source.length > 0) source + "\t" + shape(haxe.macro.Context.parse(source, haxe.macro.Context.currentPos()))
			].join("\n")
		};
	}

	public static macro function observe():Expr {
		final tokens = sys.io.File.getContent("test/oracle/source_parenthesized_seed/binary.tokens").split("\n");
		final rows = new Array<String>();
		for (token in tokens) {
			if (token.length == 0)
				continue;
			final expression = haxe.macro.Context.parse("left " + token + " right", haxe.macro.Context.currentPos());
			final name = switch expression.expr {
				case EBinop(operation, _, _): Std.string(operation);
				case _: throw "expected a binary expression for " + token;
			};
			rows.push(token + "\t" + name);
		}
		return macro $v{rows.join("\n")};
	}
}
