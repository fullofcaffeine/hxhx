/**
	Bare enum-abstract values used as call arguments.

	`T1` names a member of `ET`, which converts `to Int`, so it can be passed where an
	Int is expected. Upstream Haxe 4.3.7 resolves the bare name without qualification.
	`TypedOnly.hx` holds forms that are checked by typing only, because Stage3 cannot
	build them natively yet: a function-value call with an enum-abstract argument,
	`Map<EA, Int>` keys (haxe_ocaml-njq5n), Float arithmetic with an enum-abstract
	value, and bitwise operators (`|=` builds but keeps the old value,
	haxe_ocaml-sq6ii).
**/

// A module's own enum-abstract value comes before an imported static of the same name.
import Other.T1;

enum abstract ET(Int) to Int {
	var T1 = 1;
	var T2 = 2;
	var lower = 3;
}

enum abstract ES(String) to String {
	var SA = "a";
}

class Box {
	public final value:Int;

	public function new(value:Int) {
		this.value = value;
	}

	public function plus(amount:Int):Int {
		return value + amount;
	}
}

class Main {
	static function takesInt(value:Int):Int {
		return value * 10;
	}

	static function takesString(value:String):String {
		return value + "!";
	}

	static function second():Int {
		return T2;
	}

	static function main():Void {
		Sys.println(takesInt(T1));
		Sys.println(takesInt(lower));
		Sys.println(new Box(T2).value);
		Sys.println(new Box(1).plus(T1));
		Sys.println(second());
		final values:Array<Int> = [T1, T2];
		Sys.println(values.length + " " + values[0] + " " + values[1]);
		Sys.println(takesString(SA));
		// An operator on a `to Int` enum abstract uses its Int value.
		Sys.println(T1 + 1);
		Sys.println(T1 - T2);
		Sys.println(T1 * T2);
		Sys.println(T2 % T1);
		Sys.println(-T1);
	}
}
