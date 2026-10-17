/** Upstream rejects narrowing a stored class handle, unlike contextual use of the Array literal. */
class Narrowing {
	static function main():Void {
		final erased:Class<Array<Dynamic>> = Array;
		final narrowed:Class<Array<Bool>> = erased;
		Sys.println(narrowed == Array);
	}
}
