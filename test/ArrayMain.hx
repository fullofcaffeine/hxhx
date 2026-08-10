/**
	Exercises Array behavior through both upstream Haxe and generated OCaml.

	`M6ArrayIntegrationTest` runs this same source through both compilers, so
	each assertion is a behavior oracle rather than a generated-text snapshot.
**/
class ArrayMain {
	static var callOrder:Array<String> = [];

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

		final removed = a.splice(0, 1);
		if (removed.length != 1)
			throw "splice_len";
		if (removed[0] != 9)
			throw "splice_val";

		final b = [1, 2, 3, 4];
		final c = b.slice(1, 3);
		if (c.length != 2)
			throw "slice_len";
		if (c[0] != 2)
			throw "slice0";
		if (c[1] != 3)
			throw "slice1";

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

		if (!b.contains(3))
			throw "contains_true";
		if (b.contains(999))
			throw "contains_false";

		if (b.indexOf(3) != 2)
			throw "indexof";
		if (b.lastIndexOf(3) != 2)
			throw "lastindexof";

		final rev = b.copy();
		rev.reverse();
		if (rev[0] != 4 || rev[3] != 1)
			throw "reverse";

		final sorted = [3, 1, 2];
		sorted.sort((x, y) -> x - y);
		if (sorted[0] != 1 || sorted[2] != 3)
			throw "sort";

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

		final strArr = ["a", "b", "c"];
		if (strArr.join("-") != "a-b-c")
			throw "join";
		if (strArr.toString() != "[a,b,c]")
			throw "toString";

		final mapped = b.map(v -> v * 2);
		if (mapped.length != 4 || mapped[0] != 2 || mapped[3] != 8)
			throw "map";

		final filtered = b.filter(v -> v % 2 == 0);
		if (filtered.length != 2 || filtered[0] != 2 || filtered[1] != 4)
			throw "filter";

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
