/**
	Expression metadata as Haxe 4.3.7 parses it: `@:name(args) expr` and `@name(args) expr` stay
	`EMeta` with their exact names and arguments, and a call-site `inline f()` is `@:inline f()`.
**/
class Main {
	static function twice(x:Int):Int
		return x * 2;

	static function unchecked(values:Array<Null<Int>>):Int {
		return @:nullSafety(Off) (values[0] : Int);
	}

	static function tagged(x:Int):Int {
		return @custom(1, "a") x + 1;
	}

	static function inlined(x:Int):Int {
		return inline twice(x);
	}

	static function main() {
		Sys.println(unchecked([5]) + " " + tagged(2) + " " + inlined(4));
	}
}
