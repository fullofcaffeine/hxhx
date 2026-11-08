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
	public var byKey:Null<Map<Key, Int>> = null;

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

/**
	Method results of every dispatch kind, with an evaluation log.

	`make` and `key` record when they run, so the fixture can check that a
	nullable receiver is evaluated once and before the method arguments. When
	the receiver is null, Haxe 4.3.7 eval throws before it evaluates the key.
**/
class Provider {
	public var calls = 0;
	public var log:Array<String> = [];
	public var table:Null<Map<String, Int>> = null;

	public function new() {}

	public function make(present:Bool):Null<Map<String, Int>> {
		calls++;
		log.push("make");
		if (!present)
			return null;
		return ["k" => 1];
	}

	public function key():String {
		log.push("key");
		return "k";
	}

	public function value():Int {
		log.push("value");
		return 9;
	}

	public dynamic function dyn():Null<Map<String, Int>> {
		return ["d" => 4];
	}
}

class BaseLookup {
	public function new() {}

	public function lookup():Null<Map<String, Int>> {
		return null;
	}
}

class DerivedLookup extends BaseLookup {
	override public function lookup():Null<Map<String, Int>> {
		return ["o" => 6];
	}
}

abstract Wrap(Provider) {
	public function new(provider:Provider) {
		this = provider;
	}

	public function look():Null<Map<String, Int>> {
		return this.table;
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

	static function isAbsentInt(map:IMap<Int, String>):Bool {
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

		// A method call on a nullable Map *local* has no null check on this
		// target yet (a known gap, tracked separately), so this case only uses
		// a present Map.
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
		emit("convertIntNull=" + isAbsentInt(makeInts(false)) + " convertIntMap=" + isAbsentInt(makeInts(true)));

		// An explicit IMap local keeps null when it is never used as a method
		// receiver, whether it is unused or only compared.
		var unusedView:IMap<String, Int> = absent;
		final comparedView:IMap<String, Int> = absent;
		emit("comparedView=" + (comparedView == null));

		final provider = new Provider();
		emit("once=" + provider.make(true).get(provider.key()) + " calls=" + provider.calls + " log=" + provider.log.join(","));
		provider.log = [];
		emit("order=" + provider.make(true).exists(provider.key()) + " log=" + provider.log.join(","));
		provider.log = [];
		provider.make(true).set(provider.key(), provider.value());
		emit("setLog=" + provider.log.join(","));
		provider.log = [];
		emit("nullOrder=" + failure(() -> provider.make(false).get(provider.key())) + " log=" + provider.log.join(","));
		emit("dynamic=" + provider.dyn().get("d"));
		final lookup:BaseLookup = new DerivedLookup();
		emit("override=" + lookup.lookup().get("o"));
		provider.table = ["w" => 7];
		emit("abstract=" + new Wrap(provider).look().get("w"));

		final keyed = new Key("keyed");
		final objectTable = new Tables();
		emit("nullObjectField=" + failure(() -> objectTable.byKey.get(keyed)));
		final byKey:Map<Key, Int> = [];
		byKey.set(keyed, 11);
		objectTable.byKey = byKey;
		emit("objectField=" + objectTable.byKey.get(keyed) + " " + objectTable.byKey.exists(first));
	}
}
