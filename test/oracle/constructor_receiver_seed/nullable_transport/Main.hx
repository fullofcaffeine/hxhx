/** Observe a skipped receiver assignment through declared Int, generic, field, array, and erased boundaries. */
class Main {
	static function main():Void {
		for (assigned in [false, true]) {
			final value = new Result(assigned);
			final plain:Int = value.read();
			final holder = new Holder(plain);
			final record:{value:Int} = {value: plain};
			final array:Array<Int> = [plain];
			final label = assigned ? "assigned" : "skipped";
			observe(label + "-direct", plain);
			observe(label + "-generic", identity(plain));
			observe(label + "-field", holder.value);
			observe(label + "-record", record.value);
			observe(label + "-array", array[0]);
			observe(label + "-erased", erasedBoundary(plain));
		}
		observe("explicit-null", new NullableResult(null).read());
		observe("explicit-zero", new NullableResult(0).read());
	}

	static function identity<T>(value:T):T {
		return value;
	}

	static function observe(label:String, value:Null<Int>):Void {
		Sys.println(label + "=" + value + ",null=" + (value == null));
	}

	/** Dynamic is intentional at this test boundary: validate an erased integer immediately before returning a precise type. */
	static function erasedBoundary(value:Null<Int>):Null<Int> {
		final erased:Dynamic = value;
		if (erased == null)
			return null;
		if (!Std.isOfType(erased, Int))
			throw "erased integer changed type";
		return cast(erased, Int);
	}
}

/** A declared Int field exposes whether a constructor result loses null during ordinary storage. */
class Holder {
	public var value:Int;

	public function new(value:Int) {
		this.value = value;
	}
}

/** The public baseline admits this short-circuit assignment even when its write does not execute. */
abstract Result(Int) {
	public function new(assigned:Bool) {
		assigned && ((this = 3) == 3);

	}
	public function read():Int {
		return this;
	}
}

/** Explicit null is a payload, independently of whether a constructor performed an assignment. */
abstract NullableResult(Null<Int>) {
	public function new(value:Null<Int>) {
		this = value;
	}

	public function read():Null<Int> {
		return this;
	}
}
