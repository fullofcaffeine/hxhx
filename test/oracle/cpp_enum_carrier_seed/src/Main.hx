/**
	Seed enum used to pin Cpp enum carrier behavior before implementation.
**/
enum Color {
	Red;
	Green;
	Pair(i:Int, s:String);
}

enum Boxed {
	Box(v:Dynamic);
}

/** Recursive enum used to pin generic identity calls around enum carriers. **/
enum NestedColor {
	Leaf;
	Wrap(value:NestedColor);
}

/** Unrelated reference value used as a generic-call control. **/
class Marker {
	public final value:Int;

	public function new(value:Int) {
		this.value = value;
	}
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

	static function boxedParams(value:Boxed):Array<Dynamic> {
		return Type.enumParameters(value);
	}

	static function identity<T>(value:T):T {
		return value;
	}

	static function main():Void {
		final red = Color.Red;
		final pair = Color.Pair(7, "x");

		emit("enum-zero-01", "string", Std.string(red));
		emit("enum-zero-01", "summary", summarize(red));
		emit("enum-payload-01", "string", Std.string(pair));
		emit("enum-payload-01", "summary", summarize(pair));
		emit("enum-map-key-01", "string", [Color.Pair(11, "map") => 42].toString());
		final nested = identity(NestedColor.Wrap(NestedColor.Leaf));
		emit("enum-generic-id-01:nested", "string", Std.string(nested));
		emit("enum-generic-id-01:nested", "constructor", Type.enumConstructor(nested));
		emit("enum-generic-id-01:string", "value", identity("plain"));
		emit("enum-generic-id-01:object", "value", Std.string(identity(new Marker(13)).value));

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

		final boxedInt = Box(1);
		final boxedString = Box("1");
		final boxedIntParams = boxedParams(boxedInt);
		emit("enum-payload-identity-01", "eq-int-string", bool(Type.enumEq(boxedInt, boxedString)));
		emit("enum-payload-identity-01", "param-is-int", bool(Std.isOfType(boxedIntParams[0], Int)));
		emit("enum-payload-identity-01", "param-is-string", bool(Std.isOfType(boxedIntParams[0], String)));
		emit("enum-payload-identity-01", "param-string", Std.string(boxedIntParams[0]));

		serializerRoundTrip("enum-serializer-01:zero", red);
		serializerRoundTrip("enum-serializer-01:payload", Pair(9, "y"));
	}
}
