/** A fixed erased callback slot must carry each returned value without string conversion. */
class Main {
	static function main():Void {
		function inferred(value:String)
			return value;
		Sys.println(inferred("inferred"));
		var callback:String->Dynamic = function(value:String):Dynamic return value;
		final text = callback(Probe.argument());
		Sys.println(text + "!");
		callback = function(value:String) {
			Probe.invocations++;
			return 7;
		};
		final number = callback(Probe.argument());
		Sys.println(number + 1);
		callback = function(value:String) {
			Probe.invocations++;
			return false;
		};
		final flag = callback(Probe.argument());
		Sys.println(flag ? "yes" : "no");
		callback = function(value:String) {
			Probe.invocations++;
			return null;
		};
		Sys.println(callback(Probe.argument()) == null);
		Sys.println(Probe.arguments);
		Sys.println(Probe.invocations);
		var foo = function(x:Int, ?pos:haxe.PosInfos):String return pos == null ? "missing" : "foo" + x;
		var first:Void->String = foo.bind(0);
		Sys.println(first());
		var foo = function(count = 2):Int return count;
		var middle = foo.bind(_);
		Sys.println(middle());
		var foo = function(bar:Null<Int> = 2):Int return bar;
		var last = foo.bind(_);
		Sys.println(last());
		function positioned(value:String, ?pos:haxe.PosInfos)
			return pos == null ? "missing" : value;
		Sys.println(positioned("position"));
		var loop = function() {
			while (true)
				return "loop";
		};
		Sys.println(loop());
		var recover = function():String {
			try {
				throw "boom";
			} catch (error:Dynamic) {
				return "caught";
			}
		};
		Sys.println(recover());
		var choose = function(flag:Bool):Int {
			Probe.paths++;
			var value = 6;
			if (flag)
				return value + 1;
			else
				return value + 2;
		};
		Sys.println(choose(true));
		Sys.println(choose(false));
		var finish = function():Void {
			var nested = function():Int return 9;
			Probe.nested = nested();
		};
		finish();
		Sys.println(Probe.nested);
		Sys.println(Probe.paths);
	}
}

/** Separate counters prove argument and callback evaluation counts. */
class Probe {
	public static var arguments:Int = 0;
	public static var invocations:Int = 0;
	public static var paths:Int = 0;
	public static var nested:Int = 0;

	public static function argument():String {
		arguments++;
		return "text";
	}
}
