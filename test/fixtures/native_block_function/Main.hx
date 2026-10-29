/** Block closures keep captured values, lexical scopes, and their own early returns. */
class Main {
	static function make(captured:Int):Int->Int {
		return function(value:Int):Int {
			var result = value + captured;
			if (value < 0) {
				return captured;
			}
			{
				var result = 99;
				Sys.println(result);
			}
			return result;
		};
	}

	static function main():Void {
		final callback = make(10);
		Sys.println(callback(-1));
		Sys.println(callback(5));
		final boolValue = function():Bool {
			Sys.println("bool");
			return true;
		};
		final falseValue = function():Bool {
			return false;
		};
		final stringValue = function():String {
			return "text";
		};
		final effect = function():Void {
			Sys.println("effect");
			return;
		};
		Sys.println(boolValue());
		Sys.println(falseValue());
		Sys.println(1);
		Sys.println(stringValue());
		effect();
		Sys.println("after");
		final scan = function():Int {
			var n = 0;
			var total = 0;
			while (n < 5) {
				n++;
				if (n == 2)
					continue;
				if (n == 4)
					break;
				total += n;
			}
			return total;
		};
		final range = function():Int {
			for (n in 0...4) {
				if (n == 2)
					return n;
			}
			return -1;
		};
		final repeat = function():Int {
			var n = 0;
			do {
				n++;
				if (n < 3)
					continue;
			} while (n < 3);
			return n;
		};
		final nested = function():Int {
			var total = 0;
			for (outer in 0...3) {
				var inner = 0;
				while (inner < 4) {
					inner++;
					if (inner == 2)
						continue;
					if (inner == 3)
						break;
					total += outer + inner;
				}
				total += 10;
			}
			return total;
		};
		Sys.println(scan());
		Sys.println(range());
		Sys.println(repeat());
		Sys.println(nested());
		final branch = function(n:Int):Int {
			switch (n) {
				case 0:
					return 10;
				case 1:
					return 11;
				default:
					return 12;
			}
		};
		final selector = function():Int {
			Sys.println("select");
			return 1;
		};
		final selected = function():Int {
			switch (selector()) {
				case 0:
					return 20;
				case 1:
					return 21;
				default:
					return 22;
			}
		};
		Sys.println(branch(0));
		Sys.println(branch(1));
		Sys.println(branch(2));
		Sys.println(selected());
		final caught = function():String {
			try {
				throw "bad";
			} catch (error:String) {
				return error;
			}
		};
		final protectedReturn = function():Int {
			try {
				return 7;
			} catch (error:Dynamic) {
				return 99;
			}
		};
		final caughtLoop = function():Int {
			var n = 0;
			while (n < 4) {
				n++;
				try {
					if (n == 2)
						continue;
					if (n == 3)
						break;
				} catch (error:Dynamic) {
					return 99;
				}
			}
			return n;
		};
		final unmatched = function():String {
			try {
				try {
					throw "unmatched";
				} catch (number:Int) {
					return "wrong";
				}
			} catch (text:String) {
				return text;
			}
		};
		Sys.println(caught());
		Sys.println(protectedReturn());
		Sys.println(caughtLoop());
		Sys.println(unmatched());
		final booleanThrow = function():Bool {
			try {
				throw false;
			} catch (number:Int) {
				return true;
			} catch (value:Bool) {
				return value;
			}
		};
		final integerThrow = function():Int {
			try {
				throw 12;
			} catch (value:Bool) {
				return 99;
			} catch (number:Int) {
				return number;
			}
		};
		Sys.println(booleanThrow());
		Sys.println(integerThrow());
	}
}
