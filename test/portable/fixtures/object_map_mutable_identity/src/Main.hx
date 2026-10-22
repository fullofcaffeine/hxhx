import haxe.ds.ObjectMap;

/** A key's reachable state can change without changing which object it is. */
private class Cell {
	public var value:Int;

	public function new(value:Int) {
		this.value = value;
	}
}

/** Equal fields do not make separately allocated keys equal. */
private class Key {
	public final id:Int;
	public var revision:Int;
	public final cell:Cell;

	public function new(id:Int, revision:Int, cell:Cell) {
		this.id = id;
		this.revision = revision;
		this.cell = cell;
	}

	public function total():Int {
		return id + revision + cell.value;
	}
}

/** Map insertion must preserve dispatch through the declared base-class type. */
private class SpecializedKey extends Key {
	public function new() {
		super(7, 0, new Cell(3));
	}

	override public function total():Int {
		return super.total() + 100;
	}
}

/** Empty allocation retains class identity before ordinary field initialization. */
private class EmptyKey {
	public var value:Int;

	public function new(value:Int) {
		this.value = value;
	}

	public function read():Int {
		return value;
	}
}

/** Anonymous records remain valid keys after callers update their fields. */
private typedef RecordKey = {
	var name:String;
	var revision:Int;
}

/** Object maps use allocation identity across mutation, copying, and class lookup. */
class Main {
	static function check(condition:Bool, label:String):Void {
		if (!condition)
			throw label;
		Sys.println(label + ":ok");
	}

	static function main():Void {
		final key = new Key(7, 0, new Cell(3));
		final alias = key;
		final map = new ObjectMap<Key, Int>();
		map.set(key, 10);
		check(map.exists(alias) && map.get(alias) == 10, "initial-alias");

		key.revision = 2;
		check(map.exists(alias) && map.get(alias) == 10, "mutable-field");
		key.cell.value = 5;
		check(map.exists(alias) && map.get(alias) == 10, "nested-mutation");

		final distinct = new Key(7, 2, new Cell(5));
		check(!map.exists(distinct), "distinct-equal-fields-absent");
		map.set(distinct, 99);
		check(map.get(key) == 10 && map.get(distinct) == 99, "distinct-values");
		map.set(alias, 20);
		check(map.get(key) == 20 && map.get(distinct) == 99, "same-key-replacement");

		final copied = map.copy();
		copied.set(key, 30);
		check(map.get(key) == 20 && copied.get(alias) == 30 && copied.get(distinct) == 99, "copy-value-independence");
		key.cell.value = 9;
		check(map.get(key) == 20 && copied.get(alias) == 30, "copied-key-nested-mutation");

		check(map.remove(alias) && !map.exists(key) && copied.get(key) == 30, "remove-after-mutation");
		check(!map.remove(alias) && copied.exists(key), "missing-remove-independence");
		map.set(key, 40);
		map.clear();
		check(!map.exists(key) && !map.exists(distinct) && copied.get(key) == 30 && copied.get(distinct) == 99, "clear-original-independence");

		map.set(key, 50);
		check(copied.remove(distinct) && map.get(key) == 50 && !map.exists(distinct), "copy-remove-independence");
		copied.clear();
		check(!copied.exists(key) && map.get(alias) == 50, "clear-copy-independence");
		check(map.remove(key) && !map.exists(alias), "final-remove");

		final record:RecordKey = {name: "entry", revision: 0};
		final records = new ObjectMap<RecordKey, Int>();
		records.set(record, 61);
		record.name = "changed";
		record.revision = 4;
		check(records.exists(record) && records.get(record) == 61, "anonymous-mutation");
		final otherRecord:RecordKey = {name: "changed", revision: 4};
		records.set(otherRecord, 62);
		check(records.get(record) == 61 && records.get(otherRecord) == 62, "anonymous-distinct-values");

		final array = [1, 2];
		final arrays = new ObjectMap<Array<Int>, Int>();
		arrays.set(array, 71);
		array.push(3);
		array[0] = 9;
		check(arrays.exists(array) && arrays.get(array) == 71, "array-mutation");
		final otherArray = [9, 2, 3];
		arrays.set(otherArray, 72);
		check(arrays.get(array) == 71 && arrays.get(otherArray) == 72, "array-distinct-values");

		final first = Type.createEmptyInstance(EmptyKey);
		final second = Type.createEmptyInstance(EmptyKey);
		first.value = 8;
		second.value = 8;
		check(first != second && Type.getClass(first) == EmptyKey && Type.getClass(second) == EmptyKey, "empty-instance-class");
		final emptyKeys = new ObjectMap<EmptyKey, Int>();
		emptyKeys.set(first, 81);
		emptyKeys.set(second, 82);
		check(emptyKeys.get(first) == 81 && emptyKeys.get(second) == 82, "empty-instance-distinct-values");
		first.value = 12;
		check(Type.getClass(first) == EmptyKey
			&& Type.getClass(second) == EmptyKey
			&& first.read() == 12
			&& emptyKeys.get(first) == 81,
			"empty-instance-after-mutation");

		final specialized:Key = new SpecializedKey();
		check(specialized.total() == 110 && Type.getClass(specialized) == SpecializedKey, "method-before-insertion");
		map.set(specialized, 91);
		specialized.revision = 2;
		check(specialized.total() == 112
			&& Type.getClass(specialized) == SpecializedKey
			&& map.get(specialized) == 91, "method-after-insertion");
	}
}
