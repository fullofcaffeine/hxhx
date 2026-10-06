/** Argument admission preserves the record and callback; Main additionally requires recovery from Dynamic. */
class ArgumentContract {
	static var calls:Int = 0;

	static function same(value:Dynamic, expected:Dynamic):Bool {
		calls++;
		return value == expected;
	}

	static function accept(value:Dynamic):Void {
		calls++;
	}

	static function main():Void {
		var captured = 3;
		final direct = {item: () -> captured};
		final nested = {outer: {item: () -> captured + 1}};
		final callbacks = [() -> captured + 2];
		if (!same(direct, direct) || !same(nested, nested) || !same(callbacks, callbacks))
			throw "Dynamic argument changed allocation identity";
		accept({item: () -> captured});
		accept({
			item: function():Int {
				return captured;
			}
		});
		accept({outer: {item: () -> captured}});
		accept([() -> captured]);
		captured = 7;
		if (direct.item() != 7 || nested.outer.item() != 8 || callbacks[0]() != 9 || calls != 7)
			throw "callback argument changed capture or evaluation count";
	}
}
