/** A structural contract whose methods must stay bound to the original object. */
private typedef CounterView = {
	function add(amount:Int):Int;
	function read():Int;
}

/** Exercises a class-to-structure conversion inside an object field initializer. */
class Main {
	final counter:Counter;
	var evaluations:Int = 0;

	function new() {
		counter = new Counter(10);
	}

	function selected():Counter {
		evaluations++;
		return counter;
	}

	static function observe(input:{counter:CounterView}):Void {
		Sys.println(input.counter.add(2));
		Sys.println(input.counter.read());
	}

	function run():Void {
		observe({counter: counter});
		observe({counter: selected()});
		Sys.println(evaluations);
		Sys.println(counter.read());
		final concrete = {counter: counter};
		Sys.println(concrete.counter.read());
		observe({counter: {add: amount -> amount + 20, read: () -> 20}});
	}

	static function main():Void {
		new Main().run();
	}
}
