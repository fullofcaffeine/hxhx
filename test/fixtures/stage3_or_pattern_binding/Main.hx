/**
	Or-patterns that bind the same name in each alternative.

	Upstream Haxe 4.3.7 binds `s` from whichever alternative matched. The
	alternatives may read the payload from different positions and from
	different constructors, and an or-pattern may sit inside another
	constructor or carry a guard.
**/
enum Item {
	A(text:String);
	B(text:String);
	C(count:Int, text:String);
	D;
}

enum Box {
	Wrap(item:Item);
}

class Main {
	static function label(item:Item):String {
		return switch (item) {
			case A(s) | B(s):
				"text " + s;
			case C(_, s) if (s.length > 3):
				"long " + s;
			default:
				"not_found";
		}
	}

	static function swapped(item:Item):String {
		return switch (item) {
			case A(s) | C(_, s):
				"first " + s;
			case B(_) | D if (item != D):
				"second";
			case _:
				"rest";
		}
	}

	static function nested(box:Box):String {
		return switch (box) {
			case Wrap(A(s) | B(s)):
				"wrapped " + s;
			case Wrap(_):
				"wrapped other";
		}
	}

	static function main() {
		final items = [A("a"), B("b"), C(2, "c"), C(7, "seven"), D];
		for (item in items)
			Sys.println(label(item));
		for (item in items)
			Sys.println(swapped(item));
		for (item in items)
			Sys.println(nested(Wrap(item)));
	}
}
