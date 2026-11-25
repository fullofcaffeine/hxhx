/**
	A `for` over an array inside a local function (haxe_ocaml-kmm68), as upstream's
	`UnitBuilder.readDir` loops over a directory listing. The loops also leave the function with
	`return`, skip with `continue`, and stop with `break`.
**/
class Main {
	static function main():Void {
		var count = 0;
		function walk(items:Array<String>) {
			for (item in items)
				count += item.length;
		}
		walk(["ab", "c"]);
		Sys.println("count " + count);

		function find(items:Array<String>, wanted:String):Int {
			var index = 0;
			for (item in items) {
				if (item == wanted)
					return index;
				index++;
			}
			return -1;
		}
		Sys.println("find " + find(["a", "b", "c"], "b") + " " + find(["a"], "z"));

		function firstLong(items:Array<String>):String {
			for (item in items) {
				if (item.length < 2)
					continue;
				return item;
			}
			return "none";
		}
		Sys.println("firstLong " + firstLong(["a", "bc", "def"]) + " " + firstLong(["x"]));

		function sumUntil(values:Array<Int>, stop:Int):Int {
			var total = 0;
			for (value in values) {
				if (value == stop)
					break;
				total += value;
			}
			return total;
		}
		Sys.println("sumUntil " + sumUntil([1, 2, 3, 4], 3));

		function listing(names:Array<String>):String {
			final dir = names.copy();
			var out = "";
			for (file in dir)
				out += file.toUpperCase();
			return out;
		}
		Sys.println("listing " + listing(["a.unit.hx", "b.unit.hx"]));
	}
}
