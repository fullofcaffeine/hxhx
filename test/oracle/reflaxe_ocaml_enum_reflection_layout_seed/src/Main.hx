/**
 * Interleaves constructors with and without payloads so Haxe declaration order
 * differs from the two tag sequences used by native OCaml variants.
 */
enum MixedShape {
	Alpha;
	Bravo(value:Int);
	Charlie;
	Delta(label:String, value:Int);
	Echo;
}

/** Freezes upstream Haxe 4.3.7 enum reflection and factory behavior. */
class Main {
	static function line(value:String):Void {
		#if js
		js.Syntax.code("console.log({0})", value);
		#else
		Sys.println(value);
		#end
	}

	static function parameters(value:Dynamic):String {
		final values = Type.enumParameters(value);
		final rendered:Array<String> = [];
		for (item in values)
			rendered.push(Std.string(item));
		return rendered.join(",");
	}

	static function describe(value:Dynamic):String {
		return Type.enumConstructor(value) + ":" + Type.enumIndex(value) + ":" + parameters(value);
	}

	static function typedCases():Void {
		final values:Array<MixedShape> = [Alpha, Bravo(1), Charlie, Delta("typed", 2), Echo];
		for (value in values)
			line("typed:" + describe(value));
	}

	static function dynamicCases():Void {
		final values:Array<Dynamic> = [
			MixedShape.Alpha,
			MixedShape.Bravo(3),
			MixedShape.Charlie,
			MixedShape.Delta("dynamic", 4),
			MixedShape.Echo
		];
		for (value in values)
			line("dynamic:" + describe(value));
	}

	static function factoryCases():Void {
		final enumType:Dynamic = MixedShape;
		line("constructors:" + Type.getEnumConstructs(enumType).join(","));

		final byName:MixedShape = cast Type.createEnum(enumType, "Delta", ["made", 5]);
		line("factory-name:" + describe(byName));

		final byIndex:MixedShape = cast Type.createEnumIndex(enumType, 2);
		line("factory-index:" + describe(byIndex));
	}

	static function main():Void {
		typedCases();
		dynamicCases();
		factoryCases();
	}
}
