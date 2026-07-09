/**
	Seed enum used to pin Cpp enum carrier behavior before implementation.
**/
enum Color {
	Red;
	Green;
	Pair(i:Int, s:String);
}

/**
	Repo-owned upstream Haxe oracle cases for Cpp enum carriers.

	These cases intentionally pin observable behavior only. They do not copy
	upstream tests, and they do not imply Cpp support is implemented.
**/
class Main {
	static function emit(id:String, field:String, value:String):Void {
		Sys.println(id + "|" + field + "|" + value);
	}

	static function bool(value:Bool):String {
		return value ? "true" : "false";
	}

	static function params(value:Color):String {
		return Type.enumParameters(value).map(function(v) return Std.string(v)).join(",");
	}

	static function summarize(value:Color):String {
		return Type.enumConstructor(value) + ":" + Std.string(Type.enumIndex(value)) + ":" + params(value);
	}

	static function serializerRoundTrip(id:String, value:Color):Void {
		final serialized = haxe.Serializer.run(value);
		emit(id, "serialized", serialized);
		final decoded:Color = haxe.Unserializer.run(serialized);
		emit(id, "decoded", summarize(decoded));
	}

	static function main():Void {
		final red:Color = Red;
		final pair:Color = Pair(7, "x");

		emit("enum-zero-01", "string", Std.string(red));
		emit("enum-zero-01", "summary", summarize(red));
		emit("enum-payload-01", "string", Std.string(pair));
		emit("enum-payload-01", "summary", summarize(pair));

		emit("enum-eq-01:zero", "value", bool(Type.enumEq(red, Red)));
		emit("enum-eq-01:payload-same", "value", bool(Type.enumEq(pair, Pair(7, "x"))));
		emit("enum-eq-01:payload-different", "value", bool(Type.enumEq(pair, Pair(8, "x"))));

		emit("enum-switch-01", "payload", switch (pair) {
			case Pair(i, s):
				i + ":" + s;
			case _:
				"no";
		});

		final created = Type.createEnum(Color, "Pair", [9, "y"]);
		emit("enum-type-create-01:name", "value", Std.string(created));
		emit("enum-type-create-01:name", "summary", summarize(created));
		final createdIndex = Type.createEnumIndex(Color, 0);
		emit("enum-type-create-01:index", "value", Std.string(createdIndex));
		emit("enum-type-create-01:index", "summary", summarize(createdIndex));

		final allEnums = [for (value in Type.allEnums(Color)) Std.string(value)].join(",");
		emit("enum-reflect-01", "allEnums", allEnums);
		emit("enum-reflect-01", "constructs", Type.getEnumConstructs(Color).join(","));
		emit("enum-reflect-01", "enumName", Type.getEnumName(Color));

		final dynamicValue:Dynamic = pair;
		emit("enum-dynamic-01", "string", Std.string(dynamicValue));
		emit("enum-dynamic-01", "summary", summarize(dynamicValue));

		serializerRoundTrip("enum-serializer-01:zero", red);
		serializerRoundTrip("enum-serializer-01:payload", Pair(9, "y"));
	}
}
