private class ArrayEqualityBox {
	public final value:Int;

	public function new(value:Int) {
		this.value = value;
	}
}

/**
	Exercises Array behavior through both upstream Haxe and generated OCaml.

	`M6ArrayIntegrationTest` runs this same source through both compilers, so
	each assertion is a behavior oracle rather than a generated-text snapshot.
**/
class ArrayMain {
	static var callOrder:Array<String> = [];
	static var sortReceiverValue:Array<Int> = [];
	static var sortComparatorCalls = 0;
	static var mapCallbackCalls = 0;
	static var filterCallbackCalls = 0;

	static function makeReceiver():Array<Int> {
		callOrder.push("receiver");
		return [7];
	}

	static function makeConcatArgument():Array<Int> {
		callOrder.push("argument");
		return [8];
	}

	static function makeMutationArgument():Int {
		callOrder.push("argument");
		return 8;
	}

	static function makePairReceiver():Array<Int> {
		callOrder.push("receiver");
		return [7, 6];
	}

	static function makeInsertPosition():Int {
		callOrder.push("position");
		return 1;
	}

	static function makeInsertValue():Int {
		callOrder.push("value");
		return 8;
	}

	static function makeMatchingArgument():Int {
		callOrder.push("argument");
		return 7;
	}

	static function makeResizeLength():Int {
		callOrder.push("length");
		return 1;
	}

	static function makeSplicePosition():Int {
		callOrder.push("position");
		return 0;
	}

	static function makeSpliceLength():Int {
		callOrder.push("length");
		return 1;
	}

	static function makeSearchReceiver():Array<Int> {
		callOrder.push("receiver");
		return [7, 6, 7];
	}

	static function makeSearchValue():Int {
		callOrder.push("value");
		return 7;
	}

	static function makeSearchStart():Int {
		callOrder.push("start");
		return 1;
	}

	static function makeSliceReceiver():Array<Int> {
		callOrder.push("receiver");
		return [7, 6, 5];
	}

	static function makeSlicePosition():Int {
		callOrder.push("position");
		return 1;
	}

	static function makeSliceEnd():Int {
		callOrder.push("end");
		return 2;
	}

	static function makeSortReceiver():Array<Int> {
		callOrder.push("receiver");
		sortReceiverValue = [3, 1, 2];
		return sortReceiverValue;
	}

	static function makeSortComparator():(Int, Int) -> Int {
		callOrder.push("comparator");
		return (left, right) -> {
			sortComparatorCalls++;
			left - right;
		};
	}

	static function makeCallbackReceiver():Array<Int> {
		callOrder.push("receiver");
		return [1, 2, 3];
	}

	static function makeMapCallback():Int->String {
		callOrder.push("callback");
		return value -> {
			mapCallbackCalls++;
			callOrder.push('map:$value');
			'value=$value';
		};
	}

	static function makeFilterCallback():Int->Bool {
		callOrder.push("callback");
		return value -> {
			filterCallbackCalls++;
			callOrder.push('filter:$value');
			value % 2 == 1;
		};
	}

