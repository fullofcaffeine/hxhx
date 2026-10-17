import Mixed.Helper;

/** Type providers stay available while only actual declarations produce native code. */
class Main {
	static function main():Void {
		final record:Record = {count: 3};
		final mixed:Mixed = 5;
		Sys.println(record.count);
		Sys.println(mixed);
		Sys.println(Helper.value());
		Sys.println(Unknown.value());
	}
}
