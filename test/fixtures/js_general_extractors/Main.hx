using Extractors;

/** A returned enum must retain its constructor selection in an extractor pattern. */
enum Choice {
	Some(value:String);
	None;
}

/** Independent expected values and effects for currently unsupported general extractors. */
class Main {
	public static var events:String = "";

	static function pick(value:Int):Choice {
		events += "pick;";
		return value > 0 ? Some("odd") : None;
	}

	static function extract(value:Int):String
		return switch value {
			case _.isEven() => true: "even";
			case pick(_) => Some(value): value;
			case _: "other";
		};

	static function main():Void {
		events = "";
		if (extract(2) != "even" || events != "even;")
			throw "extension extractor or branch order";
		events = "";
		if (extract(3) != "odd" || events != "even;pick;")
			throw "function extractor or captured result";
		events = "";
		if (extract(-1) != "other" || events != "even;pick;")
			throw "extractor fallback";
	}
}
