/** Observe stored binary64 values, without depending on decimal display precision. */
class Probe {
	static function bits(name:String, value:Float):Void {
		final raw = haxe.io.FPHelper.doubleToI64(value);
		Sys.println(name + ":" + StringTools.hex(raw.high, 8) + StringTools.hex(raw.low, 8));
	}

	static function main():Void {
		Main.main();
		bits("zero", Main.zero);
		bits("negativeZero", Main.negativeZero);
		bits("one", Main.one);
		bits("tenth", Main.tenth);
		bits("precision", Main.precision);
		bits("adjacent", Main.adjacent);
		bits("smallest", Main.smallest);
		bits("normal", Main.normal);
		bits("largest", Main.largest);
		bits("negative", Main.negative);
		bits("local", Main.zzLocal);
		bits("returned", Main.zzReturned);
	}
}
