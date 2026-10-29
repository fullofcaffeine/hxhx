/** Record the upstream ordering contract before changing native initialization. */
class Main {
	static function argument(value:Int):Int {
		Sys.println("argument:" + value);
		return value;
	}

	static function main():Void {
		var child = Child.create(argument(7));
		Sys.println(child.value);
		child.output("callable field");
		Sys.println(child.flag);
		Sys.println(child.fromLocal);
		Sys.println(child.next());
		Sys.println(child.next());
		var forwarded = new Forwarded(argument(11));
		Sys.println(forwarded.value);
		Sys.println(forwarded.extra);
		Sys.println(forwarded.next());
		Sys.println(child.next());
		Sys.println(Early.instance.value);
		try {
			new Broken();
		} catch (error:Dynamic) {
			Sys.println(error);
		}
	}
}

class Base {
	public var value:Int;

	var initial:Int = observe("base field", 2);

	static function observe(label:String, value:Int):Int {
		Sys.println(label);
		return value;
	}

	public function new(value:Int) {
		Sys.println("base body:" + initial);
		this.value = value;
	}
}

class Child extends Base {
	var initialChild:Int = observeChild("child field", 3);
	var secondChild:Int = observeChild("child second", 4);

	public var output:Dynamic->Void = Sys.println;
	public var flag:Dynamic = true;
	public var fromLocal:Int = {
		var value = 19;
		value;
	};
	public var next:Void->Int = {
		var count = 10;
		function():Int {
			count++;
			return count;
		};
	};

	public static function create(value:Int):Child
		return new Child(value);

	static function observeChild(label:String, value:Int):Int {
		Sys.println(label);
		return value;
	}

	public function new(value:Int) {
		Sys.println("child before super");
		super(observeChild("super argument", value + 1));
		Sys.println("child after super:" + initialChild + ":" + secondChild);
	}
}

class Forwarded extends Child {
	public var extra:Int = observeExtra();

	static function observeExtra():Int {
		Sys.println("forwarded field");
		return 5;
	}
}

/** Construction during static initialization needs field helpers before the static value. */
class Early {
	public static var instance:Early = new Early();

	public var value:Int = observed();

	public function new() {}

	static function observed():Int {
		Sys.println("early field");
		return 17;
	}
}

/** A failing initializer prevents later field effects and entry into the constructor body. */
class Broken {
	var skipped:Int = unexpected();
	var failure:Int = fail();

	public function new() {
		Sys.println("unexpected constructor");
	}

	static function unexpected():Int {
		Sys.println("unexpected field");
		return 0;
	}

	static function fail():Int {
		Sys.println("failing field");
		throw "init failure";
	}
}
