/** A user-defined array carrier, unrelated to the standard Rest implementation. */
abstract Buffer<T>(Array<T>) from Array<T> to Array<T> {
	public var length(get, never):Int;

	inline function get_length():Int
		return this.length;

	@:arrayAccess public inline function get(index:Int):T
		return this[index];
}

/** A second abstract checks that type parameters survive the whole carrier chain. */
abstract Nested<T>(Buffer<T>) from Buffer<T> to Buffer<T> {
	public var length(get, never):Int;

	inline function get_length():Int
		return this.length;
}

class Main {
	static final source:Array<Int> = [4, 5];
	static var calls:Int = 0;

	static function produce():Array<Int> {
		calls++;
		return source;
	}

	static function main():Void {
		final value:Buffer<Int> = cast(produce() : Dynamic);
		final any:Any = source;
		final implicit:Buffer<Int> = any;
		final nested:Nested<Int> = cast any;
		source.push(6);
		Sys.println("explicit=" + value.length + "," + value[2]);
		Sys.println("implicit=" + implicit.length + "," + implicit[2]);
		Sys.println("nested=" + nested.length);
		Sys.println("same=" + ((value : Array<Int>) == source) + ",calls=" + calls);
	}
}
