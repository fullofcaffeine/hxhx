package counters;

/**
	Static fields that another module writes and reads.
	`doubled` reads `base` during startup, so it checks same-module initializer order.
**/
class Registry {
	public static var count:Int = 0;
	public static var total:Float = 0.5;
	public static var label:String = "start";
	public static var enabled:Bool = false;
	public static var names:Array<String> = ["a"];
	public static var last:Null<Item>;
	public static var pending:Null<Int>;
	public static var base:Int = 10;
	public static var doubled:Int = base * 2;
	public static var hits(default, null):Int = 0;

	public static function hit():Int {
		hits++;
		return hits;
	}

	public static function bump():Int {
		return ++count;
	}

	public static function setTotal(n:Int):Void {
		total = n;
	}

	/** Reads this module's statics after another module wrote them. */
	public static function report():String {
		return count + " " + label + " " + enabled + " " + names.join(",");
	}
}
