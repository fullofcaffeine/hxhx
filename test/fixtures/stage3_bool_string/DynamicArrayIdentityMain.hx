/** Erasing an array type must preserve its identity and later element mutations. */
class DynamicArrayIdentityMain {
	/** Dynamic is the conversion boundary under test; consume it only through Std.string. */
	static function text(value:Dynamic):String {
		return Std.string(value);
	}

	static function produced():Array<Bool> {
		Sys.println("producer");
		return [false, true];
	}

	static function main():Void {
		final flags:Array<Bool> = [true, false];
		// Retain the erased alias before mutation: copying at this boundary is incorrect.
		final erased:Dynamic = flags;
		Sys.println(text(erased));
		final numbers:Array<Int> = [1, 0];
		Sys.println(text(numbers));
		flags[0] = false;
		flags.push(true);
		Sys.println(text(erased));
		Sys.println(Std.string(erased == flags));
		Sys.println(text(numbers));
		final nested:Array<Array<Bool>> = [flags];
		final erasedNested:Dynamic = nested;
		Sys.println(text(erasedNested));
		flags[1] = true;
		Sys.println(text(erasedNested));
		final empty:Array<Bool> = [];
		final erasedEmpty:Dynamic = empty;
		Sys.println(text(erasedEmpty));
		empty.push(false);
		Sys.println(text(erasedEmpty));
		Sys.println(text(produced()));
		final absent:Null<Array<Bool>> = null;
		Sys.println(text(absent));
	}
}
