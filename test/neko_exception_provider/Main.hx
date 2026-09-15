/** Checks the selected exception provider before catch dispatch changes. */
class Main {
	static function main():Void {
		final original = new haxe.Exception("problem");
		try {
			throw original;
		} catch (caught:haxe.Exception) {
			Sys.println(caught.message);
			Sys.println(caught == original ? "same-exception" : "changed-exception");
		}
		try {
			throw "primitive";
		} catch (caught:haxe.Exception) {
			Sys.println(caught.message);
		}
		// Dynamic is the raw language exception boundary; inspect it immediately.
		try {
			throw "raw";
		} catch (caught:Dynamic) {
			Sys.println(caught == "raw" ? "raw-preserved" : "raw-changed");
		}
	}
}
