class Hidden {
	function new() {}
}

class WrongPrivate {
	@:generic static function make<Cls:haxe.Constraints.Constructible<() -> Void>>(c:Class<Cls>):Cls
		return new Cls();

	static function main() {
		make(Hidden);
	}
}
