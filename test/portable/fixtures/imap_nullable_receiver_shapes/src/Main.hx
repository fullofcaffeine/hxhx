import haxe.Constraints.IMap;
import haxe.ds.StringMap;

/**
	Instance fields whose type is a nullable standard Map.

	This mirrors a compiler class that fills its lookup tables lazily: each
	field starts as `null`, is assigned a Map later, and is then read through
	the ordinary Map API without first copying it into a non-null local.
**/
class Tables {
	public var names:Null<Map<String, String>> = null;
	public var counts:Null<Map<Int, Int>> = null;
	public var raw:Null<StringMap<Int>> = null;

	public function new() {}

	public function fill():Void {
		final created:Map<String, String> = [];
		created.set("a.b", "gap");
		names = created;
		final numbers:Map<Int, Int> = [];
		numbers.set(1, 10);
		counts = numbers;
		final direct = new StringMap<Int>();
		direct.set("x", 7);
		raw = direct;
	}

	public function name(key:String):Null<String> {
		return names.get(key);
	}

	public function guardedName(key:String):String {
		if (names != null)
			return "found:" + names.get(key);
		return "no-table";
	}

	public function exercise():String {
		names.set("c.d", "other");
		counts.set(2, 20);
		raw.set("y", 8);
		final nameKeys = [for (key in names.keys()) key];
		nameKeys.sort(Reflect.compare);
		final countValues = [for (value in counts) value];
		countValues.sort(Reflect.compare);
		final rawKeys = [for (key in raw.keys()) key];
		rawKeys.sort(Reflect.compare);
		return [
			"exists=" + names.exists("c.d"),
			"removed=" + names.remove("c.d"),
			"after=" + names.exists("c.d"),
			"nameKeys=" + nameKeys.join(","),
			"count=" + counts.get(2),
			"countHas=" + counts.exists(3),
			"countRemoved=" + counts.remove(1),
			"countValues=" + countValues.join(","),
			"raw=" + raw.get("x"),
			"rawRemoved=" + raw.remove("x"),
			"rawKeys=" + rawKeys.join(",")
		].join(" ");
	}
}

/** A generic class whose nullable Map field is typed by its own parameters. */
class Box<K, V> {
	public var entries:Null<Map<K, V>> = null;

	public function new() {}

	public function read(key:K):Null<V> {
		return entries.get(key);
	}

	public function write(key:K, value:V):Void {
		entries.set(key, value);
	}

	public function has(key:K):Bool {
		return entries.exists(key);
	}

	public function drop(key:K):Bool {
		return entries.remove(key);
	}

	public function size():Int {
		var count = 0;
		for (_ in entries.keys())
			count++;
		for (_ in entries)
			count++;
		return count;
	}
}

/** An object key, compared by identity like every class instance key. */
class Key {
	public final name:String;

	public function new(name:String) {
		this.name = name;
	}
}

typedef Holder = {
	final table:Null<Map<String, Int>>;
}

/**
	Calls Map methods on values whose static type is `Null<Map<K,V>>`.

	A present Map must behave like any other Map. A null Map must fail with a
	catchable error at the method call, as the Haxe 4.3.7 eval target does.
**/
class Main {
	static function emit(line:String):Void {
		#if js
		js.Syntax.code("console.log({0})", line);
		#else
		Sys.println(line);
		#end
	}

	static function makeInts(present:Bool):Null<Map<Int, String>> {
		if (!present)
			return null;
		final created:Map<Int, String> = [];
		created.set(4, "four");
		return created;
	}

	static function isAbsent(map:IMap<String, Int>):Bool {
		return map == null;
	}

	static function failure(action:() -> Void):String {
		try {
			action();
			return "no-error";
		} catch (_:Dynamic) {
			return "caught";
		}
	}

	static function main():Void {
		final tables = new Tables();
		emit("emptyGuard=" + tables.guardedName("a.b"));
		emit("nullField=" + failure(() -> tables.name("a.b")));
		emit("nullFieldSet=" + failure(() -> tables.counts.set(1, 1)));
		tables.fill();
		emit("field=" + tables.name("a.b"));
		emit("guard=" + tables.guardedName("a.b"));
		emit(tables.exercise());

		emit("call=" + makeInts(true).get(4));
		emit("nullCall=" + failure(() -> makeInts(false).get(4)));

		final local:Null<Map<Int, String>> = makeInts(true);
		local.set(5, "five");
		emit("local=" + local.get(5) + " " + local.exists(4));

		final holder:Holder = {table: ["k" => 3]};
		emit("anon=" + holder.table.get("k"));

		// Generic `Map<K,V>` code uses the object-key map carrier, so these cases
		// use class keys. String and Int keys through generic code are a separate,
		// known target limitation.
		final first = new Key("first");
		final second = new Key("second");
		final boxed = new Box<Key, Int>();
		emit("genericNull=" + failure(() -> boxed.read(first)));
		final created:Map<Key, Int> = [];
		created.set(first, 1);
		boxed.entries = created;
		boxed.write(second, 2);
		emit("generic="
			+ boxed.read(first)
			+ " "
			+ boxed.read(second)
			+ " "
			+ boxed.has(second)
			+ " "
			+ boxed.drop(first)
			+ " "
			+ boxed.size());

		final absent:Null<Map<String, Int>> = null;
		final present:Null<Map<String, Int>> = ["p" => 1];
		emit("convertNull=" + isAbsent(absent) + " convertMap=" + isAbsent(present));
	}
}
