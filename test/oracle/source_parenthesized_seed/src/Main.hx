/** Grouping preserves assignment destinations, callable selection, and evaluation order. */
class Main {
	static function addOne(value:Int):Int
		return value + 1;

	static function __hxhx_parenthesized(value:Int):Int
		return value + 100;

	static function main():Void {
		var value = 1;
		value = 4;
		var assigned = ((value = 7));
		var callable = (function(input:Int):Int {
			return input + 2;
		});
		Sys.println((1 + 2) * 3);
		Sys.println(value);
		Sys.println(assigned);
		Sys.println(((addOne))(5));
		Sys.println((callable)(3));
		Sys.println(__hxhx_parenthesized(2));
	}
}
