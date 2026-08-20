/** Proves nullable Boolean results independently from an unsupported parameter ABI. */
class Main {
	static function hasValues(values:Array<Int>):Null<Bool> {
		if (values == null)
			return null;
		return values.length > 0;
	}

	static function main():Void {
		Sys.println("missing=" + (hasValues(null) == null));
		Sys.println("empty=" + hasValues([]));
		Sys.println("present=" + hasValues([1]));
	}
}
