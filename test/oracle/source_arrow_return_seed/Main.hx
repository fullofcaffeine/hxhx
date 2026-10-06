/** A return inside an arrow block exits that arrow, not the enclosing main function. */
class Main {
	static function main():Void {
		final read = () -> {
			return 7;
		};
		if (read() != 7)
			throw "arrow returned from the wrong function";
	}
}
