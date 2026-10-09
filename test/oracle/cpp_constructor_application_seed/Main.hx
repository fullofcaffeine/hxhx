/** Two applications share an authored generic constructor but require different native signatures. */
class Main {
	static function main():Void {
		final first = new Box<Int>(7);
		final second = new Box<String>("word");
		if (first.read() != 7)
			throw "Int application changed its value";
		if (second.read() != "word")
			throw "String application changed its value";
	}
}

/** The captured local retains the owner binder through a nested callable and receiver assignment. */
abstract Box<T>(T) {
	public function new(value:T) {
		var stored:T = value;
		final read:() -> T = function():T {
			return stored;
		};
		this = read();
	}

	public function read():T {
		return this;
	}
}

/** A same-spelled binder belongs to this separate declaration and must never substitute for Box.T. */
abstract Other<T>(T) {
	public function new(value:T) {
		this = value;
	}
}
