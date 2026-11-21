/**
	Reading an optional structure field yields `Null<T>` in Haxe 4.3.7: an absent `?crc:Int`
	reads as `null`, not as an `Int`. The operations live in their own class, declared before
	`Main`, so that calls from `main` cannot supply the evidence.
**/
typedef Entry = {name:String, ?crc:Int, ?label:String};

/** Direct reads; the test checks that hxhx types their results as `Null<Int>` and `Null<String>`. **/
class Reads {
	public static function crcOf(e:Entry)
		return e.crc;

	public static function labelOf(e:Entry)
		return e.label;
}

class Ops {
	public static function describe(name:String, withCrc:Bool) {
		final entry:Entry = withCrc ? {name: name, crc: 7} : {name: name};
		final crc = entry.crc;
		return name + ":" + (crc == null ? "none" : Std.string(crc));
	}

	public static function label(name:String) {
		final entry:Entry = {name: name};
		final text = entry.label;
		return text == null ? "no label" : text;
	}
}

class Main {
	static function main() {
		Sys.println(Ops.describe("a", true));
		Sys.println(Ops.describe("b", false));
		Sys.println(Ops.label("c"));
		Sys.println(Reads.crcOf({name: "z"}) == null);
	}
}
