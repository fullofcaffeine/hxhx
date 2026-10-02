import haxe.macro.Expr;
import hxhxmacrohost.api.RuntimeMacroExprs;

/** Compare public runtime macro parsing with independently observed upstream operators. */
class M14MacroBinaryOperatorTest {
	static function shape(expression:Expr):String {
		return switch expression.expr {
			case EConst(CIdent(name)): name;
			case EBinop(operation, left, right): Std.string(operation) + "(" + shape(left) + "," + shape(right) + ")";
			case EParenthesis(inner): "paren(" + shape(inner) + ")";
			case ETernary(condition, yes, no): "if(" + shape(condition) + "," + shape(yes) + "," + shape(no) + ")";
			case _: throw "unexpected macro precedence node";
		};
	}

	static function main():Void {
		final root = "test/oracle/source_parenthesized_seed/";
		final tokens = sys.io.File.getContent(root + "binary.tokens").split("\n");
		final rows = new Array<String>();
		for (token in tokens) {
			if (token.length == 0)
				continue;
			var name:String;
			try {
				name = switch RuntimeMacroExprs.parse("left " + token + " right", null).expr {
					case EBinop(operation, _, _): Std.string(operation);
					case _: "not-binary";
				};
			} catch (error:haxe.Exception) {
				name = "rejected:" + error.message;
			}
			rows.push(token + "\t" + name);
		}
		final actual = rows.join("\n") + "\n";
		if (actual != sys.io.File.getContent(root + "binary.stdout"))
			throw "macro binary operators differ from upstream:\n" + actual;
		final cases = sys.io.File.getContent(root + "binary.precedence").split("\n");
		final precedence = [
			for (source in cases)
				if (source.length > 0) source + "\t" + shape(RuntimeMacroExprs.parse(source, null))
		].join("\n") + "\n";
		if (precedence != sys.io.File.getContent(root + "binary-precedence.stdout"))
			throw "macro operator precedence differs:\n" + precedence;
		for (source in ["left trailing", "left + right trailing", "left;", "left; right"]) {
			var rejected = false;
			try {
				RuntimeMacroExprs.parse(source, null);
			} catch (error:haxe.Exception) {
				rejected = true;
			}
			if (!rejected)
				throw "runtime macro parser accepted a source prefix: " + source;
		}
		Sys.println("MACRO_BINARY_OPERATOR:PASS");
	}
}
