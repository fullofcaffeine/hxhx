enum Sample {
	Item(value:Int);
}

enum Other {
	Entry(value:Int);
}

/** Typed inputs for admission tests; unsafe callback uses are never executed. */
@:keep
class Generic<T> {
	var stored:T->T;

	public function new() {}

	public function invoke(callback:T->T):Void {
		callback(null);
	}

	public function retain(callback:T->T):T->T {
		return callback;
	}

	public function compare(callback:T->T):Bool {
		return callback == callback;
	}

	public function store(callback:T->T):Void {
		stored = callback;
	}

	public function replace(callback:T->T):Void {
		callback = value -> value;
	}
}

/** Supplies real typed calls so the test checks semantic selection before emission. */
@:keep
class ContractCases {
	static function check():Void {
		final receiver = new Generic<Sample>();
		final callback = (value:Sample) -> value;
		receiver.invoke(callback);
		receiver.retain(callback);
		receiver.compare(callback);
		receiver.store(callback);
		receiver.replace(callback);
		new Generic<Int>().invoke(value -> value);
	}

	static function main():Void {}
}
