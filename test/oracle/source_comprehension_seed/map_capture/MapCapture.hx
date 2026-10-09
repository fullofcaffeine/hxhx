/** Replacing a map entry must release its old closure and retain the new iteration binding. */
class MapCapture {
	public static function strings():haxe.ds.Map<String, Void->Int>
		return [
			for (index => key in ["a", "b", "a"])
				(key => function() {
					return index + 1;
				})
		];

	public static function collect():haxe.ds.Map<Int, Void->Int>
		return [
			for (index => key in [1, 0, 1])
				(key => function() {
					return index + 1;
				})
		];
}
