/** Concrete full-function defaults preserve entry values, mutations, and escaping captures. */
class FullFunctionDefaults {
	static function main():Void {
		function read(value:Int = 5):Int {
			value++;
			return value;
		}
		final anonymous = function(value = 5) {
			value++;
			return value;
		};
		function optional(?value:Int = 5):Int
			return value;
		if (read() != 6 || read(null) != 6 || read(8) != 9)
			throw "named function default or parameter update changed";
		if (anonymous() != 6 || anonymous(null) != 6 || anonymous(8) != 9)
			throw "anonymous function inferred default changed";
		if (optional() != 5 || optional(null) != 5 || optional(8) != 8)
			throw "question-mark default changed";
		function make(value:Int = 5):Void->Int {
			value++;
			return () -> value;
		}
		if (make()() != 6 || make(8)() != 9)
			throw "captured full-function default lost its entry value";
		var order = 0;
		function first():Int {
			order = order * 10 + 1;
			return 2;
		}
		function second():Int {
			order = order * 10 + 2;
			return 3;
		}
		function combine(left:Int = 7, right:Int = 9):Int
			return left * 10 + right;
		if (combine(first(), second()) != 23 || order != 12)
			throw "defaulted function changed supplied operand order";
	}
}
