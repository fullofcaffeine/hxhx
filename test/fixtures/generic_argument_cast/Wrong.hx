enum abstract Kind(Int) to Int {
	var First = 1;
}

/** The binding goes to the first argument: Int does not cast to Kind, so upstream rejects this. */
class Wrong {
	static function same<T>(a:T, b:T):Bool
		return a == b;

	static function main()
		Sys.println(same(First, 1));
}
