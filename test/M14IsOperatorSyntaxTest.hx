import haxe.macro.Expr;
import hxhxmacrohost.MacroSyntaxWire;

/**
	The `is` operator crosses the macro boundary as upstream parses it (haxe_ocaml-1jxp9).

	Haxe 4.3.7 parses `x is T` as `EIs(x, T)` with a type on the right (`grammar.mly`, the `is`
	case of `expr_next`), so `x is T<Int>` keeps its type parameters. hxhx keeps `x is T` as an
	`is` binary operation whose right side is the type path written as an expression;
	`MacroSyntaxExport` refused it, and the upstream unit suite stopped at
	`unitstd/haxe/ds/StringMap.unit.hx` (`(map1 is haxe.ds.StringMap)`). `x is T<Int>` did not
	even parse as a type.

	For each argument of `Syntax.show` in the fixture, the test exports it, sends it through the
	plugin payload (`MacroSyntaxWire`) both ways, imports it, and requires the parser's exact body
	fingerprint to be unchanged. The exported syntax must print, with the structure of each `is`
	type, as upstream's macro printed it (`expected.stdout`).
**/
class M14IsOperatorSyntaxTest {
	static final root = "test/fixtures/is_operator_syntax";

	static function require(value:Bool, message:String):Void {
		if (!value)
			throw message;
	}

	/** The argument of every `Syntax.show(...)` call in `main`, in source order. */
	static function arguments(file:String):Array<HxExpr> {
		final found = new Array<HxExpr>();
		function visit(expression:Null<HxExpr>):Void {
			switch expression {
				case ECall(EField(EIdent("Syntax"), "show"), [argument]):
					found.push(argument);
				case ECall(callee, values):
					visit(callee);
					for (value in values)
						visit(value);
				case _:
			}
		}
		final decl = ParserStage.parse(sys.io.File.getContent(file), file).getDecl();
		for (functionDecl in HxClassDecl.getFunctions(HxModuleDecl.getMainClass(decl)))
			for (statement in HxFunctionDecl.getBody(functionDecl))
				switch statement {
					case SExpr(expression, _):
						visit(expression);
					case _:
				}
		return found;
	}

	static function roundTrip(file:String, argument:HxExpr):Expr {
		final positions = new MacroSyntaxPositions(file);
		final exported = new MacroSyntaxExport(positions).argument(argument, 0);
		final payload = MacroSyntaxWire.encodeArguments([exported]);
		final decoded = MacroSyntaxWire.decodeArguments(payload);
		require(MacroSyntaxWire.encodeArguments(decoded) == payload, file + ": payload is not stable across a decode");
		final returned = MacroSyntaxWire.decodeResult(MacroSyntaxWire.encodeResult(decoded[0]));
		final imported = new MacroSyntaxImport(positions).result(returned);
		final before = TypedBodyFingerprint.exactExpression(argument);
		final after = TypedBodyFingerprint.exactExpression(imported);
		require(before == after, "round trip changed the syntax:\n  before " + before + "\n  after  " + after);
		return exported;
	}

	public static function main():Void {
		final file = root + "/Main.hx";
		final expected = StringTools.trim(sys.io.File.getContent(root + "/expected.stdout")).split("\n");
		final found = arguments(file);
		require(found.length == expected.length, "expected " + expected.length + " Syntax.show arguments, found " + found.length);
		for (index in 0...found.length) {
			final printed = Syntax.describe(roundTrip(file, found[index]));
			require(printed == expected[index], "argument " + index + ":\n  upstream " + expected[index] + "\n  hxhx     " + printed);
		}
		Sys.println("IS_OPERATOR_ROUND_TRIP:PASS");
	}
}
