/** Calls the target runtime's array length function through an extern boundary. */
@:native("HxArray")
extern class RestNative {
	@:native("length")
	static function count(values:haxe.Rest<Int>):Int;
}
