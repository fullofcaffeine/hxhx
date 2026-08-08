/**
 * Records the observable Haxe 4.3.7 `Reflect.compare` contract.
 *
 * The public API promises exact ordering only for compatible numeric and
 * string values. This fixture also prints special and unspecified cases so a
 * target can label real host differences instead of accidentally treating one
 * host's result as a language-wide rule.
 */
class Main {
	static function printLine(value:String):Void {
		#if js
		js.Syntax.code("console.log({0})", value);
		#else
		Sys.println(value);
		#end
	}

	/** Reports only the ordering direction promised by the public API. */
	static function sign(value:Int):String
		return value < 0 ? "negative" : (value > 0 ? "positive" : "zero");

	static function callbackResult():String {
		final names = ["b", "a"];
		names.sort(Reflect.compare);
		return names.join(",");
	}

	static function main():Void {
		final dynamicInts:Array<Dynamic> = [1, 2];
		final dynamicStrings:Array<Dynamic> = ["a", "b"];
		printLine("int.lt=" + sign(Reflect.compare(1, 2)));
		printLine("int.eq=" + sign(Reflect.compare(1, 1)));
		printLine("float.lt=" + sign(Reflect.compare(0.25, 0.5)));
		printLine("float.eq=" + sign(Reflect.compare(0.5, 0.5)));
		printLine("float.nan.nan=" + sign(Reflect.compare(Math.NaN, Math.NaN)));
		printLine("float.nan.zero=" + sign(Reflect.compare(Math.NaN, 0.0)));
		printLine("float.zero.nan=" + sign(Reflect.compare(0.0, Math.NaN)));
		printLine("float.negativeZero.zero=" + sign(Reflect.compare(-0.0, 0.0)));
		printLine("float.negativeInfinity.zero=" + sign(Reflect.compare(Math.NEGATIVE_INFINITY, 0.0)));
		printLine("float.positiveInfinity.zero=" + sign(Reflect.compare(Math.POSITIVE_INFINITY, 0.0)));
		printLine("string.lt=" + sign(Reflect.compare("a", "b")));
		printLine("string.eq=" + sign(Reflect.compare("same", "same")));
		printLine("bool.false.true=" + sign(Reflect.compare(false, true)));
		printLine("bool.eq=" + sign(Reflect.compare(true, true)));
		printLine("null.eq=" + sign(Reflect.compare(null, null)));
		printLine("null.string=" + sign(Reflect.compare(null, "value")));
		printLine("dynamic.int.lt=" + sign(Reflect.compare(dynamicInts[0], dynamicInts[1])));
		printLine("dynamic.string.lt=" + sign(Reflect.compare(dynamicStrings[0], dynamicStrings[1])));
		printLine("callback.strings=" + callbackResult());
	}
}
