/** Models an external API that accepts a Haxe Dynamic value and prints it. */
class Sink {
	public static function describe(value:Dynamic):String {
		return Std.string(value);
	}
}
