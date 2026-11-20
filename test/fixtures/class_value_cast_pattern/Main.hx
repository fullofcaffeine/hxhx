/**
	A switch on a class value can match `cast` patterns with a dotted type path, as
	`haxe.Serializer` does with `case cast haxe.ds.StringMap:`. Haxe 4.3.7 treats the path as a
	type, not as a qualified enum constructor. The operations live in their own class, declared
	before `Main`, so that calls from `main` cannot supply the evidence.
**/
class Ops {
	public static function kind(value:Dynamic) {
		return switch (Type.getClass(value)) {
			case cast Array: "array";
			case cast haxe.ds.StringMap: "string map";
			case cast haxe.ds.IntMap: "int map";
			case _: "other";
		}
	}
}

class Main {
	static function main() {
		Sys.println(Ops.kind([1]));
		Sys.println(Ops.kind(new haxe.ds.StringMap<Int>()));
		Sys.println(Ops.kind(new haxe.ds.IntMap<Int>()));
		Sys.println(Ops.kind("text"));
	}
}
