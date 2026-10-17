/** A finite enum needs no wildcard to cover every well-typed input. */
enum Choice {
	One(value:Int);
}

/** Both guard outcomes initialize the result before returning it to native C#. */
class Main {
	static function label(value:Choice):String {
		return switch value {
			case One(number) if (number > 1): ">1";
			case One(_): "<=1";
		};
	}

	static function main():Void {
		Sys.println(label(One(1)));
		Sys.println(label(One(2)));
	}
}
