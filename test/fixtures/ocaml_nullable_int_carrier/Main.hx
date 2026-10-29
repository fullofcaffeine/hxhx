/**
	Observe how `Null<Int>` and `Null<Float>` values move between a nullable
	and a concrete representation.

	The version parser is the shape that failed in the end-to-end Stage3 job: a
	ternary whose branches mix a nullable `Std.parseInt` result with a plain `0`.
	It receives the already split version parts because this root-only harness
	emits no `String.split` provider.
	The remaining cases cover a plain assignment into a nullable local, arithmetic
	after a null check, comparing a nullable value with a literal, returning a
	nullable value from a function whose branches disagree about nullability,
	passing values between nullable and concrete parameters, whole-number
	Float values, ordered comparisons, array indexing, String and Array
	intrinsics with nullable Int arguments, instance and constructor defaults,
	and the untouched Null<Bool> behaviour.
	Upstream Haxe and the native OCaml program must print the same lines.
 */
class Main {
	static inline final DEFAULT_COMPILER_VERSION:Int = 40307;

	static function parseCompilerVersion(parts:Array<String>):Int {
		if (parts.length == 0)
			return DEFAULT_COMPILER_VERSION;
		final major = Std.parseInt(parts[0]);
		final minor = parts.length > 1 ? Std.parseInt(parts[1]) : 0;
		final patch = parts.length > 2 ? Std.parseInt(parts[2]) : 0;
		if (major == null || minor == null || patch == null)
			return DEFAULT_COMPILER_VERSION;
		return (major * 10000) + (minor * 100) + patch;
	}

	static function parsedOrSeven(useParsed:Bool, raw:String):Null<Int> {
		return useParsed ? Std.parseInt(raw) : 7;
	}

	static function absentOrThree(absent:Bool):Null<Int> {
		return absent ? null : 3;
	}

	static function square(value:Int):Int {
		return value * value;
	}

	static function sizeOr(?size:Int):Int {
		return size == null ? 16 : size;
	}

	static function scaled(value:Int, ?scale:Int = 3):Int {
		return value * scale;
	}

	static function stretched(value:Int, ?factor:Float = 1.5):Float {
		return value * factor;
	}

	static function flagText(?flag:Bool):String {
		return flag == null ? "null" : (flag ? "Y" : "N");
	}

	final offset:Int;

	public function new(?offset:Int = 4) {
		this.offset = offset;
	}

	function shifted(value:Int, ?by:Int = 10):Int {
		return value + by + offset;
	}

	static function main():Void {
		Sys.println(Std.string(parseCompilerVersion(["4", "3", "7"])));
		Sys.println(Std.string(parseCompilerVersion(["4", "3"])));
		Sys.println(Std.string(parseCompilerVersion(["4"])));
		Sys.println(Std.string(parseCompilerVersion([])));
		Sys.println(Std.string(parseCompilerVersion(["4", "x", "7"])));
		var count:Null<Int> = 0;
		count = 41;
		final next:Null<Int> = count == null ? 0 : count + 1;
		Sys.println(Std.string(next));
		count = null;
		Sys.println(Std.string(count == null)
			+ " "
			+ Std.string(next == 42)
			+ " "
			+ Std.string(count != null)
			+ " "
			+ Std.string(next != 42));
		var ratio:Null<Float> = null;
		Sys.println(Std.string(ratio));
		ratio = 1.25;
		final doubled:Null<Float> = ratio == null ? 0.5 : ratio * 2;
		Sys.println(Std.string(doubled) + " " + Std.string(doubled == 2.5));
		Sys.println(Std.string(parsedOrSeven(true, "12"))
			+ " "
			+ Std.string(parsedOrSeven(true, "nope"))
			+ " "
			+ Std.string(parsedOrSeven(false, "12")));
		Sys.println(Std.string(absentOrThree(true)) + " " + Std.string(absentOrThree(false)));
		final fromParts = parsedOrSeven(true, "9");
		if (fromParts != null)
			Sys.println(Std.string(square(fromParts)));
		Sys.println(Std.string(sizeOr()) + " " + Std.string(sizeOr(8)) + " " + Std.string(sizeOr(fromParts)));
		Sys.println(Std.string(scaled(2)) + " " + Std.string(scaled(2, 5)) + " " + Std.string(scaled(2, fromParts)));
		var whole:Null<Float> = 2.0;
		final tripled:Float = whole * 3;
		Sys.println(Std.string(tripled == 6) + " " + Std.string(whole == 2) + " " + Std.string(whole > 1.5));
		Sys.println(Std.string(stretched(2) == 3) + " " + Std.string(stretched(2, 3.0) == 6) + " " + Std.string(stretched(3, 0.5)));
		var maybeFlag:Null<Bool> = true;
		Sys.println(flagText() + " " + flagText(true) + " " + flagText(false) + " " + (maybeFlag ? "on" : "off"));
		final values = [10, 20, 30];
		var index:Null<Int> = 1;
		index = 2;
		Sys.println(Std.string(values[index])
			+ " "
			+ Std.string(index > 1)
			+ " "
			+ Std.string(index <= 1)
			+ " "
			+ Std.string(index >= fromParts));
		final text = "abcabc";
		var start:Null<Int> = null;
		Sys.println(Std.string(text.indexOf("a", start)) + " " + Std.string(text.lastIndexOf("a", start)) + " " + text.substr(1, start));
		start = 3;
		Sys.println(Std.string(text.indexOf("a", start)) + " " + Std.string(text.charCodeAt(start)) + " " + text.substring(start, start)
			+ text.substr(start, start));
		var sliceEnd:Null<Int> = null;
		Sys.println(Std.string(values.slice(1, sliceEnd).length) + " " + Std.string(values.indexOf(30, sliceEnd)));
		sliceEnd = 2;
		Sys.println(Std.string(values.slice(sliceEnd).length) + " " + Std.string(values.lastIndexOf(10, sliceEnd)));
		final plain = new Main();
		final custom = new Main(1);
		Sys.println(Std.string(plain.shifted(1)) + " " + Std.string(custom.shifted(1, fromParts)) + " " + Std.string(custom.shifted(1, 2)));
	}
}
