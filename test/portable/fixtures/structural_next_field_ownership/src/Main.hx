private typedef LinkedNode = {
	var value:Int;
	var next:LinkedNode;
}

private typedef FlagField = {
	var hasNext:Bool;
}

private typedef StoredEntry = {
	var key:String;
	var value:Int;
}

/**
	Exercises ordinary structural fields whose names overlap Iterator protocols.

	The linked-node `next` and payload `value` fields are stored object data. The
	separate `StoredEntry` also proves that `key` and `value` remain readable and
	mutable. In contrast, the `IMap` loop receives genuine key/value iterator
	elements from the target's tuple-producing map runtime. Keeping both cases in
	one executable prevents either representation from being selected merely from
	the field spelling.

	Taking `ListSort.sortSingleLinked` as a value keeps the generic implementation
	as a real generated function, so the test also observes the same `q.next`
	reads and `tail.next = value` writes that previously became Iterator closures
	or no-ops.
**/
class Main {
	static function emit(line:String):Void {
		#if js
		js.Syntax.code("console.log({0})", line);
		#else
		Sys.println(line);
		#end
	}

	static function node(value:Int, next:LinkedNode):LinkedNode {
		return {value: value, next: next};
	}

	static function values(head:LinkedNode):String {
		final out:Array<String> = [];
		var current = head;
		while (current != null) {
			out.push(Std.string(current.value));
			current = current.next;
		}
		return out.join(",");
	}

	static function nestedNextValue(head:LinkedNode):Int {
		final readNext = () -> head.next.value;
		return readNext();
	}

	static function enableFlag(flag:FlagField):Bool {
		flag.hasNext = true;
		return flag.hasNext;
	}

	static function updateStoredEntry(entry:StoredEntry):String {
		entry.key = "after";
		entry.value = 2;
		return entry.key + ":" + entry.value;
	}

	static function mapEntries(map:haxe.Constraints.IMap<String, Int>):String {
		final entries:Array<String> = [];
		for (key => value in map)
			entries.push(key + ":" + value);
		entries.sort((left, right) -> left < right ? -1 : (left > right ? 1 : 0));
		return entries.join(",");
	}

	#if ocaml_structural_tuple_write_negative
	/** Exercises the compile-time rejection of mutation on a proven Map pair. */
	static function writeMapPair(map:haxe.Constraints.IMap<String, Int>):Void {
		final iterator = map.keyValueIterator();
		final pair = iterator.next();
		pair.value = 99;
	}
	#end

	static function main():Void {
		final third = node(3, null);
		final first = node(2, node(1, third));
		emit("field.read=" + first.next.value);
		emit("field.nested=" + nestedNextValue(first));
		emit("field.hasNext=" + enableFlag({hasNext: false}));
		emit("field.entry=" + updateStoredEntry({key: "before", value: 1}));

		final map = new haxe.ds.StringMap<Int>();
		map.set("b", 2);
		map.set("a", 1);
		#if ocaml_structural_tuple_write_negative
		writeMapPair(map);
		#end
		emit("iterator.entries=" + mapEntries(map));

		final sort:LinkedNode->(LinkedNode->LinkedNode->Int) -> LinkedNode = haxe.ds.ListSort.sortSingleLinked;
		final sorted = sort(first, (left, right) -> left.value - right.value);
		emit("listsort.values=" + values(sorted));
	}
}
