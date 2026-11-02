/**
	Arithmetic whose operand is a nullable value or a Dynamic value must have
	the type Haxe gives it, also when the result goes straight into a call:
	`Null<Float> * 2 + 0.5` is a Float, `Null<Int> / Int` is a Float, and
	`Dynamic + Int` is Dynamic. Each printed Float has a fractional part, so
	the output does not depend on how whole-number Floats are formatted.
**/
class Main {
	static function half(x:Float):Float
		return x / 2;

	static function main():Void {
		// A Null<Float> compound assignment value used as an operand.
		var ratio:Null<Float> = 1.5;
		final r = (ratio *= 2.5) + 0.5;
		Sys.println(r);
		Sys.println((ratio -= 1) * 2);
		var count:Null<Int> = 3;
		Sys.println((count += 2) / 4);
		// A Map<String, Float> lookup (Null<Float>) as an operand.
		final weights = new Map<String, Float>();
		weights.set("a", 1.25);
		Sys.println(weights.get("a") + 0.5);
		Sys.println(weights.get("a") * 3);
		Sys.println(half(weights.get("a") + 2));
		final ages = new Map<String, Int>();
		ages.set("x", 7);
		Sys.println(ages.get("x") / 2);
		Sys.println(ages.get("x") + 1);
		// Null<Int> / Int passed to a Float parameter.
		final s = "Hello";
		Sys.println(Std.int(s.charCodeAt(0) / 2));
		Sys.println(half(s.charCodeAt(1) / 4));
		Sys.println(s.charCodeAt(0) / 16);
		// A Dynamic + Int result passed straight to Sys.println.
		final boxed:Dynamic = 41;
		Sys.println(boxed + 1);
		Sys.println(boxed * 0.5);
		// `- * / %` with a Dynamic operand are Float in Haxe.
		final scaled:Float = boxed * 0.25;
		Sys.println(scaled);
		Sys.println(half(boxed - 0.5));
		Sys.println(boxed / 4);
	}
}
