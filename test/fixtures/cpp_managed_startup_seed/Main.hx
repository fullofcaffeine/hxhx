/** A loaded sibling class can run startup code without a call from main. */
class Main {
	static function main():Void {
		Sys.println("main");
	}
}

/** The initializer's output makes silently dropping this class observable. */
class Unused {
	public static var value:Int = initialize();

	static function initialize():Int {
		Sys.println("unused");
		return 1;
	}
}
