/** Static function values retain their declaration, identity, and callee-owned defaults. */
class Main {
	static final initial:Int->Int = increment;

	static function consume(value:Int):Void
		Sys.println(value);

	static function twice(value:Int):Int
		return value * 2;

	static function increment(value:Int):Int
		return value + 1;

	static function withDefault(value:Int = 9):Int
		return value;

	static function prime():Void {
		final cached = twice;
		cached(0);
	}

	static function integerIdentity(value:Int):Int
		return value;

	static function booleanIdentity(value:Bool):Bool
		return value;

	/** Static methods and equivalent closures must apply the same target-specific null conversion. */
	static function checkNullTransport():Void {
		final integerMethod:Null<Int>->Null<Int> = integerIdentity;
		final integerClosure:Null<Int>->Null<Int> = function(value:Int):Int return value;
		if (integerMethod(null) != integerClosure(null))
			throw "static and closure Int transport differ";
		final booleanMethod:Null<Bool>->Null<Bool> = booleanIdentity;
		final booleanClosure:Null<Bool>->Null<Bool> = function(value:Bool):Bool return value;
		if (booleanMethod(null) != booleanClosure(null))
			throw "static and closure Bool transport differ";
	}

	static function main():Void {
		prime();
		checkNullTransport();
		consume({
			var value = 7;
			value;
		});
		final stored = twice;
		Sys.println(stored(4));
		final again = Main.twice;
		Sys.println(stored == again);
		final other = increment;
		Sys.println(stored == other);
		var twice:Int->Int = increment;
		Sys.println(twice(4));
		final defaulted = withDefault;
		Sys.println(defaulted());
		Sys.println(initial == other);
		final controlled = NumberTools.twice({
			var argument = 6;
			argument;
		});
		Sys.println(controlled);
		final abstractMethod = NumberTools.twice;
		Sys.println(abstractMethod(8));
		final qualified = Main.NumberTools.twice;
		Sys.println(qualified == abstractMethod);
		{
			final NumberTools = {twice: function(value:Int):Int return value + 100};
			Sys.println(NumberTools.twice(3));
		}
	}
}

/** An abstract can own static methods without being a runtime class object. */
abstract NumberTools(Int) {
	public static function twice(value:Int):Int
		return value * 2;
}
