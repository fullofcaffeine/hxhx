/** Object key used to verify identity-based Map lookups. **/
class ArrowObjectKey {
	public final id:Int;

	public function new(id:Int) {
		this.id = id;
	}
}

/** Enum-key control for the existing enum carrier path. **/
enum ArrowMarker {
	First;
	Second;
}

/**
	Upstream Haxe 4.3.7 oracle for arrow-map literal specialization.

	Each literal must behave as a Map whose runtime specialization follows its
	key type. The ordinary array at the end remains an Array control.
**/
class Main {
	static function main():Void {
		final ints = [1 => "two", 3 => "four"];
		Sys.println(ints is haxe.ds.IntMap);
		Sys.println(ints.get(1));
		Sys.println(ints.get(3));

		final strings = ["one" => 2, "three" => 4];
		Sys.println(strings is haxe.ds.StringMap);
		Sys.println(strings.get("one"));
		Sys.println(strings.get("three"));

		final first = new ArrowObjectKey(1);
		final second = new ArrowObjectKey(2);
		final sameId = new ArrowObjectKey(1);
		final objects = [first => "left", second => "right"];
		Sys.println(objects is haxe.ds.ObjectMap);
		Sys.println(objects.get(first));
		Sys.println(objects.get(second));
		Sys.println(objects.get(sameId) == null);

		final markers = [ArrowMarker.First => 10, ArrowMarker.Second => 20];
		Sys.println(markers is haxe.ds.EnumValueMap);
		Sys.println(markers.get(ArrowMarker.Second));

		final ordinary:Array<Int> = [1, 2, 3];
		Sys.println(ordinary[1] == 2 ? "array" : "bad-array");
	}
}
