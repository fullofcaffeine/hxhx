import haxe.macro.Context;
import haxe.macro.Expr;

/** Independent upstream syntax observer; it inspects parsed expressions without typing their names. */
class ShapeMacro {
	static function shape(expression:Expr):String {
		return switch expression.expr {
			case EParenthesis(inner): "paren(" + shape(inner) + ")";
			case EArray(value, index): "index(" + shape(value) + "," + shape(index) + ")";
			case EConst(CIdent(name)): name;
			case EConst(CInt(value)): value;
			case _: "other";
		};
	}

	public static macro function inspect():Expr {
		for (source in [
			"switch (values) { default: 0; }",
			"switch ((values)) { default: 0; }",
			"switch (values)[0] { default: 0; }"
		]) {
			switch Context.parse(source, Context.currentPos()).expr {
				case ESwitch(subject, _, _):
					Sys.println(shape(subject));
				case _:
					Context.error("expected switch", Context.currentPos());
			}
		}
		return macro null;
	}
}
