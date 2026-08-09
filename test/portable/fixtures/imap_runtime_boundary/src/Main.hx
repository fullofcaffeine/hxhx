import haxe.Constraints.IMap;

private class ObjectKey {
	public final id:Int;

	public function new(id:Int) {
		this.id = id;
	}
}

/**
	Exercises Haxe 4.3.7's standard Map contract through an `IMap` receiver.

	The fixed key types are intentional: the OCaml target can select the standard
	StringMap, IntMap, or ObjectMap carrier before syntax without claiming
	dispatch for arbitrary user-defined `IMap` implementations.
**/
class Main {
	static var forwarded:Map<String, Int> = [];
	static var forwardedInts:Map<Int, String> = [];
	static var forwardedObjects:Map<ObjectKey, Int> = [];

	static function compareText(left:String, right:String):Int {
		return left < right ? -1 : (left > right ? 1 : 0);
	}

	static function emit(line:String):Void {
		#if js
		js.Syntax.code("console.log({0})", line);
		#else
		Sys.println(line);
		#end
	}

	static function hasMapText(text:String, expectedEntries:Array<String>):Bool {
		if (text.charAt(0) != "[" || text.charAt(text.length - 1) != "]")
			return false;
		for (entry in expectedEntries) {
			if (text.indexOf(entry) < 0)
				return false;
		}
		return true;
	}

	static function runStrings(map:IMap<String, Int>):Void {
		map.set("a", 1);
		map.set("b", 2);
		emit("string.get=" + map.get("a"));
		emit("string.missing=" + (map.get("missing") == null));
		emit("string.exists=" + map.exists("b"));
		final removed = map.remove("b");
		final removedAgain = map.remove("b");
		emit("string.remove=" + removed + ":" + removedAgain);
		map.set("c", 3);
		final keys = [for (key in map.keys()) key];
		keys.sort(compareText);
		emit("string.keys=" + keys.join(","));
		var valueSum = 0;
		for (value in map)
			valueSum += value;
		emit("string.values=" + valueSum);
		var pairSum = 0;
		for (_ => value in map)
			pairSum += value;
		emit("string.pairs=" + pairSum);
		final copy = map.copy();
		copy.set("a", 9);
		emit("string.copy=" + map.get("a") + ":" + copy.get("a"));
		emit("string.text=" + hasMapText(map.toString(), ["a => 1", "c => 3"]));
		map.clear();
		emit("string.clear=" + !map.keys().hasNext());
	}

	static function runInts(map:IMap<Int, String>):Void {
		map.set(20, "y");
		map.set(10, "x");
		emit("int.get=" + map.get(10));
		emit("int.missing=" + (map.get(30) == null));
		emit("int.exists=" + map.exists(20));
		final removed = map.remove(20);
		final removedAgain = map.remove(20);
		emit("int.remove=" + removed + ":" + removedAgain);
		map.set(20, "y");
		final keys = [for (key in map.keys()) key];
		keys.sort((left, right) -> left - right);
		emit("int.keys=" + keys.join(","));
		final values = [for (value in map) value];
		values.sort(compareText);
		emit("int.values=" + values.join(""));
		var pairSum = 0;
		for (key => _ in map)
			pairSum += key;
		emit("int.pairs=" + pairSum);
		final copy = map.copy();
		copy.set(10, "z");
		emit("int.copy=" + map.get(10) + ":" + copy.get(10));
		emit("int.text=" + hasMapText(map.toString(), ["10 => x", "20 => y"]));
		map.clear();
		emit("int.clear=" + !map.iterator().hasNext());
	}

	static function runObjects(map:IMap<ObjectKey, Int>, first:ObjectKey, equalLooking:ObjectKey):Void {
		map.set(first, 123);
		emit("object.identity=" + map.get(first) + ":" + (map.get(equalLooking) == null));
		emit("object.exists=" + map.exists(first));
		var keySum = 0;
		for (key in map.keys())
			keySum += key.id;
		emit("object.keys=" + keySum);
		var valueSum = 0;
		for (value in map)
			valueSum += value;
		emit("object.values=" + valueSum);
		var pairSum = 0;
		for (key => value in map)
			pairSum += key.id + value;
		emit("object.pairs=" + pairSum);
		final removed = map.remove(first);
		final removedAgain = map.remove(first);
		emit("object.remove=" + removed + ":" + removedAgain);
		map.set(first, 7);
		final copy = map.copy();
		copy.set(first, 8);
		emit("object.copy=" + map.get(first) + ":" + copy.get(first));
		emit("object.text=" + hasMapText(map.toString(), [" => 7"]));
		map.clear();
		emit("object.clear=" + !map.keyValueIterator().hasNext());
	}

	/** Proves that a function literal owns its own IMap decisions and standard Map aliases. */
	static function runNested():Void {
		forwarded.set("nested", 8);
		forwardedInts.set(4, "four");
		final forwardedObject = new ObjectKey(2);
		forwardedObjects.set(forwardedObject, 6);
		final hasKey = function(key:String):Bool {
			final concrete = new haxe.ds.StringMap<Int>();
			concrete.set(key, 7);
			final map:IMap<String, Int> = concrete;
			return map.exists(key)
				&& forwarded != null
				&& forwarded.exists(key)
				&& forwardedInts.exists(4)
				&& forwardedObjects.exists(forwardedObject);
		};
		emit("nested.exists=" + hasKey("nested"));

		// A source-level Map crossing into IMap is a real interface boundary. It
		// must still receive the dispatch adapter; only Haxe's closed native-map
		// expansion temporary may keep raw target storage.
		final standard:Map<String, Int> = [];
		standard.set("boxed", 9);
		final boxed:IMap<String, Int> = standard;
		emit("nested.mapInterface=" + boxed.exists("boxed"));
	}

	static function main():Void {
		runStrings(new haxe.ds.StringMap<Int>());
		runInts(new haxe.ds.IntMap<String>());
		final first = new ObjectKey(1);
		runObjects(new haxe.ds.ObjectMap<ObjectKey, Int>(), first, new ObjectKey(1));
		runNested();
	}
}
