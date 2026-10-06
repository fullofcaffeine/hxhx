/** Whole optional values must reach a deduced assertion helper without unwrapping. */
class Main {
	static function main():Void {
		var absent:Null<Int> = null;
		Sys.println(Assert.q(Probe.next()));
		Sys.println(Assert.q(absent));
		Sys.println(Assert.q(true));
		Sys.println(Probe.evaluations);
		Sys.println(Serializer.run(23));
		Sys.println(Serializer.run(absent));
		final words = ["alpha", "beta"];
		final empty:Array<String> = [];
		Sys.println(Lambda.has(words, "beta"));
		Sys.println(Lambda.has(["gamma"], "gamma"));
		Sys.println(Lambda.has(words, "delta"));
		Sys.println(Lambda.has(empty, "unused"));
		Sys.println(Lambda.has([], "unused"));
		Sys.println(Lambda.has([7], Probe.next()));
		Sys.println(Probe.evaluations);
		var status:AssertionStatus = {expectedValue: "", actualValue: "", error: ""};
		Sys.println(Assert.sameAs(7, 7, status, 0));
		Sys.println(status.expectedValue);
		Sys.println(status.actualValue);
		Sys.println(status.error == "");
		Sys.println(Assert.sameAs(7, 8, status, 0));
		Sys.println(status.error);
		Sys.println(Assert.sameAs(8, 8, status));
		Sys.println(Assert.same(Probe.next(), 7));
		Sys.println(Assert.same(7, 8, false, "different"));
		Sys.println(Assert.same(absent, absent));
		Sys.println(Probe.evaluations);
		final before = Probe.assertions;
		final test = new Test();
		test.eq(Probe.next(), 7);
		test.eq(7, 8);
		test.eq(absent, absent);
		Sys.println(Probe.assertions - before);
		Sys.println(Probe.evaluations);
		test.exc(Probe.callback());
		test.unspec(Probe.callback());
		Sys.println(Probe.callbacks);
		Sys.println(Probe.executions);
		final callback = Probe.callback();
		callback();
		Sys.println(Probe.executions);
		test.t(Probe.next());
		test.f(absent);
		Sys.println(Probe.evaluations);
		test.allow("alpha", ["alpha"]);
		test.allow("empty", []);
		test.allow(Probe.next(), [7]);
		test.allow(absent, [absent]);
		Sys.println(Probe.evaluations);
	}
}

/** Count the argument effect in ordinary helper-class storage. */
class Probe {
	public static var evaluations:Int = 0;
	public static var assertions:Int = 0;
	public static var callbacks:Int = 0;
	public static var executions:Int = 0;

	/** Constructing a callback is observable even when a neutral wrapper does not invoke it. */
	public static function callback():Void->Void {
		callbacks++;
		return function() {
			executions++;
		};
	}

	public static function next():Int {
		evaluations++;
		return 7;
	}
}

/** Match the source helper's string conversion while exercising its specialized target signature. */
class Assert {
	public static function q(T:Dynamic):String
		return Std.string(T);

	/** Integer and null cases observe optional arguments without introducing approximation policy. */
	public static function same(__hxhx_status:Dynamic, TValue:Dynamic, ?recursive:Bool, ?msg:String, ?approx:Float, ?pos:haxe.PosInfos):Bool
		return __hxhx_status == TValue ? pass(msg, pos) : fail(msg, pos);

	public static function pass(message:String, ?pos:haxe.PosInfos):Bool {
		Probe.assertions++;
		return true;
	}

	public static function fail(message:String, ?pos:haxe.PosInfos):Bool {
		Probe.assertions++;
		return false;
	}

	/** Match the diagnostic helper's Dynamic boundary while requiring mutation of the caller's typed record. */
	public static function sameAs(expected:Dynamic, value:Dynamic, __hxhx_status:AssertionStatus, approx:Float = 0):Bool {
		__hxhx_status.expectedValue = Std.string(expected);
		__hxhx_status.actualValue = Std.string(value);
		final same = expected == value;
		__hxhx_status.error = same ? "" : "expected " + __hxhx_status.expectedValue + " but it is " + __hxhx_status.actualValue;
		return same;
	}
}

/** Both source arities must reach the assertion observer without unwrapping an absent position. */
class Test implements ITest {
	public function new() {}

	public function exc(pos:Void->Void, ?where:haxe.PosInfos):Void {}

	public function unspec(pos:Void->Void):Void {}

	public function t<TValue>(TValue:TValue, ?where:haxe.PosInfos):Void {}

	public function f(value:Dynamic):Void {}

	#if allow_without_generic
	public function allow(value:Dynamic, values:Array<Dynamic>):Void {}
	#elseif eq_without_pos
	public function allow<A>(value:A, values:Array<A>):Void {}
	#else
	public function allow<A>(value:A, values:Array<A>, ?position:haxe.PosInfos):Void {}
	#end

	#if eq_without_pos
	public function eq(pos:Dynamic, value:Dynamic):Void
		Assert.same(pos, value);
	#else
	public function eq(pos:Dynamic, value:Dynamic, ?where:haxe.PosInfos):Void
		Assert.same(pos, value, null, null, null, where);
	#end
}

/** Select the existing unit-test support class route without requiring assertion-body semantics. */
interface ITest {}

/** A structural record exposes accidental by-value status copies in generated C++. */
typedef AssertionStatus = {
	var expectedValue:String;
	var actualValue:String;
	var error:String;
}

/** Observe run's by-value forwarding and local names, without asserting a serialization format. */
class Serializer {
	var output:String;

	public function new() {
		output = "";
	}

	public function serialize<T>(value:T):Void {
		output = Std.string(value);
	}

	public function toString():String
		return output;

	public static function run(s:Dynamic):String {
		final writer = new Serializer();
		writer.serialize(s);
		return writer.toString();
	}
}

/** The iterable owns element deduction; x also tests the generated loop-variable boundary. */
class Lambda {
	public static function has<A>(values:Iterable<A>, x:A):Bool {
		for (value in values)
			if (value == x)
				return true;
		return false;
	}
}
