/** Independently inspect the native opaque-value boundary before choosing a provider representation. */
class Main {
	/** Dynamic is the measured input/output boundary; typed Int64 operations follow explicit recovery. */
	static function sample(name:String):Dynamic {
		// Each return crosses Dynamic independently.
		switch (name) {
			case "wide":
				return haxe.Int64.make(1, 7);
			case "negative_wide":
				return haxe.Int64.make(-2, 7);
			case "zero64":
				return haxe.Int64.ofInt(0);
			case "small64":
				return haxe.Int64.ofInt(42);
			case "max32_64":
				return haxe.Int64.ofInt(2147483647);
			case "min32_64":
				return haxe.Int64.ofInt(-2147483647 - 1);
			case "integer":
				return 42;
			case "fraction":
				return 17.875;
			case "whole_float":
				return 256.0;
			case "small_float":
				return 2.0;
			case "null":
				return null;
			case "true":
				return true;
			case "numeric_string":
				return "17";
			case "word":
				return "value";
			case "record":
				return {high: 1, low: 7};
			case "array":
				return [1, 7];
			case _:
				throw "unknown probe case";
		}
	}

	static function main():Void {
		final args = Sys.args();
		if (args.length != 2)
			throw "expected mode and case";
		final value:Dynamic = sample(args[1]);
		if (args[0] == "kind")
			observe(value);
		else
			recover(value);
	}

	/** Explicit Dynamic parameters keep later recovery from specializing the observed local. */
	static function observe(value:Dynamic):Void {
		Sys.println(Type.enumConstructor(Type.typeof(value)));
		final owner = Type.getClass(value);
		Sys.println(owner == null ? "no-class" : Type.getClassName(owner));
		Sys.println(haxe.Int64.isInt64(value));
		Sys.println(Std.isOfType(value, Int));
	}

	static function recover(value:Dynamic):Void {
		final recovered:haxe.Int64 = value;
		Sys.println(recovered.high);
		Sys.println(recovered.low);
		Sys.println(haxe.Int64.toStr(recovered));
		Sys.println(Type.enumConstructor(Type.typeof((recovered : Dynamic))));
	}
}
