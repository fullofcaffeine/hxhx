import haxe.ds.StringMap;

class Main {
	static function makeMap<V>(value:V):StringMap<V> {
		final result = new StringMap<V>();
		result.set("value", value);
		return result;
	}

	static function makeList<A>(value:A):List<A> {
		final result = new List<A>();
		result.add(value);
		return result;
	}

	static function main():Void {
		final map = makeMap(42);
		if (map.get("value") != 42)
			throw "generic StringMap constructor lost its value";

		final list = makeList("ok");
		if (list.first() != "ok")
			throw "generic List constructor lost its value";
	}
}