	static function main() {
		final a = [];

		if (a.push(1) != 1)
			throw "push_result_1";
		if (a.push(2) != 2)
			throw "push_result_2";
		if (a.length != 2)
			throw "len2";
		if (a[0] != 1)
			throw "idx0";
		if (a[1] != 2)
			throw "idx1";

		a[1] = 3;
		if (a[1] != 3)
			throw "set";

		final p = a.pop();
		if (p != 3)
			throw "pop";
		if (a.length != 1)
			throw "len1";

		a.unshift(0);
		if (a[0] != 0)
			throw "unshift";

		final s = a.shift();
		if (s != 0)
			throw "shift";

		final empty:Array<Int> = [];
		if (empty.pop() != null)
			throw "empty_pop";
		if (empty.shift() != null)
			throw "empty_shift";

		a.insert(0, 9);
		if (a[0] != 9)
			throw "insert";
		final insertion = [1, 3];
		insertion.insert(1, 2);
		insertion.insert(-1, 9);
		insertion.insert(99, 4);
		if (insertion.join(",") != "1,2,9,3,4")
			throw "insert_normalized_positions";

		final removed = a.splice(0, 1);
		if (removed.length != 1)
			throw "splice_len";
		if (removed[0] != 9)
			throw "splice_val";
		final normalizedSplice = [1, 2, 3, 4];
		final normalizedRemoved = normalizedSplice.splice(-2, 10);
		if (normalizedRemoved.join(",") != "3,4" || normalizedSplice.join(",") != "1,2")
			throw "splice_normalized_range";

		final resized:Array<Null<Int>> = [1, 2];
		resized.resize(4);
		if (resized.length != 4 || resized[0] != 1 || resized[1] != 2 || resized[2] != null || resized[3] != null)
			throw "resize_grow_null_fill";
		resized.resize(1);
		if (resized.length != 1 || resized[0] != 1)
			throw "resize_shrink";

		final b = [1, 2, 3, 4];
		final c = b.slice(1, 3);
		if (c.length != 2)
			throw "slice_len";
		if (c[0] != 2)
			throw "slice0";
		if (c[1] != 3)
			throw "slice1";
		final sliceValues = [0, 1, 2, 3];
		if (sliceValues.slice(1).join(",") != "1,2,3"
			|| sliceValues.slice(1, null).join(",") != "1,2,3"
			|| sliceValues.slice(-3, -1).join(",") != "1,2"
			|| sliceValues.slice(-99, 99).join(",") != "0,1,2,3"
			|| sliceValues.slice(3, 1).length != 0
			|| sliceValues.slice(99).length != 0
			|| sliceValues.join(",") != "0,1,2,3")
			throw "slice_ranges_or_source_mutation";
		callOrder = [];
		if (makeSliceReceiver().slice(makeSlicePosition()).join(",") != "6,5" || callOrder.join(",") != "receiver,position")
			throw "slice_default_receiver_once";
		callOrder = [];
		if (makeSliceReceiver().slice(makeSlicePosition(), makeSliceEnd()).join(",") != "6"
			|| callOrder.join(",") != "receiver,position,end")
			throw "slice_order";

		final d = b.concat([5, 6]);
		if (d.length != 6)
			throw "concat_len";
		if (d[5] != 6)
			throw "concat_val";

		final copy = b.copy();
		if (copy.length != b.length)
			throw "copy_len";
		if (copy[0] != b[0])
			throw "copy_val";
		copy[0] = 99;
		if (b[0] == 99)
			throw "copy_alias";

		callOrder = [];
		final orderedConcat = makeReceiver().concat(makeConcatArgument());
		if (callOrder.join(",") != "receiver,argument")
			throw "concat_order";
		if (orderedConcat.length != 2 || orderedConcat[0] != 7 || orderedConcat[1] != 8)
			throw "concat_once";

		callOrder = [];
		final orderedPushLength = makeReceiver().push(makeMutationArgument());
		if (callOrder.join(",") != "receiver,argument" || orderedPushLength != 2)
			throw "push_order_or_result";

		callOrder = [];
		makeReceiver().unshift(makeMutationArgument());
		if (callOrder.join(",") != "receiver,argument")
			throw "unshift_order";

		callOrder = [];
		if (makeReceiver().pop() != 7 || callOrder.join(",") != "receiver")
			throw "pop_receiver_once";

		callOrder = [];
		if (makeReceiver().shift() != 7 || callOrder.join(",") != "receiver")
			throw "shift_receiver_once";

		callOrder = [];
		makePairReceiver().reverse();
		if (callOrder.join(",") != "receiver")
			throw "reverse_receiver_once";

		callOrder = [];
		makePairReceiver().insert(makeInsertPosition(), makeInsertValue());
		if (callOrder.join(",") != "receiver,position,value")
			throw "insert_order";

		callOrder = [];
		if (!makeReceiver().remove(makeMatchingArgument()) || callOrder.join(",") != "receiver,argument")
			throw "remove_order_or_result";

		callOrder = [];
		if (!makeReceiver().contains(makeMatchingArgument()) || callOrder.join(",") != "receiver,argument")
			throw "contains_order_or_result";

		callOrder = [];
		makePairReceiver().resize(makeResizeLength());
		if (callOrder.join(",") != "receiver,length")
			throw "resize_order";

		callOrder = [];
		final orderedSplice = makePairReceiver().splice(makeSplicePosition(), makeSpliceLength());
		if (callOrder.join(",") != "receiver,position,length" || orderedSplice.join(",") != "7")
			throw "splice_order_or_result";

		callOrder = [];
		if (makeSearchReceiver().lastIndexOf(makeSearchValue()) != 2 || callOrder.join(",") != "receiver,value")
			throw "last_index_default_receiver_once";

		callOrder = [];
		if (makeSearchReceiver().indexOf(makeSearchValue(), makeSearchStart()) != 2 || callOrder.join(",") != "receiver,value,start")
			throw "index_search_order";

		if (!b.contains(3))
			throw "contains_true";
		if (b.contains(999))
			throw "contains_false";

		final repeated = [1, 2, 1];
		if (!repeated.remove(1) || repeated.join(",") != "2,1")
			throw "remove_first_match";
		if (repeated.remove(9) || repeated.join(",") != "2,1")
			throw "remove_missing";

		final identityValue = new ArrayEqualityBox(1);
		final equalShape = new ArrayEqualityBox(1);
		final identityValues = [identityValue];
		if (!identityValues.contains(identityValue) || identityValues.contains(equalShape))
			throw "contains_object_identity";
		if (identityValues.remove(equalShape) || identityValues.length != 1)
			throw "remove_object_identity";

		final searchValues = [1, 2, 1, 2];
		if (searchValues.indexOf(1) != 0 || searchValues.indexOf(1, null) != 0 || searchValues.indexOf(1, 1) != 2 || searchValues.indexOf(1, -2) != 2
			|| searchValues.indexOf(1, -99) != 0 || searchValues.indexOf(1, 99) != -1 || searchValues.indexOf(9) != -1)
			throw "index_of_ranges";
		if (searchValues.lastIndexOf(1) != 2
			|| searchValues.lastIndexOf(1, null) != 2
			|| searchValues.lastIndexOf(1, 1) != 0
			|| searchValues.lastIndexOf(1, -2) != 2
			|| searchValues.lastIndexOf(1, -99) != 0
			|| searchValues.lastIndexOf(1, 99) != 2
			|| searchValues.lastIndexOf(9) != -1)
			throw "last_index_of_ranges";
		if (empty.indexOf(1) != -1 || empty.lastIndexOf(1) != -1)
			throw "empty_index_search";
		if (identityValues.indexOf(identityValue) != 0
			|| identityValues.indexOf(equalShape) != -1
			|| identityValues.lastIndexOf(identityValue) != 0
			|| identityValues.lastIndexOf(equalShape) != -1)
			throw "index_search_object_identity";

		final rev = b.copy();
		rev.reverse();
		if (rev[0] != 4 || rev[3] != 1)
			throw "reverse";

		final sorted = [3, 1, 2];
		sorted.sort((x, y) -> x - y);
		if (sorted[0] != 1 || sorted[2] != 3)
			throw "sort";
		callOrder = [];
		sortComparatorCalls = 0;
		makeSortReceiver().sort(makeSortComparator());
		if (callOrder.join(",") != "receiver,comparator" || sortReceiverValue.join(",") != "1,2,3" || sortComparatorCalls == 0)
			throw "sort_order_mutation_or_callback";
		sortComparatorCalls = 0;
		final emptySort:Array<Int> = [];
		emptySort.sort((left, right) -> {
			sortComparatorCalls++;
			left - right;
		});
		final singleSort = [1];
		singleSort.sort((left, right) -> {
			sortComparatorCalls++;
			left - right;
		});
		if (sortComparatorCalls != 0 || emptySort.length != 0 || singleSort.join(",") != "1")
			throw "sort_empty_or_single";
		final sortedObjects = [new ArrayEqualityBox(3), new ArrayEqualityBox(1), new ArrayEqualityBox(2)];
		sortedObjects.sort((left, right) -> left.value - right.value);
		if (sortedObjects[0].value != 1 || sortedObjects[1].value != 2 || sortedObjects[2].value != 3)
			throw "sort_objects";

		final sortedFloats = [Math.POSITIVE_INFINITY, -0.0, 4.5, Math.NEGATIVE_INFINITY];
		sortedFloats.sort((x, y) -> x < y ? -1 : (x > y ? 1 : 0));
		if (sortedFloats[0] != Math.NEGATIVE_INFINITY || sortedFloats[2] != 4.5 || sortedFloats[3] != Math.POSITIVE_INFINITY)
			throw "sort_float_order";
		if (1.0 / sortedFloats[1] != Math.NEGATIVE_INFINITY)
			throw "sort_float_negative_zero";

		final floatCopy = sortedFloats.copy();
		if (floatCopy[0] != Math.NEGATIVE_INFINITY || floatCopy[3] != Math.POSITIVE_INFINITY)
			throw "copy_float";
		final floatSlice = sortedFloats.slice(1, 3);
		if (floatSlice.length != 2 || 1.0 / floatSlice[0] != Math.NEGATIVE_INFINITY || floatSlice[1] != 4.5)
			throw "slice_float";
		final floatConcat = floatSlice.concat([Math.NaN]);
		if (floatConcat.length != 3 || !Math.isNaN(floatConcat[2]))
			throw "concat_float_nan";
		final floatSplice = floatCopy.splice(1, 2);
		if (floatSplice.length != 2 || 1.0 / floatSplice[0] != Math.NEGATIVE_INFINITY || floatSplice[1] != 4.5)
			throw "splice_float";

		final sortedStrings = ["c", "a", "b"];
		sortedStrings.sort((x, y) -> x < y ? -1 : (x > y ? 1 : 0));
		if (sortedStrings.join("") != "abc")
			throw "sort_string";

		final sortedNullable:Array<Null<Int>> = [3, null, 1];
		sortedNullable.sort((x, y) -> x == null ? (y == null ? 0 : -1) : (y == null ? 1 : x - y));
		if (sortedNullable[0] != null || sortedNullable[1] != 1 || sortedNullable[2] != 3)
			throw "sort_nullable";

		final deoptimizedFloats:Array<Dynamic> = [1.5, 2.5];
		deoptimizedFloats.push("x");
		if (deoptimizedFloats[0] != 1.5 || deoptimizedFloats[1] != 2.5 || deoptimizedFloats[2] != "x")
			throw "float_deopt";
		deoptimizedFloats.insert(1, "middle");
		if (!deoptimizedFloats.contains("middle") || !deoptimizedFloats.remove("middle") || deoptimizedFloats.contains("middle"))
			throw "dynamic_insert_membership_remove";

		final strArr = ["a", "b", "c"];
		if (strArr.join("-") != "a-b-c")
			throw "join";
		if (strArr.toString() != "[a,b,c]")
			throw "toString";

		final mapped = b.map(v -> v * 2);
		if (mapped.length != 4 || mapped[0] != 2 || mapped[3] != 8)
			throw "map";
		callOrder = [];
		mapCallbackCalls = 0;
		final mappedStringsFromInts = makeCallbackReceiver().map(makeMapCallback());
		if (mappedStringsFromInts.length != 3
			|| mappedStringsFromInts[0] != "value=1"
			|| mappedStringsFromInts[2] != "value=3"
			|| mapCallbackCalls != 3
			|| callOrder.join(",") != "receiver,callback,map:1,map:2,map:3")
			throw "map_type_change_order_or_callback";

		final filtered = b.filter(v -> v % 2 == 0);
		if (filtered.length != 2 || filtered[0] != 2 || filtered[1] != 4)
			throw "filter";
		callOrder = [];
		filterCallbackCalls = 0;
		final filteredInts = makeCallbackReceiver().filter(makeFilterCallback());
		if (filteredInts.join(",") != "1,3"
			|| filterCallbackCalls != 3
			|| callOrder.join(",") != "receiver,callback,filter:1,filter:2,filter:3")
			throw "filter_order_or_callback";

		mapCallbackCalls = 0;
		filterCallbackCalls = 0;
		final emptyCallbacks:Array<Int> = [];
		if (emptyCallbacks.map(value -> {
			mapCallbackCalls++;
			value;
		}).length != 0
			|| emptyCallbacks.filter(value -> {
				filterCallbackCalls++;
				true;
			}).length != 0
			|| mapCallbackCalls != 0
			|| filterCallbackCalls != 0)
			throw "map_filter_empty_callback";

		final mapFilterSource = [1, 2, 3];
		mapFilterSource.map(value -> value + 1);
		mapFilterSource.filter(value -> value > 1);
		if (mapFilterSource.join(",") != "1,2,3")
			throw "map_filter_source_mutation";

		final mappedFloats = [1.5, 2.5].map(value -> value + 0.5);
		if (mappedFloats.length != 2 || mappedFloats[0] != 2.0 || mappedFloats[1] != 3.0)
			throw "map_float_storage";
		final filteredStrings = ["a", "bb", "c"].filter(value -> value.length == 1);
		if (filteredStrings.join(",") != "a,c")
			throw "filter_string_storage";
		final mappedNullable:Array<Int> = ([null, 2] : Array<Null<Int>>).map(value -> value == null ? -1 : value);
		if (mappedNullable.join(",") != "-1,2")
			throw "map_nullable_storage";
		final filteredObjects = [new ArrayEqualityBox(1), new ArrayEqualityBox(2)].filter(value -> value.value == 2);
		if (filteredObjects.length != 1 || filteredObjects[0].value != 2)
			throw "filter_object_storage";

		final mixed:Array<Dynamic> = [];
		mixed.push(1);
		mixed.push(2);
		mixed.push("x");
		if (mixed.length != 3)
			throw "mixed_len";
		if (mixed[2] != "x")
			throw "mixed_val";
		mixed.push(null);
		if (mixed[3] != null)
			throw "mixed_null";
	}
}
