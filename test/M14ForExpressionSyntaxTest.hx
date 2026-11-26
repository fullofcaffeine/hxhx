import haxe.macro.Expr;
import hxhxmacrohost.MacroSyntaxWire;

/**
	`for` with any expression in its head crosses the macro boundary as upstream parses it
	(haxe_ocaml-fqzjd).

	Haxe 4.3.7 reads `for (` followed by any expression (`grammar.mly`, the `for` case of `expr`), so
	`for (1) "foo"` is `EFor(1, "foo")`; only typing requires `name in iterable`. hxhx required a
	binding name, and the upstream unit suite stopped at `macro for (1) "foo"`
	(`unitstd/haxe/macro/ExprTools.unit.hx`).

	For each argument of `Syntax.show` in the fixture, the test exports it, sends it through the
	plugin payload both ways, imports it, and requires the parser's exact body fingerprint to be
	unchanged. The exported syntax must print, with the shape of each `for` iterator, as upstream's
	macro printed it. The quoted form must also lower, as the unit suite's spec writes it.
**/
class M14ForExpressionSyntaxTest {
	static final root = "test/fixtures/for_expression_syntax";

	static function require(value:Bool, message:String):Void {
		if (!value)
			throw message;
	}

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
		Sys.println("FOR_EXPRESSION_ROUND_TRIP:PASS");

		// The unit suite's spec line: the quotation parses and lowers.
		final statements = HxParser.parseFunctionBodyText('var efor = macro for (1) "foo";');
		final quoted = switch statements {
			case [SVar("efor", _, EMacroExpr(quoted, wrappers), _, _)]: {expression: quoted, wrappers: wrappers};
			case _: throw "the spec line did not parse as a quotation: " + statements;
		};
		MacroReificationLowering.lowerExpression(quoted.expression, quoted.wrappers, "spec.hx", new HxPos(0, 1, 1), _ -> TyType.unknown(), false, false);
		Sys.println("FOR_EXPRESSION_QUOTATION:PASS");
	}
}
