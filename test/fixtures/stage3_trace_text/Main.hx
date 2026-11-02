enum Box {
	Flagged(on:Bool);
	Pair(on:Bool, label:String);
	Maybe(on:Null<Bool>);
}

class Holder {
	public var label:String;

	public function new() {}
}

class Main {
	static var flag = true;

	static function main() {
		// Trace prefixes the call's file and line.
		trace("hello");
		trace(flag);
		trace(42, "extra", true);
		trace(null);
		final nothing:String = null;
		trace(nothing);
		trace(Flagged(true), Pair(false, "p"));
		Helper.report(7);
		haxe.Log.trace("direct", null);
		// Bool enum arguments.
		Sys.println(Std.string(Flagged(true)) + " " + Pair(false, "x"));
		Sys.println([Flagged(false), Flagged(true)].join(","));
		Sys.println(Std.string(Maybe(true)) + " " + Std.string(Maybe(null)));
		// String += on a field with null operands. Static targets are left to
		// haxe_ocaml-nq65n (PR #131), which stores static field writes.
		final holder = new Holder();
		holder.label += "x";
		Sys.println(holder.label);
		holder.label += nothing;
		Sys.println(holder.label);
	}
}
