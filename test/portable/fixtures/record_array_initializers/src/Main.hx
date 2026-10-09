/** Each construction must allocate both arrays and retain the following field. */
private class Holder {
	public var first:Array<Int> = [];
	public var second:Array<Int> = [];
	public var count:Int = 7;

	public function new() {}
}

/** Native compilation and output expose record grouping and shared-array mistakes. */
class Main {
	static function main():Void {
		final left = new Holder();
		final right = new Holder();
		left.first.push(11);
		left.second.push(22);
		Sys.println(left.first[0]);
		Sys.println(left.second[0]);
		Sys.println(right.first.length);
		Sys.println(right.second.length);
		Sys.println(left.count);
		Sys.println(right.count);
	}
}
