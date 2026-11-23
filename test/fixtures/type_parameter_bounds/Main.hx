/**
	Members read through a type parameter's bounds, abstract headers with braces before the body,
	and a field assignment that binds a generic instance's type argument, as in Haxe 4.3.7
	(haxe.ds.HashMap).
**/
class Base {
	public function new() {}

	public function code():Int
		return 1;
}

typedef Coded = {function code():Int;}

class Key {
	public var id:Int;

	public function new(id:Int)
		this.id = id;

	public function hashCode():Int
		return id;

	public function code():Int
		return id * 10;
}

/** The constraint's braces come before the body: the scanner must not read them as it. **/
abstract Table<K:{function hashCode():Int;}, V>(Array<V>) {
	public inline function new()
		this = [];

	public inline function set(k:K, v:V)
		this[k.hashCode()] = v;

	public inline function get(k:K)
		return this[k.hashCode()];
}

/** The underlying type's braces come before the body. **/
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

class Ops {
	/** A class bound supplies `code`. **/
	public static function viaClass<T:Base>(t:T)
		return t.code();

	/** A typedef bound supplies `code`. **/
	public static function viaTypedef<T:Coded>(t:T)
		return t.code();

	/** A short structure bound supplies `id`. **/
	public static function viaShort<T:{id:Int}>(t:T)
		return t.id;

	/** A declaration-form structure bound keeps `function hashCode` as written. **/
	public static function hash<K:{function hashCode():Int;}>(k:K)
		return k.hashCode();

	/** The field assignment binds `new Box()`'s type argument (HashMap.copy). **/
	public static function fill(source:Array<Int>) {
		var box = new Box();
		box.items = source.copy();
		return box;
	}
}

class Main {
	static function main() {
		Sys.println(Ops.viaClass(new Base()) + " " + Ops.viaTypedef(new Key(4)) + " " + Ops.viaShort(new Key(5)) + " " + Ops.hash(new Key(6)));
		final table = new Table<Key, String>();
		table.set(new Key(3), "three");
		Sys.println(table.get(new Key(3)) + " " + new Point(2, 5).sum() + " " + Ops.fill([1, 2]).items.length);
	}
}
