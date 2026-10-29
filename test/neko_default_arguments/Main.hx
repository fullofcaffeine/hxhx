/** Missing and explicit-null arguments select the declared default; a supplied value remains unchanged. */
class Main {
	static function value(number:Int = 7):Int {
		return number;
	}

	static function optional(?number:Int):String {
		return number == null ? "absent" : "present";
	}

	static function flag(enabled:Bool = true):Bool {
		return enabled;
	}

	static function hygienic(__hxhx_args:Int = 4, __hxhx_args_1:Int = 5):Int {
		return __hxhx_args + __hxhx_args_1;
	}

	static function observe(label:String, number:Int):Int {
		Sys.println(label);
		return number;
	}

	static function pair(first:Int = 1, second:Int = 2):Int {
		return first * 10 + second;
	}

	/** A required backing parameter stays required even when a stored view permits omission. */
	static function requiredView(first:Int, second:Null<Int>):Int {
		return first * 1000 + (second == null ? 99 : second);
	}

	static function invokeView(callback:(Int, ?Int) -> Int):Int {
		return callback(11);
	}

	static function main():Void {
		Sys.println(value());
		Sys.println(value(null));
		Sys.println(value(3));
		Sys.println(value(0));
		final callback = value;
		Sys.println(callback());
		Sys.println(optional());
		Sys.println(optional(0));
		Sys.println(flag());
		Sys.println(flag(false));
		Sys.println(hygienic());
		Sys.println(hygienic(8, 9));
		Sys.println(pair(observe("first", 3), observe("second", 4)));
		final receiver = new Receiver();
		Sys.println(receiver.value);
		Sys.println(receiver.read());
		Sys.println(receiver.read(0));
		final method = receiver.read;
		Sys.println(method());
		Sys.println(new Receiver(0).value);
		// The casts deliberately model a callable obtained through an unchecked
		// boundary. The written local signature owns omission, not the backing method.
		final object = {run: requiredView};
		final view:(Int, ?Int) -> Int = cast object.run;
		Sys.println(view(7));
		Sys.println(view(8, 0));
		final unchecked:(Int, ?Int) -> Int = untyped object.run;
		Sys.println(unchecked(9));
		final alias = view;
		Sys.println(alias(10));
		Sys.println(invokeView(view));
		Sys.println(view(observe("view-first", 12), observe("view-second", 13)));
		Sys.println(view(observe("view-only", 14)));
		{
			final view:(Int, Null<Int>) -> Int = requiredView;
			Sys.println(view(15, 16));
		}
	}
}

/** Ordinary constructors and methods share the same default-argument contract. */
class Receiver {
	public var value:Int;

	public function new(value:Int = 11) {
		this.value = value;
	}

	public function read(extra:Int = 2):Int {
		return value + extra;
	}
}
