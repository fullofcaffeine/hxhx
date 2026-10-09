/**
	Native callback-array recovery shares reference/Dynamic storage and copies
	fixed scalar storage. Dynamic is confined to the recovery and value observer.
	The cpp-only assertions record native behavior that differs from eval.
 */
class ArrayRecoveryContract {
	static function recover(value:Dynamic):Array<() -> Int> {
		return value;
	}

	static function identical(left:Dynamic, right:Dynamic):Bool {
		return left == right;
	}

	static function main():Void {
		var captured = 3;
		final callbacks = [() -> captured];
		final recovered = recover(callbacks);
		captured = 7;
		recovered.push(() -> captured + 1);
		callbacks[0] = () -> captured + 2;
		if (callbacks.length != 2 || callbacks[1]() != 8 || recovered[0]() != 9)
			throw "callback recovery lost shared storage or capture";
		final mixed:Array<Dynamic> = [() -> captured];
		final mixedView = recover(mixed);
		mixedView.push(() -> captured + 3);
		mixed[0] = () -> captured + 4;
		if (mixed.length != 2 || mixedView[0]() != 11 || mixedView[1]() != 10)
			throw "Dynamic array recovery lost shared mutation";
		final emptyCallbacks:Array<() -> Int> = [];
		final emptyView = recover(emptyCallbacks);
		emptyView.push(() -> 13);
		if (emptyCallbacks.length != 1 || emptyCallbacks[0]() != 13)
			throw "empty callback array lost its storage identity";

		#if cpp
		if (recover(null) != null || recover(7) != null || recover("text") != null || recover({item: 1}) != null)
			throw "non-array recovery did not produce null";
		final integers = [7];
		final integerView = recover(integers);
		integerView.push(() -> 17);
		if (integers.length != 1 || integerView.length != 2 || !identical(integerView[0], 7) || integerView[1]() != 17)
			throw "integer array recovery did not copy boxed elements";
		final booleans = [true];
		final booleanView = recover(booleans);
		booleanView.push(() -> 19);
		if (booleans.length != 1 || !identical(booleanView[0], true) || booleanView[1]() != 19)
			throw "Boolean array recovery did not copy boxed elements";
		final strings = ["text"];
		final stringView = recover(strings);
		stringView.push(() -> 23);
		if (strings.length != 1 || !identical(stringView[0], "text") || stringView[1]() != 23)
			throw "String array recovery did not copy boxed elements";
		final records = [{item: 1}];
		final recordView = recover(records);
		recordView.push(() -> 29);
		if (records.length != 2 || recordView[1]() != 29)
			throw "reference array recovery copied shared storage";
		final emptyIntegers:Array<Int> = [];
		final emptyIntegerView = recover(emptyIntegers);
		emptyIntegerView.push(() -> 31);
		if (emptyIntegers.length != 0 || emptyIntegerView[0]() != 31)
			throw "empty integer array lost its representation";
		#end
	}
}
