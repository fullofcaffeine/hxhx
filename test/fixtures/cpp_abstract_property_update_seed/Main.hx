/** Getter/setter updates use one-unit arithmetic, even when the abstract overload adds ten or one hundred. */
class Main {
	public static var decrementPostfix:Int = 0;
	public static var decrementPrefix:Int = 0;
	public static var getterCalls:Int = 0;
	public static var incrementPostfix:Int = 0;
	public static var incrementPrefix:Int = 0;
	public static var receiverCalls:Int = 0;
	public static var setterCalls:Int = 0;
	public static var stored:Int = 0;

	static function choose(holder:Holder):Holder {
		receiverCalls++;
		return holder;
	}

	public static function main():Void {
		final holder = new Holder();
		final upBefore:Step = ++choose(holder).value;
		final upAfter:Step = choose(holder).value++;
		final downBefore:Step = --choose(holder).value;
		final downAfter:Step = choose(holder).value--;
		incrementPrefix = upBefore.get();
		incrementPostfix = upAfter.get();
		decrementPrefix = downBefore.get();
		decrementPostfix = downAfter.get();
		stored = holder.saved().get();
	}
}

/** The property schedule must not select these overloaded increment bodies. */
abstract Step(Int) {
	public inline function new(value:Int)
		this = value;

	@:op(++A) public inline function before():Step {
		this += 10;
		return cast this;
	}

	@:op(A++) public inline function after():Step {
		var old = this;
		this += 100;
		return cast old;
	}

	public function get():Int
		return this;
}

/** Count accessor calls independently of the saved-value observer. */
class Holder {
	var current:Step;

	public var value(get, set):Step;

	public function new()
		current = new Step(9);

	public function get_value():Step {
		Main.getterCalls++;
		return current;
	}

	public function set_value(value:Step):Step {
		Main.setterCalls++;
		return current = value;
	}

	public function saved():Step
		return current;
}
