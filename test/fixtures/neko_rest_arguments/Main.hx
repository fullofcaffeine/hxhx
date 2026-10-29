/** Rest operands preserve container identity, call order, and the native reflection convention. */
class Main {
	static var effects = "";

	public static function total(prefix:Int, ...values:Int):Int {
		var result = prefix;
		for (value in values)
			result += value;
		return result;
	}

	static function optional(prefix:Int = 4, ...values:Int):Int {
		var result = prefix;
		for (value in values)
			result += value;
		return result;
	}

	static function nested(...values:Array<Int>):Int {
		var result = 0;
		for (value in values)
			result += value.length;
		return result;
	}

	static function invoke(callback:haxe.Rest<Int>->Int):Int
		return callback(4, 5);

	static function effect(label:String, value:Int):Int {
		effects += label;
		return value;
	}

	static function main():Void {
		Sys.println(total(10));
		Sys.println(total(10, 1, 2));
		final saved = total;
		Sys.println(saved(3, 4, 5));
		// Reflection is the untyped boundary. Validate the callable and compare its result immediately.
		final reflected = Reflect.field(Main, "total");
		if (!Reflect.isFunction(reflected))
			throw "missing reflected rest function";
		var rejected = false;
		try {
			Reflect.callMethod(null, reflected, [10, 1, 2]);
		} catch (_:Dynamic) {
			rejected = true;
		}
		Sys.println(rejected);
		Sys.println(Reflect.callMethod(null, reflected, [10, [1, 2]]) == 13);
		rejected = false;
		try {
			Reflect.callMethod(null, reflected, [10]);
		} catch (_:Dynamic) {
			rejected = true;
		}
		Sys.println(rejected);
		rejected = false;
		try {
			Reflect.callMethod(null, reflected, [10, null]);
		} catch (_:Dynamic) {
			rejected = true;
		}
		Sys.println(rejected);

		final tail = [2, 3];
		Sys.println(total(10, ...tail));
		Sys.println(saved(1, ...tail));
		Sys.println(optional());
		Sys.println(optional(2, 3));
		Sys.println(nested([1, 2], [3]));
		final arrays = [[1, 2], [3, 4, 5]];
		Sys.println(nested(...arrays));
		final callback = function(...values:Int):Int {
			var result = 0;
			for (value in values)
				result += value;
			return result;
		};
		Sys.println(callback());
		Sys.println(callback(2, 3));
		Sys.println(invoke(callback));

		final receiver = new Receiver(2, 3);
		Sys.println(receiver.total(1, 4));
		final method = receiver.total;
		Sys.println(method(2, 3));
		Sys.println(new Child().total());
		Sys.println(new Total(5).add(2, 3));
		Sys.println(total(effect("p", 1), effect("a", 2), effect("b", 3)));
		Sys.println(effects);
	}
}

/** Constructors and saved instance methods use the same packed rest slot. */
class Receiver {
	final seed:Int;

	public function new(...values:Int) {
		var result = 0;
		for (value in values)
			result += value;
		seed = result;
	}

	public function total(...values:Int):Int {
		var result = seed;
		for (value in values)
			result += value;
		return result;
	}
}

/** Super calls preserve the constructor's selected rest membership. */
class Child extends Receiver {
	public function new()
		super(2, 3);
}

/** An abstract receiver occupies a separate native slot from its rest operands. */
abstract Total(Int) {
	public function new(value:Int)
		this = value;

	public function add(...values:Int):Int {
		var result = this;
		for (value in values)
			result += value;
		return result;
	}
}
