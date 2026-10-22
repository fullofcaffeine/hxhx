import choices.Choice;

/** Same-module constructors must remain accessible without a self-module prefix. */
enum LocalChoice {
	LocalEmpty;
	LocalPair(count:Int, label:String);
}

/** Exercises typed enum reflection across a module boundary. */
class Main {
	static var evaluations:Int = 0;

	static function describe(choice:Choice):String {
		return Type.enumConstructor(choice);
	}

	static function produce():Choice {
		evaluations++;
		return Pair(7, "seven");
	}

	static function main():Void {
		Sys.println(describe(Empty));
		Sys.println(describe(Pair(7, "seven")));
		final local = LocalPair(8, "eight");
		Sys.println(Type.enumConstructor(local));
		Sys.println(Type.enumConstructor(produce()));
		Sys.println(evaluations);
	}
}
