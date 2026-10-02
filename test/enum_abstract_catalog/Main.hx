/** Execute the exact declaration fixture with upstream Haxe as a behavior oracle. */
class Main {
	static function main():Void {
		var value:Counter<Int> = 1;
		final negated:Int = -value;
		final prefix:Int = ++value;
		final postfix:Int = value++;
		if (negated != -1 || prefix != 2 || postfix != 2 || value.read() != 3 || value.read(4) != 7)
			throw "enum-abstract operator result or receiver mutation changed";
		if (Counter.One != 1 || Counter.Three != 3)
			throw "enum-abstract values changed";
		Sys.println("ENUM_ABSTRACT_UPSTREAM:PASS");
	}
}
