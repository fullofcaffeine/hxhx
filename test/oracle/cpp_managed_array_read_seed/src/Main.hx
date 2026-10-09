/** Native array bounds and receiver/index effects have separate interpreter expectations. */
class Main {
	static var events:String = '';
	static var initialized:Int = [1, 2, 3][1];
	static var initializedLength:Int = [1, 2, 3].length;
	static var changing:Array<String> = ['original'];

	static function choose():Array<String> {
		events += 'r';
		return changing;
	}

	static function position():Int {
		events += 'i';
		changing = ['replacement'];
		return 0;
	}

	static function integer(values:Array<Int>, index:Int):Int {
		return values[index];
	}

	/** The native observer supplies a collecting callback and checks exceptional cleanup. */
	static function readWithIndex(values:Array<Int>, index:Void->Int):Int {
		return values[index()];
	}

	/** The observer supplies erased payloads and checks alias versus conversion behavior. */
	static function recoverBoolean(value:Dynamic):Array<Bool> {
		final recovered:Array<Bool> = value;
		return recovered;
	}

	/** A return conversion must obey the same contract as a local initializer. */
	static function returnBoolean(value:Dynamic):Array<Bool> {
		return value;
	}

	/** Boolean reads may use a shared Dynamic array view after recovery. */
	static function readBoolean(values:Array<Bool>, index:Int):Bool {
		return values[index];
	}

	/** Native observers check alias writes, growth defaults, and negative indices. */
	static function writeBoolean(values:Array<Bool>, index:Int, value:Bool):Bool {
		return values[index] = value;
	}

	static function writeInteger(values:Array<Int>, index:Int, value:Int):Int {
		return values[index] = value;
	}

	/** Both callbacks may collect; their ordering follows the native assignment contract. */
	static function writeWithIndex(values:Array<Int>, index:Void->Int, value:Void->Int):Int {
		return values[index()] = value();
	}

	static function assignedText():String {
		events += 'v';
		return 'written';
	}

	/** The native observer checks a recovered view and a discarded public call. */
	static function pushBoolean(values:Array<Bool>, value:Bool):Int {
		return values.push(value);
	}

	static function discardPush(values:Array<Bool>, value:Bool):Void {
		values.push(value);
	}

	/** A collecting argument must not release or replace the chosen array. */
	static function pushWithValue(values:Array<Int>, value:Void->Int):Int {
		return values.push(value());
	}

	static function appendText():String {
		events += 'a';
		changing = ['replacement'];
		return 'appended';
	}

	/** This uncalled source body supplies a same-name, nonstandard instance declaration. */
	static function shadowPush(value:PushShadow):Int {
		return value.push(true);
	}

	/** Native observers read live size through an alias and check null-root cleanup. */
	static function lengthBoolean(values:Array<Bool>):Int {
		return values.length;
	}

	static function shadowLength(value:PushShadow):Int {
		return value.length;
	}

	/** Native C++ consumes a nullable index as zero while its source and generic callback retain null. */
	static function nullableIndices():Void {
		final absent:Null<Int> = null;
		final values = [7, 9];
		if (values[absent] != 7)
			throw "nullable index did not select zero";
		values[absent] = 11;
		if (values[0] != 11 || absent != null)
			throw "nullable index write changed its source";
		final source = new NullableIndex<Int>(absent);
		final read:() -> Int = source.reader();
		final retained:Null<Int> = read();
		if (retained != null || source.calls != 1)
			throw "generic index callback lost null before indexing";
		if (values[read()] != 11 || source.calls != 2)
			throw "callback index read lost conversion or effects";
		values[read()] = 23;
		if (values[0] != 23 || values[1] != 9 || source.calls != 3)
			throw "callback index write changed storage or invocation count";
	}

	static function main():Void {
		#if cpp
		// The upstream interpreter throws on null indices; this is a native C++ contract.
		nullableIndices();
		#end
		if (initialized != 2)
			throw "array read initializer differs";
		if (initializedLength != 3)
			throw 'array length initializer differs';
		final values:Array<Int> = [1, 2, 3];
		Sys.println(integer(values, 1));
		Sys.println(integer(values, -1));
		Sys.println(integer(values, 3));
		final flags:Array<Bool> = [true];
		Sys.println(flags[4]);
		final words:Array<String> = ['present'];
		Sys.println(words[4] == null);
		final optional:Array<Null<Int>> = [7];
		Sys.println(optional[4] == null);
		Sys.println(choose()[position()]);
		Sys.println(events);
		Sys.println(changing[0]);
		events = '';
		final before = changing;
		Sys.println(choose()[position()] = assignedText());
		Sys.println(events);
		Sys.println(before[0]);
		events = '';
		final chosen = changing;
		Sys.println(choose().push(appendText()));
		Sys.println(events);
		Sys.println(chosen[1]);
		Sys.println(changing[0]);
		events = '';
		Sys.println(choose().length);
		Sys.println(events);
	}
}

/** Preserve a generic null behind a concrete Int callback alias until its array-index use. */
class NullableIndex<T> {
	final value:T;

	public var calls:Int = 0;

	public function new(value:T)
		this.value = value;

	public function reader():() -> T {
		return function():T {
			calls++;
			return value;
		};
	}
}

/** A method name alone must never select the standard Array implementation. */
class PushShadow {
	public var length:Int;

	public function push(value:Bool):Int {
		return 99;
	}
}
