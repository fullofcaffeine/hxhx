import haxe.ds.StringMap;

/** A map copy must preserve both the key and the enum payload. */
enum Entry {
	Value(number:Int);
}

/** Copies use the instance field directly, as compiler inference forks do. */
class Table {
	final entries = new StringMap<Entry>();

	public function new() {}

	public function put(key:String, value:Entry):Void {
		entries.set(key, value);
	}

	public function number(key:String):Int {
		return switch entries.get(key) {
			case Value(number): number;
			case _: -1;
		};
	}

	public function copy():Table {
		final result = new Table();
		for (key => value in entries)
			result.entries.set(key, value);
		return result;
	}
}

/** The copy must retain entries and own subsequent map updates independently. */
class Main {
	/** An unrelated iterator returns ordinary records with the same field names. */
	static function ordinaryPairs():haxe.iterators.ArrayIterator<{key:String, value:Int}> {
		return [{key: "ordinary", value: 31}].iterator();
	}

	static function main():Void {
		final original = new Table();
		original.put("selected", Value(17));
		final copied = original.copy();
		Sys.println("original=" + original.number("selected"));
		Sys.println("copied=" + copied.number("selected"));
		copied.put("selected", Value(29));
		Sys.println("independent=" + original.number("selected") + ":" + copied.number("selected"));
		final ordinary = ordinaryPairs();
		final alias = ordinary;
		final pair = alias.next();
		Sys.println("object=" + pair.key + ":" + pair.value);
	}
}
