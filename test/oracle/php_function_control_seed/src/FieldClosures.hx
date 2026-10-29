/** Field initialization, receiver capture, and captured method parameters use the same lifetime contract. */
class FieldClosures {
	static var make:Int->(Void->Int) = function(seed:Int):Void->Int {
		var value = seed;
		return function():Int {
			value = value + 1;
			return value;
		};
	};

	var count:Int = 2;
	var initial:Void->Int = function():Int {
		return 7;
	};
	var next:Void->Int;

	public function new() {
		next = function():Int {
			count = count + 1;
			return count;
		};
	}

	static function fromParameter(value:Int):Void->Int {
		return function():Int {
			value = value + 2;
			return value;
		};
	}

	static function main():Void {
		final first = make(10);
		final second = make(20);
		Sys.println(first());
		Sys.println(second());
		Sys.println(first());
		final counter = fromParameter(30);
		Sys.println(counter());
		Sys.println(counter());
		final object = new FieldClosures();
		Sys.println(object.initial());
		Sys.println(object.next());
		Sys.println(object.next());
		Sys.println(object.count);
	}
}
