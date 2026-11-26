import haxe.macro.Expr;
#if macro
import haxe.macro.Context;
import haxe.macro.MacroStringTools;
#end

/**
	Macros that format text with `MacroStringTools.formatString`, as upstream's
	`unit.HelperMacros.pipeMarkupLiteral` does (haxe_ocaml-8zlo5).
**/
class Fmt {
	/** The formatted text, as an expression the program runs. */
	public static macro function format(text:String):Expr {
		#if macro
		return MacroStringTools.formatString(text, literal(text));
		#else
		return null;
		#end
	}

	/** The formatted text's parts and their ranges, counted from the literal's opening quote. */
	public static macro function shape(text:String):Expr {
		#if macro
		return {expr: EConst(CString(chain(MacroStringTools.formatString(text, literal(text))), DoubleQuotes)), pos: Context.currentPos()};
		#else
		return null;
		#end
	}

	/** Format `text` as if its literal's opening quote were at offset `min` of `file`, so errors point there. */
	public static macro function formatAt(text:String, file:String, min:Int):Expr {
		#if macro
		return MacroStringTools.formatString(text, Context.makePosition({min: min, max: min + text.length + 2, file: file}));
		#else
		return null;
		#end
	}

	#if macro
	static inline final BASE = 100;

	/** A fixed literal position, so every compiler prints the same ranges. */
	static function literal(text:String):Position
		return Context.makePosition({min: BASE, max: BASE + text.length + 2, file: "Format.hx"});

	/** The `+` chain; its first part is always text. */
	static function chain(e:Expr):String {
		return switch e.expr {
			case EBinop(OpAdd, left, right): "(" + chain(left) + " + " + part(right) + ")" + range(e);
			case _: part(e);
		}
	}

	/** A text part, a `$name`, or the root of a `${...}` expression. */
	static function part(e:Expr):String {
		return switch e.expr {
			case EConst(CString(s, DoubleQuotes)): "\"" + s + "\"" + range(e);
			case EConst(CString(s, _)): "single " + s + range(e);
			case EConst(CIdent(name)): name + range(e);
			case EBinop(_, _, _): "binop" + range(e);
			case EField(_, _): "field" + range(e);
			case _: "expr" + range(e);
		}
	}

	static function range(e:Expr):String {
		final p = Context.getPosInfos(e.pos);
		return "@" + (p.min - BASE) + ".." + (p.max - BASE);
	}
	#end
}
