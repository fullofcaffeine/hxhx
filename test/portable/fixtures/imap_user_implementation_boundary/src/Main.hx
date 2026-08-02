import haxe.Constraints.IMap;

private class ObjectKey {
	public final id:Int;

	public function new(id:Int) {
		this.id = id;
	}
}

/**
	A user-authored `IMap` whose visible marker and call log prove real interface dispatch.

	The private `StringMap` supplies storage only. Calls received through the public
	`IMap` boundary must still execute these methods, including `copy()` returning
	another interface value, rather than bypassing this class and calling the OCaml
	standard-Map runtime directly.
**/
private class TaggedStringMap implements IMap<String, Int> {
	final storage:haxe.ds.StringMap<Int>;
	final tag:String;

	public final calls:Array<String>;

	public function new(tag:String) {
		this.tag = tag;
		this.storage = new haxe.ds.StringMap<Int>();
		this.calls = [];
	}

	public function get(key:String):Null<Int> {
		calls.push("get:" + key);
		return storage.get(key);
	}

	public function set(key:String, value:Int):Void {
		calls.push("set:" + key);
		storage.set(key, value);
	}

	public function exists(key:String):Bool {
		calls.push("exists:" + key);
		return storage.exists(key);
	}

	public function remove(key:String):Bool {
		calls.push("remove:" + key);
		return storage.remove(key);
	}

	public function keys():Iterator<String> {
		calls.push("keys");
		return storage.keys();
	}

	public function iterator():Iterator<Int> {
		calls.push("iterator");
		return storage.iterator();
	}

	public function keyValueIterator():KeyValueIterator<String, Int> {
		calls.push("pairs");
		return storage.keyValueIterator();
	}

	public function copy():IMap<String, Int> {
		calls.push("copy");
		final copied = new TaggedStringMap(tag + "-copy");
		for (key => value in storage)
			copied.storage.set(key, value);
		return copied;
	}

	public function toString():String {
		calls.push("text");
		return "tagged:" + tag;
	}

	public function clear():Void {
		calls.push("clear");
		storage.clear();
	}
}

/**
	Exercises both sources of an `IMap` value: a user implementation and Haxe's
	three standard Map specializations. A passing native build proves that the
	interface boundary dispatches through the received value instead of treating
	every receiver as a key-selected standard hash table.
**/
class Main {
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

	static function orderedReceiver(order:Array<String>, map:IMap<String, Int>):IMap<String, Int> {
		order.push("receiver");
		return map;
	}

	static function orderedKey(order:Array<String>):String {
		order.push("key");
		return "ordered";
	}

	static function orderedValue(order:Array<String>):Int {
		order.push("value");
		return 5;
	}

	static function exerciseCustom(map:IMap<String, Int>):Void {
		map.set("b", 2);
		map.set("a", 1);
		final found = map.get("a");
		final missing = map.get("missing");
		emit("custom.get=" + found + ":" + (missing == null));
		emit("custom.exists=" + map.exists("b"));
		final removedFirst = map.remove("b");
		final removedSecond = map.remove("b");
		emit("custom.remove=" + removedFirst + ":" + removedSecond);
		map.set("b", 2);
		final keys = [for (key in map.keys()) key];
		keys.sort(compareText);
		emit("custom.keys=" + keys.join(","));
		var values = 0;
		for (value in map)
			values += value;
		emit("custom.values=" + values);
		var pairs = 0;
		for (_ => value in map)
			pairs += value;
		emit("custom.pairs=" + pairs);
		final copied = map.copy();
		copied.set("a", 9);
		emit("custom.copy=" + map.get("a") + ":" + copied.get("a"));
		emit("custom.text=" + map.toString());
		map.clear();
		emit("custom.clear=" + !map.keys().hasNext());
	}

	static function exerciseStringStandard(map:IMap<String, Int>):Void {
		map.set("s", 7);
		emit("standard.string=" + map.get("s"));
	}

	/** Exercises a constructor whose expected return type is already the interface. */
	static function newStringStandard():IMap<String, Int> {
		return new haxe.ds.StringMap<Int>();
	}

	static function exerciseIntStandard(map:IMap<Int, String>):Void {
		map.set(4, "four");
		emit("standard.int=" + map.get(4));
	}

	static function exerciseObjectStandard(map:IMap<ObjectKey, Int>, key:ObjectKey):Void {
		map.set(key, 11);
		emit("standard.object=" + map.get(key));
	}

	static function main():Void {
		final order:Array<String> = [];
		final ordered = new TaggedStringMap("ordered");
		orderedReceiver(order, ordered).set(orderedKey(order), orderedValue(order));
		emit("custom.order=" + order.join("|") + ":" + ordered.get("ordered"));
		final custom = new TaggedStringMap("source");
		exerciseCustom(custom);
		emit("custom.calls=" + custom.calls.join("|"));
		exerciseStringStandard(newStringStandard());
		exerciseIntStandard(new haxe.ds.IntMap<String>());
		final key = new ObjectKey(1);
		exerciseObjectStandard(new haxe.ds.ObjectMap<ObjectKey, Int>(), key);
		emit("OK imap_user_implementation_boundary");
	}
}
