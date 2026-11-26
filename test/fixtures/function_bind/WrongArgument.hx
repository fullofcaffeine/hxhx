class WrongArgument {
	static function add(a:Int, b:Int):Int
		return a + b;

	static function main() {
		final f = add.bind("x");
	}
}
