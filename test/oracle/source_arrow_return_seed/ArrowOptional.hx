/** An optional scalar retains null until source code selects a value. */
class ArrowOptional {
	static function main():Void {
		final read = (?value:Int) -> value == null ? 7 : value;
		if (read() != 7 || read(null) != 7 || read(8) != 8)
			throw "optional arrow argument lost null";
	}
}
