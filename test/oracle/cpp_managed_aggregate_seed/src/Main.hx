/** Ordered aggregate construction and callbacks must preserve one shared array graph. */
class Main {
	static function records() {
		final entries = [{name: "first"}, {name: "hit"}];
		return entries;
	}

	static function mixed(effect:Void->Array<Int>) {
		final values = [{tag: "first", items: effect()}, {tag: "second", items: effect()}];
		return {
			values: values,
			callback: function() {
				return values;
			}
		};
	}

	static function ordered(effect:Void->Int) {
		return {z: effect(), a: effect()};
	}

	static function empty():Array<Int> {
		return [];
	}

	static function strings():Array<String> {
		return ["", "é", "a\x00b9"];
	}

	static function main():Void {
		Sys.println(records()[1].name);
		var calls = 0;
		final result = mixed(function():Array<Int> {
			calls++;
			return [calls];
		});
		Sys.println(result.values[0].tag);
		Sys.println(result.values[1].items[0]);
		Sys.println(result.callback() == result.values);
		var order = 0;
		final record = ordered(function():Int {
			return ++order;
		});
		Sys.println(record.z);
		Sys.println(record.a);
		Sys.println(empty().length);
		Sys.println(strings()[2] == "a\x00b9");
	}
}
