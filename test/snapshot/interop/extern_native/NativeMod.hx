@:native("Native.Mod")
extern class NativeMod {
	@:native("hello_world")
	static function hello():String;

	// Full-path override should bypass the class' @:native module mapping.
	@:native("Native.Other.goodbye")
	static function goodbye():String;
}
