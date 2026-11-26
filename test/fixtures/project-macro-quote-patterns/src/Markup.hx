import haxe.macro.Expr;
#if macro
import haxe.macro.Context;
import haxe.macro.MacroStringTools;
#end

/**
	Upstream's `unit.HelperMacros.pipeMarkupLiteral` and `pipeMarkupLiteralUnprocessed`
	(haxe_ocaml-ikf1n): `case macro` patterns bind `s:String` and `el:Array<Expr>`. The markup text
	comes as a String and is parsed with Context.parseInlineString, as upstream's test builder parses
	its specs.
**/
class Markup {
	public static macro function pipe(code:String):Expr {
		#if macro
		return piped(Context.parseInlineString(code, Context.currentPos()));
		#else
		return null;
		#end
	}

	#if macro
	/**
		Upstream's `loop` as a static function: the Stage3 plugin emitter cannot yet pass a local
		function to `map` inside its own body.
	**/
	static function piped(e:Expr):Expr {
		return switch (e) {
			case macro @:markup $v{(s : String)} :
				MacroStringTools.formatString(s, e.pos);
			case macro $b{el} :
				el = el.map(piped);
				macro $a{el}.join("");
			case _:
				Context.error("Markup literal expected", e.pos);
		}
	}
	#end

	public static macro function unprocessed(code:String):Expr {
		#if macro
		final e = Context.parseInlineString(code, Context.currentPos());
		return switch (e) {
			case macro @:markup $v{(s : String)} :
				macro $v{s};
			case _:
				Context.error("Markup literal expected", e.pos);
		}
		#else
		return null;
		#end
	}
}
