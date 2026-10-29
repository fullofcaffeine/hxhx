/** Observe declared annotation conversions and a contextually typed function through ordinary source. */
class Main {
	public static var calls:Int = 0;
	public static var input:Input<Int> = 7;
	public static var plain:Int = (input : Int);
	public static var effect:Effect = 7;
	public static var converted:Int = (effect : Int);
	public static var result:Int = 0;

	public static function main():Void {
		final increment = ((function(value) {
			return value + 2;
		}) : Int->Int);
		result = increment(plain);
	}
}

/** A declared output header exposes the generic backing value without an executable conversion. */
abstract Input<T>(T) from T to T {}

/** An annotation must invoke this conversion exactly once; using the backing value would return seven. */
abstract Effect(Int) from Int {
	@:to public function toInt():Int {
		Main.calls++;
		return this + 1;
	}
}
