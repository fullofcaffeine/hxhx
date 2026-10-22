/** Identity exports exercise native Float transport without adding arithmetic policy. */
#if native_host
@:native("Stdlib.Fun")
extern class Host {
	@:native("id") public static function value(value:Float):Float;
	@:native("id") public static function values(value:Array<Float>):Array<Float>;
}

@:native("HxFPHelper")
extern class Bits {
	@:native("i32ToFloat") public static function decode(value:Int):Float;
	@:native("floatToI32") public static function encode(value:Float):Int;
}
#else
class Host {
	public static function value(value:Float):Float
		return value;

	public static function values(value:Array<Float>):Array<Float>
		return value;
}

class Bits {
	public static function decode(value:Int):Float
		return haxe.io.FPHelper.i32ToFloat(value);

	public static function encode(value:Float):Int
		return haxe.io.FPHelper.floatToI32(value);
}
#end

class Main {
	static function produced():Float {
		Sys.println("produce");
		return 1.25;
	}

	static function main():Void {
		Sys.println(Host.value(1.25) == 1.25);
		final retained = Host.value;
		Sys.println(retained(produced()) == 1.25);
		for (bits in [0, -2147483648, 1067450368, 2139095040, -8388608, 2143289344]) {
			final value = Bits.decode(bits);
			final before = Bits.encode(value);
			Sys.println(before == bits);
			Sys.println(Bits.encode(Host.value(value)) == before);
			Sys.println(Bits.encode(retained(value)) == before);
		}
		final values = [1.25, 2.5];
		final alias = Host.values(values);
		alias[0] = 3.75;
		Sys.println(values[0] == 3.75);
		values[1] = 7.5;
		Sys.println(alias[1] == 7.5);
	}
}
