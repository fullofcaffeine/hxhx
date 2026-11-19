class Main {
	static function maybeInt(present:Bool):Null<Int>
		return present ? 4 : null;

	static function maybeFloat(present:Bool):Null<Float>
		return present ? 1.5 : null;

	static function maybeBool(present:Bool):Null<Bool>
		return present ? true : null;

	static function main() {
		Sys.println("present " + maybeInt(true) + " " + maybeFloat(true) + " " + maybeBool(true));
		final assigned:Int = maybeInt(false);
		final widened:Float = maybeInt(false);
		final flag:Bool = maybeBool(false);
		Sys.println("assign int=" + assigned + " float=" + widened + " bool=" + flag);
		final n = maybeInt(false);
		Sys.println("int operand " + (maybeInt(false) + 1));
		final f = maybeFloat(false);
		Sys.println("float operand " + (f * 2));
		final b = maybeBool(false);
		Sys.println("bool operand " + (b ? "yes" : "no") + " " + !b);
		final joined:Int = n != null ? 3 : maybeInt(false);
		Sys.println("branch " + joined);
	}
}
