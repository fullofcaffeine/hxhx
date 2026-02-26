private class WeakKey {
	public final id:Int;

	public function new(id:Int) {
		this.id = id;
	}
}

private class HashKey {
	public final id:Int;

	public function new(id:Int) {
		this.id = id;
	}

	public function hashCode():Int {
		return id;
	}
}

class Main {
	static function main() {
		final arrayValues = [3, 1, 2, 1];
		haxe.ds.ArraySort.sort(arrayValues, (left, right) -> Reflect.compare(left, right));
		Sys.println("arraysort=" + arrayValues.join(","));

		final either:haxe.ds.Either<Int, String> = haxe.ds.Either.Left(7);
		Sys.println("either=" + Std.string(either));

		final optionValue:haxe.ds.Option<Int> = haxe.ds.Option.None;
		final optionIsNone = switch (optionValue) {
			case None: true;
			case Some(_): false;
		};
		Sys.println("option.none=" + optionIsNone);

		final readOnly:haxe.ds.ReadOnlyArray<Int> = [4, 5];
		Sys.println("readonly.len=" + readOnly.length);
		final readOnlyConcat = readOnly.concat([6]);
		Sys.println("readonly.concat=" + readOnlyConcat.join(","));

		final vector = new haxe.ds.Vector<Int>(3);
		vector[0] = 9;
		vector[1] = 8;
		vector[2] = 7;
		Sys.println("vector.join=" + vector.join(","));

		final balancedTree = new haxe.ds.BalancedTree<String, Int>();
		Sys.println("balancedTree.created=" + (balancedTree != null));

		final enumValueMap = new haxe.ds.EnumValueMap<haxe.ds.Option<Int>, String>();
		Sys.println("enumValueMap.created=" + (enumValueMap != null));

		final genericStack = new haxe.ds.GenericStack<Int>();
		Sys.println("genericStack.created=" + (genericStack != null));

		final hashMap = new haxe.ds.HashMap<HashKey, Int>();
		Sys.println("hashMap.created=" + (hashMap != null));

		final list = new haxe.ds.List<Int>();
		Sys.println("list.created=" + (list != null));

		final weakMapCreated = try {
			final weakMap = new haxe.ds.WeakMap<WeakKey, Int>();
			weakMap != null;
		} catch (_:haxe.Exception) {
			false;
		};
		Sys.println("weakMap.created=" + weakMapCreated);

		final listSortRef = haxe.ds.ListSort.sortSingleLinked;
		Sys.println("listsort.ref=" + (listSortRef != null));
	}
}
