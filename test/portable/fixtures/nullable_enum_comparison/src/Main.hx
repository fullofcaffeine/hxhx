/** Ordinary variants exercise constant identity and allocated payload identity. */
enum Choice {
	Plain;
	Other;
	Payload(value:Int);
	Pair(left:Int, right:Int);
	Optional(?value:Int);
}

/** Returns a nullable enum through the same method boundary as compiler metadata. */
class Picker {
	public function new() {}

	public function choose(present:Bool):Null<Choice> {
		if (present)
			return Plain;
		return null;
	}
}

/** Checks comparisons without converting nullable values or avoiding equality syntax. */
class Main {
	static final initialized:Bool = new Picker().choose(true) == Plain;

	static function createPayload():Choice {
		return Payload(7);
	}

	static function argument(label:String, value:Int):Int {
		Sys.println(label);
		return value;
	}

	static function observe(label:String, value:Bool):Void {
		Sys.println(label + "=" + value);
	}

	static function left():Null<Choice> {
		Sys.println("left");
		return Plain;
	}

	static function right():Choice {
		Sys.println("right");
		return Plain;
	}

	static function compare(value:Null<Choice>):Void {
		observe("plain-eq", value == Plain);
		observe("plain-ne", value != Plain);
		observe("reverse-eq", Plain == value);
		observe("reverse-ne", Plain != value);
		observe("other-eq", value == Other);
		observe("null-eq", value == null);
		observe("null-ne", null != value);
	}

	static function comparePayload(value:Null<Choice>, alias:Choice, separate:Choice):Void {
		observe("payload-alias", value == alias);
		observe("payload-reverse", alias == value);
		observe("payload-separate", value == separate);
		observe("payload-separate-ne", separate != value);
	}

	static function main():Void {
		final picker = new Picker();
		observe("method-eq", picker.choose(true) == Plain);
		observe("method-ne", picker.choose(true) != Plain);
		compare(picker.choose(true));
		compare(picker.choose(false));
		final payload:Choice = Payload(7);
		comparePayload(payload, payload, Payload(7));
		observe("ordered-eq", left() == right());
		observe("ordered-ne", left() != right());
		observe("initializer", initialized);
		final nested = () -> picker.choose(false) != Plain;
		observe("nested", nested());
		final first = createPayload();
		final second = createPayload();
		observe("repeated-construction", first == second);
		final pair = Pair(argument("first-argument", 1), argument("second-argument", 2));
		observe("pair-alias", pair == pair);
		final optional = Optional();
		final anotherOptional = Optional();
		observe("optional-separate", optional == anotherOptional);
	}
}
