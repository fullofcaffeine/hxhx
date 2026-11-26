class WrongResult {
	static function add(a:Int, b:Int):Int
		return a + b;

	static function main() {
		final text:String = add.bind(1)(2);
	}
}
