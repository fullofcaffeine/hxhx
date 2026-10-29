/** Observable closure behavior; expected output is authored independently of the PHP emitter. */
class Main {
	static function main():Void {
		final early = function(value:Int):Int {
			final local = value + 1;
			if (local > 3)
				return local;
			return 0;
		};
		Sys.println(early(4));
		Sys.println(early(1));

		var shared = 3;
		final read = function():Int {
			return shared;
		};
		final update = function():Int {
			shared = shared + 2;
			return shared;
		};
		shared = 10;
		Sys.println(read());
		Sys.println(update());
		Sys.println(shared);

		final factory = function(seed:Int):Void->Int {
			var local = seed;
			return function():Int {
				local = local + 1;
				shared = shared + 1;
				return local + shared;
			};
		};
		final counter = factory(20);
		Sys.println(counter());
		Sys.println(counter());
		Sys.println(shared);

		final shadow = function(shared:Int):Int {
			final readInner = function():Int {
				return shared;
			};
			shared = shared + 4;
			return readInner();
		};
		Sys.println(shadow(2));
		Sys.println(shared);

		final otherCounter = factory(100);
		Sys.println(otherCounter());
		Sys.println(counter());

		final iterations:Array<Void->Int> = [];
		for (i in 0...3) {
			var local = i;
			iterations.push(function():Int {
				local = local + 10;
				return local;
			});
		}
		Sys.println(iterations[0]());
		Sys.println(iterations[1]());
		Sys.println(iterations[0]());
		Sys.println(iterations[2]());

		final direct:Array<Void->Int> = [];
		for (i in 0...3)
			direct.push(function():Int {
				return i;
			});
		Sys.println(direct[0]());
		Sys.println(direct[1]());
		Sys.println(direct[2]());
		final find = function():Int {
			for (i in 0...5) {
				if (i == 1)
					continue;
				if (i == 3)
					return i;
			}
			return 9;
		};
		Sys.println(find());
		Sys.println((function(value:Int):Int {
			return value + 1;
		})(5));

		final typeValue = function() {
			return String;
		};
		Sys.println(typeValue() == String ? "type-ok" : "type-bad");
	}
}
