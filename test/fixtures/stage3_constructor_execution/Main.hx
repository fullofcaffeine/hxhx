/** Observe constructor bodies, parent calls, and argument order without relying on field initializers. */
class Main {
	static function observed(value:Int):Int {
		Sys.println("argument " + value);
		return value;
	}

	static function defaultFlag(value:Bool = true):Bool
		return value;

	static function main():Void {
		var child = new Child(7);
		Sys.println(child.value);
		var pair = new Pair(observed(1), observed(2));
		Sys.println(pair.first);
		Sys.println(pair.second);
		var flag = new Flag(true);
		Sys.println(flag.value);
		var forwarded = new Forwarded(42);
		Sys.println(forwarded.value);
		var defaults = new Defaults();
		Sys.println(defaults.value);
		var supplied = new Defaults(0);
		Sys.println(supplied.value);
		new Many(observed(3), observed(4));
		var spread = [5, 6];
		new Many(...spread);
		new Many();
		new ForwardRest(7, 8);
		Sys.println(defaultFlag());
		Sys.println(defaultFlag(false));
	}
}

class Base {
	public var value:Int;

	public function new(value:Int) {
		Sys.println("base constructor");
		this.value = value;
	}
}

class Child extends Base {
	public function new(value:Int) {
		super(value + 1);
		Sys.println("child constructor");
	}
}

class Forwarded extends Child {}

class Pair {
	public var first:Int;
	public var second:Int;

	public function new(left:Int, right:Int) {
		Sys.println("pair constructor");
		first = right;
		second = left;
	}
}

class Flag {
	public var value:Dynamic;

	public function new(value:Dynamic) {
		this.value = value;
	}
}

class Defaults {
	public var value:Int;

	public function new(value:Int = 9) {
		this.value = value;
	}
}

class Many {
	public function new(...values:Int) {
		Sys.println(values.length);
		for (value in values)
			Sys.println(value);
	}
}

class ForwardRest extends Many {
	public function new(...values:Int) {
		super(...values);
	}
}
