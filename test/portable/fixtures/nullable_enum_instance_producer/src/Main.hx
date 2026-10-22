/** A native enum returned through an instance method with a nullable result. */
enum Value {
	Item(value:Int);
}

/** Keeps the exact enum producer separate from the nullable result boundary. */
class Reader {
	public function new() {}

	static function make():Value
		return Item(7);

	public function read(ok:Bool):Null<Value> {
		if (!ok)
			return null;
		return make();
	}
}

/** Checks present payloads and early null returns against upstream behavior. */
class Main {
	static function main() {
		final r = new Reader();
		switch r.read(true) {
			case Item(n):
				Sys.println(n);
			case null:
				throw "missing";
		}
		Sys.println(r.read(false) == null);
	}
}
