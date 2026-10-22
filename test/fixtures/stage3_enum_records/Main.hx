/** A stored record may have extra fields without changing its enum payload carrier. */
typedef Box = {
	var count:Int;
	var flag:Bool;
}

typedef WideBox = {
	var count:Int;
	var flag:Bool;
	var extra:String;
}

enum Packet {
	Record(value:Box);
	Pair(left:Box, right:Box);
	Optional(?value:Box);
	Nullable(value:Null<Box>);
}

/** Observe the ordinary record contract without macro APIs or untyped escapes. */
class Main {
	static function make(label:String, count:Int, flag:Bool):Box {
		Sys.println(label);
		return {count: count, flag: flag};
	}

	static function count():Int {
		Sys.println("count");
		return 3;
	}

	static function flag():Bool {
		Sys.println("flag");
		return false;
	}

	static function main():Void {
		final original:Box = {count: 7, flag: true};
		final packet = Record(original);
		original.count = 9;
		original.flag = false;
		switch packet {
			case Record(stored):
				Sys.println(stored == original);
				Sys.println(stored.count);
				Sys.println(stored.flag);
				stored.count = 10;
				stored.flag = true;
			case _:
				throw "wrong record constructor";
		}
		Sys.println(original.count);
		Sys.println(original.flag);
		final wider:WideBox = {count: 20, flag: true, extra: "retained"};
		final narrowed = Record(wider);
		wider.count = 23;
		wider.flag = false;
		switch narrowed {
			case Record(stored):
				Sys.println(stored == wider);
				Sys.println(stored.count);
				Sys.println(stored.flag);
			case _:
				throw "wrong width-subtyping constructor";
		}
		Sys.println(wider.extra);
		final ordered = Pair(make("left", 1, true), make("right", 2, false));
		switch ordered {
			case Pair(left, right):
				Sys.println(left.count);
				Sys.println(left.flag);
				Sys.println(right.count);
				Sys.println(right.flag);
			case _:
				throw "wrong pair constructor";
		}
		final literal = Record({count: count(), flag: flag()});
		switch literal {
			case Record(stored):
				Sys.println(stored.count);
				Sys.println(stored.flag);
			case _:
				throw "wrong literal constructor";
		}
		for (value in [Optional(), Optional(null), Nullable(null), Record(null)])
			switch value {
				case Optional(stored), Nullable(stored), Record(stored):
					Sys.println(stored == null);
				case _:
					throw "wrong null constructor";
			}
		for (value in [Optional(original), Nullable(original)])
			switch value {
				case Optional(stored), Nullable(stored):
					Sys.println(stored == original);
				case _:
					throw "wrong present constructor";
			}
	}
}
