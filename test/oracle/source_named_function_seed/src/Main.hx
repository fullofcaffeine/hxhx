/** Named functions retain lexical bindings, recursive calls, and lifetime after their creator returns. */
class Main {
	static function makeCounter():Int->Int {
		var calls = 0;
		function count(value:Int):Int {
			calls++;
			if (value == 0)
				return calls;
			return count(value - 1);
		}
		return count;
	}

	static function main():Void {
		final entries = [{name: "first"}, {name: "hit"}];
		final selected = switch (1) {
			case 1:
				function has(name:String):Bool {
					for (entry in entries)
						if (entry.name == name)
							return true;
					return false;
				}
				has("hit");
			default: false;
		};
		Sys.println(selected);
		function sum(value:Int):Int {
			if (value == 0)
				return 0;
			return value + sum(value - 1);
		}
		Sys.println(sum(4));
		final counter = makeCounter();
		Sys.println(counter(2));
		Sys.println(counter(1));
	}
}
