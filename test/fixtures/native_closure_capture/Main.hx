/** Escaping closures retain shared locations and the receiver of their creating invocation. */
class Main {
	var stored:Int;

	public function new(value:Int) {
		stored = value;
	}

	function set(value:Int):Void {
		stored = value;
	}

	function capture():() -> Int {
		return function():Int {
			return stored;
		};
	}

	static function make(seed:Int):Int->Int {
		var value = seed;
		return function(delta:Int):Int {
			value += delta;
			function read():Int {
				return value;
			}
			return read();
		};
	}

	static function makeParameter(seed:Int):() -> Int {
		return function():Int {
			seed += 1;
			return seed;
		};
	}

	static function main():Void {
		final first = make(10);
		final second = make(100);
		Sys.println(first(1));
		Sys.println(first(2));
		Sys.println(second(1));
		final alias = first;
		Sys.println(alias(3));
		Sys.println(first(0));
		Sys.println(second(0));
		final parameter = makeParameter(20);
		Sys.println(parameter());
		Sys.println(parameter());
		final independent = makeParameter(20);
		Sys.println(independent());
		final owner = new Main(13);
		final left = owner.capture();
		final right = new Main(23).capture();
		Sys.println(left());
		Sys.println(right());
		owner.set(17);
		Sys.println(left());
		Sys.println(right());
		var value = 7;
		final shadow = function():Int {
			var value = 100;
			value++;
			return value;
		};
		Sys.println(shadow());
		Sys.println(value);
		final localParameter = function(value:Int):Int {
			value += 2;
			return value;
		};
		Sys.println(localParameter(5));
		Sys.println(localParameter(5));
		var shared = 2;
		final read = function():Int {
			return shared;
		};
		shared = 9;
		Sys.println(read());
		final bump = function():Void {
			shared++;
		};
		bump();
		Sys.println(read());
	}
}
