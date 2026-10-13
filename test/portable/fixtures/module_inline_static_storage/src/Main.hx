/** Observe the constants and both classes after native module initialization. */
class Main {
	static function main():Void {
		Sys.println(Left.TEXT);
		Sys.println(Left.NUMBER);
		Sys.println(Left.FLAG);
		Sys.println(Right.value(3) + Left.Secondary.value());
	}
}
