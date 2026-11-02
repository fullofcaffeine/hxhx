/**
	Constant switch patterns, compared with upstream Haxe 4.3.7.

	A Float constant pattern must match only its own value: `case 1.5:` used
	to parse as a wildcard and matched every value. The other literal kinds
	(Int, negative numbers, String, Bool, null) must stay exact too, including
	inside or-patterns and with guards. Results are printed as Strings, so no
	Float formatting is involved.
**/
class Main {
	static function float(x:Float):String {
		return switch x {
			case 1.5: "one and a half";
			case -2.5: "minus two and a half";
			case 1e3: "thousand";
			case 2.5e-1: "quarter";
			case .5: "half";
			case 3: "three (Int pattern)";
			case -4: "minus four (Int pattern)";
			case 7 | 8.5: "seven or eight and a half";
			case 0.1 | 0.2: "a tenth or two tenths";
			case v if (v > 100): "large";
			case 42.0 if (false): "never";
			case 42.0: "forty-two";
			case _: "other";
		}
	}

	/** `case 1.:` is a valid Haxe spelling; `0.0` and `-0.0` match each other, and NaN matches no constant. */
	static function special(x:Float):String {
		return switch x {
			case 0.0: "zero";
			case 1.: "one";
			case _: "other";
		}
	}

	static function negativeZero(x:Float):String {
		return switch x {
			case -0.0: "negative zero pattern";
			case _: "other";
		}
	}

	static function integer(x:Int):String {
		return switch x {
			case -1: "minus one";
			case 0: "zero";
			case 1 | 2: "one or two";
			case n if (n < 0): "negative";
			case _: "positive";
		}
	}

	static function text(s:Null<String>):String {
		return switch s {
			case null: "null";
			case "": "empty";
			case "a" | "b": "a or b";
			case v if (v.length > 3): "long";
			case _: "short";
		}
	}

	static function flag(b:Null<Bool>):String {
		return switch b {
			case true: "yes";
			case false: "no";
			case _: "unknown";
		}
	}

	static function main() {
		for (x in [
			1.5,
			-2.5,
			1000.0,
			0.25,
			0.5,
			3.0,
			-4.0,
			7.0,
			8.5,
			0.1,
			0.2,
			0.30000000000000004,
			101.0,
			42.0,
			9.0,
			1.4999999999999998
		])
			Sys.println(float(x));
		for (x in [0.0, -0.0, 1.0, Math.NaN])
			Sys.println(special(x));
		for (x in [0.0, -0.0, Math.NaN])
			Sys.println(negativeZero(x));
		for (x in [-1, 0, 1, 2, -7, 9])
			Sys.println(integer(x));
		for (s in [null, "", "a", "b", "long text", "xy"])
			Sys.println(text(s));
		for (b in [true, false, null])
			Sys.println(flag(b));
	}
}
