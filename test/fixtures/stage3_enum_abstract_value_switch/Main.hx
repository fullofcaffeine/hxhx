/**
	Value switches over an Int-backed enum abstract with no default arm. Both
	switches name every declared value (one through an alternative), so upstream
	Haxe 4.3.7 treats them as exhaustive. The `label` method mirrors std
	`XmlType.toString`, which switches over `(cast this : XmlType)`.
 */
enum abstract Kind(Int) {
	var Alpha = 0;
	var Beta = 1;
	var Gamma = 2;

	public function label():String {
		return switch (cast this : Kind) {
			case Alpha: "alpha";
			case Beta: "beta";
			case Gamma: "gamma";
		};
	}
}

class Main {
	static function name(kind:Kind):String {
		return switch kind {
			case Alpha: "A";
			case Beta | Gamma: "BG";
		};
	}

	static function main() {
		Sys.println(name(Kind.Alpha) + name(Kind.Gamma));
		Sys.println(Kind.Beta.label());
	}
}
