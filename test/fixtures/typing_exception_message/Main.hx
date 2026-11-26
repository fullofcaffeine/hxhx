/**
	`Helper` (typed after `Main`) gives `Main.show`'s omitted input its type, so typing finalizes
	`Main` again in method-input finalization (`TyMethodInputPublication.finish`).
**/
class Main {
	public static function show(value) {
		Sys.println(value);
	}

	static function main() {
		Helper.run();
	}
}
