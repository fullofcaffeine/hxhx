typedef DynamicStringCallback = Dynamic->String;

/** Call targets that receive a Boolean through the Haxe Dynamic carrier. */
class DynamicCalls {
	public static function describe(value:Dynamic):String {
		return Std.string(value);
	}

	public static function describeWithLabel(value:Dynamic, ?label:String):String {
		return (label == null ? "optional" : label) + ":" + Std.string(value);
	}
}

/** Exercises each admitted call shape and makes argument evaluation visible. */
class Main {
	static var evaluations = 0;

	static function observedBool(label:String, value:Bool):Bool {
		evaluations += 1;
		Sys.println('evaluate-$label=$evaluations');
		return value;
	}

	static function callback():DynamicStringCallback {
		return DynamicCalls.describe;
	}

	static function main():Void {
		Sys.println("static=" + DynamicCalls.describe(observedBool("static", true)));
		Sys.println("function=" + callback()(observedBool("function", false)));
		Sys.println(DynamicCalls.describeWithLabel(observedBool("optional", true)));
		Sys.println("evaluations=" + evaluations);
	}
}
