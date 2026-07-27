/**
	A closed user class whose values preserve identity and shared field mutation.

	The class deliberately has no superclass, interfaces, generic parameters,
	extern boundary, or dynamic methods.
**/
class Counter {
	static var events:Array<String> = [];

	public var value:Int;

	public static function record(event:String):Void {
		events.push(event);
	}

	public static function reset():Void {
		events = [];
	}

	public static function renderEvents():String {
		return events.join(",");
	}

	public function new(value:Int) {
		record("ctor");
		this.value = value;
	}

	public function bump(delta:Int):Int {
		record("method");
		value += delta;
		return value;
	}
}

/** Freezes Haxe 4.3.7 behavior for the first nominal class-carrier slice. */
class Main {
	static function printLine(value:String):Void {
		#if js
		js.Syntax.code("console.log({0})", value);
		#else
		Sys.println(value);
		#end
	}

	static function sourceValue():Int {
		Counter.record("arg");
		return 2;
	}

	static function writeValue():Int {
		Counter.record("write");
		return 9;
	}

	static function delta():Int {
		Counter.record("delta");
		return 2;
	}

	static function makeCounter():Counter {
		Counter.record("factory");
		return new Counter(5);
	}

	/** Returns one constructor-produced local from a nested branch. */
	static function chooseBranch(stop:Bool, earlyValue:Int, fallbackValue:Int):Counter {
		final early = new Counter(earlyValue);
		final fallback = new Counter(fallbackValue);
		if (stop)
			return early;
		return fallback;
	}

	/** Returns one constructor-produced local from inside a lexical loop. */
	static function chooseLoop(stop:Bool, earlyValue:Int, fallbackValue:Int):Counter {
		final early = new Counter(earlyValue);
		final fallback = new Counter(fallbackValue);
		var first = true;
		while (first) {
			first = false;
			if (stop)
				return early;
		}
		return fallback;
	}

	/**
		Returns through a source `catch` without letting it intercept the return.

		The `caught` event is observable evidence that ordinary Haxe exception
		handling did not mistake function-local control for a source exception.
	**/
	static function chooseThroughCatch(stop:Bool, earlyValue:Int, fallbackValue:Int):Counter {
		final early = new Counter(earlyValue);
		final fallback = new Counter(fallbackValue);
		try {
			if (stop)
				return early;
		} catch (_:Dynamic) {
			Counter.record("caught");
		}
		return fallback;
	}

	/**
		Keeps null-to-nominal return behavior visible but outside the first proof.

		The nominal record decision does not yet own the conversion from Haxe's
		null sentinel into a class carrier, so this function must remain on the
		legacy path until that conversion has a separate typed contract.
	**/
	static function chooseNull(stop:Bool, fallbackValue:Int):Counter {
		if (stop)
			return null;
		return new Counter(fallbackValue);
	}

	static function constructorLocalCase():Void {
		Counter.reset();
		final counter = new Counter(sourceValue());
		final result = counter.bump(1);
		printLine("constructor_local result=" + result + " events=" + Counter.renderEvents());
	}

	static function aliasCase():Void {
		Counter.reset();
		final counter = new Counter(4);
		final alias = counter;
		alias.value = writeValue();
		printLine("alias identity=" + (counter == alias) + " value=" + counter.value + " events=" + Counter.renderEvents());
	}

	static function factoryReceiverCase():Void {
		Counter.reset();
		final result = makeCounter().bump(delta());
		printLine("factory_receiver result=" + result + " events=" + Counter.renderEvents());
	}

	static function capturedLocalCase():Void {
		Counter.reset();
		final counter = new Counter(6);
		final read = function():Int {
			return counter.value;
		}
		counter.value = writeValue();
		printLine("captured_local value=" + read() + " events=" + Counter.renderEvents());
	}

	/**
		Records captured-and-reassigned class behavior across every oracle route.

		The closure must read the replacement object, not the original binding.
		Constructor events also prove that both direct producers run once.
	**/
	static function reassignedCapturedLocalCase():Void {
		Counter.reset();
		var counter = new Counter(10);
		final read = function():Int {
			return counter.value;
		}
		counter = new Counter(11);
		printLine("captured_reassigned value=" + read() + " events=" + Counter.renderEvents());
	}

	static function branchEarlyReturnCase():Void {
		Counter.reset();
		final selected = chooseBranch(true, 20, 30);
		selected.value = 21;
		final fallbackSelected = chooseBranch(false, 20, 30);
		printLine("return_branch value="
			+ selected.value
			+ " fallback_value="
			+ fallbackSelected.value
			+ " events="
			+ Counter.renderEvents());
	}

	static function nullEarlyReturnCase():Void {
		Counter.reset();
		final selected = chooseNull(true, 40);
		printLine("return_null is_null=" + (selected == null) + " events=" + Counter.renderEvents());
	}

	static function loopEarlyReturnCase():Void {
		Counter.reset();
		final selected = chooseLoop(true, 50, 60);
		printLine("return_loop value=" + selected.value + " events=" + Counter.renderEvents());
	}

	static function catchEarlyReturnCase():Void {
		Counter.reset();
		final selected = chooseThroughCatch(true, 70, 80);
		printLine("return_catch value=" + selected.value + " events=" + Counter.renderEvents());
	}

	#if class_carrier_negative_boundaries
	/**
		Keeps unadmitted mutable and call-produced class values executable.

		These cases must stay correct through the legacy carrier until their
		producer or storage domains gain separate typed proofs.
	**/
	static function excludedCarrierBoundaries():Void {
		var ordinary = new Counter(12);
		ordinary = new Counter(13);
		if (ordinary.value != 13)
			throw "ordinary mutable class local lost its replacement";

		var called = new Counter(14);
		final read = function():Int {
			return called.value;
		}
		called = makeCounter();
		if (read() != 5)
			throw "call-produced captured class local lost shared storage";
	}
	#end

	static function main():Void {
		constructorLocalCase();
		aliasCase();
		capturedLocalCase();
		reassignedCapturedLocalCase();
		branchEarlyReturnCase();
		nullEarlyReturnCase();
		loopEarlyReturnCase();
		catchEarlyReturnCase();
		#if class_carrier_factory_receiver
		factoryReceiverCase();
		#end
		#if class_carrier_negative_boundaries
		excludedCarrierBoundaries();
		#end
	}
}
