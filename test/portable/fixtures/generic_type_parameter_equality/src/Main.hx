/** Compares generic values with the same runtime rules as upstream Haxe. */
class Main {
	static function same<T>(left:T, right:T):Bool {
		return left == right;
	}

	static function different<T>(left:T, right:T):Bool {
		return left != right;
	}

	static function main():Void {
		final floats = [1.5, 2.25];
		Sys.println("float-read:" + same(floats[0], floats[0]) + ":" + different(floats[0], floats[1]));
		Sys.println("float-value:" + same(0.1 + 0.2, 0.1 + 0.2));
		final word = "first";
		final copy = ("x" + word).substr(1);
		Sys.println("string:" + same(word, copy) + ":" + different(word, copy) + ":" + same(word, "second"));
		Sys.println("int:" + same(3, 3) + ":" + different(3, 4));
		Sys.println("bool:" + same(true, true) + ":" + same(true, false));
		final absent:Null<Int> = null;
		final present:Null<Int> = 0;
		Sys.println("nullable:" + same(absent, null) + ":" + same(absent, present) + ":" + same(present, 0));
		final first = new Box(4);
		final second = new Box(4);
		Sys.println("object:" + same(first, first) + ":" + same(first, second));
		final record = {value: 1};
		Sys.println("record:" + same(record, record) + ":" + same(record, {value: 1}));
	}
}

/** Two boxes with equal contents remain distinct objects. */
class Box {
	public final value:Int;

	public function new(value:Int) {
		this.value = value;
	}
}
