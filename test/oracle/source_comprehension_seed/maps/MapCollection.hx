/** Map yields retain written grouping, guarded branches, and exact loop bindings. */
class MapCollection {
	public static function plain():Map<Int, Int>
		return [for (item in [1, 2]) item => item + 1];

	public static function grouped():Map<Int, Int>
		return [for (item in [1, 2]) (item => item + 1)];

	public static function nested():Map<Int, Int>
		return [for (item in [1, 2]) ((item => item + 1))];

	public static function guarded():Map<Int, Int>
		return [for (item in [1, 2, 3]) if (item > 1) (item => item + 1)];

	public static function indexed():Map<Int, Int>
		return [for (key => item in [5, 8]) ((key => item))];

	public static function branches():Map<Int, Int>
		return [for (item in [1, 2]) if (item == 1) (item => 10) else (item => 20)];

	public static function loops():Map<Int, Int>
		return [for (left in [1, 2]) for (right in [3, 4]) (left * 10 + right => right)];

	public static function qualifiedMapValues():Array<haxe.ds.Map<Int, Int>>
		return [for (item in [1, 2]) [item => item + 1]];

	public static function mapValues():Array<Map<Int, Int>>
		return [for (item in [1, 2]) [item => item + 1]];
}
