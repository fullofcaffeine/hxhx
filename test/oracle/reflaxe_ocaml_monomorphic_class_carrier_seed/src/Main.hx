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

	#if class_carrier_mutable_capture_negative
	/**
		Keeps the captured-and-reassigned family in the portable target fixture.

		The immutable capture slice must not assign this local a nominal immutable
		binding: both scopes need one shared cell because the whole object reference
		changes after the closure is created.
	**/
	static function reassignedCapturedLocalBoundary():Void {
		var counter = new Counter(10);
		final read = function():Int {
			return counter.value;
		}
		counter = new Counter(11);
		if (read() != 11)
			throw "captured reassignment lost shared storage";
	}
	#end

	static function main():Void {
		constructorLocalCase();
		aliasCase();
		capturedLocalCase();
		#if class_carrier_factory_receiver
		factoryReceiverCase();
		#end
		#if class_carrier_mutable_capture_negative
		reassignedCapturedLocalBoundary();
		#end
	}
}
