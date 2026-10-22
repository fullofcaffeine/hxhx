/** The metadata lookup shape needs iteration and returns inside a capturing function. */
class Main {
	static function main():Void {
		final entries = [{name: "first"}, {name: "hit"}, {name: "last"}];
		final has = function(name:String):Bool {
			for (entry in entries)
				if (entry.name == name)
					return true;
			return false;
		};
		Sys.println(has("hit"));
		Sys.println(has("missing"));
		final rangeSum = function():Int {
			var limit = 5;
			var sum = 0;
			var seen = 0;
			for (index in 0...limit) {
				limit = 0;
				if (index == 0)
					continue;
				if (index == 3)
					break;
				sum += index;
				seen++;
			}
			return sum + seen * 10;
		};
		Sys.println(rangeSum());
		final values = function():Array<String> {
			Sys.println("iterable");
			return ["a", "b"];
		};
		final keyValues = function():String {
			var result = "";
			for (key => value in values())
				result += key + value;
			return result;
		};
		Sys.println(keyValues());
		final total = {
			var sum = 0;
			for (number in [1, 2])
				sum += number;
			sum;
		};
		Sys.println(total);
		var limit = 3;
		var count = 0;
		for (index in 0...limit) {
			limit = 0;
			count++;
		}
		Sys.println(count);
	}
}
