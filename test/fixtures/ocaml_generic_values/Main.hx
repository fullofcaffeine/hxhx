/** Generic bodies observe values and return them without changing their source type. */
class GenericValues {
	public var calls:Int = 0;

	public function new() {}

	public function echo<T>(value:T):T {
		calls++;
		return value;
	}

	public function text<T>(value:T):String
		return Std.string(value);
}

/** Independent output distinguishes Boolean carriers from native integer immediates. */
class Main {
	static function text<T>(value:T):String
		return Std.string(value);

	static function echo<T>(value:T):T
		return value;

	static function forward<T>(value:T):T
		return echo(value);

	static function produce<T>(get:() -> T):T
		return get();

	static function second<T>(left:T, right:T):T
		return right;

	static function count<T>(values:Array<T>):Int
		return values.length;

	static function main():Void {
		if (count([true, false]) != 2)
			throw "unchanged generic container interface";
		Sys.println(text(true));
		Sys.println(text(1));
		Sys.println(text(false));
		Sys.println(text(0));
		if (!echo(true) || echo(false) || echo(7) + 1 != 8)
			throw "direct generic result";
		if (!forward(true) || forward(false))
			throw "generic forwarding";
		if (!produce(function():Bool return true))
			throw "generic callback result";
		var choose:Bool->Bool->Bool = second;
		if (!choose(false, true) || choose(true, false))
			throw "generic multi-argument capture";
		var staticTruth:Bool->Bool = echo;
		if (!staticTruth(true) || staticTruth(false))
			throw "static generic capture";
		final values = new GenericValues();
		var truth:Bool->Bool = values.echo;
		var number:Int->Int = values.echo;
		var decimal:Float->Float = values.echo;
		var printed:Bool->String = values.text;
		if (values.calls != 0)
			throw "eager capture";
		if (!truth(true) || truth(false) || number(7) + 1 != 8 || decimal(1.5) != 1.5)
			throw "instance generic capture";
		if (values.calls != 4)
			throw "capture invocation count";
		Sys.println(printed(true));
		Sys.println(printed(false));
		Sys.println("generic-values-ok");
	}
}
