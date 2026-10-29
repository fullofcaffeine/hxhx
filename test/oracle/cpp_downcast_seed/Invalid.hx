/** The destination must satisfy the source type bound even though mismatching values can return null. */
class Invalid {
	static function main():Void {
		Std.downcast(new Sibling(), Child);
	}
}

class Base {
	public function new() {}
}

class Sibling extends Base {}
class Child extends Base {}
