/**
	Prints Floats through each `reflaxe.ocaml` String conversion and requires
	the same text as upstream Haxe 4.3.7 (haxe_ocaml-iffj5).

	OCaml's `string_of_float` printed `2.` for `2.0` and kept only 12
	significant digits. `test.sh` compares this program's eval output with
	`expected.stdout`, so the native output is checked against upstream too.
	NaN and the infinities are left out: upstream targets print them
	differently.
**/
class Main {
	static var field:Float = 3.0;

	static function half(value:Float):Float {
		return value / 2;
	}

	static function main() {
		var whole:Float = 2.0;
		var seven:Float = 7.0;
		var nullable:Null<Float> = 4.0;
		var dynamicValue:Dynamic = 5.0;
		Sys.println("std=" + Std.string(whole));
		Sys.println("concat=" + whole + "/" + field + "/" + half(200));
		Sys.println("literal=" + 2.0 + "/" + 0.5);
		Sys.println("signed=" + 0.0 + "/" + (-0.0));
		Sys.println("digits=" + seven / 3 + "/" + (0.1 + 0.2) + "/" + 1234567890123.0);
		Sys.println("exponent=" + 1e15 + "/" + 1e21 + "/" + 1e-5 + "/" + 5e-324);
		Sys.println("short=" + 0.1 + "/" + 1.5 + "/" + 12345.678);
		Sys.println("nullable=" + nullable + " dynamic=" + dynamicValue);
		var text = "compound=";
		text += whole;
		Sys.println(text);
		final values:Array<Float> = [1.0, 2.5, seven / 3];
		Sys.println("array=" + values.toString() + " join=" + values.join(","));
		final map:Map<String, Float> = ["a" => 6.0];
		Sys.println("map=" + map.toString());
		Sys.println("object=" + Std.string({a: 3.0}));
	}
}
