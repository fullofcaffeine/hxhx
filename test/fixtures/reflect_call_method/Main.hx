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
	}
}
