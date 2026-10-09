/** The native observer compares this returned class handle with instance storage. */
class Main {
	static var selected:Class<Key> = Key;

	static function pick():Class<Key> {
		return Key;
	}

	static function value():Dynamic {
		Sys.println("value");
		return new Key();
	}

	static function target():Dynamic {
		Sys.println("type");
		return Key;
	}

	static function left():Class<Key> {
		Sys.println('left');
		return Key;
	}

	static function right():Class<Key> {
		Sys.println('right');
		return Key;
	}

	/** Native observers pass null and descriptors through the typed value boundary. */
	static function same(a:Class<Key>, b:Class<Key>):Bool {
		return a == b;
	}

	static function different(a:Class<Key>, b:Class<Key>):Bool {
		return a != b;
	}

	static function main():Void {
		Sys.println(selected != null);
		Sys.println(pick() != null);
		Sys.println(Std.isOfType(value(), target()));
		Sys.println(Std.isOfType(selected, selected));
		Sys.println(Std.isOfType(null, selected));
		Sys.println(Std.isOfType(new Key(), null));
		Sys.println(PredicateShadow.isOfType(new Key(), selected));
		Sys.println(!Std.isOfType(null, selected));
		Sys.println(!!Std.isOfType(new Key(), selected));
		Sys.println(selected == pick());
		Sys.println(selected != pick());
		final missing:Class<Key> = null;
		Sys.println(same(missing, missing));
		Sys.println(same(missing, selected));
		Sys.println(different(selected, missing));
		Sys.println(left() == right());
	}
}

/** A matching method name and signature must keep its authored behavior. */
class PredicateShadow {
	public static function isOfType(value:Dynamic, type:Dynamic):Bool {
		return false;
	}
}

/** One declared field distinguishes a real layout from an identity-only descriptor. */
class Key {
	public var id:Int;

	public function new() {
		id = 7;
	}
}
