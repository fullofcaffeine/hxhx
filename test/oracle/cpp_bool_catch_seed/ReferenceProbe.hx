/** Print public observations independently of the candidate compiler's lowering. */
class ReferenceProbe {
	static function observe(value:Dynamic):String {
		try {
			return "selected:" + BoolCatch.select(value);
		} catch (escaped:Dynamic) {
			return "escaped:" + (escaped == value);
		}
	}

	static function main():Void {
		final raw:Array<Dynamic> = [true, false, null, "true"];
		for (value in raw)
			Sys.println(observe(value));
		final yes = new haxe.ValueException(true);
		final no = new haxe.ValueException(false);
		final text = new haxe.ValueException("true");
		final nested = new haxe.ValueException(yes);
		for (value in [yes, no, text, nested])
			Sys.println(observe(value));
		Sys.println(BoolCatch.escaped(text) == text);
		Sys.println(BoolCatch.unmatched(text) == text);
		Sys.println(BoolCatch.escaped(nested) == nested);
		Sys.println(BoolCatch.handlerThrows());
		final first = BoolCatch.capture(yes);
		final second = BoolCatch.capture(no);
		Sys.println(first(false));
		Sys.println(first(true));
		Sys.println(second(true));
		Sys.println(second(false));
	}
}
