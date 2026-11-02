class Holder {
	public var value:Int = 5;

	public function new() {}

	public function add(amount:Int):Int {
		return value + amount;
	}

	public function label(prefix:String, count:Int):String {
		return prefix + value + "x" + count;
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
		// Array<Function> literal elements.
		final handlers:Array<haxe.Constraints.Function> = [holder.add, function(x:Int):Int return x * 3, Holder.twice];
		Sys.println(Reflect.callMethod(holder, handlers[0], [1]) + " " + Reflect.callMethod(null, handlers[1], [2]) + " "
			+ Reflect.callMethod(null, handlers[2], [4]));
	}
}
