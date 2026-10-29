/** Ordinary String fields and an effectful receiver share the same length contract. */
class StringLength {
	public static function read(value:String):Int {
		return value.length;
	}

	public static function boundary(value:Void->String):Int {
		return value().length;
	}

	public static function shadow(value:LengthOwner):Int {
		return value.length;
	}
}

/** A same-named authored field must retain ordinary class storage. */
class LengthOwner {
	public var length:Int = 42;

	public function new() {}
}
