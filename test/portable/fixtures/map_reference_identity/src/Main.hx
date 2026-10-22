import haxe.ds.IntMap;
import haxe.ds.StringMap;
import haxe.ds.ObjectMap;

typedef MaybeMap = Null<Map<Int, String>>;

/** Equality preserves identity, null values, and left-to-right effects in eval and native output. */
class Main {
	static var effects:String = "";
	static final initial:Map<Int, String> = [3 => "same"];
	static final initialSame:Bool = keep(initial) == initial;

	static function keep(value:Null<Map<Int, String>>):Null<Map<Int, String>> {
		return value;
	}

	static function effect(label:String, value:MaybeMap):MaybeMap {
		effects += label;
		return value;
	}

	static function require(value:Bool, name:String):Void {
		if (!value)
			throw "Map identity failed: " + name;
	}

	static function main():Void {
		final value:Map<Int, String> = [3 => "same"];
		final other:Map<Int, String> = [3 => "same"];
		Sys.println(keep(value) == value);
		Sys.println(value == other);
		require(initialSame, "static initializer");
		require(value == keep(value), "reversed nullable");
		require(!(keep(value) != value), "same nullable inequality");
		require(value != keep(other), "different nullable inequality");
		require(keep(value) == keep(value), "two nullable aliases");
		require(keep(value) != keep(other), "two nullable distinct maps");
		final absent:MaybeMap = null;
		require(absent == keep(null), "two null maps");
		require(absent != value && value != absent, "null versus map");
		require(value != null && null != value, "literal null");
		require(absent == null && null == absent, "nullable literal null");
		final nested = () -> keep(value) == value;
		require(nested(), "nested function");
		require(keep(value) == value, "outer plan restored");
		require(effect("L", value) == effect("R", value), "effectful equality");
		require(effects == "LR", "equality effects once in order");
		effects = "";
		require(effect("L", value) != effect("R", other), "effectful inequality");
		require(effects == "LR", "inequality effects once in order");
		final ints = new IntMap<String>();
		final otherInts = new IntMap<String>();
		ints.set(1, "same");
		otherInts.set(1, "same");
		final nullableInts:Null<IntMap<String>> = ints;
		require(ints == nullableInts && ints != otherInts, "IntMap");
		final strings = new StringMap<Int>();
		final otherStrings = new StringMap<Int>();
		strings.set("key", 1);
		otherStrings.set("key", 1);
		final nullableStrings:Null<StringMap<Int>> = strings;
		require(nullableStrings == strings && otherStrings != strings, "StringMap");
		final objects = new ObjectMap<Key, String>();
		final otherObjects = new ObjectMap<Key, String>();
		final key = new Key();
		objects.set(key, "same");
		otherObjects.set(key, "same");
		final nullableObjects:Null<ObjectMap<Key, String>> = objects;
		require(objects == nullableObjects && objects != otherObjects, "ObjectMap");
		final stringAbstract:Map<String, Int> = ["key" => 1];
		final otherStringAbstract:Map<String, Int> = ["key" => 1];
		require(stringAbstract != otherStringAbstract, "string Map abstract");
		final objectAbstract:Map<Key, Int> = [key => 1];
		final otherObjectAbstract:Map<Key, Int> = [key => 1];
		require(objectAbstract != otherObjectAbstract, "object Map abstract");
		Sys.println("map identity contracts: OK");
	}
}

/** Concrete object-map key shared by two distinct maps. */
class Key {
	public function new() {}
}
