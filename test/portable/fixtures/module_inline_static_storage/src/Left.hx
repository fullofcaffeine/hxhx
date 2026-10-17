/** Inline constants must not allocate static cells when this module has two classes. */
class Left {
	@:keep public static inline var TEXT:String = "ready";
	@:keep public static inline var NUMBER:Int = 5;
	@:keep public static inline var FLAG:Bool = true;

	public static function value(n:Int):Int {
		return n == 0 ? 0 : Right.value(n - 1) + 1;
	}
}

/** Its use retains a second concrete class and exercises module storage planning. */
class Secondary {
	public static function value():Int {
		return 1;
	}
}
