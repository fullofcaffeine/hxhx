/**
	`var a = 1, b = 2;` as Haxe 4.3.7 parses it: one `EVars` with every declarator. (In
	single-statement position upstream reads one declarator only, so the fixture does not use it.)
**/
class Main {
	static function sum(a:Int, b:Int):Int {
		var x = a * 2, y = b * 3;
		var total:Int = x + y, label = "sum";
		return total + label.length;
	}

	static function grouped(flag:Bool):Int {
		var first = 1, second = 2, third = first + second;
		return flag ? third : 0;
	}

	static function uninitialized():String {
		var left:String, right = "b";
		left = "a";
		return left + right;
	}

	static function main() {
		Sys.println(sum(1, 2) + " " + grouped(true) + " " + uninitialized());
	}
}
