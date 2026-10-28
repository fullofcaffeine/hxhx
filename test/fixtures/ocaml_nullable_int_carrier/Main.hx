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
	and passing values between nullable and concrete parameters.
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
	}
}
