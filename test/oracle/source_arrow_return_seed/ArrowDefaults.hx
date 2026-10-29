/** Defaults apply at entry, before updates to the parameter's own storage. */
class ArrowDefaults {
	static function main():Void {
		final read = (value:Int = 5) -> {
			value++;
			return value;
		};
		if (read() != 6 || read(null) != 6 || read(8) != 9)
			throw "arrow default or parameter update changed";
		final make = (value:Int = 5) -> {
			value++;
			return () -> value;
		};
		if (make()() != 6 || make(8)() != 9)
			throw "captured default parameter lost its entry value";
	}
}
