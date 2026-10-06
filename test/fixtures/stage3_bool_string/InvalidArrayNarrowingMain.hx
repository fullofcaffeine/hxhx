/** Array context cannot silently narrow a Float element into an Int slot. */
class InvalidArrayNarrowingMain {
	static function main():Void {
		final values:Array<Int> = [1.5];
		Sys.println(values);
	}
}
