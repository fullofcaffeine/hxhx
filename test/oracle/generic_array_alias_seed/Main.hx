typedef Buffer = Array<Int>;

/** An alias constructor must supply the same semantic type as its target constructor. */
class Main {
	static function retain<T>(values:Array<T>, count:Int):Array<T> {
		return values;
	}

	static function main():Void {
		final values = new Buffer();
		retain(values, 2);
		Sys.println(values.length);
	}
}
