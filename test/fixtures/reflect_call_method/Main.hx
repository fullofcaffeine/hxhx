class Holder {
	public var value:Int = 5;

	public function new() {}

	public function add(amount:Int):Int {
		return value + amount;
	}

	public function label(prefix:String, count:Int):String {
		return prefix + value + "x" + count;
	}

	public function half(x:Float):Float {
		return x / 2;
	}

	public static function twice(amount:Int):Int {
		return amount * 2;
	}
}

class Main {
	static function callThrough(f:haxe.Constraints.Function):Dynamic {
		return Reflect.callMethod(null, f, [5]);
	}

	/** The event-listener shape: a callback whose inputs are not annotated. */
	static function listen(name:String, arguments:Array<Dynamic>, f:haxe.Constraints.Function):Void {
		Sys.println("listen " + name);
		Reflect.callMethod(null, f, arguments);
	}

	static function compute(arguments:Array<Dynamic>, f:haxe.Constraints.Function):Dynamic {
		return Reflect.callMethod(null, f, arguments);
	}

	static function main():Void {
		final holder = new Holder();
		// An ordinary typed instance method keeps its receiver.
		final arguments:Array<Dynamic> = [7];
		Sys.println(Reflect.callMethod(holder, holder.add, arguments) == 12);
		Sys.println(Reflect.callMethod(holder, holder.add, [8]));
		Sys.println(Reflect.callMethod(holder, holder.label, ["v", 3]));
		// The receiver is the bound method's object.
		holder.value = 10;
		Sys.println(Reflect.callMethod(null, holder.add, [1]));
		// A static method and a local function.
		Sys.println(Reflect.callMethod(null, Holder.twice, [21]));
		final local = (a:Int, b:Int) -> a - b;
		Sys.println(Reflect.callMethod(null, local, [9, 4]));
		// A function stored as haxe.Constraints.Function, then passed on.
		final stored:haxe.Constraints.Function = holder.add;
		Sys.println(Reflect.callMethod(holder, stored, [3]));
		Sys.println(callThrough(Holder.twice));
		// Lambdas whose inputs are not annotated take Dynamic inputs.
		listen("a", [7], function(d) {
			Sys.println(d);
		});
		listen("b", [8], d -> Sys.println(d));
		// `"listener " + d` types `d` as String (upstream too). Reflect.callMethod
		// still passes whatever the arguments are: an Int prints as its text.
		listen("c", [9], function(d) Sys.println("listener " + d));
		listen("d", ["text"], function(d) Sys.println("listener " + d));
		// A null `d` is passed as null; printing it in a concatenation needs the
		// null-String text fix of PR #160 (haxe_ocaml-txs4e), so it is not here.
		Sys.println(compute([3, 4], (a, b) -> a));
		Sys.println(Reflect.callMethod(null, (x) -> x, [1]));
		final identity = (x) -> x;
		Sys.println(Reflect.callMethod(null, identity, [2]));
		// Float parameters accept an Int argument, as in eval.
		Sys.println(Reflect.callMethod(holder, holder.half, [3]) + " " + Reflect.callMethod(holder, holder.half, [5.0]));
		// Functions stored in a Function local follow the same convention.
		final shout:haxe.Constraints.Function = function(s:String) Sys.println("shout " + s);
		Reflect.callMethod(null, shout, ["hey"]);
		Reflect.callMethod(null, shout, [7]);
		// A missing argument is null for a reference parameter, as in eval.
		listen("f", [1], function(a:Int, b:String) Sys.println("a=" + a));
		// More arguments than parameters raise a catchable error, as in eval.
		try {
			Reflect.callMethod(null, shout, ["one", "two"]);
			Sys.println("no error");
		} catch (error:Dynamic) {
			Sys.println("too many arguments rejected");
		}
		// Array<Function> elements: Bool parameters and results keep their meaning.
		final checks:Array<haxe.Constraints.Function> = [function(b:Bool) Sys.println("b=" + b), function(x:Int) return x > 1];
		Reflect.callMethod(null, checks[0], [false]);
		Reflect.callMethod(null, checks[0], [true]);
		Sys.println(Reflect.callMethod(null, checks[1], [2]) + " " + Reflect.callMethod(null, checks[1], [0]));
		// Array<Function> literal elements.
		final handlers:Array<haxe.Constraints.Function> = [holder.add, function(x:Int):Int return x * 3, Holder.twice];
		Sys.println(Reflect.callMethod(holder, handlers[0], [1]) + " " + Reflect.callMethod(null, handlers[1], [2]) + " "
			+ Reflect.callMethod(null, handlers[2], [4]));
	}
}
