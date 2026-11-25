/** An element that is not a subclass of the expected element type must still be rejected. **/
class Base {
	public function new() {}
}

class Other {
	public function new() {}
}

class Wrong {
	static function main() {
		final items:Array<Base> = [new Other()];
		Sys.println(items.length);
	}
}
