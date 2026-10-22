/** A concrete Float cannot silently become an integer endpoint. */
class Main {
	static function main():Void {
		final lower:Float = 1.5;
		final span = lower...4;
		for (value in span)
			trace(value);
	}
}
