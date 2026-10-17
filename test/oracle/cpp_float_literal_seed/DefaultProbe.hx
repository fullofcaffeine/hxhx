/** Keep target-specific uninitialized Float behavior separate from literal bits. */
class DefaultProbe {
	static var value:Float;
	static var nullable:Null<Float>;

	static function main():Void {
		final observed:Dynamic = value;
		Sys.println(observed == null);
		Sys.println(Std.string(value));
		Sys.println(nullable == null);
		final values:Array<Float> = [1.0];
		Sys.println(Std.string(values[2]));
		values[3] = 2.0;
		Sys.println(Std.string(values[2]));
	}
}
