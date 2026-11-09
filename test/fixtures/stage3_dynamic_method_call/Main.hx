/**
	Calls class methods through `Dynamic` receivers and prints each result.
	The native Stage3 program must print exactly what upstream Haxe prints.
**/
class Base {
	public function new() {}

	public function pick(?x:Int):String
		return "base:" + x;

	public function inherited():String
		return "inherited";

	public function add(a:Int, b:Int):Int
		return a + b;

	public function withDefault(x:Int = 7):Int
		return x * 2;

	public function label(name:String, ?suffix:String):String
		return name + "/" + suffix;

	public function half(value:Float):Float
		return value / 2;

	public function negate(flag:Bool):Bool
		return !flag;

	public function touch():Void
		Sys.println("touched");

	public function optionalPair(?x:Float, ?y:Bool):String
		return x + "/" + y;

	public inline function inlined():String
		return "inlined";

	public dynamic function replaceable():String
		return "replaceable";
}

class Late extends Base {
	public function new() {
		super();
	}

	override public function pick(?x:Int):String
		return "late:" + x;

	public function own():String
		return "own";
}

class Leaf extends Late {
	public function new() {
		super();
	}
}

class Other {
	public function new() {}

	public function pick():String
		return "other";

	public function callPick(value:Dynamic):String
		return value.pick();
}

interface Named {
	function name():String;
}

class Person implements Named {
	public var callback:Int->Int;

	public function new() {
		callback = value -> value + 100;
	}

	public function name():String
		return "person";
}

class Main {
	static function attempt(label:String, action:() -> Void):Void {
		try {
			action();
		} catch (error:Dynamic) {
			Sys.println(label + ": caught");
		}
	}

	static function tick(label:String, value:Int):Int {
		Sys.println(label);
		return value;
	}

	static function provide():Dynamic
		return new Late();

	static function main() {
		final late:Dynamic = new Late();
		Sys.println(late.pick());
		Sys.println(late.pick(4));
		Sys.println(late.inherited());
		Sys.println(late.own());
		Sys.println(late.add(2, 3));
		Sys.println(late.withDefault());
		Sys.println(late.withDefault(5));
		Sys.println(late.label("a"));
		Sys.println(late.label("a", "b"));
		Sys.println(late.half(3.0));
		Sys.println(late.half(3));
		Sys.println(late.negate(true));
		Sys.println(late.negate(false) ? "yes" : "no");
		late.touch();

		Sys.println(late.optionalPair());
		Sys.println(late.optionalPair(2.5, true));
		Sys.println(late.optionalPair(1.5, false));
		Sys.println(late.inlined());
		Sys.println(late.replaceable());
		Sys.println(late.add(tick("first", 1), tick("second", 2)));
		final flag:Dynamic = false;
		Sys.println(late.negate(flag));

		final leaf:Dynamic = new Leaf();
		Sys.println(leaf.pick());
		Sys.println(leaf.inherited());
		Sys.println(new Other().callPick(leaf));

		Sys.println(provide().pick());
		final list:Array<Dynamic> = [late];
		Sys.println(list[0].pick());
		final holder:Dynamic = {inner: late};
		Sys.println(holder.inner.pick());

		final base:Dynamic = new Base();
		Sys.println(base.pick());

		final person:Dynamic = new Person();
		Sys.println(person.name());
		Sys.println(person.callback(1));

		final stored:Dynamic = {answer: () -> 42, plus: (value:Int) -> value + 1};
		Sys.println(stored.answer());
		Sys.println(stored.plus(1));

		attempt("missing method", () -> late.absent());
		attempt("not a function", () -> {
			final value:Dynamic = {f: 5};
			value.f();
		});
		attempt("missing field", () -> stored.absent());
		final nothing:Dynamic = null;
		attempt("null receiver", () -> nothing.pick());
	}
}
