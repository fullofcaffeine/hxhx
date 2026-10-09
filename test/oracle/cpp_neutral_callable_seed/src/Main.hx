/** Calls must agree with both class-selected neutral assertion signatures. */
class Main {
	static function main():Void {
		var absent:Null<Int> = null;
		Sys.println(utest.Assert.observe(Probe.next(), "value"));
		Sys.println(utest.Assert.observe(absent, "absent"));
		Sys.println(utest.Assert.observeGeneric(absent));
		Sys.println(Probe.evaluations);
		utest.Assert.createAsync()();
		utest.Assert.createEvent(Probe.eventCallback())("neutral");
		Sys.println(Probe.constructions);
		Sys.println(Probe.executions);
		utest.Assert.createAsync = Probe.asyncFactory;
		utest.Assert.createEvent = Probe.eventFactory;
		utest.Assert.createAsync()();
		utest.Assert.createEvent(Probe.eventCallback())("rebound");
		Sys.println(Probe.constructions);
		Sys.println(Probe.executions);
		Sys.println(Probe.dynamicSum(2, 3));
		Probe.dynamicSum = Probe.multiply;
		Sys.println(Probe.dynamicSum(2, 3));
		final identity:Dynamic->Dynamic = function(value:Dynamic):Dynamic return value;
		Sys.println(identity(7));
		Sys.println(identity(false));
		Sys.println(identity("text"));
		Sys.println(identity(null));
	}
}

/** An independent counter makes lost or repeated argument evaluation observable. */
class Probe {
	public static var evaluations:Int = 0;
	public static var constructions:Int = 0;
	public static var executions:Int = 0;

	/** Factory and callback counters distinguish construction from invocation. */
	public static function eventCallback():Dynamic->Void {
		constructions++;
		return function(event:Dynamic) {
			executions++;
		};
	}

	public static function asyncFactory(?callback:Void->Void, ?timeout:Int):Void->Void
		return function() {
			executions++;
		};

	public static function eventFactory(callback:Dynamic->Void, ?timeout:Int):Dynamic->Void
		return callback;

	public static dynamic function dynamicSum(int:Int, int_:Int):Int
		return int + int_;

	public static function multiply(left:Int, right:Int):Int
		return left * right;

	public static function next():Int {
		evaluations++;
		return 7;
	}
}
