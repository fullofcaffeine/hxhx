/** Methods in this view must call the original interface receiver. */
private typedef CounterView = {
	function add(amount:Int):Int;
	function read():Int;
}

/** Exercises explicit and contextual interface-to-structure conversions. */
class Main {
	static var selections:Int = 0;

	static function requireView(counter:Null<ICounter>):CounterView {
		if (counter == null)
			throw "missing counter";
		// The interface proves every method required by this structural view.
		return cast counter;
	}

	static function selected(counter:ICounter):ICounter {
		selections++;
		return counter;
	}

	static function observe(input:{counter:CounterView}):Void {
		Sys.println(input.counter.add(3));
		Sys.println(input.counter.read());
	}

	static function main():Void {
		final concrete = new Counter(10);
		final contract:ICounter = concrete;
		final view = requireView(contract);
		Sys.println(view.add(2));
		Sys.println(view.read());
		observe({counter: selected(contract)});
		Sys.println(selections);
		Sys.println(concrete.read());
		try {
			requireView(null);
		} catch (error:String) {
			Sys.println(error);
		}
		DispatchSemantics.check();
	}
}
