/** Observe native Int64 erasure, word recovery and public identity through real providers. */
class Main {
	static var effects:Int = 0;

	static function next():haxe.Int64 {
		effects++;
		return haxe.Int64.make(1, 7);
	}

	/** Dynamic is the public boundary under test, isolated from the typed recovery local. */
	static function show(value:Dynamic):Void {
		Sys.println(haxe.Int64.isInt64(value));
		Sys.println(Std.string(value));
		Sys.println(Type.getClass(value) == null);
		recover(value);
	}

	static function recover(value:Dynamic):Void {
		final restored:haxe.Int64 = value;
		Sys.println(Std.string(restored.high));
		Sys.println(Std.string(restored.low));
		Sys.println(haxe.Int64.toStr(restored));
	}

	static function main():Void {
		final erased:Dynamic = next();
		final values:Array<Dynamic> = [erased];
		show(values[0]);
		show(haxe.Int64.make(-2, 7));
		show(haxe.Int64.make(-2147483647 - 1, 0));
		show(haxe.Int64.make(2147483647, -1));
		show(haxe.Int64.ofInt(0));
		show(haxe.Int64.ofInt(-1));
		show(haxe.Int64.ofInt(255));
		show(haxe.Int64.ofInt(256));
		show(42);
		Sys.println(effects);
		Sys.println(haxe.Int64.isInt64(2.0));
		Sys.println(haxe.Int64.isInt64(256.0));
		Sys.println(haxe.Int64.isInt64(2.5));
		Sys.println(haxe.Int64.isInt64(null));
		Sys.println(haxe.Int64.isInt64(true));
		Sys.println(haxe.Int64.isInt64("2"));
		Sys.println(haxe.Int64.isInt64([1, 7]));
		Sys.println(haxe.Int64.isInt64({high: 1, low: 7}));
	}
}
