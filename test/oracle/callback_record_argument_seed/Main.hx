/** Callback fields remain callable after their record crosses a Dynamic argument. */
class Main {
	static var calls:Int = 0;

	static function pass(value:Dynamic):Dynamic {
		calls++;
		return value;
	}

	static function main():Void {
		var captured = 3;
		final direct:{item:() -> Int} = pass({item: () -> captured});
		final written:{item:() -> Int} = pass({
			item: function():Int {
				return captured + 1;
			}
		});
		final nested:{outer:{item:() -> Int}} = pass({outer: {item: () -> captured + 2}});
		final callbacks:Array<() -> Int> = pass([() -> captured + 3]);
		captured = 7;
		if (direct.item() != 7 || written.item() != 8 || nested.outer.item() != 9 || callbacks[0]() != 10 || calls != 4)
			throw "callback record transfer failed";
	}
}
