/** Enum constants retain their declared abstract identity without owning property storage. */
enum abstract Code(Int) {
	var Ready = 7;

	public function number():Int
		return this;
}

enum abstract Flavor(String) {
	var Bold = "strong";

	public function label():String
		return this;
}

class Main {
	static function main():Void {
		if (Code.Ready.number() != 7)
			throw "integer enum constant changed";
		if (Flavor.Bold.label() != "strong")
			throw "string enum constant changed";
	}
}
