package pk;

/** An abstract with `@:using` whose provider takes the abstract's `to` type. **/
@:using(pk.Meter.MeterTools)
abstract Meter(Int) to Int {
	public inline function new(value:Int)
		this = value;
}

class MeterTools {
	public static function doubled(value:Int):Int
		return value * 2;
}
