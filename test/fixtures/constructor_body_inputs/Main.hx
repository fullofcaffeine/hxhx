/** Constructor inputs inferred from fields must survive generic application and retention. */
class Main {
	static function main():Void {
		final box = new Box<String, Int>(null, "key", 7, null);
		if (box.key != "key" || box.value != 7 || box.height != -1)
			throw "inferred constructor fields or default";
		final child = new Child(null, 3, "child", null, 5);
		if (child.key != 3 || child.value != "child" || child.height != 5)
			throw "inherited constructor specialization";
		final inferred = new Box(null, "inferred", 9, null);
		if (inferred.key != "inferred" || inferred.value != 9 || inferred.height != -1)
			throw "omitted owner arguments";
		if (Box.calls != 3)
			throw "constructor effects";
	}
}

/** Field assignments and the written default provide the omitted input types. */
class Box<K, V> {
	public static var calls:Int = 0;

	public var left:Box<K, V>;
	public var right:Box<K, V>;
	public var key:K;
	public var value:V;
	public var height:Int;

	public function new(l, k, v, r, h = -1) {
		left = l;
		key = k;
		value = v;
		right = r;
		height = h;
		calls++;
	}
}

/** The allocated child differs from the constructor's declaring generic owner. */
class Child extends Box<Int, String> {}
