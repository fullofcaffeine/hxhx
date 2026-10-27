enum Choice {
	Empty;
	Pair(number:Int, flag:Bool);
	Last;
	Text(value:String);
	Wrap(value:Choice);
	Maybe(value:Null<Choice>);
	OptionalNumber(?number:Int);
	NullableNumber(number:Null<Int>);
	OptionalFlag(?flag:Bool);
	OptionalText(?value:String);
	OptionalChoice(?value:Choice);
	AnyValue(value:Dynamic);
	OptionalAny(?value:Dynamic);
	NullableAny(value:Null<Dynamic>);
	AnyPair(first:Dynamic, second:Dynamic);
	OptionalTail(number:Int, ?flag:Bool, ?text:String);
}

enum Other {
	Empty;
	Pair(number:Int);
}

/** An ordinary reference must retain identity when stored in a Dynamic payload. */
class Token {
	public var value:Int;

	public function new(value:Int) {
		this.value = value;
	}
}

class Main {
	/** Omitted patterns ignore optional values; execution still matches the full stored constructor payload. */
	static function omitted(value:Choice):Int {
		return switch value {
			case Choice.OptionalTail(number): number;
			case Choice.OptionalNumber(): 71;
			case Choice.Wrap(Choice.OptionalTail(number)): number + 1000;
			case Choice.OptionalFlag() if (true): 72;
			case _: 0;
		};
	}

	/** Pattern extraction returns the same checked Dynamic value stored by construction. */
	static function readAny(value:Choice):Dynamic {
		return switch value {
			case AnyValue(value), OptionalAny(value), NullableAny(value): value;
			case AnyPair(first, _): first;
			case _: null;
		};
	}

	static function read(value:Choice):Int {
		return switch value {
			case Choice.Empty: 1;
			case Choice.Pair(number, flag): flag ? number : -number;
			case Last: 2;
			case Text("yes"): 3;
			case Choice.Wrap(Choice.Pair(number, true)): number + 100;
			case Wrap(Choice.Empty): 4;
			case Maybe(null): 5;
			case Maybe(Pair(number, true)): number + 200;
			case OptionalNumber(number): number == null ? 30 : number + 300;
			case NullableNumber(number): number == null ? 31 : number + 400;
			case OptionalFlag(flag): flag == null ? 32 : flag ? 41 : 40;
			case OptionalText(value): value == null ? 33 : value.length + 500;
			case OptionalChoice(value): value == null ? 34 : read(value) + 600;
			case _: 0;
		};
	}

	static function other(value:Other):Int {
		return switch value {
			case Other.Empty: 10;
			case Other.Pair(number): number;
			case _: 0;
		};
	}

	static function number():Int {
		Sys.println("number");
		return 9;
	}

	static function flag():Bool {
		Sys.println("flag");
		return false;
	}

	static function main():Void {
		Sys.println(read(Choice.Empty));
		Sys.println(read(Choice.Pair(7, true)));
		Sys.println(read(Choice.Pair(8, false)));
		Sys.println(read(Choice.Last));
		Sys.println(read(Choice.Text("yes")));
		Sys.println(read(Choice.Text("no")));
		Sys.println(read(Choice.Wrap(Choice.Pair(5, true))));
		Sys.println(read(Choice.Wrap(Choice.Pair(5, false))));
		Sys.println(read(Choice.Wrap(Choice.Empty)));
		Sys.println(read(Choice.Pair(number(), flag())));
		Sys.println(Type.enumIndex(Choice.Empty));
		Sys.println(Type.enumIndex(Choice.Pair(0, false)));
		Sys.println(Type.enumIndex(Choice.Last));
		Sys.println(Type.enumIndex(Choice.Text("index")));
		Sys.println(Type.enumIndex(Choice.Wrap(Choice.Empty)));
		Sys.println(read(Choice.Maybe(null)));
		Sys.println(read(Choice.Maybe(Choice.Pair(6, true))));
		Sys.println(read(Choice.Maybe(Choice.Pair(6, false))));
		Sys.println(other(Other.Empty));
		Sys.println(other(Other.Pair(12)));
		Sys.println(read(Choice.OptionalNumber()));
		Sys.println(read(Choice.OptionalNumber(null)));
		Sys.println(read(Choice.OptionalNumber(0)));
		Sys.println(read(Choice.OptionalNumber(number())));
		Sys.println(read(Choice.NullableNumber(null)));
		Sys.println(read(Choice.NullableNumber(0)));
		var nullable:Null<Int> = null;
		Sys.println(read(Choice.NullableNumber(nullable)));
		nullable = 8;
		Sys.println(read(Choice.NullableNumber(nullable)));
		Sys.println(read(Choice.OptionalFlag()));
		Sys.println(read(Choice.OptionalFlag(false)));
		Sys.println(read(Choice.OptionalFlag(true)));
		Sys.println(read(Choice.OptionalText()));
		Sys.println(read(Choice.OptionalText("")));
		Sys.println(read(Choice.OptionalText("yes")));
		Sys.println(read(Choice.OptionalChoice()));
		Sys.println(read(Choice.OptionalChoice(Choice.Pair(7, true))));
		Sys.println(readAny(Choice.AnyValue(7)));
		Sys.println(readAny(Choice.AnyValue(true)));
		Sys.println(readAny(Choice.AnyValue(false)));
		Sys.println(readAny(Choice.AnyValue(null)));
		Sys.println(readAny(Choice.AnyValue("text")));
		Sys.println(readAny(Choice.AnyValue(true)) == 1);
		Sys.println(readAny(Choice.AnyValue(1)) == true);
		var already:Dynamic = true;
		Sys.println(readAny(Choice.AnyValue(already)));
		Sys.println(readAny(Choice.OptionalAny()));
		Sys.println(readAny(Choice.OptionalAny(null)));
		Sys.println(readAny(Choice.OptionalAny(false)));
		Sys.println(readAny(Choice.NullableAny(null)));
		Sys.println(readAny(Choice.NullableAny(true)));
		final token = new Token(4);
		final wrapped = Choice.AnyValue(token);
		Sys.println(readAny(wrapped) == token);
		token.value = 9;
		Sys.println(readAny(wrapped) == token);
		Sys.println(token.value);
		Sys.println(readAny(Choice.AnyPair(flag(), number())));
		Sys.println(omitted(Choice.OptionalTail(7)));
		Sys.println(omitted(Choice.OptionalTail(8, false, "stored")));
		Sys.println(omitted(Choice.OptionalNumber(19)));
		Sys.println(omitted(Choice.Wrap(Choice.OptionalTail(9, true, "nested"))));
		Sys.println(omitted(Choice.OptionalFlag(false)));
	}
}
