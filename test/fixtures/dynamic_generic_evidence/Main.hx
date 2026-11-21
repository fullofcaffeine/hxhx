/**
	A generic method called with Dynamic arguments, as `haxe.Unserializer` calls
	`unserializeEnum<T>(edecl:Enum<T>, ...)` with an `Enum<Dynamic>`. Dynamic does not bind `T` in
	Haxe 4.3.7, but the call is still valid and its result can go into an `Array<Dynamic>`.
**/
enum Color {
	Red;
	Green;
}

class Gen {
	static function make<T>(e:Enum<T>, tag:String)
		return Type.createEnum(e, tag);

	static function first<T>(items:Array<T>)
		return items[0];

	public static function remember(e:Enum<Dynamic>, cache:Array<Dynamic>, tag:String) {
		var value = make(e, tag);
		cache.push(value);
		return cache.length;
	}

	public static function head(items:Array<Dynamic>)
		return first(items);
}

/** The observed operations take simple inputs; `Gen` holds the generic calls. **/
class Ops {
	public static function count(tag:String) {
		final cache:Array<Dynamic> = [];
		Gen.remember(Color, cache, tag);
		return Gen.remember(Color, cache, tag);
	}

	public static function firstText(text:String)
		return Std.string(Gen.head([text, "other"]));
}

class Main {
	static function main() {
		Sys.println(Ops.count("Red"));
		Sys.println(Ops.firstText("one"));
	}
}
