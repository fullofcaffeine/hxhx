/** A loop in a value group repeats its condition and leaves the group's final value intact. */
class Main {
	static function main():Void {
		var index = 0;
		final result = {
			while (index < 4) {
				index++;
				if (index == 2)
					continue;
				if (index == 4)
					break;
				Sys.println(index);
			}
			"done";
		};
		Sys.println(result);
		final callback = function():String {
			var value = 0;
			while (value < 3) {
				value++;
				if (value == 1)
					continue;
				if (value == 2)
					break;
			}
			return "callable" + value;
		};
		Sys.println(callback());
	}
}
