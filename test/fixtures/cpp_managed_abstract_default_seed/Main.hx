/** Read abstract defaults during class startup without invoking an abstract conversion. */
class Main {
	public static var absent:View<Int>;
	public static var chain:Outer<Int>;
	public static var flag:Flag;
	public static var generic:Slot<Int>;
	public static var nullable:Null<Count>;
	public static var number:Count;
	public static var seen:View<Int>;

	static function __init__():Void {
		seen = absent;
	}

	public static function main():Void {}
}

/** A reference carrier makes the null representation independent of library names. */
class Carrier<T> {}

/** A generic abstract keeps its parameter when selecting the reference carrier. */
abstract View<T>(Carrier<T>) {}

/** Chained abstracts must substitute parameters at each declaration boundary. */
abstract Outer<T>(View<T>) {}

/** An Int-backed abstract has the native zero default. */
abstract Count(Int) from Int to Int {}

/** A Bool-backed abstract has the native false default. */
abstract Flag(Bool) from Bool to Bool {}

/** Substitution must select the applied type before choosing a scalar default. */
abstract Slot<T>(T) to T {}
