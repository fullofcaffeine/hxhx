/**
	The shapes frozen Stage3 can run: it cannot emit generic methods with constraints or call a
	method on a type parameter value, on main too.
**/
abstract Point({x:Int, y:Int}) {
	public inline function new(x:Int, y:Int)
		this = {x: x, y: y};

	public inline function sum()
		return this.x + this.y;
}

class Box<T> {
	public var items:Array<T>;

	public function new()
		items = [];
}

class Main {
	static function fill(source:Array<Int>) {
		var box = new Box();
		box.items = source.copy();
		return box;
	}

	static function main() {
		Sys.println(new Point(2, 5).sum() + " " + fill([1, 2]).items.length + " " + fill([3]).items[0]);
	}
}
