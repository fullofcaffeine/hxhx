/** Exercises entry-class static members and local names that must remain separate. */
class Main {
	static var calls:Int = 0;
	static var entries:Int = 0;
	static var entry:Void->Void = main;

	static function next():Int {
		calls = calls + 1;
		return Main.calls;
	}

	static function read():Int
		return calls;

	static function main():Void {
		Main.entries = Main.entries + 1;
		if (Main.entries > 1) {
			Sys.println(Main.entries);
			Helper.main();
			return;
		}
		Sys.println(Main.next());
		Sys.println(next());
		final calls = 40;
		final next = (value:Int) -> value + 2;
		Sys.println(next(calls));
		Main.calls = Main.calls + 3;
		Sys.println(Main.read());
		Sys.println(calls);
		entry();
		Main.main();
	}
}

/** A method named main on another class is an ordinary static member. */
class Helper {
	static var message:String = "helper";

	public static function main():Void {
		print();
	}

	static function print():Void {
		Sys.println(message);
	}
}
