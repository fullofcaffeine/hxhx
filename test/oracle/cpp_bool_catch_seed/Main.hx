/** Independent assertions cover raw values, one wrapper layer, propagation, and escaping handler state. */
class Main {
	static function require(value:Bool):Void {
		if (!value)
			throw "Boolean catch contract failed";
	}

	/** Primitive payloads exercise handler selection without requiring object-to-string conversion. */
	public static function primitives():Void {
		require(BoolCatch.select(true) == 1);
		require(BoolCatch.select(false) == 2);
		require(BoolCatch.select(null) == 3);
		require(BoolCatch.select("true") == 3);
		final yes = new haxe.ValueException(true);
		final no = new haxe.ValueException(false);
		final text = new haxe.ValueException("true");
		require(BoolCatch.select(yes) == 1);
		require(BoolCatch.select(no) == 2);
		require(BoolCatch.escaped(text) == text);
		require(BoolCatch.unmatched(text) == text);
		final absent = new haxe.ValueException(null);
		require(BoolCatch.escaped(absent) == absent);
		require(BoolCatch.select(new BoolWrapper(true)) == 1);
		require(!BoolCatch.handlerThrows());
		final first = BoolCatch.capture(yes);
		final second = BoolCatch.capture(no);
		require(first(false));
		require(!first(true));
		require(!second(true));
		require(second(false));
	}

	static function main():Void {
		primitives();
		final yes = new haxe.ValueException(true);
		final nested = new haxe.ValueException(yes);
		require(BoolCatch.escaped(nested) == nested);
	}
}

/** An inherited payload must use the declaring provider's field layout. */
class BoolWrapper extends haxe.ValueException {
	public function new(value:Bool)
		super(value);
}
