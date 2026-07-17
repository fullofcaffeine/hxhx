/**
	Repo-owned generic helper shared by the upstream and native C++ harnesses.

	The local starts without an explicit element type, then receives values from
	two generic iterables. Its returned array must retain the caller's element
	type for both primitive and string values.
**/
class GenericArrayLocal {
	public static function appendBoth<T>(left:Iterable<T>, right:Iterable<T>):Array<T> {
		final result = new Array();
		for (value in left)
			result.push(value);
		for (value in right)
			result.push(value);
		return result;
	}

	public static function lines():Array<String> {
		final empty = new Array<Int>();
		return [
			"ints=" + appendBoth([1, 2], [3, 4]).join(","),
			"strings=" + appendBoth(["a"], ["b", "c"]).join("|"),
			"right-only=" + appendBoth(empty, [7, 8]).join(",")
		];
	}
}
