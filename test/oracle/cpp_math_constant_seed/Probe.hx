/** Observe public values without assuming a particular NaN payload. */
class Probe {
	static function bits(name:String, value:Float):Void {
		final raw = haxe.io.FPHelper.doubleToI64(value);
		Sys.println(name + ":" + StringTools.hex(raw.high, 8) + StringTools.hex(raw.low, 8));
	}

	static function main():Void {
		Main.main();
		bits("pi", Main.pi);
		bits("positive", Main.positive);
		bits("negative", Main.negative);
		Sys.println("nan:" + Math.isNaN(Main.nan));
		bits("local", Main.zLocal);
		bits("shadow", Main.zShadow);
	}
}
