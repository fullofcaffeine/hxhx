enum Color {
	Red;
	Rgb(r:Int, g:Int, b:Int);
}

enum Shape {
	Named(name:String);
	Painted(color:Color);
	Sized(size:{w:Int});
}

enum abstract Kind(Int) {
	var First = 1;
	var Second = 2;
}

abstract Meters(Float) from Float to Float {}
abstract Count(Int) from Int to Int {}
abstract Switch(Bool) from Bool to Bool {}

/**
	Uninitialized statics whose carrier is an unboxed number or Bool. Upstream
	eval prints null for them and Stage3 holds 0, 0.0 or false (the
	static-target default, haxe_ocaml-a8wbz), so the fixture only reads them
	in comparisons that print the same on both. The test checks the emitted
	defaults.
**/
class Numbers {
	public static var kind:Kind;
	public static var meters:Meters;
	public static var count:Count;
	public static var flag:Switch;
	public static var unsigned:UInt;
	public static var int32:haxe.Int32;
	public static var plain:Int;
	public static var ratio:Float;
}

class Holder {
	public static var slabel:String;
	public static var scount:Null<Int>;
	public static var sflag:Null<Bool>;
	public static var sitems:Array<Int>;

	public var label:String;

	public function new() {}
}

class Main {
	static var staticText:String = null;

	static function maybe(flag:Bool):String {
		return flag ? "yes" : null;
	}

	static function count(flag:Bool):Null<Int> {
		return flag ? 3 : null;
	}

	static function main() {
		// Null Strings on either side of +.
		final nothing:String = maybe(false);
		final present = maybe(true);
		Sys.println("x=" + nothing);
		Sys.println(nothing + "=x");
		Sys.println("call " + maybe(false) + " " + maybe(true));
		Sys.println("static " + staticText);
		final holder = new Holder();
		Sys.println("field " + holder.label);
		Sys.println(present + nothing);
		// Null Strings through other text paths.
		Sys.println(nothing);
		Sys.println(Std.string(nothing));
		Sys.println('interpolated ${nothing}');
		final words:Array<String> = ["a", null, "b"];
		Sys.println(words.join(","));
		Sys.println(Std.string(words));
		// String += on a null local, as a statement and as a value.
		var s:String = null;
		s += "x";
		Sys.println(s);
		var t:String = null;
		final r = (t += "y");
		Sys.println(r + " " + t);
		var u = "start";
		u += nothing;
		Sys.println(u);
		// Null<Int> values in concatenation.
		final hello = "Hello";
		Sys.println("concat " + (hello.charCodeAt(9) + "a"));
		Sys.println("code " + hello.charCodeAt(0) + " " + hello.charCodeAt(9));
		Sys.println("count " + count(true) + " " + count(false));
		final missing:Null<Int> = null;
		Sys.println(missing + "!");
		// A parenthesized Int addition inside a concatenation stays arithmetic.
		final number = 41;
		Sys.println("sum " + (number + 1) + " " + ("(" + (number + 1) + ")"));
		// Enum values.
		Sys.println("e=" + Red);
		Sys.println("e=" + Rgb(1, 2, 3));
		final color = Rgb(4, 5, 6);
		Sys.println(Std.string(color) + " " + Std.string(Red));
		Sys.println([Red, Rgb(7, 8, 9)].join(" "));
		Sys.println(Std.string([Red, color]));
		// Null enum values and enum arguments of other types.
		final noColor:Color = null;
		Sys.println("none " + noColor + " " + Std.string(noColor));
		Sys.println(Std.string(Named("n")) + " " + Named(null) + " " + Painted(Rgb(1, 2, 3)) + " " + Painted(null));
		Sys.println(Std.string(Sized({w: 2})));
		// Statics without an initializer hold null.
		Sys.println(Holder.slabel);
		Sys.println("numbers " + (Numbers.kind == Numbers.kind) + " " + (Numbers.meters == Numbers.meters) + " " + (Numbers.count == Numbers.count) + " "
			+ (Numbers.flag == Numbers.flag) + " " + (Numbers.int32 == Numbers.int32) + " " + (Numbers.plain == Numbers.plain) + " "
			+ (Numbers.ratio == Numbers.ratio));
		Sys.println("statics " + Holder.slabel + " " + Holder.scount + " " + Holder.sflag + " " + Holder.sitems);
	}
}
