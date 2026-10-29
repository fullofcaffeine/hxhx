/** A destination type must not conceal an incompatible array element. */
class InvalidArrayMain {
	static function main():Void {
		final values:Array<Int> = [false];
		Sys.println(values);
	}
}
