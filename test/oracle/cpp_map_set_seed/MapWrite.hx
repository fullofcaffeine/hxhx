/** Public Map mutation preserves each typed callback and its authored evaluation order. */
class MapWrite {
	public static function strings(receiver:Void->Map<String, Bool>, key:Void->String, value:Void->Bool):Void
		receiver().set(key(), value());

	public static function integers(receiver:Void->Map<Int, String>, key:Void->Int, value:Void->String):Void
		receiver().set(key(), value());

	public static function number(receiver:Void->Map<String, Float>, key:Void->String, value:Void->Int):Void
		receiver().set(key(), value());

	public static function objects(receiver:Void->Map<{id:Int}, {name:String}>, key:Void->{id: Int}, value:Void->{name: String}):Void
		receiver().set(key(), value());
}

/** Matching method spelling and argument types do not grant standard Map ownership. */
class Other {
	public function new() {}

	public function set(key:String, value:Bool):Void {}

	public static function invoke(receiver:Other):Void
		receiver.set("item", true);
}
