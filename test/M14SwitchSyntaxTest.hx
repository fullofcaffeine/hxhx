import haxe.macro.Expr;
import hxhxmacrohost.MacroSyntaxWire;

/**
	Switch expressions cross the macro boundary as upstream parses them (haxe_ocaml-ujjik).

	Haxe 4.3.7 parses `switch e { case p1, p2 if (g): body; default: d }` as
	`ESwitch(e, [{values: [p1, p2], guard: g, expr: {body}}], {d})` (`grammar.mly`, the `switch` case
	of `expr` and `parse_switch_cases`); patterns are expressions, an empty case has a null body,
	and a written `default:` is separate. `MacroSyntaxExport` refused every switch, so each upstream
	unit spec that uses one in its own code stopped in `Context.parseInlineString`.

	For each argument of `Syntax.show` in the fixture, the test exports it, sends it through the
	plugin payload both ways, imports it, and requires the parser's exact body fingerprint to be
	unchanged. The exported syntax must print, with the shape of its cases and default, exactly as
	upstream's macro printed it (`expected.stdout`).
**/
class M14SwitchSyntaxTest {
	static final root = "test/fixtures/switch_syntax";

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
				case EArrayDecl(values):
					for (value in values)
						visit(value);
				case _:
			}
		}
		final decl = ParserStage.parse(sys.io.File.getContent(file), file).getDecl();
		for (functionDecl in HxClassDecl.getFunctions(HxModuleDecl.getMainClass(decl)))
			for (statement in HxFunctionDecl.getBody(functionDecl))
				switch statement {
					case SVar(_, _, initializer, _, _):
						visit(initializer);
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
		Sys.println("SWITCH_ROUND_TRIP:PASS");
	}
}
