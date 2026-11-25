/**
	Extractor patterns as Haxe 4.3.7 parses them: a case pattern is an expression, so
	`_.get() => v` is an `=>` binary operation whose left side runs on the matched value.
**/
class Main {
	static function size(value:String):String {
		return switch (value) {
			case _.length => 0: "empty";
			case _.toUpperCase() => "ABC": "abc";
			case ~/^[0-9]+$/.match(_) => true: "digits";
			case Std.parseInt(_) => n if (n != null && n < 0): "negative";
			case _ + "," + _ => "x,x": "x";
			case _: "other";
		}
	}

	static function nested(value:Array<Int>):String {
		return switch (value) {
			case [first(_) => 1, _]: "starts with one";
			case(_ : Array<Int>) => []: "none";
			case _: "other";
		}
	}

	static function person(value:{name:String, age:Int}):String {
		return switch (value) {
			case {name: _.length => 3, age: _ * 2 => 4}: "bob two";
			case _: "other";
		}
	}

	static function chained(value:String):String {
		return switch (value) {
			case _.toLowerCase() => _.charAt(0) => "q": "q";
			case _: "other";
		}
	}

	static function first(value:Int):Int {
		return value;
	}

	static function main() {
		Sys.println([size(""), size("abc"), size("42"), size("-3"), size("x"), size("y,z")].join(" "));
		Sys.println([nested([1, 2]), nested([3, 4]), nested([]), nested([5])].join(" "));
		Sys.println([person({name: "Bob", age: 2}), person({name: "Al", age: 2})].join(" "));
		Sys.println([chained("Quit"), chained("go")].join(" "));
	}
}
