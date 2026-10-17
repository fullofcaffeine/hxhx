/** Independent assertions cover handler order, payload views, propagation, and escaped storage. */
class Main {
	static function require(value:Bool):Void {
		if (!value)
			throw "String catch contract failed";
	}

	static function main():Void {
		final text = new haxe.ValueException("wrapped");
		final boolean = new haxe.ValueException(false);
		final absent = new haxe.ValueException(null);
		final child = new StringWrapper("child");
		for (booleanFirst in [false, true]) {
			require(StringCatch.select("raw", booleanFirst) == "string:raw");
			require(StringCatch.select("", booleanFirst) == "string:");
			require(StringCatch.select(true, booleanFirst) == "bool:true");
			require(StringCatch.select(false, booleanFirst) == "bool:false");
			require(StringCatch.select(null, booleanFirst) == "carrier");
			require(StringCatch.select(text, booleanFirst) == "string:wrapped");
			require(StringCatch.select(boolean, booleanFirst) == "bool:false");
			require(StringCatch.select(child, booleanFirst) == "string:child");
			require(StringCatch.escaped(absent, booleanFirst) == absent);
		}
		require(StringCatch.unmatched(absent) == absent);
		require(StringCatch.replacement() == "replacement");
		final first = StringCatch.capture(text);
		final second = StringCatch.capture(child);
		require(first("next") == "wrapped");
		require(second("other") == "child");
		require(first("last") == "next");
		require(second("end") == "other");
		final nested = new haxe.ValueException(text);
		require(StringCatch.escaped(nested, false) == nested);
		require(StringCatch.escaped(nested, true) == nested);
	}
}

/** An inherited payload must use the real declaring provider's storage. */
class StringWrapper extends haxe.ValueException {
	public function new(value:String)
		super(value);
}
