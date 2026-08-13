typedef FieldTextAlias = String;

/** Exercises direct `String.length` reads through generated and compiled OCaml. */
class Main {
	static var receiverCalls = 0;
	static final standaloneLength = "root".length;

	/** Returns a String and records each evaluation of this receiver. */
	static function receiver():String {
		receiverCalls++;
		return "side";
	}

	static function main():Void {
		final text = "local";
		final alias:FieldTextAlias = "alias";
		final nested = () -> "nested".length;

		Sys.println("local=" + text.length);
		Sys.println("alias=" + alias.length);
		Sys.println("standalone=" + standaloneLength);
		Sys.println("nested=" + nested());
		Sys.println("side=" + receiver().length);
		Sys.println("receiverCalls=" + receiverCalls);
	}
}
