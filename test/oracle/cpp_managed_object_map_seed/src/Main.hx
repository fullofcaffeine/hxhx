/** Equal record fields do not make equal object keys; repeated keys replace values. */
class Main {
	public static function create(nullKey:{id:Int}) {
		final first = {id: 7};
		final second = {id: 7};
		final map = [first => [1], first => [2], second => [3], nullKey => [4]];
		return {first: first, second: second, map: map};
	}

	static function main():Void {
		final result = create(null);
		Sys.println(result.map is haxe.ds.ObjectMap);
		Sys.println(result.map.get(result.first)[0]);
		Sys.println(result.map.get(result.second)[0]);
		Sys.println(result.map.get({id: 7}) == null);
		Sys.println(result.map.get(null)[0]);
	}
}
