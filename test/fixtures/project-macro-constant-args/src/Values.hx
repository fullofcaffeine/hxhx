/**
	Project macros whose parameters are constants, not syntax. Each macro receives the values the
	call wrote and returns one String literal built from them.
**/
class Values {
	public static macro function describe(label:String, count:Int, ratio:Float, flag:Bool):haxe.macro.Expr {
		return macro $v{label + " " + count + " " + ratio + " " + flag};
	}

	/** No declared result: upstream infers `haxe.macro.Expr` from the returned quotation. */
	public static macro function shout(text:String) {
		return macro $v{text.toUpperCase()};
	}
}
