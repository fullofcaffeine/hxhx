/** Native map construction contracts with explicit provider identities. */
class MapExecution {
	public static function plain():haxe.ds.Map<Int, Int>
		return [for (item in [1, 2]) ((item => item + 1))];

	public static function duplicates():haxe.ds.Map<Int, Int>
		return [for (item in [1, 2, 3]) (item % 2 => item)];

	public static function guarded():haxe.ds.Map<Int, Int>
		return [
			for (left in [1, 2])
				for (right in [3, 4])
					if (right == 4)
						(left * 10 + right => right)
		];

	public static function effects():haxe.ds.Map<Int, Int> {
		var order = 0;
		return [for (item in [1, 2]) ((order = order * 10 + item) => (order = order * 10 + 9))];
	}

	public static function captures():haxe.ds.Map<Int, Void->Int>
		return [
			for (item in [1, 2])
				(item => function() {
					return item;
				})
		];

	public static function strings():haxe.ds.Map<String, Int>
		return [for (index => item in ["a", "b", "a"]) (item => index)];
}
