/**
	Pass `Null<Int>` and `Null<Float>` values (and, through the ordinary call path, a `Null<Bool>`) to parameters of the concrete type.

	Haxe allows `Null<Int>` where `Int` is expected. The native route keeps a
	nullable value in a boxed carrier and a concrete `Int` as a native `int`, so
	every call boundary must convert. This program covers the standard static
	call `String.fromCharCode`, ordinary static, instance, and constructor calls,
	Array and Map methods, String methods, and `Math.abs`. All values are non-null
	here; the null case is native-only (see `../stage3_nullable_call_arguments_null`).
**/
class Box {
	public final value:Int;

	public function new(value:Int) {
		this.value = value;
	}

	public function scaled(factor:Int):Int {
		return value * factor;
	}
}

class Main {
	static function plusOne(n:Int):Int {
		return n + 1;
	}

	static function half(x:Float):Float {
		return x / 2;
	}

	static function answer(b:Bool):String {
		return b ? "yes" : "no";
	}

	static function main():Void {
		final code:Null<Int> = Std.parseInt("65");
		final two:Null<Int> = Std.parseInt("2");
		Sys.println("fromCharCode: " + String.fromCharCode(Std.parseInt("72")) + String.fromCharCode(code));
		Sys.println("static: " + plusOne(two));
		final box = new Box(two);
		Sys.println("constructor and instance: " + box.value + " " + box.scaled(two));

		final values = [10, 20, 30];
		Sys.println("array index: " + values[two]);
		values.push(two);
		values.insert(two, 5);
		Sys.println("array push and insert: " + values.join(","));
		Sys.println("array indexOf: " + values.indexOf(two));
		Sys.println("array slice: " + values.slice(two).join(","));

		final names = new Map<Int, String>();
		names.set(two, "two");
		Sys.println("map: " + names.get(two) + " " + names.exists(two));

		Sys.println("string: " + "abcdef".charAt(two) + " " + "abcdef".substr(two, two));
		final three:Null<Int> = Std.parseInt("-3");
		final absolute = Math.abs(three);
		// Print through Std.int: whole-number Float text is haxe_ocaml-iffj5.
		Sys.println("math abs: " + Std.int(absolute));

		final ratio:Null<Float> = Std.parseFloat("3.5");
		final halves = [half(ratio), half(three)];
		Sys.println("float: " + halves[0] + " " + halves[1]);
		final flag:Null<Bool> = two > 1;
		Sys.println("bool: " + answer(flag));
	}
}
