/** Receiver reads must retain identity through entry allocations and escaping closures. */
class Main {
	public function new() {}

	public function direct():Main {
		return this;
	}

	public function self(value:Main):Main {
		final hold = function():Main {
			return value;
		};
		final temporary = {keep: hold};
		return this;
	}

	public function capture(value:Main):Void->Main {
		final argument = function():Main {
			return value;
		};
		return function():Main {
			final temporary = {keep: argument};
			return this;
		};
	}

	public function forward():Void->(Void->Main) {
		return function():Void->Main {
			return function():Main {
				return this;
			};
		};
	}

	public function ignore(value:Int):Int {
		return value + 1;
	}

	static function main():Void {
		final first = new Main();
		final second = new Main();
		Sys.println(first.self(second) == first);
		Sys.println(first.capture(second)() == first);
		Sys.println(first.forward()()() == first);
		Sys.println(second.direct() != first);
		Sys.println(first.ignore(4));
	}
}
