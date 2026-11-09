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
		return x + "/" + (y == null ? "null" : (y ? "T" : "F"));

	public inline function inlined():String
		return "inlined";

	public dynamic function replaceable():String
		return "replaceable";
}

abstract Meters(Float) from Float to Float {}
abstract Count(Int) from Int to Int {}
abstract Flag(Bool) from Bool to Bool {}

class Late extends Base {
	public function new() {
		super();
	}

	override public function pick(?x:Int):String
		return "late:" + x;

	public function own():String
		return "own";

	public function me():Late
		return this;

	public function yes(flag:Bool):Bool
		return flag;

	public function defaultBool(flag:Bool = true):Bool
		return flag;

	public function defaultQuarter(value:Float = 1.5):Float
		return value * 0.25;

	public function nullableBool(?flag:Bool):String
		return flag == null ? "null" : (flag ? "T" : "F");

	public function meters(value:Meters):Float
		return (value : Float) * 0.25;

	public function count(value:Count):Int
		return (value : Int) + 1;

	public function flagged(value:Flag):String
		return (value : Bool) ? "T" : "F";

	public function same<T>(value:T):T
		return value;

	public function sameGeneric(other:Dynamic):Int
		return other.same(3);

	public function secondOf<T>(value:T, second:Int):Int
		return second;

	public function describe(value:Dynamic):String
		return Std.string(value);
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

enum abstract Level(Int) {
	var Low = 0;
	var High = 1;
}

/** Calls inside a class that has same-named methods. The receiver's type decides the call. */
class Scoped {
	public function new() {}

	public function flag(value:Bool):String
		return value ? "T" : "F";

	public function yes(value:Bool):Bool
		return value;

	public function nested(other:Dynamic):String
		return other.flag(other.yes(false));

	public function compared(other:Dynamic):Bool
		return other.yes(false) == false;

	public function direct(other:Dynamic):String
		return flag(other.yes(false));

	public function level(value:Level):String
		return value == High ? "H" : "L";
}

class Holder {
	public function new() {}

	public function flag(value:Bool):String
		return value ? "T" : "F";
}

class Main {
	static function no():Bool
		return false;

	static function always():Bool
		return true;

	static function dflt(?x:Int):String
		return "x=" + x;

	static function defI(x:Int = 7):Int
		return x + 1;

	static function twice(x:Float):Float
		return x * 0.5;

	static function show(x:Dynamic):String
		return Std.string(x);

	static function viaReturn(value:Dynamic):Bool
		return value.yes(false);

	static function takeB(value:Bool):String
		return value ? "T" : "F";

	static function logged(label:String, value:Dynamic):Dynamic {
		Sys.println("receiver " + label);
		return value;
	}

	static function nest(value:Int):Int
		return value + 1;

	static function sameFlag(value:Bool):String
		return value ? "T" : "F";

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

		final storedFlags:Dynamic = {flag: sameFlag, bound: new Holder().flag};
		Sys.println(storedFlags.flag(false));
		Sys.println(storedFlags.flag(true));
		Sys.println(storedFlags.bound(false));

		Sys.println(late.defaultBool());
		Sys.println(late.defaultBool(false));
		Sys.println(late.defaultBool(true));
		Sys.println(late.defaultQuarter());
		Sys.println(late.defaultQuarter(3));
		Sys.println(late.nullableBool());
		Sys.println(late.nullableBool(false));
		Sys.println(late.nullableBool(true));

		Sys.println(late.me().own());
		Sys.println(late.me().me().pick());
		if (!late.yes(false))
			Sys.println("branch taken");
		else
			Sys.println("branch skipped");
		Sys.println(!late.yes(true));
		Sys.println(late.yes(false) && true);
		Sys.println(late.yes(false) || false);
		Sys.println(late.yes(true) == true);
		Sys.println(late.yes(false) == false);
		Sys.println(late.half(2) == 1);
		Sys.println(late.add(1, 2) == 3.0);

		Sys.println(late.meters(3));
		Sys.println(late.meters(1.5));
		Sys.println(late.count(3));
		Sys.println(late.flagged(false));

		Sys.println(late.same(3));
		Sys.println(late.same("text"));
		Sys.println(late.same(1.5));
		Sys.println(late.same(true));
		Sys.println(late.secondOf("first", 4));
		Sys.println(new Late().sameGeneric(late));
		Sys.println(late.describe(true));
		Sys.println(late.describe(false));

		final storedBools:Dynamic = {n: no, y: always};
		if (!storedBools.n())
			Sys.println("stored branch taken");
		Sys.println(!storedBools.y());
		Sys.println(storedBools.n() && true);
		Sys.println(storedBools.y() || false);
		Sys.println(storedBools.y() == true);
		Sys.println(storedBools.n() == false);
		final fromStored:Bool = storedBools.n();
		Sys.println(fromStored);

		final scoped:Dynamic = new Scoped();
		final inScope = new Scoped();
		Sys.println(inScope.nested(scoped));
		Sys.println(inScope.compared(scoped));
		Sys.println(inScope.direct(scoped));
		final highest:Level = High;
		Sys.println(scoped.level(highest));
		Sys.println(scoped.level(High));

		Sys.println(viaReturn(late));
		Sys.println(takeB(late.yes(false)));
		final flags:Array<Bool> = [late.yes(false)];
		Sys.println(flags[0] ? "T" : "F");

		final sameNames:Dynamic = {
			dflt: dflt,
			defI: defI,
			twice: twice,
			show: show
		};
		Sys.println(sameNames.dflt());
		Sys.println(sameNames.dflt(4));
		Sys.println(sameNames.defI());
		Sys.println(sameNames.defI(1));
		Sys.println(sameNames.twice(2.25));
		Sys.println(sameNames.twice(3));
		Sys.println(sameNames.show(false));

		Sys.println(logged("method", late).add(tick("method a", 1), tick("method b", 2)));
		final tickers:Dynamic = {add: (a:Int, b:Int) -> a + b};
		Sys.println(logged("stored", tickers).add(tick("stored a", 3), tick("stored b", 4)));

		final nesting:Dynamic = {nest: nest};
		Sys.println(nesting.nest(nesting.nest(nesting.nest(nesting.nest(nesting.nest(nesting.nest(nesting.nest(nesting.nest(0)))))))));
		Sys.println(late.add(late.add(late.add(late.add(late.add(late.add(late.add(late.add(1, 1), 1), 1), 1), 1), 1), 1), 1));

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
