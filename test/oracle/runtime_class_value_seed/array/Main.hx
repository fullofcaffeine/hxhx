/** A checked erased array keeps its category and shares storage after recovery. */
class Main {
	static final selected:Class<Array<Bool>> = Array;
	static final original:Array<Bool> = [true];

	// This isolated probe deliberately crosses Haxe's Dynamic boundary. Its only
	// producer owns an Array<Bool>; the consumer checks the category before recovery.
	static function erase():Dynamic
		return original;

	static function main():Void {
		final value = erase();
		if (!Std.isOfType(value, selected))
			throw "lost array category";
		final recovered:Array<Bool> = value;
		recovered[0] = false;
		Sys.println(Std.isOfType(value, selected));
		Sys.println(Std.isOfType(null, selected));
		Sys.println(Std.isOfType(value, null));
		Sys.println(Std.isOfType(selected, Array));
		Sys.println(selected == Array);
		Sys.println(original[0]);
		original.push(true);
		Sys.println(recovered.length);
	}
}
