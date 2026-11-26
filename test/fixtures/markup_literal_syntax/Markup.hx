import haxe.macro.Context;
import haxe.macro.Expr;

class Markup {
	/**
		The text of an inline markup literal, which the parser stores as `@:markup "<text>"`.
		A block of literals gives their texts joined with `|`.
	**/
	public static macro function text(e:Expr):Expr {
		return macro $v{read(e)};
	}

	/** Replace each markup literal field initializer with its text. */
	public static macro function fields():Array<Field> {
		final fields = Context.getBuildFields();
		for (field in fields)
			switch field.kind {
				case FVar(type, value) if (value != null && value.expr.match(EMeta({name: ":markup"}, _))):
					field.kind = FVar(type, macro $v{read(value)});
				case _:
			}
		return fields;
	}

	#if macro
	static function read(e:Expr):String {
		return switch e.expr {
			case EMeta({name: ":markup", params: []}, {expr: EConst(CString(value, DoubleQuotes))}): value;
			case EBlock(items): [for (item in items) read(item)].join("|");
			case _: Context.error("markup literal expected", e.pos);
		}
	}
	#end
}
