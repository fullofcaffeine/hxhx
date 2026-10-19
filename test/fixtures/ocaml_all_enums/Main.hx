/** Interleaved constructors expose the difference between native tags and Haxe indexes. */
enum Choice {
	Payload(value:Int);
	First;
	More(value:String);
	Last;
}

enum PayloadOnly {
	Value(value:Int);
}

enum Other {
	First;
}

/** Observe ordered constants, fresh arrays, and descriptor evaluation through public APIs. */
class Main {
	/** Type.getEnum exposes Enum<Dynamic>; retain that exact standard reflection boundary. */
	static function descriptor():Enum<Dynamic> {
		Sys.println("descriptor");
		return Type.getEnum(Choice.First);
	}

	static function main():Void {
		final values = Type.allEnums(descriptor());
		Sys.println(values.length);
		for (value in values) {
			Sys.println(Type.enumConstructor(value));
			Sys.println(Type.enumIndex(value));
		}
		Sys.println(values[0] == Choice.First);
		Sys.println(values[1] == Choice.Last);
		final again = Type.allEnums(Type.getEnum(Choice.Last));
		Sys.println(again[0] == values[0]);
		values[0] = Choice.Last;
		Sys.println(again[0] == Choice.First);
		Sys.println(again.length);
		final empty = Type.allEnums(Type.getEnum(PayloadOnly.Value(3)));
		Sys.println(empty.length);
		final other = Type.allEnums(Type.getEnum(Other.First));
		Sys.println(other.length);
		Sys.println(other[0] == Other.First);
		Sys.println(Type.getEnumName(Type.getEnum(other[0])));
		Sys.println(Type.getEnumName(Type.getEnum(again[0])));
	}
}
