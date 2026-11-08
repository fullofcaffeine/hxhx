/**
	Bare enum-abstract values that Stage3 cannot build natively yet: a function-value
	call with an `ET` argument, Float arithmetic and a bitwise compound with an `ET`
	value, and `Map<EA, Int>` keys (haxe_ocaml-jl3s8).
**/
enum abstract ET(Int) to Int {
	var T2 = 2;
}

enum abstract EA(Int) {
	var Uno = 1;
	var Dos = 2;
}

class TypedOnly {
	static function takesInt(value:Int):Int {
		return value * 10;
	}

	static function main():Void {
		final callback = takesInt;
		Sys.println(callback(T2));
		Sys.println(T2 * 1.5);
		var bits = 0;
		bits |= T2;
		Sys.println(bits);
		Sys.println(T2 | 1);
		final dynamicValue:Dynamic = 5;
		Sys.println(T2 + dynamicValue);
		Sys.println(dynamicValue - T2);
		final counts = new Map<EA, Int>();
		counts.set(Uno, 1);
		counts.set(Dos, 2);
		counts[Uno] = counts[Uno] + 10;
		Sys.println(counts.get(Uno) + " " + counts.get(Dos) + " " + counts.exists(Dos));
	}
}
