import haxe.ds.Map;

/** A nominal object key, independent of Map's standard-library declarations. */
class Key {
	public function new() {}
}

/** An enum key must remain distinct from an ordinary class key. */
enum Marker {
	First;
}

/** Exercise inferred, written, and generic Map contracts through real providers. */
class Main {
	static function ints()
		return [1 => "one", 2 => "two"];

	static function strings()
		return ["one" => 1];

	static function objects()
		return [new Key() => "one"];

	static function enums()
		return [Marker.First => "one"];

	static function ordinary()
		return [1, 2];

	static function records()
		return [{name: "first"}, {name: "hit"}];

	static function nested()
		return [[{name: "nested"}]];

	static function genericArray<V>(value:V)
		return [value];

	static function written():Map<Int, String>
		return [1 => "one"];

	static function generic<V>(value:V):Map<String, V>
		return ["one" => value];

	static function main():Void {
		Sys.println(ints().get(2));
		Sys.println(strings().get("one"));
		Sys.println(enums().get(Marker.First));
		Sys.println(written().get(1));
		Sys.println(generic("generic").get("one"));
		Sys.println(ordinary()[1]);
		Sys.println(records()[1].name);
		Sys.println(nested()[0][0].name);
		Sys.println(genericArray("array")[0]);
	}
}
