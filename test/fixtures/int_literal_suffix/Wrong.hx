/** A suffixed integer literal is an Int, not a String: upstream reports `Int should be String`. */
class Wrong {
	static function main() {
		final text:String = 7i32;
		Sys.println(text);
	}
}
